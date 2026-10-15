@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:intercity_mobile/core/services/secure_store_web.dart';

void main() {
  const namespace = 'intercity.secure-store-regression';
  final storage = web.window.localStorage;
  void clean() {
    for (final key in ['encryption_key', 'access', 'refresh']) {
      storage.removeItem('$namespace.$key');
    }
    storage.removeItem('intercity.unrelated-regression');
  }

  setUp(clean);
  tearDown(clean);
  for (final invalid in ['AQID', 'not valid base64!!']) {
    test(
        'repairs invalid browser key $invalid without plaintext or unrelated data loss',
        () async {
      storage.setItem('$namespace.encryption_key', invalid);
      storage.setItem('intercity.unrelated-regression', 'keep');
      final store = createSecureStore(namespace: namespace);
      await store.write('access', 'access-test-value');
      await store.write('refresh', 'refresh-test-value');
      expect(await store.read('access'), 'access-test-value');
      expect(await createSecureStore(namespace: namespace).read('refresh'),
          'refresh-test-value');
      expect(base64Decode(storage.getItem('$namespace.encryption_key')!).length,
          32);
      expect(storage.getItem('$namespace.access'),
          isNot(contains('access-test-value')));
      expect(storage.getItem('intercity.unrelated-regression'), 'keep');
    });
  }
  test('valid encryption key and existing session values survive another write',
      () async {
    final store = createSecureStore(namespace: namespace);
    await store.write('access', 'existing-access');
    final key = storage.getItem('$namespace.encryption_key');
    await createSecureStore(namespace: namespace)
        .write('refresh', 'new-refresh');
    expect(storage.getItem('$namespace.encryption_key'), key);
    expect(await store.read('access'), 'existing-access');
  });
}
