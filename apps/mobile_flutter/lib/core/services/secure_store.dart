import 'secure_store_base.dart';
import 'secure_store_stub.dart'
    if (dart.library.io) 'secure_store_native.dart'
    if (dart.library.js_interop) 'secure_store_web.dart' as impl;

export 'secure_store_base.dart';

SecureStore createSecureStore({required String namespace}) {
  return impl.createSecureStore(namespace: namespace);
}
