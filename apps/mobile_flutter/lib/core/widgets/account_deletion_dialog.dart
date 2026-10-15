import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../api/api_client.dart';
import '../services/app_preferences.dart';
import '../utils/location_session.dart';
import '../utils/error_message_ru.dart';
import '../utils/localization_service.dart';

String _t(String ru, String kk) => LocalizationService.translate(ru, kk);

Future<void> showAccountDeletion(BuildContext context, ApiClient api) async {
  var filesPending = false;
  final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AccountDeletionDialog(
          api: api, onFilesPending: (value) => filesPending = value));
  if (deleted != true) return;
  await api.clearTokens();
  await Future.wait([
    AppPreferences.clearOrderDraft(),
    AppPreferences.clearOrderCity(),
    AppPreferences.clearCurrentCityId(),
    AppPreferences.clearCurrentCityName(),
    AppPreferences.clearDeletedAccountState(),
    AppPreferences.clearPendingReferralCode()
  ]);
  sharedLocationSession.clear();
  if (!context.mounted) return;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
            title: Text(_t('Аккаунт удалён', 'Аккаунт жойылды')),
            content: Text(_t(
                filesPending
                    ? 'Аккаунт удалён. Очистка документов выполняется автоматически. Войти в прежний аккаунт больше нельзя.'
                    : 'Ваш аккаунт удалён. Войти в прежний аккаунт больше нельзя. Обязательные финансовые записи хранятся отдельно в пределах требований закона.',
                filesPending
                    ? 'Аккаунт жойылды. Құжаттар автоматты түрде жойылады. Бұрынғы аккаунтқа енді кіру мүмкін емес.'
                    : 'Аккаунтыңыз жойылды. Бұрынғы аккаунтқа енді кіру мүмкін емес. Заң бойынша міндетті қаржылық жазбалар бөлек сақталады.')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(_t('Понятно', 'Түсінікті')))
            ],
          ));
  if (context.mounted) context.go('/login');
}

class AccountDeletionDialog extends StatefulWidget {
  const AccountDeletionDialog(
      {super.key, required this.api, this.onFilesPending});
  final ApiClient api;
  final ValueChanged<bool>? onFilesPending;
  @override
  State<AccountDeletionDialog> createState() => _AccountDeletionDialogState();
}

class _AccountDeletionDialogState extends State<AccountDeletionDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api
          .post('/auth/delete-account', data: {'password': _password.text});
      if (result.data is! Map || result.data['deleted'] != true) {
        throw StateError('Удаление не подтверждено');
      }
      if (mounted) {
        widget.onFilesPending?.call(result.data['filesPending'] == true);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessageRu(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_t('Удалить аккаунт?', 'Аккаунтты жою керек пе?')),
        content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(_t(
                  'Удаление необратимо. Будут удалены профиль, личные данные, документы и сохранённые карты. Минимальные обязательные финансовые записи и защищённый ИИН для учтённого дохода хранятся отдельно по требованиям закона.',
                  'Жою қайтымсыз. Профиль, жеке деректер, құжаттар және сақталған карталар жойылады. Есепке алынған табыс бойынша заңға сай міндетті қаржылық жазбалар мен қорғалған ЖСН бөлек сақталады.')),
              const SizedBox(height: 12),
              Text(_t(
                  'Перед удалением завершите поездку и при необходимости выведите деньги с баланса. Бонусы акций не выводятся. Реферальный денежный доход доступен к выводу при достижении порога.',
                  'Жоймас бұрын сапарды аяқтап, қажет болса баланстан ақшаны шығарыңыз. Акция бонустары шығарылмайды. Рефералдық ақшалай табыс шекке жеткенде шығаруға қолжетімді.')),
              const SizedBox(height: 16),
              TextField(
                  key: const ValueKey('account-delete-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                      labelText: _t('Пароль аккаунта', 'Аккаунт құпиясөзі'))),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent))),
            ])),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(_t('Отмена', 'Болдырмау'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: _busy || _password.text.isEmpty ? null : _delete,
              child: Text(_busy
                  ? _t('Удаляем…', 'Жойылуда…')
                  : _t('Удалить навсегда', 'Біржола жою')))
        ],
      ));
}
