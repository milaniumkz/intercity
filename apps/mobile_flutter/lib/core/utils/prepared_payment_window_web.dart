import 'package:web/web.dart' as web;

class PreparedPaymentWindow {
  PreparedPaymentWindow(this._window);

  final web.Window? _window;

  Future<bool> open(String url) async {
    final window = _window;
    if (window == null || window.closed) return false;
    try {
      window.location.href = url;
      window.focus();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> close() async {
    try {
      _window?.close();
    } catch (_) {
      // Ignore browsers that block script closing.
    }
  }
}

PreparedPaymentWindow? preparePaymentWindow() {
  try {
    final window = web.window.open('about:blank', '_blank');
    return PreparedPaymentWindow(window);
  } catch (_) {
    return null;
  }
}
