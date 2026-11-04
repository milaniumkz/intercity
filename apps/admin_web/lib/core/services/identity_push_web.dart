import 'dart:js_interop';

@JS('window.intercityAdminPushPermission')
external JSPromise<JSBoolean> _permission();
@JS('window.intercityAdminPushSubscribe')
external JSPromise<JSString> _subscribe(JSString key);
@JS('window.intercityAdminReviewSound')
external void _sound();

class IdentityPush {
  static Future<bool> permission() async => (await _permission().toDart).toDart;
  static Future<String> subscribe(String key) async =>
      (await _subscribe(key.toJS).toDart).toDart;
  static void sound() {
    _sound();
  }
}
