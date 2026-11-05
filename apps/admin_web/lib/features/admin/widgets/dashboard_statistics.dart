import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';

class DashboardStatistics extends StatefulWidget {
  const DashboardStatistics({super.key});
  @override
  State<DashboardStatistics> createState() => _DashboardStatisticsState();
}

class _DashboardStatisticsState extends State<DashboardStatistics> {
  String _period = '24h';
  DateTimeRange? _custom;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  int _request = 0;
  static const _modes = {
    'CITY_FIXED': 'Город',
    'CITY': 'Город',
    'CITY_AUCTION': 'Аукцион',
    'INTERCITY': 'Межгород',
    'CARGO': 'Грузовые',
    'DELIVERY': 'Доставка',
    'DELIVERY_CITY': 'Доставка по городу',
    'DELIVERY_INTERCITY': 'Междугородняя доставка',
    'DELIVERY_RF': 'Доставка по РФ'
  };
  static const _statuses = {
    'CREATED': 'Создан',
    'SEARCHING_DRIVER': 'Поиск водителя',
    'OPEN': 'Поиск предложений',
    'ACCEPTED': 'Водитель выбран',
    'DRIVER_ASSIGNED': 'Водитель назначен',
    'DRIVER_EN_ROUTE': 'Водитель едет',
    'DRIVER_ARRIVED': 'Водитель прибыл',
    'IN_PROGRESS': 'В пути',
    'COMPLETED': 'Завершён',
    'CANCELLED': 'Отменён',
    'EXPIRED': 'Истёк',
    'REJECTED': 'Отклонён'
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _time(dynamic value) {
    final d =
        DateTime.tryParse('$value')?.toUtc().add(const Duration(hours: 5));
    return d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      final response = await AdminApiClient.instance
          .get('/admin/dashboard/statistics', query: {
        'period': _period,
        if (_period == 'custom' && _custom != null) ...{
          'from': _date(_custom!.start),
          'to': _date(_custom!.end)
        }
      });
      if (!mounted || id != _request) {
        return;
      }
      setState(() => _data = Map<String, dynamic>.from(response.data as Map));
    } catch (_) {
      if (mounted && id == _request) {
        setState(() =>
            _error = 'Не удалось загрузить статистику. Повторите попытку.');
      }
    } finally {
      if (mounted && id == _request) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(String period) async {
    if (period == 'custom') {
      final now = DateTime.now().toUtc().add(const Duration(hours: 5));
      final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year, now.month, now.day),
          initialDateRange: _custom,
          helpText: 'Период статистики · UTC+5',
          saveText: 'Применить');
      if (picked == null || !mounted) {
        return;
      }
      if (picked.end.difference(picked.start).inDays >= 366) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Максимальный период — 366 дней')));
        return;
      }
      _custom = picked;
    }
    setState(() => _period = period);
    await _load();
  }

  Widget _section(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            ...children
          ])));
  Map<String, dynamic> get _rangeQuery =>
      {'from': _data?['range']?['from'], 'to': _data?['range']?['to']};
  void _open(String route, Map<String, dynamic> query) => Navigator.pushNamed(
      context,
      Uri(path: route, queryParameters: query.map((k, v) => MapEntry(k, '$v')))
          .toString());
  Widget _metric(String label, dynamic value,
          {String? route, Map<String, dynamic> query = const {}}) =>
      InkWell(
          onTap: route == null ? null : () => _open(route, query),
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
              width: 185,
              child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .06),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$value',
                            style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 4),
                        Text(label)
                      ]))));
  List<dynamic> _list(String key) => (_data?[key] as List?) ?? [];
  Widget _table(List<String> headers, List<List<String>> rows,
          {void Function(int)? onRowTap}) =>
      rows.isEmpty
          ? const Text('За выбранный период данных нет.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                  columns:
                      headers.map((h) => DataColumn(label: Text(h))).toList(),
                  showCheckboxColumn: false,
                  rows: rows
                      .asMap()
                      .entries
                      .map((entry) => DataRow(
                          onSelectChanged: onRowTap == null
                              ? null
                              : (_) => onRowTap(entry.key),
                          cells: entry.value
                              .map((c) => DataCell(Text(c)))
                              .toList()))
                      .toList()));
  String _money(dynamic v) => (v is num ? v : 0).toStringAsFixed(2);
  @override
  Widget build(BuildContext context) {
    final users = (_data?['users'] as Map?) ?? {},
        orders = (_data?['orders'] as Map?) ?? {},
        drivers = (_data?['drivers'] as Map?) ?? {};
    final modeRows = <Map<String, dynamic>>[
      for (final mode in [
        'CITY_FIXED',
        'CITY_AUCTION',
        'INTERCITY',
        'CARGO',
        'DELIVERY_CITY',
        'DELIVERY_INTERCITY',
        'DELIVERY_RF'
      ])
        _list('byMode')
                .where((r) => r['mode'] == mode)
                .map((r) => Map<String, dynamic>.from(r as Map))
                .firstOrNull ??
            {
              'mode': mode,
              'total': 0,
              'completed': 0,
              'cancelled': 0,
              'active': 0,
              'expired': 0
            },
      for (final row in _list('byMode'))
        if (![
          'CITY_FIXED',
          'CITY_AUCTION',
          'INTERCITY',
          'CARGO',
          'DELIVERY_CITY',
          'DELIVERY_INTERCITY',
          'DELIVERY_RF'
        ].contains(row['mode']))
          Map<String, dynamic>.from(row as Map),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _section('Статистика приложения', [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final entry in const {
            '24h': 'Последние сутки',
            'today': 'Сегодня',
            'week': '7 дней',
            'month': '30 дней',
            'custom': 'Выбрать период'
          }.entries)
            ChoiceChip(
                label: Text(entry.value),
                selected: _period == entry.key,
                onSelected: (_) => _select(entry.key)),
          IconButton(
              tooltip: 'Обновить статистику',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        const SizedBox(height: 10),
        const Text(
            'Все даты — UTC+5. Неделя и месяц включают сегодня. Заказы отбираются по дате создания; статус — на момент обновления.'),
        if (_period == 'custom' && _custom != null)
          Text(
              '${_date(_custom!.start)} — ${_date(_custom!.end)} включительно'),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (_error != null) ...[
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: _load, child: const Text('Повторить загрузку'))
        ],
      ]),
      if (_data != null) ...[
        _section('Новые пользователи за период', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _metric('Всего регистраций', users['newTotal'] ?? 0,
                route: '/users', query: _rangeQuery),
            _metric('Пассажиры', users['newPassengers'] ?? 0,
                route: '/users', query: {..._rangeQuery, 'kind': 'passenger'}),
            _metric('Водители', users['newDrivers'] ?? 0,
                route: '/drivers', query: _rangeQuery),
            _metric('Новые анкеты водителей', drivers['newProfiles'] ?? 0,
                route: '/drivers',
                query: {..._rangeQuery, 'profileCreated': 'true'})
          ]),
          const SizedBox(height: 10),
          const Text(
              'Водитель — пользователь с анкетой водителя или ролью водителя. Остальные пользователи — пассажиры. Администраторы не учитываются. Новая анкета может принадлежать ранее зарегистрированному пользователю.'),
        ]),
        _section('Заказы и поездки за период', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _metric('Создано заказов', orders['total'] ?? 0,
                route: '/trip-register', query: _rangeQuery),
            _metric('Завершено из этих заказов', orders['completed'] ?? 0,
                route: '/trip-register',
                query: {..._rangeQuery, 'status': 'COMPLETED'}),
            _metric(
                'Поездок завершено за период', _data!['completedInPeriod'] ?? 0,
                route: '/trip-register',
                query: {..._rangeQuery, 'completedInPeriod': 'true'}),
            _metric('Отменено', orders['cancelled'] ?? 0,
                route: '/trip-register',
                query: {..._rangeQuery, 'status': 'CANCELLED'}),
            _metric('Активных из периода', orders['active'] ?? 0,
                route: '/trip-register',
                query: {..._rangeQuery, 'status': 'ACTIVE'}),
            _metric('Истекло / отклонено', orders['expired'] ?? 0,
                route: '/trip-register',
                query: {..._rangeQuery, 'status': 'EXPIRED_GROUP'}),
            _metric('Заказавших пассажиров', orders['uniquePassengers'] ?? 0,
                route: '/users', query: {..._rangeQuery, 'hasOrders': 'true'})
          ]),
          const SizedBox(height: 16),
          _table([
            'Режим',
            'Заказов',
            'Завершено',
            'Отменено',
            'Активно',
            'Истекло'
          ], [
            for (final row in modeRows)
              [
                _modes[row['mode']] ?? '${row['mode']}',
                '${row['total']}',
                '${row['completed']}',
                '${row['cancelled']}',
                '${row['active']}',
                '${row['expired']}'
              ]
          ],
              onRowTap: (i) => _open('/trip-register',
                  {..._rangeQuery, 'mode': modeRows[i]['mode']})),
        ]),
        _section('Суммы по валютам', [
          if ((_data!['missingCompletionDates'] as num? ?? 0) > 0)
            Text(
                'Старых заказов без даты завершения: ${_data!["missingCompletionDates"]}. Они не включены в суммы по дате завершения.'),
          const Text(
              'Стоимость поездок, завершённых в выбранном периоде, включая заказы, созданные ранее. Это стоимость услуг, а не выручка платформы. Комиссии — фактические списания за период, включая принятие межгородских заявок.'),
          _table([
            'Валюта',
            'Стоимость завершённых заказов',
            'Комиссии сервиса'
          ], [
            for (final currency in {
              ..._list('finance').map((r) => r['currency']),
              ..._list('commissions').map((r) => r['currency'])
            })
              [
                '$currency',
                _money(_list('finance')
                    .where((r) => r['currency'] == currency)
                    .map((r) => r['turnover'])
                    .firstOrNull),
                _money(_list('commissions')
                    .where((r) => r['currency'] == currency)
                    .map((r) => r['amount'])
                    .firstOrNull)
              ]
          ]),
        ]),
        _section('Пользовательская база и водители сейчас', [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _metric('Активных заказов сейчас', _data!['activeOrdersNow'] ?? 0,
                route: '/trip-register', query: {'status': 'ACTIVE'}),
            _metric('Всего пользователей', users['total'] ?? 0,
                route: '/users'),
            _metric('Всего пассажиров', users['passengers'] ?? 0,
                route: '/users', query: {'kind': 'passenger'}),
            _metric('Всего водителей', users['drivers'] ?? 0,
                route: '/drivers'),
            _metric('Водители онлайн', drivers['online'] ?? 0,
                route: '/drivers', query: {'online': 'true'}),
            _metric('Анкеты одобрены', drivers['approved'] ?? 0,
                route: '/drivers', query: {'approved': 'true'}),
            _metric('Анкеты на проверке', drivers['pending'] ?? 0,
                route: '/drivers', query: {'driverStatus': 'PENDING'})
          ]),
          const SizedBox(height: 10),
          const Text(
              'Эти показатели текущие и не ограничены выбранным периодом.'),
        ]),
        _section('Динамика по дням', [
          SizedBox(
              height: 200,
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final day in _list('daily'))
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Tooltip(
                                  message:
                                      '${day['date']}: регистрации ${day['users']}, заказы ${day['orders']}',
                                  child: SizedBox(
                                      width: 70,
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Text(
                                                '${day['users']} / ${day['orders']}'),
                                            const SizedBox(height: 4),
                                            Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Container(
                                                      width: 18,
                                                      height:
                                                          _bar(day['users']),
                                                      color: Colors.deepPurple),
                                                  const SizedBox(width: 4),
                                                  Container(
                                                      width: 18,
                                                      height:
                                                          _bar(day['orders']),
                                                      color: Colors.teal)
                                                ]),
                                            const SizedBox(height: 5),
                                            Text('${day['date']}'.substring(5),
                                                style: const TextStyle(
                                                    fontSize: 11))
                                          ]))))
                      ]))),
          const SizedBox(height: 10),
          const Text(
              'Фиолетовый — регистрации. Зелёный — заказы. Числа над столбцами: регистрации / заказы.'),
        ]),
        _section('Последние 10 заказов выбранного периода', [
          _table([
            'Создан · UTC+5',
            'Режим',
            'Маршрут',
            'Статус',
            'Стоимость'
          ], [
            for (final row in _list('recentOrders'))
              [
                _time(row['createdAt']),
                _modes[row['mode']] ?? '${row['mode']}',
                '${row['origin']} → ${row['destination']}',
                _statuses[row['status']] ?? '${row['status']}',
                '${_money(row['price'])} ${row['currency']}'
              ]
          ],
              onRowTap: (i) => _open(
                  '/trip-register', {'id': _list('recentOrders')[i]['id']}))
        ]),
        _section('Последние 10 регистраций выбранного периода', [
          _table([
            'Зарегистрирован · UTC+5',
            'Имя',
            'Телефон',
            'Категория'
          ], [
            for (final row in _list('recentUsers'))
              [
                _time(row['createdAt']),
                '${row['name']}',
                '${row['phone']}',
                row['driver'] == true ? 'Водитель' : 'Пассажир'
              ]
          ],
              onRowTap: (i) => Navigator.pushNamed(
                  context, '/person/${_list('recentUsers')[i]['id']}'))
        ]),
      ],
    ]);
  }

  double _bar(dynamic value) {
    final maximum = _list('daily').fold<num>(
        1,
        (m, r) => [m, r['users'] as num, r['orders'] as num]
            .reduce((a, b) => a > b ? a : b));
    return 2 + ((value as num) / maximum) * 115;
  }
}
