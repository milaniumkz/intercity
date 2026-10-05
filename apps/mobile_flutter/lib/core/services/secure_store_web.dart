import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'secure_store_base.dart';

SecureStore createSecureStore({required String namespace}) {
  return _EncryptedBrowserSecureStore(namespace);
}

class _EncryptedBrowserSecureStore implements SecureStore {
  _EncryptedBrowserSecureStore(this._namespace);

  final String _namespace;

  web.Storage get _storage => web.window.localStorage;
  String get _encryptionKeyStorageKey => '$_namespace.encryption_key';

  @override
  Future<void> delete(String key) async {
    _storage.removeItem(_entryKey(key));
  }

  @override
  Future<String?> read(String key) async {
    final cipherText = _storage.getItem(_entryKey(key));
    return _decryptValue(cipherText, storageKey: key);
  }

  @override
  Future<void> write(String key, String value) async {
    final iv =
        (web.window.crypto.getRandomValues(Uint8List(12).toJS) as JSUint8Array)
            .toDart;
    final algorithm = _algorithm(iv);
    final encryptionKey = await _getEncryptionKey(algorithm);
    final encryptedContent = (await web.window.crypto.subtle
        .encrypt(
          algorithm,
          encryptionKey,
          Uint8List.fromList(utf8.encode(value)).toJS,
        )
        .toDart)! as JSArrayBuffer;

    _storage.setItem(
      _entryKey(key),
      '${base64Encode(iv)}.${base64Encode(encryptedContent.toDart.asUint8List())}',
    );
  }

  String _entryKey(String key) => '$_namespace.$key';

  JSAny _algorithm(Uint8List iv) =>
      <String, Object>{'name': 'AES-GCM', 'length': 256, 'iv': iv}.jsify()!;

  Future<web.CryptoKey> _getEncryptionKey(JSAny algorithm) async {
    final encodedKey = _storage.getItem(_encryptionKeyStorageKey);
    if (encodedKey != null && encodedKey.isNotEmpty) {
      final rawKey = base64Decode(encodedKey);
      return web.window.crypto.subtle
          .importKey(
            'raw',
            rawKey.toJS,
            algorithm,
            false,
            _cryptoUsages.toJS,
          )
          .toDart;
    }

    final encryptionKey = (await web.window.crypto.subtle
        .generateKey(algorithm, true, _cryptoUsages.toJS)
        .toDart)! as web.CryptoKey;
    final exported = await web.window.crypto.subtle
        .exportKey('raw', encryptionKey)
        .toDart as JSArrayBuffer;
    _storage.setItem(
      _encryptionKeyStorageKey,
      base64Encode(exported.toDart.asUint8List()),
    );
    return encryptionKey;
  }

  Future<String?> _decryptValue(
    String? cipherText, {
    required String storageKey,
  }) async {
    if (cipherText == null || cipherText.isEmpty) {
      return null;
    }

    try {
      final parts = cipherText.split('.');
      if (parts.length != 2) {
        throw const FormatException('Cipher payload is malformed.');
      }

      final iv = base64Decode(parts[0]);
      final encryptedValue = base64Decode(parts[1]);
      final decryptionKey = await _getEncryptionKey(_algorithm(iv));
      final decryptedContent = await web.window.crypto.subtle
          .decrypt(
            _algorithm(iv),
            decryptionKey,
            Uint8List.fromList(encryptedValue).toJS,
          )
          .toDart as JSArrayBuffer;

      return utf8.decode(decryptedContent.toDart.asUint8List());
    } catch (error, stackTrace) {
      _storage.removeItem(_entryKey(storageKey));
      if (kDebugMode) {
        debugPrint(
            'Failed to decrypt mobile secure value "$storageKey": $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }
}

const List<String> _cryptoUsages = <String>['encrypt', 'decrypt'];

extension on List<String> {
  JSArray<JSString> get toJS => <JSString>[...map((entry) => entry.toJS)].toJS;
}
