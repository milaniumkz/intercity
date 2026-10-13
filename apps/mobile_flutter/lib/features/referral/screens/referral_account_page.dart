import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';
import '../widgets/referral_profile_card.dart';
import '../widgets/tax_status_panel.dart';

class ReferralAccountPage extends StatefulWidget {
  const ReferralAccountPage({super.key, this.apiClient});
  final ApiClient? apiClient;
  @override
  State<ReferralAccountPage> createState() => _ReferralAccountPageState();
}

class _ReferralAccountPageState extends State<ReferralAccountPage> {
  late final _api = widget.apiClient ?? ApiClient();
  Map<String, dynamic>? _summary;
  String _error = '';
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _api.get('/tax/me');
      if (mounted) {
        setState(() {
          _summary = Map<String, dynamic>.from(response.data);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessageRu(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _amount(dynamic value) =>
      (double.tryParse('$value') ?? 0).toStringAsFixed(2);
  Future<void> _withdraw() async {
    final amount =
        TextEditingController(text: _amount(_summary?['referralBalance']));
    final card = TextEditingController();
    var saving = false;
    String error = '';
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Вывести реферальный доход'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        'Минимум ${_amount(_summary?['minPayout'])} тг. Бонусы акций не выводятся.'),
                    TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Сумма, тг')),
                    TextField(
                        controller: card,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Номер карты')),
                    if (error.isNotEmpty)
                      Text(error,
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                update(() => saving = true);
                                try {
                                  final response = await _api
                                      .post('/wallet/payout-request', data: {
                                    'source': 'REFERRAL',
                                    'currency': 'KZT',
                                    'amount': double.tryParse(
                                        amount.text.replaceAll(',', '.')),
                                    'cardNumber': card.text
                                  });
                                  if (!ctx.mounted) {
                                    return;
                                  }
                                  Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '${response.data['message'] ?? 'Заявка на вывод создана'}')));
                                    await _load();
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    update(() {
                                      error = errorMessageRu(e);
                                      saving = false;
                                    });
                                  }
                                }
                              },
                        child: Text(saving ? 'Отправляем…' : 'Создать заявку'))
                  ],
                )));
    amount.dispose();
    card.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _summary?['profile'] as Map?;
    final verified = profile?['status'] == 'VERIFIED';
    final income = (_summary?['income'] as List?) ?? [];
    return Scaffold(
        appBar: AppBar(title: const Text('Реферальная система')),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Приглашайте. Получайте доход.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Вознаграждение за завершённые поездки ваших друзей — в отдельном денежном балансе.'),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Text(_error),
                          TextButton(
                              onPressed: _load, child: const Text('Повторить'))
                        ]))),
              if (_summary != null && _summary!['enabled'] != true)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Денежный учёт готовится к запуску. Пока действуют прежние бонусы; перечисление социальных платежей ещё не включено.'))),
              if (profile != null)
                Card(
                    child: ListTile(
                        leading: Icon(verified
                            ? Icons.verified_outlined
                            : Icons.schedule),
                        title: Text(profile['kind'] == 'IE'
                            ? 'Индивидуальный предприниматель'
                            : 'Самозанятый'),
                        subtitle: Text(verified
                            ? 'Статус подтверждён · Казахстан'
                            : profile['status'] == 'REJECTED'
                                ? 'Нужны уточнения: ${profile['verificationReference'] ?? ''}'
                                : 'Статус на проверке · ИИН •••• ${profile['iinLast4']}'))),
              if (_summary != null && profile != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Доступно к выводу'),
                              const SizedBox(height: 6),
                              Text(
                                  '${_amount(_summary!['referralBalance'])} тг',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium),
                              const SizedBox(height: 6),
                              Text(
                                  'Порог вывода: ${_amount(_summary!['minPayout'])} тг'),
                              if ((double.tryParse(
                                          '${_summary!['pendingReferral']}') ??
                                      0) >
                                  0)
                                Text(
                                    'Ожидают подтверждения: ${_amount(_summary!['pendingReferral'])} тг'),
                              const SizedBox(height: 12),
                              SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                      onPressed: verified &&
                                              (double.tryParse(
                                                          '${_summary!['referralBalance']}') ??
                                                      0) >=
                                                  (double.tryParse(
                                                          '${_summary!['minPayout']}') ??
                                                      5000)
                                          ? _withdraw
                                          : null,
                                      icon: const Icon(
                                          Icons.account_balance_outlined),
                                      label: const Text('Вывести на карту'))),
                              const Text(
                                  'Обычные бонусы и бонусы акций не доступны для вывода.'),
                            ]))),
              if (_summary != null && !verified)
                TaxStatusPanel(
                    apiClient: _api,
                    driver: _summary!['isDriver'] == true,
                    onSaved: _load),
              if (_summary != null)
                ReferralProfileCard(
                    user: const {},
                    apiClient: _api,
                    showLegacyTotals: _summary!['enabled'] != true),
              if (verified)
                TextButton.icon(
                    onPressed: () => showTaxGuide(context),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Как учитываются платежи')),
              if (income.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Начисления и удержания',
                    style: Theme.of(context).textTheme.titleLarge),
                ...income.take(20).map((item) => Card(
                    child: ListTile(
                        title: Text(
                            '${item['sourceKind'] == 'REFERRAL' ? 'Реферальный доход' : 'Поездка'} · ${_amount(item['gross'])} тг'),
                        subtitle: Text(item['status'] == 'ACCOUNTED'
                            ? 'Учтено · удержано ${_amount(item['withheld'])} тг'
                            : 'Ожидает проверки'),
                        trailing: Text('${item['period']}'))))
              ],
            ])));
  }
}
