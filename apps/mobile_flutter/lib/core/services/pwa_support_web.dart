import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('window.intercityShowPwaHelp')
external JSFunction? get _showHelp;

class PwaSupport {
  static bool get isWeb => true;
  static bool get isIosWeb =>
      RegExp(r'iPad|iPhone|iPod').hasMatch(web.window.navigator.userAgent) ||
      (web.window.navigator.platform == 'MacIntel' &&
          web.window.navigator.maxTouchPoints > 1);
  static void showHelp() {
    _showHelp?.callAsFunction();
  }

  static void refresh() {
    web.window.dispatchEvent(web.Event('intercity-pwa-refresh'));
  }
}
