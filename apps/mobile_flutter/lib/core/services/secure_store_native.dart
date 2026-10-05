import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_store_base.dart';

SecureStore createSecureStore({required String namespace}) {
  return const _NativeSecureStore();
}

class _NativeSecureStore implements SecureStore {
  const _NativeSecureStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}
