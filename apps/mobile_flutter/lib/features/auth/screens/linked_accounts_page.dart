import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import '../../../core/api/api_client.dart';

class LinkedAccountsEntry extends StatelessWidget {
  const LinkedAccountsEntry({super.key});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.link),
    label: const Text('Аккаунты для восстановления'),
    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const LinkedAccountsPage())),
  );
}

class LinkedAccountsPage extends StatefulWidget {
  const LinkedAccountsPage({super.key});
  @override
  State<LinkedAccountsPage> createState() => _LinkedAccountsState();
}

class _LinkedAccountsState extends State<LinkedAccountsPage> {
  final api = ApiClient();
  Set<String>? linked;
  bool busy = false;
  String message = '';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final result = await api.get('/auth/recovery/links');
      final providers = Set<String>.from(result.data['providers'] as List);
      if (mounted) setState(() { linked = providers; message = ''; });
    } catch (_) {
      if (mounted) setState(() => message = 'Не удалось получить список аккаунтов.');
    }
  }

  Future<void> connect(String provider) async {
    final google = provider == 'GOOGLE';
    final client = google ? const String.fromEnvironment('GOOGLE_OIDC_CLIENT_ID') : const String.fromEnvironment('APPLE_OIDC_CLIENT_ID');
    final redirect = google ? const String.fromEnvironment('GOOGLE_OIDC_REDIRECT') : const String.fromEnvironment('APPLE_OIDC_REDIRECT');
    if (kIsWeb || client.isEmpty || redirect.isEmpty) {
      setState(() => message = 'Подключение пока недоступно на этом устройстве.');
      return;
    }
    String currentPassword = '';
    final approved = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Подтвердите пароль InterCity'),
      content: TextField(obscureText: true, onChanged: (v) => currentPassword = v),
      actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Продолжить'))],
    ));
    if (!mounted || approved != true || currentPassword.isEmpty) return;
    setState(() {busy = true; message = '';});
    try {
      final start = await api.post('/auth/recovery/link/start', data: {'provider': provider});
      final nonce = start.data['nonce'] as String;
      final result = await const FlutterAppAuth().authorizeAndExchangeCode(
        AuthorizationTokenRequest(client, redirect, issuer: google ? 'https://accounts.google.com' : 'https://appleid.apple.com',
          scopes: const ['openid'], nonce: nonce));
      if (result.idToken == null) throw StateError('missing token');
      await api.post('/auth/recovery/link/verify', data: {'provider':provider,'nonce':nonce,'idToken':result.idToken,'password':currentPassword});
      await load();
    } catch (_) {
      if (mounted) setState(() => message = 'Привязка не завершена. Проверьте пароль и повторите.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Аккаунты для восстановления')),
    body: ListView(children: [
      for (final provider in defaultTargetPlatform == TargetPlatform.iOS ? ['APPLE','GOOGLE'] : ['GOOGLE','APPLE'])
        ListTile(title: Text(provider == 'APPLE' ? 'Apple' : 'Google'),
          subtitle: Text(linked == null ? 'Проверяем подключение' : linked!.contains(provider) ? 'Подключён' : 'Не подключён'),
          trailing: TextButton(onPressed: linked == null || busy || linked!.contains(provider) ? null : () => connect(provider), child: const Text('Подключить'))),
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty) Text(message),
      if (linked == null && message.isNotEmpty) TextButton(onPressed: load, child: const Text('Повторить')),
    ]),
  );
}
