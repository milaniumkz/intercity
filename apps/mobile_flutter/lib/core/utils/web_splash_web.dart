import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('removeSplashFromWeb')
external void _removeSplashFromWeb();

void removeWebSplash() {
  web.document.getElementById('splash')?.remove();
  web.document.getElementById('splash-branding')?.remove();
  web.document.body?.style.background = 'transparent';
  try {
    _removeSplashFromWeb();
  } catch (_) {
    // The direct DOM cleanup above is the reliable path for web tests.
  }
}
