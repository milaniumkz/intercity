#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile_flutter"
OUTPUT_DIR="${OUTPUT_DIR:-$APP_DIR/web_deploy}"
DOCKERFILE_SOURCE="$APP_DIR/deploy/web.Dockerfile"
source "$ROOT_DIR/scripts/lib/flutter_release_helpers.sh"

resolve_flutter_bin

if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Builds reproducible mobile web deploy artifacts into web_deploy/.

Environment variables:
  FLUTTER_BIN  Flutter executable path. Defaults to local SDK path when present,
               otherwise falls back to "flutter" from PATH.
  OUTPUT_DIR   Web output directory (default: $APP_DIR/web_deploy)
  INTERCITY_API_BASE_URL
               Optional compile-time API base URL. When present, the script
               passes it through --dart-define for the Flutter web build.
  INTERCITY_FIREBASE_WEB_VAPID_KEY
               Optional Firebase Web Push VAPID public key. When present, the
               script passes it through --dart-define for browser FCM token
               registration.

Example:
  bash scripts/build_mobile_web_deploy.sh
  docker build -f apps/mobile_flutter/deploy/web.Dockerfile -t intercity-mobile-web "\$OUTPUT_DIR"
EOF
  exit 0
fi

flutter_args=(
  build web
  --release
  --no-wasm-dry-run
  --pwa-strategy=none
  --output "$OUTPUT_DIR"
)
if [[ -n "${INTERCITY_API_BASE_URL:-}" ]]; then
  flutter_args+=(
    "--dart-define=INTERCITY_API_BASE_URL=${INTERCITY_API_BASE_URL}"
  )
fi
if [[ -n "${INTERCITY_FIREBASE_WEB_VAPID_KEY:-}" ]]; then
  flutter_args+=(
    "--dart-define=INTERCITY_FIREBASE_WEB_VAPID_KEY=${INTERCITY_FIREBASE_WEB_VAPID_KEY}"
  )
fi

(
  cd "$APP_DIR"
  "$FLUTTER_BIN" "${flutter_args[@]}"
)

cp "$DOCKERFILE_SOURCE" "$OUTPUT_DIR/Dockerfile"

python3 - "$OUTPUT_DIR" <<'PY'
import pathlib
import re
import sys
import time

out = pathlib.Path(sys.argv[1])
version = str(int(time.time()))
service_worker = out / "flutter_service_worker.js"
service_worker.write_text(
    """
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.registration.unregister();
    const clientsList = await clients.matchAll({ type: 'window' });
    await Promise.all(clientsList.map((client) => client.navigate(client.url)));
  })());
});
""".strip()
)

bootstrap = out / "flutter_bootstrap.js"
if bootstrap.exists():
    text = bootstrap.read_text()
    text = re.sub(
        r"_flutter\.loader\.load\(\{\s*serviceWorkerSettings:\s*\{.*?\}\s*\}\);",
        "_flutter.loader.load();",
        text,
        flags=re.S,
    )
    text = re.sub(
        r'("mainJsPath"\s*:\s*)"main\.dart\.js(?:\?v=[^"]*)?"',
        rf'\1"main.dart.js?v={version}"',
        text,
    )
    text = text.replace('c("main.dart.js")', f'c("main.dart.js?v={version}")')
    text = text.replace('??"main.dart.js"', f'??"main.dart.js?v={version}"')
    bootstrap.write_text(text)

index = out / "index.html"
if index.exists():
    text = index.read_text()
    cache_clear_script = f"""
  <script id="intercity-cache-reset">
    (function() {{
      var version = "{version}";
      var reloadKey = "intercity-sw-reload-" + version;
      var loaded = false;
      function loadFlutter() {{
        if (loaded) return;
        loaded = true;
        var script = document.createElement("script");
        script.id = "flutter-bootstrap-loader";
        script.src = "flutter_bootstrap.js?v={version}";
        script.async = true;
        document.body.appendChild(script);
      }}
      function clearCaches() {{
        return Promise.resolve()
          .then(function() {{
            if (!("serviceWorker" in navigator)) return [];
            return navigator.serviceWorker.getRegistrations()
              .then(function(regs) {{
                return Promise.all(regs.map(function(reg) {{ return reg.unregister(); }}));
              }});
          }})
          .then(function() {{
            if (!window.caches) return [];
            return caches.keys().then(function(keys) {{
              return Promise.all(keys.map(function(cacheKey) {{ return caches.delete(cacheKey); }}));
            }});
          }});
      }}
      function start() {{
        clearCaches()
          .then(function() {{
            if (navigator.serviceWorker && navigator.serviceWorker.controller &&
                sessionStorage.getItem(reloadKey) !== "1") {{
              sessionStorage.setItem(reloadKey, "1");
              window.location.reload();
              return;
            }}
            loadFlutter();
          }})
          .catch(loadFlutter);
      }}
      if (document.readyState === "loading") {{
        document.addEventListener("DOMContentLoaded", start);
      }} else {{
        start();
      }}
      setTimeout(loadFlutter, 2500);
    }})();
  </script>
"""
    text = re.sub(
        r'\s*<script id="intercity-cache-reset">.*?</script>',
        "",
        text,
        flags=re.S,
    )
    text = text.replace("</head>", cache_clear_script + "\n</head>")
    text = re.sub(
        r'\s*<script src="flutter_bootstrap\.js(?:\?v=[^"]*)?" async=""></script>',
        "",
        text,
    )
    index.write_text(text)
PY
