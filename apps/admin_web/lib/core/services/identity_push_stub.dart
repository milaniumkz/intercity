class IdentityPush {
  static Future<bool> permission() async => false;
  static Future<String> subscribe(String key) async =>
      throw UnsupportedError('Push доступны в браузере');
  static void sound() {}
}
