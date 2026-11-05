import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import '../../../core/utils/csv_export.dart';
import '../screens/admin_people_page.dart';

class FinanceDashboard extends StatefulWidget {
  const FinanceDashboard({super.key});
  @override
  State<FinanceDashboard> createState() => _FinanceDashboardState();
}

class _FinanceDashboardState extends State<FinanceDashboard> {
  String _period = 'today', _currency = 'KZT', _category = '';
  DateTimeRange? _custom;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _request = 0, _entryRequest = 0, _skip = 0, _total = 0;
  List<dynamic> _entries = [];
  static const categories = {
    'TOPUP': 'Реальные пополнения',
    'DEMO_TOPUP': 'Тестовые пополнения',
    'COMMISSION': 'Списанные комиссии',
    'PAYOUT_RESERVE': 'Заявки на вывод / резервирование',
    'REFUND': 'Возвраты',
    'BONUS_AWARD': 'Начисленные бонусы',
    'BONUS_SPENT': 'Списанные бонусы',
    'ADJUSTMENT': 'Ручные корректировки',
    'OTHER': 'Прочие операции'
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  Map<String, dynamic> get _range => {
        if (_data?['range']?['from'] != null) 'from': _data!['range']['from'],
        if (_data?['range']?['to'] != null) 'to': _data!['range']['to']
      };
  Future<void> _load() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r =
          await AdminApiClient.instance.get('/admin/finance-dashboard', query: {
        'period': _period,
        if (_period == 'custom' && _custom != null) ...{
          'from': _day(_custom!.start),
          'to': _day(_custom!.end)
        }
      });
      if (!mounted || id != _request) return;
      setState(() => _data = Map<String, dynamic>.from(r.data as Map));
      _skip = 0;
      await _loadEntries();
    } catch (e) {
      if (mounted && id == _request) setState(() => _error = recordError(e));
    } finally {
      if (mounted && id == _request) setState(() => _loading = false);
    }
  }

  Future<void> _loadEntries() async {
    final id = ++_entryRequest;
    try {
      final r =
          await AdminApiClient.instance.get('/admin/finance-entries', query: {
        ..._range,
        'currency': _currency,
        if (_category.isNotEmpty) 'category': _category,
        'skip': _skip,
        'take': 30
      });
      if (mounted && id == _entryRequest) {
        setState(() {
          _entries = r.data['items'] as List? ?? [];
          _total = (r.data['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (mounted && id == _entryRequest) {
        setState(() => _error = recordError(e));
      }
    }
  }

  Future<void> _periodChange(String value) async {
    if (value == 'custom') {
      final now = DateTime.now().toUtc().add(const Duration(hours: 5));
      final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year, now.month, now.day),
          helpText: 'Финансовый период · UTC+5',
          saveText: 'Применить',
          initialDateRange: _custom);
      if (picked == null) return;
      _custom = picked;
    }
    setState(() => _period = value);
    await _load();
  }

  void _show(String category) {
    setState(() {
      _category = category;
      _skip = 0;
    });
    _loadEntries();
  }

  void _trips(bool completed) {
    Navigator.pushNamed(
        context,
        Uri(path: '/trip-register', queryParameters: {
          ..._range.map((k, v) => MapEntry(k, '$v')),
          'currency': _currency,
          if (completed) 'completedInPeriod': 'true'
        }).toString());
  }

  Future<void> _export() async {
    final text =
        StringBuffer('Дата;Пользователь;Категория;Направление;Сумма;Валюта\n');
    String cell(dynamic v) =>
        '"${'$v'.replaceAll('"', '""').replaceFirst(RegExp(r'^[=+@-]'), "'")}"';
    for (final e in _entries) {
      text.writeln([
        recordTime(e['createdAt']),
        e['userName'],
        categories[e['category']] ?? e['type'],
        e['direction'] == 'CREDIT' ? 'Зачисление' : 'Списание',
        e['amount'],
        e['currency']
      ].map(cell).join(';'));
    }
    final downloaded = await exportCsv(text.toString(),
        filename: 'finance-${_currency.toLowerCase()}.csv');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(downloaded
              ? 'CSV скачан'
              : 'CSV готов и скопирован в буфер обмена')));
    }
  }

  Widget _tile(String title, String value, VoidCallback tap) => SizedBox(
      width: 230,
      child: Card(
          child: InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(title),
                        const SizedBox(height: 6),
                        const Text('Открыть подробности →',
                            style: TextStyle(fontSize: 12))
                      ])))));
  @override
  Widget build(BuildContext context) {
    final groups = (_data?['groups'] as List?) ?? [],
        trips = (_data?['trips'] as List?) ?? [];
    final trip = trips.where((r) => r['currency'] == _currency).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      recordSection(context, 'Период финансового отчёта', [
        Wrap(spacing: 12, runSpacing: 8, children: [
          for (final e in {
            'today': 'Сегодня',
            '24h': 'Последние сутки',
            'week': 'Неделя',
            'month': 'Месяц',
            'custom': 'Выбрать даты'
          }.entries)
            ChoiceChip(
                label: Text(e.value),
                selected: _period == e.key,
                onSelected: (_) => _periodChange(e.key)),
          OutlinedButton(
              onPressed: _loading ? null : _load, child: const Text('Обновить'))
        ]),
        const SizedBox(height: 10),
        Text(_data?['range'] == null
            ? ''
            : '${recordTime(_data!['range']['from'])} — ${recordTime(_data!['range']['to'])} · UTC+5, окончание не включается'),
        SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'KZT', label: Text('Тенге ₸')),
              ButtonSegment(value: 'RUB', label: Text('Рубли ₽'))
            ],
            selected: {
              _currency
            },
            onSelectionChanged: (v) {
              setState(() {
                _currency = v.first;
                _skip = 0;
              });
              _loadEntries();
            }),
        const SizedBox(height: 10),
        const Text(
            'Пополнения и комиссии считаются по фактическим операциям кошельков. Тестовые пополнения выделены отдельно. Оборот поездок — стоимость завершённых поездок, а не доход платформы. Резервирование вывода не означает банковскую выплату.'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]),
      recordSection(context, 'Заказы и оборот', [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _tile('Создано заказов', '${trip?['created'] ?? 0}',
              () => _trips(false)),
          _tile('Завершено поездок', '${trip?['completed'] ?? 0}',
              () => _trips(true)),
          _tile('Оборот завершённых поездок',
              recordMoney(trip?['turnover'], _currency), () => _trips(true))
        ]),
      ]),
      recordSection(context, 'Движение денег и бонусов', [
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final e in categories.entries)
            Builder(builder: (context) {
              final row = groups
                  .where((r) =>
                      r['currency'] == _currency && r['category'] == e.key)
                  .firstOrNull;
              return _tile('${e.value} · операций: ${row?['count'] ?? 0}',
                  recordMoney(row?['amount'], _currency), () => _show(e.key));
            })
        ]),
        const SizedBox(height: 12),
        Text(
            'Зачислено: ${recordMoney(groups.where((r) => r['currency'] == _currency).fold<num>(0, (s, r) => s + (r['credit'] as num? ?? 0)), _currency)} · Списано: ${recordMoney(groups.where((r) => r['currency'] == _currency).fold<num>(0, (s, r) => s + (r['debit'] as num? ?? 0)), _currency)}'),
        for (final payout in (_data?['payouts'] as List? ?? [])
            .where((r) => r['currency'] == _currency))
          Text(
              'Выплаты: ${recordStatuses[payout['status']] ?? payout['status']} · ${payout['_count']} · ${recordMoney(payout['_sum']?['amount'], _currency)} (по времени последнего изменения заявки)'),
      ]),
      recordSection(context, 'Операции за выбранный период: $_total', [
        Wrap(spacing: 12, children: [
          DropdownButton<String>(
              value: _category,
              items: [
                const DropdownMenuItem(value: '', child: Text('Все категории')),
                for (final e in categories.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value))
              ],
              onChanged: (v) => _show(v ?? '')),
          OutlinedButton(onPressed: _export, child: const Text('Экспорт CSV'))
        ]),
        const Text('CSV содержит текущую страницу найденных операций.'),
        if (_entries.isEmpty) const Text('За выбранный период операций нет.'),
        for (final e in _entries)
          ListTile(
              title: Text(
                  '${categories[e['category']] ?? e['type']} · ${recordMoney(e['amount'], e['currency'])}'),
              subtitle: Text(
                  '${recordTime(e['createdAt'])} · ${e['direction'] == 'CREDIT' ? 'Зачисление' : 'Списание'}\n${e['userName']} · ${e['userPhone']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/person',
                  arguments: {'id': e['userId']})),
        Row(children: [
          TextButton(
              onPressed: _skip == 0
                  ? null
                  : () {
                      _skip = (_skip - 30).clamp(0, 1 << 30);
                      _loadEntries();
                    },
              child: const Text('Назад')),
          Text('Показано ${_entries.length} из $_total'),
          TextButton(
              onPressed: _skip + 30 >= _total
                  ? null
                  : () {
                      _skip += 30;
                      _loadEntries();
                    },
              child: const Text('Далее'))
        ]),
      ]),
      recordSection(context, 'По дням · UTC+5', [
        for (final day in (_data?['days'] as List? ?? [])
            .where((r) => r['currency'] == _currency))
          ListTile(
              title: Text('${day['day']} · операций: ${day['count']}'),
              subtitle: Text(
                  'Зачислено ${recordMoney(day['credit'], _currency)} · Списано ${recordMoney(day['debit'], _currency)}'),
              onTap: () {
                final start = DateTime.parse('${day['day']}T00:00:00+05:00');
                _custom = DateTimeRange(
                    start: DateTime(
                        start.add(const Duration(hours: 5)).year,
                        start.add(const Duration(hours: 5)).month,
                        start.add(const Duration(hours: 5)).day),
                    end: DateTime(
                        start.add(const Duration(hours: 5)).year,
                        start.add(const Duration(hours: 5)).month,
                        start.add(const Duration(hours: 5)).day));
                setState(() => _period = 'custom');
                _load();
              })
      ]),
    ]);
  }
}
