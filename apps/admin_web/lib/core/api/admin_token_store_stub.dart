import 'admin_token_store_base.dart';

AdminTokenStore createAdminTokenStore() => _InMemoryAdminTokenStore();

class _InMemoryAdminTokenStore implements AdminTokenStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
