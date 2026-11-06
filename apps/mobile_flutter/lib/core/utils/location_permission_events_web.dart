import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// A trusted permission transition retries GPS without reloading the order.
Stream<void> locationPermissionGrantedEvents() {
  late final StreamController<void> controller;
  final callback = ((web.Event _) => controller.add(null)).toJS;
  controller = StreamController<void>(
    onListen: () => web.window
        .addEventListener('intercity-location-permission-granted', callback),
    onCancel: () => web.window
        .removeEventListener('intercity-location-permission-granted', callback),
  );
  return controller.stream;
}
