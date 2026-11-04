import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../utils/error_message_ru.dart';

Future<void> showPasswordChangeDialog(
    BuildContext context, ApiClient api) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PasswordChangeDialog(api: api),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Пароль изменён. Остальные сессии завершены.')),
    );
  }
}

class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({super.key, required this.api});
  final ApiClient api;
  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_current.text.isEmpty ||
        _next.text.length < 12 ||
        utf8.encode(_next.text).length > 72 ||
        _next.text != _confirm.text ||
        _current.text == _next.text) {
      setState(() => _error =
          'Введите текущий пароль и новый пароль от 12 символов (до 72 байт). Повтор должен совпадать, новый пароль должен отличаться.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.post('/auth/change-password', data: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      await widget.api.setTokens(result.data['accessToken'] as String,
          result.data['refreshToken'] as String);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessageRu(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: const Text('Сменить пароль'),
          content: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Новый пароль — от 12 символов. После смены пароля другие устройства выйдут из аккаунта.'),
              TextField(
                  controller: _current,
                  obscureText: true,
                  enabled: !_saving,
                  decoration:
                      const InputDecoration(labelText: 'Текущий пароль')),
              TextField(
                  controller: _next,
                  obscureText: true,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Новый пароль')),
              TextField(
                  controller: _confirm,
                  obscureText: true,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                      labelText: 'Повторите новый пароль')),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ],
          )),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Сохраняем…' : 'Сохранить пароль')),
          ],
        ),
      );
}
