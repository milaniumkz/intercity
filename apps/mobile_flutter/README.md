# mobile_flutter

Passenger/driver/admin Flutter client for INTERCITY.

## Runtime Configuration

The app reads API base URL from the shared `INTERCITY_API_BASE_URL` environment
variable:

```bash
export INTERCITY_API_BASE_URL="https://your-api-host.example/api"
```

If the variable is missing, the app falls back to the safe placeholder
`https://api.intercity.invalid/api`. Real environments should not rely on that
fallback.

## Local Checks

```bash
/Volumes/PD1000/job/flutter/bin/flutter pub get
/Volumes/PD1000/job/flutter/bin/flutter analyze
/Volumes/PD1000/job/flutter/bin/flutter test
/Volumes/PD1000/job/flutter/bin/flutter test integration_test/app_smoke_test.dart -d macos
/Volumes/PD1000/job/flutter/bin/flutter build web
```

Or run the shared verification script from repository root:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/verify_flutter_apps.sh
```

For a live production API smoke run with fresh `QA_TEST_*` accounts:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/smoke_prod_core.sh
CLEANUP_USERS=1 bash /Volumes/PD1000/job/INTERCITY/scripts/smoke_prod_core.sh
```

With `CLEANUP_USERS=1`, the smoke script first tries admin safe-delete and then
falls back to anonymizing fresh `QA_TEST_*` accounts if legacy production
relations block a hard delete.

For older production QA backlogs:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/cleanup_prod_qa_users.sh
DRY_RUN=1 bash /Volumes/PD1000/job/INTERCITY/scripts/cleanup_prod_qa_users.sh
```

The script auto-detects the local Flutter SDK path used in this workspace and
falls back to `flutter` from `PATH` in CI or on other machines.

## Reproducible Web Deploy Output

`web_deploy/` is a generated output directory. Rebuild it instead of editing it:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/build_mobile_web_deploy.sh
docker build -f /Volumes/PD1000/job/INTERCITY/apps/mobile_flutter/deploy/web.Dockerfile \
  -t intercity-mobile-web /Volumes/PD1000/job/INTERCITY/apps/mobile_flutter/web_deploy
```

## Android Release

Release builds require signing credentials through environment variables:

```bash
export INTERCITY_ANDROID_RELEASE_KEYSTORE_PATH="/absolute/path/to/release.keystore"
export INTERCITY_ANDROID_RELEASE_STORE_PASSWORD="..."
export INTERCITY_ANDROID_RELEASE_KEY_ALIAS="..."
export INTERCITY_ANDROID_RELEASE_KEY_PASSWORD="..."
```

CI can provide the keystore as base64 instead:

```bash
export INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64="base64-encoded-keystore"
```

GitHub Actions manual release builds expect these repository secrets:

- `INTERCITY_ANDROID_RELEASE_KEYSTORE_BASE64`
- `INTERCITY_ANDROID_RELEASE_STORE_PASSWORD`
- `INTERCITY_ANDROID_RELEASE_KEY_ALIAS`
- `INTERCITY_ANDROID_RELEASE_KEY_PASSWORD`

Then build with the release wrapper:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/build_mobile_android_release.sh
```

Release config enables resource shrinking and code minification by default.
The wrapper is the preferred entrypoint because it also handles the known
Flutter false-negative where raw `flutter build appbundle` can fail on machines
without Android `cmdline-tools/apkanalyzer` even after producing a valid `.aab`.

Before building, run the Android release preflight from repository root:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/verify_release_readiness.sh
```

Useful toggles:

```bash
ALLOW_MISSING_SIGNING=1 bash /Volumes/PD1000/job/INTERCITY/scripts/verify_release_readiness.sh
RUN_APPBUNDLE_BUILD=1 bash /Volumes/PD1000/job/INTERCITY/scripts/verify_release_readiness.sh
```

Or use the release build wrapper directly, which runs preflight first:

```bash
bash /Volumes/PD1000/job/INTERCITY/scripts/build_mobile_android_release.sh
```

Alternative modes:

```bash
RELEASE_TARGET=apk bash /Volumes/PD1000/job/INTERCITY/scripts/build_mobile_android_release.sh
RUN_FLUTTER_BUILD=0 ALLOW_MISSING_SIGNING=1 bash /Volumes/PD1000/job/INTERCITY/scripts/build_mobile_android_release.sh
```
