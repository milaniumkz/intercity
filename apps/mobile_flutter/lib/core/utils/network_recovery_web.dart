import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Browser connectivity is a retry signal, not proof an upstream is available.
Stream<void> networkRecoveryEvents() {
  late final StreamController<void> controller;
  DateTime? last;
  void restored() {
    final now = DateTime.now();
    if (!web.window.navigator.onLine ||
        (last != null && now.difference(last!) < const Duration(seconds: 2))) {
      return;
    }
    last = now;
    controller.add(null);
  }

  final online = ((web.Event _) => restored()).toJS;
  controller = StreamController<void>(
    onListen: () => web.window.addEventListener('online', online),
    onCancel: () => web.window.removeEventListener('online', online),
  );
  return controller.stream;
}
