import 'admin_token_store_base.dart';
import 'admin_token_store_stub.dart'
    if (dart.library.js_interop) 'admin_token_store_web.dart' as impl;

export 'admin_token_store_base.dart';

AdminTokenStore createDefaultAdminTokenStore() => impl.createAdminTokenStore();
