import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/widgets/ic_premium.dart';

class DriverEarningsPage extends StatefulWidget {
  const DriverEarningsPage({super.key, this.apiClient});
  final ApiClient? apiClient;

  @override
  State<DriverEarningsPage> createState() => _DriverEarningsPageState();
}

class _DriverEarningsPageState extends State<DriverEarningsPage> {
  late final _api = widget.apiClient ?? ApiClient();
  late final DateTime _currentMonth;
  late DateTime _month;
  String _currency = 'KZT', _error = '';
  Map<String, dynamic>? _summary;
  bool _loading = true;
  int _request = 0;
  static const _months = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  String get _period =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  String get _symbol => _currency == 'RUB' ? '₽' : '₸';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    _currentMonth = DateTime(now.year, now.month);
    _month = _currentMonth;
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = '';
      _summary = null;
    });
    try {
      final response = await _api.get('/driver/earnings',
          queryParameters: {'period': _period, 'currency': _currency});
      if (!mounted || request != _request) return;
      setState(() => _summary = Map<String, dynamic>.from(response.data));
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = errorMessageRu(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  String _money(dynamic value) {
    final amount = double.tryParse('${value ?? 0}') ?? 0;
    final parts = amount.toStringAsFixed(2).split('.');
    final whole = parts[0]
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
    return '$whole,${parts[1]} $_symbol';
  }

  Widget _row(String label, dynamic amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
            flex: 2,
            child: Text(_money(amount),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700))),
      ]));

  Widget _section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ICCard(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ...children,
          ])));

  @override
  Widget build(BuildContext context) {
    final data = _summary;
    final tax = Map<String, dynamic>.from(data?['tax'] as Map? ?? {});
    final trips = data?['trips'] as Map? ?? {};
    final profile = data?['profile'] as Map?;
    final social = tax['showSocialPayments'] == true;
    final incomplete = social &&
        ((tax['unaccountedTrips'] as num? ?? 0) > 0 || tax['enabled'] != true);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Заработок'),
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => goBackOr(context, fallback: '/driver/profile'))),
      body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                IconButton(
                    tooltip: 'Предыдущий месяц',
                    onPressed: _month.year > 2000 || _month.month > 1
                        ? () => _changeMonth(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                    child: Text('${_months[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                    tooltip: 'Следующий месяц',
                    onPressed: _month.isBefore(_currentMonth)
                        ? () => _changeMonth(1)
                        : null,
                    icon: const Icon(Icons.chevron_right)),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'KZT', label: Text('Тенге · ₸')),
                    ButtonSegment(value: 'RUB', label: Text('Рубли · ₽')),
                  ],
                  selected: {
                    _currency
                  },
                  onSelectionChanged: (value) {
                    setState(() => _currency = value.first);
                    _load();
                  }),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              if (_error.isNotEmpty)
                _section('Не удалось загрузить заработок', [
                  Text(_error),
                  TextButton(onPressed: _load, child: const Text('Повторить')),
                ]),
              if (data != null) ...[
                _section(
                    incomplete
                        ? 'Предварительный итог'
                        : social
                            ? 'После комиссии и соцплатежей'
                            : 'После комиссии',
                    [
                      Text(
                          _money(
                              social ? data['net'] : data['afterCommission']),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(
                          'Завершено поездок: ${trips['total']} · город: ${trips['city']}, межгород: ${trips['intercity']}'),
                      if (trips['total'] == 0)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'За этот месяц завершённых поездок пока нет.')),
                      if (incomplete)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'Налоговый учёт неполный. Итог изменится после учёта социальных платежей.')),
                    ]),
                _section('Доход и комиссия по поездкам', [
                  _row('Стоимость завершённых поездок', data['gross']),
                  _row('Наличные и перевод', data['cash']),
                  _row('Зачислено с банковских карт', data['card']),
                  _row('Ожидает оплаты картой', data['pendingCard']),
                  if ((double.tryParse('${data['refundedCard']}') ?? 0) > 0)
                    _row('Возвращено по картам', data['refundedCard']),
                  const Divider(),
                  _row('Комиссия сервиса', data['commission']),
                  if (social)
                    _row('Начисленные соцплатежи по этим поездкам',
                        tax['rideAccrued']),
                  const SizedBox(height: 8),
                  const Text(
                      'Комиссия — фактические списания по завершённым поездкам, включая плату за принятие межгородских заявок. '
                      'Наличные учитываются по сумме поездки; неоплаченные карты не входят в итог. Это не баланс для вывода.'),
                  if ((trips['legacyDates'] as num? ?? 0) > 0)
                    const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                            'У старых поездок без даты завершения используется дата последнего изменения.')),
                ]),
                if (social)
                  _section('Налоги и социальные платежи', [
                    const Text(
                        'На СНР для самозанятых ИПН — 0% при соблюдении условий режима. Ниже — учтённые социальные платежи.'),
                    if (tax['enabled'] != true)
                      const Text(
                          'Операторский учёт социальных платежей не включён.'),
                    _row('ОПВ · пенсионные взносы', tax['opv']),
                    _row('ОПВР · взносы работодателя', tax['opvr']),
                    _row('СО · социальные отчисления', tax['so']),
                    _row('ОСМС · медстрахование', tax['osms']),
                    const Divider(),
                    _row('Всего начислено', tax['accrued']),
                    _row('Удержано платформой', tax['withheld']),
                    _row('Осталось удержать', tax['debt']),
                    _row(
                        'Перечислено по платёжным документам', tax['remitted']),
                    _row('Осталось перечислить', tax['payable']),
                    _row('В начислениях — реферальные соцплатежи',
                        tax['referralAccrued']),
                    if ((tax['reviewCount'] as num? ?? 0) > 0)
                      Text(
                          'Ожидают налогового учёта: ${tax['reviewCount']} начислений, ${_money(tax['reviewGross'])} дохода.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Суммы взяты из налогового реестра за месяц, включая реферальный доход. '
                        'Удержание не означает перечисление. В итог поездок выше включены только соцплатежи по этим поездкам.'),
                  ])
                else
                  _section('Налоговый статус', [
                    Text(profile?['kind'] == 'IE'
                        ? 'Индивидуальный предприниматель'
                        : profile?['kind'] == 'INDIVIDUAL'
                            ? 'Физическое лицо'
                            : 'Социальные платежи самозанятого для этой валюты или статуса не рассчитаны.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Личные налоги по своему режиму вы рассчитываете самостоятельно в предусмотренных законом случаях. '
                        'Они не вычитаются из показанного итога автоматически.'),
                  ]),
                const Text(
                    'Месяц считается по времени Казахстана (UTC+5). Тенге и рубли учитываются отдельно.'),
              ],
            ],
          )),
    );
  }
}
