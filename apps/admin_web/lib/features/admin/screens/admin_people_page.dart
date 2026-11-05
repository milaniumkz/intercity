import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

const recordStatuses = {
  'PENDING': 'На проверке',
  'APPROVED': 'Одобрен',
  'ACTIVE': 'Активен',
  'REJECTED': 'Отклонён',
  'VERIFIED': 'Пройдена',
  'READY': 'Ожидает записи',
  'PROCESSING': 'Обрабатывается',
  'FAILED': 'Ошибка обработки',
  'REVIEW': 'Нужна проверка',
  'EXPIRED': 'Срок истёк',
  'CREATED': 'Создан',
  'SEARCHING_DRIVER': 'Поиск водителя',
  'OPEN': 'Поиск предложений',
  'ACCEPTED': 'Водитель выбран',
  'DRIVER_ASSIGNED': 'Водитель назначен',
  'DRIVER_EN_ROUTE': 'Водитель едет',
  'DRIVER_ARRIVED': 'Водитель прибыл',
  'IN_PROGRESS': 'В пути',
  'COMPLETED': 'Завершён',
  'CANCELLED': 'Отменён'
};
const recordModes = {
  'CITY': 'Городская поездка',
  'CITY_FIXED': 'Городская поездка',
  'CITY_AUCTION': 'Городской аукцион',
  'INTERCITY': 'Межгород',
  'CARGO': 'Грузовые',
  'DELIVERY': 'Доставка',
  'DELIVERY_CITY': 'Доставка по городу',
  'DELIVERY_INTERCITY': 'Междугородняя доставка',
  'DELIVERY_RF': 'Доставка по РФ'
};
String recordRole(Map user) => user['role'] == 'ADMIN'
    ? 'Администратор'
    : user['driverProfile'] != null || user['role'] == 'DRIVER'
        ? 'Водитель'
        : 'Пассажир';
String recordTime(dynamic raw) {
  final d = DateTime.tryParse('$raw')?.toUtc().add(const Duration(hours: 5));
  return d == null
      ? '—'
      : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String recordError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String &&
          message.length < 500 &&
          RegExp('[А-Яа-яЁё]').hasMatch(message)) {
        return message;
      }
    }
  }
  return 'Не удалось выполнить действие. Проверьте права доступа и соединение, затем повторите.';
}

String recordMoney(dynamic value, String currency) =>
    '${(num.tryParse('$value') ?? 0).toStringAsFixed(2)} ${currency == 'RUB' ? '₽' : '₸'}';
Widget recordSection(
        BuildContext context, String title, List<Widget> children) =>
    Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  ...children
                ])));
Widget recordLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Wrap(spacing: 12, children: [
      SizedBox(
          width: 180,
          child: Text(label, style: const TextStyle(color: Colors.blueGrey))),
      SelectableText(
          value == null || '$value'.isEmpty ? 'Не указано' : '$value')
    ]));
Future<String?> recordReason(BuildContext context, String title) async {
  String reason = '';
  return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
                  title: Text(title),
                  content: SizedBox(
                      width: 460,
                      child: TextField(
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (v) => update(() => reason = v),
                          decoration: const InputDecoration(
                              labelText: 'Причина действия',
                              helperText:
                                  'Не менее 5 символов. Сохранится в истории.'))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: reason.trim().length < 5
                            ? null
                            : () => Navigator.pop(dialog, reason.trim()),
                        child: const Text('Подтвердить'))
                  ])));
}

class AdminPeoplePage extends StatefulWidget {
  const AdminPeoplePage({super.key, this.drivers = false});
  final bool drivers;
  @override
  State<AdminPeoplePage> createState() => _AdminPeoplePageState();
}

class _AdminPeoplePageState extends State<AdminPeoplePage> {
  final _search = TextEditingController();
  Timer? _debounce;
  Map<String, dynamic> _filter = {};
  List<dynamic> _items = [];
  bool _loading = true, _initialized = false;
  String? _error;
  int _skip = 0, _total = 0, _request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _filter = {
        ...((ModalRoute.of(context)?.settings.arguments as Map?)
                ?.cast<String, dynamic>() ??
            {}),
        if (widget.drivers) 'kind': 'driver'
      };
      _search.text = '${_filter.remove('search') ?? ''}';
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AdminApiClient.instance.get('/admin/people', query: {
        ..._filter,
        'search': _search.text.trim(),
        'skip': _skip,
        'take': 30
      });
      if (mounted && request == _request) {
        setState(() {
          _items = r.data['items'] as List;
          _total = (r.data['total'] as num).toInt();
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = recordError(e));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _change(String key, dynamic value) {
    setState(() {
      if (value == null || value == '') {
        _filter.remove(key);
      } else {
        _filter[key] = value;
      }
      _skip = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: widget.drivers ? 'Водители' : 'Пользователи',
      subtitle: widget.drivers
          ? 'Все водители: одобренные, на проверке и отклонённые. Поиск по имени, телефону или автомобилю.'
          : 'Найдите человека по имени или телефону и откройте его карточку.',
      child: ListView(children: [
        recordSection(context, 'Поиск и фильтры', [
          TextField(
              controller: _search,
              decoration: InputDecoration(
                  labelText: widget.drivers
                      ? 'Имя, телефон, госномер или модель автомобиля'
                      : 'Имя или телефон',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      tooltip: 'Очистить поиск',
                      onPressed: () {
                        _search.clear();
                        _skip = 0;
                        _load();
                      },
                      icon: const Icon(Icons.close))),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  _skip = 0;
                  _load();
                });
              },
              onSubmitted: (_) {
                _skip = 0;
                _load();
              }),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, children: [
            if (!widget.drivers)
              DropdownButton<String>(
                  value: _filter['kind'] ?? '',
                  items: const [
                    DropdownMenuItem(
                        value: '', child: Text('Все пользователи')),
                    DropdownMenuItem(
                        value: 'passenger', child: Text('Пассажиры')),
                    DropdownMenuItem(value: 'driver', child: Text('Водители'))
                  ],
                  onChanged: (v) => _change('kind', v)),
            if (widget.drivers)
              DropdownButton<String>(
                  value: _filter['driverStatus'] ?? '',
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('Все статусы')),
                    for (final s in [
                      'PENDING',
                      'APPROVED',
                      'ACTIVE',
                      'REJECTED'
                    ])
                      DropdownMenuItem(
                          value: s, child: Text(recordStatuses[s]!))
                  ],
                  onChanged: (v) => _change('driverStatus', v)),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить')),
            if (_filter.containsKey('from'))
              InputChip(
                  label: const Text('Период с главной страницы'),
                  onDeleted: () {
                    _filter.remove('from');
                    _filter.remove('to');
                    _skip = 0;
                    _load();
                  })
          ]),
        ]),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          recordSection(context, 'Не удалось загрузить список', [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Повторить'))
          ]),
        recordSection(context, 'Найдено: $_total', [
          if (!_loading && _items.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'По этим условиям никто не найден. Попробуйте изменить поиск или убрать фильтры.')),
          for (final raw in _items)
            Builder(builder: (context) {
              final u = Map<String, dynamic>.from(raw as Map);
              final d = u['driverProfile'] as Map?;
              final name = '${u['name'] ?? 'Без имени'}';
              return Card(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      leading: CircleAvatar(
                          child: Icon(d == null
                              ? Icons.person_outline
                              : Icons.directions_car)),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${u['phone']} • ${u['city']?['name'] ?? 'Город не указан'}\n${d == null ? recordRole(u) : 'Водитель • ${recordStatuses[d['status']] ?? d['status']}'}${d == null ? '' : ' • ${d['carModel'] ?? 'Автомобиль не указан'} ${d['carNumber'] ?? ''}'}${u['blockedAt'] != null ? ' • Заблокирован' : ''}'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.pushNamed(context, '/person/${u['id']}')));
            }),
          const SizedBox(height: 12),
          Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_total == 0
                    ? 'Нет записей'
                    : '${_skip + 1}–${(_skip + _items.length).clamp(0, _total)} из $_total'),
                OutlinedButton(
                    onPressed: _loading || _skip == 0
                        ? null
                        : () {
                            _skip = (_skip - 30).clamp(0, _total);
                            _load();
                          },
                    child: const Text('Назад')),
                OutlinedButton(
                    onPressed: _loading || _skip + 30 >= _total
                        ? null
                        : () {
                            _skip += 30;
                            _load();
                          },
                    child: const Text('Далее'))
              ])
        ])
      ]));
}

class AdminPersonPage extends StatefulWidget {
  const AdminPersonPage({super.key, required this.userId});
  final String userId;
  @override
  State<AdminPersonPage> createState() => _AdminPersonPageState();
}

class _AdminPersonPageState extends State<AdminPersonPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r =
          await AdminApiClient.instance.get('/admin/people/${widget.userId}');
      if (mounted) {
        setState(() => _data = Map<String, dynamic>.from(r.data as Map));
      }
    } catch (e) {
      if (mounted) setState(() => _error = recordError(e));
    }
  }

  Future<void> _action(String path, Map<String, dynamic> data,
      {bool patch = false}) async {
    setState(() => _busy = true);
    try {
      if (patch) {
        await AdminApiClient.instance.patch(path, data: data);
      } else {
        await AdminApiClient.instance.post(path, data: data);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Изменения сохранены')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(recordError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final u = _data!['user'] as Map;
    String name = '${u['name']}', phone = '${u['phone']}', reason = '';
    String? cityId = u['cityId'];
    bool cityValid = true;
    final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Изменить данные пользователя'),
                    content: SizedBox(
                        width: 480,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextFormField(
                                  initialValue: name,
                                  onChanged: (v) => name = v,
                                  decoration:
                                      const InputDecoration(labelText: 'Имя')),
                              const SizedBox(height: 12),
                              TextFormField(
                                  initialValue: phone,
                                  onChanged: (v) => phone = v,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                      labelText: 'Телефон, начиная с +7')),
                              const SizedBox(height: 12),
                              Autocomplete<Map<String, dynamic>>(
                                  initialValue: TextEditingValue(
                                      text: '${u['city']?['name'] ?? ''}'),
                                  displayStringForOption: (o) =>
                                      '${o['name']} • ${o['countryCode']} ${o['region'] ?? ''}',
                                  optionsBuilder: (value) async {
                                    if (value.text.trim().length < 2) {
                                      return const <Map<String, dynamic>>[];
                                    }
                                    try {
                                      final r = await AdminApiClient.instance
                                          .get('/admin/people-cities', query: {
                                        'search': value.text.trim()
                                      });
                                      return r.data is List
                                          ? (r.data as List).map((x) =>
                                              Map<String, dynamic>.from(
                                                  x as Map))
                                          : const <Map<String, dynamic>>[];
                                    } catch (_) {
                                      return const <Map<String, dynamic>>[];
                                    }
                                  },
                                  onSelected: (o) => update(() {
                                        cityId = o['id'];
                                        cityValid = true;
                                      }),
                                  fieldViewBuilder: (context, controller, focus,
                                          submit) =>
                                      TextField(
                                          controller: controller,
                                          focusNode: focus,
                                          onChanged: (v) => update(() {
                                                cityValid = v.trim().isEmpty ||
                                                    v.trim() ==
                                                        '${u['city']?['name'] ?? ''}';
                                                if (v.trim().isEmpty) {
                                                  cityId = null;
                                                }
                                              }),
                                          decoration: InputDecoration(
                                              labelText:
                                                  'Город — выберите из подсказки',
                                              helperText: cityValid
                                                  ? null
                                                  : 'Выберите город из списка'))),
                              const SizedBox(height: 12),
                              TextField(
                                  onChanged: (v) => update(() => reason = v),
                                  decoration: const InputDecoration(
                                      labelText: 'Причина изменения',
                                      helperText:
                                          'При смене телефона пользователь войдёт заново.'))
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: reason.trim().length < 5 || !cityValid
                              ? null
                              : () => Navigator.pop(dialog, {
                                    'fields': {
                                      'name': name.trim(),
                                      'phone': phone.trim(),
                                      'cityId': cityId
                                    },
                                    'reason': reason.trim()
                                  }),
                          child: const Text('Сохранить'))
                    ])));
    if (values != null) {
      await _action('/admin/people/${widget.userId}', values, patch: true);
    }
  }

  Future<void> _editDriver() async {
    final d = _data!['user']['driverProfile'] as Map;
    String car = '${d['carModel'] ?? ''}',
        plate = '${d['carNumber'] ?? ''}',
        reason = '';
    final flags = <String, bool>{
      for (final key in [
        'acceptCityFixed',
        'acceptCityAuction',
        'acceptIntercity',
        'acceptDelivery',
        'acceptCargo'
      ])
        key: d[key] == true,
      'hasCheckers': d['priorityFlags']?['hasCheckers'] == true,
      'hasBranding': d['priorityFlags']?['hasBranding'] == true
    };
    final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Настройки водителя'),
                    content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextFormField(
                                  initialValue: car,
                                  onChanged: (v) => car = v,
                                  decoration: const InputDecoration(
                                      labelText: 'Марка и модель автомобиля')),
                              const SizedBox(height: 12),
                              TextFormField(
                                  initialValue: plate,
                                  onChanged: (v) => plate = v,
                                  decoration: const InputDecoration(
                                      labelText: 'Госномер')),
                              const SizedBox(height: 12),
                              const Text(
                                  'Изменение автомобиля потребует повторной сверки документов. Во время активной поездки менять автомобиль нельзя.'),
                              SwitchListTile(
                                  title: const Text('Городские поездки'),
                                  value: flags['acceptCityFixed'] == true ||
                                      flags['acceptCityAuction'] == true,
                                  onChanged: (v) => update(() {
                                        flags['acceptCityFixed'] = v;
                                        flags['acceptCityAuction'] = v;
                                      })),
                              for (final entry in {
                                'acceptIntercity': 'Межгород',
                                'acceptDelivery': 'Доставка',
                                'acceptCargo': 'Грузовые'
                              }.entries)
                                SwitchListTile(
                                    title: Text(entry.value),
                                    value: flags[entry.key]!,
                                    onChanged: (v) =>
                                        update(() => flags[entry.key] = v)),
                              for (final entry in {
                                'hasCheckers': 'Есть шашки',
                                'hasBranding': 'Есть брендирование'
                              }.entries)
                                SwitchListTile(
                                    title: Text(entry.value),
                                    value: flags[entry.key]!,
                                    onChanged: (v) =>
                                        update(() => flags[entry.key] = v)),
                              TextField(
                                  onChanged: (v) => update(() => reason = v),
                                  decoration: const InputDecoration(
                                      labelText: 'Причина изменения'))
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: reason.trim().length < 5
                              ? null
                              : () => Navigator.pop(dialog, {
                                    'fields': {
                                      ...flags,
                                      if (car.trim().isNotEmpty)
                                        'carModel': car.trim(),
                                      if (plate.trim().isNotEmpty)
                                        'carNumber': plate.trim()
                                    },
                                    'reason': reason.trim()
                                  }),
                          child: const Text('Сохранить'))
                    ])));
    if (values != null) {
      await _action('/admin/people/${widget.userId}/driver', values,
          patch: true);
    }
  }

  Future<void> _documents() async {
    setState(() => _busy = true);
    try {
      final r = await AdminApiClient.instance
          .get('/admin/people/${widget.userId}/documents');
      final docs = r.data as Map? ?? {};
      final images = <String, dynamic>{};
      for (final entry in {
        'selfieUrl': 'Фото водителя',
        'passportUrl': 'Удостоверение личности',
        'driverLicenseUrl': 'Водительское удостоверение',
        'techPassportFrontUrl': 'Техпаспорт — лицевая сторона',
        'techPassportBackUrl': 'Техпаспорт — оборотная сторона'
      }.entries) {
        final path = docs[entry.key]?.toString();
        if (path != null && path.startsWith('/api/driver/docs/files/')) {
          try {
            images[entry.value] = await AdminApiClient.instance
                .readPrivateBytes(path.substring(4));
          } catch (_) {
            images[entry.value] = null;
          }
        }
      }
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: const Text('Документы водителя'),
                  content: SizedBox(
                      width: 700,
                      child: SingleChildScrollView(
                          child: Column(children: [
                        if (images.isEmpty)
                          const Text(
                              'Доступных документов нового формата нет. Проверьте историю проверок и техническую панель.'),
                        for (final entry in images.entries)
                          Column(children: [
                            Text(entry.key),
                            const SizedBox(height: 8),
                            if (entry.value != null)
                              Image.memory(entry.value,
                                  height: 280,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Text('Предпросмотр недоступен'))
                            else
                              const Text('Документ недоступен или отклонён'),
                            const SizedBox(height: 20)
                          ])
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Закрыть'))
                  ]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(recordError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _block() async {
    final blocked = _data!['user']['blockedAt'] != null;
    final reason = await recordReason(
        context,
        blocked
            ? 'Разблокировать пользователя?'
            : 'Заблокировать пользователя?');
    if (reason != null) {
      await _action(
          '/admin/people/${widget.userId}',
          {
            'fields': {'blocked': !blocked},
            'reason': reason
          },
          patch: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _data?['user'] as Map?, d = u?['driverProfile'] as Map?;
    return AdminShell(
        title: u?['name'] ?? 'Карточка пользователя',
        subtitle: 'Профиль, заказы, операции и проверки — в одном месте.',
        child: ListView(children: [
          Wrap(spacing: 12, runSpacing: 8, children: [
            TextButton.icon(
                onPressed: () => Navigator.canPop(context)
                    ? Navigator.pop(context)
                    : Navigator.pushReplacementNamed(context, '/users'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('К списку')),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить')),
            if (u != null) ...[
              FilledButton.icon(
                  onPressed: _busy ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Изменить данные')),
              OutlinedButton(
                  onPressed: _busy ? null : _block,
                  child: Text(u['blockedAt'] == null
                      ? 'Заблокировать'
                      : 'Разблокировать'))
            ]
          ]),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!),
          if (u == null && _error == null) const LinearProgressIndicator(),
          if (u != null) ...[
            recordSection(context, '${u['name']} • ${recordRole(u)}', [
              recordLine('Телефон', u['phone']),
              recordLine('Город', u['city']?['name']),
              recordLine('Дата регистрации', recordTime(u['createdAt'])),
              recordLine('Доступ',
                  u['blockedAt'] == null ? 'Разрешён' : 'Заблокирован'),
              recordLine(
                  'Видеопроверка',
                  u['biometricProfile']?['status'] == 'VERIFIED'
                      ? 'Пройдена'
                      : 'Не пройдена'),
              if (d != null) ...[
                recordLine('Статус водителя',
                    recordStatuses[d['status']] ?? d['status']),
                recordLine('Автомобиль',
                    '${d['carModel'] ?? 'Не указан'} • ${d['carNumber'] ?? 'Номер не указан'}'),
                recordLine('На линии',
                    d['online']?['isOnline'] == true ? 'Да' : 'Нет'),
                recordLine('Причина отклонения', d['rejectionReason'])
              ]
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < 4; i++)
                ChoiceChip(
                    label:
                        Text(['Заказы', 'Операции', 'Рефералы', 'Проверки'][i]),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i))
            ]),
            const SizedBox(height: 16),
            if (_tab == 0) AdminTripList(userId: widget.userId),
            if (_tab == 1)
              recordSection(context, 'Кошелёк и операции', [
                if (_data!['permissions']['finance'] != true)
                  const Text('Нет доступа к финансовой информации.')
                else ...[
                  recordLine('Деньги, тенге',
                      recordMoney(_data!['wallet']?['money'], 'KZT')),
                  recordLine('Бонусы, тенге',
                      recordMoney(_data!['wallet']?['bonus'], 'KZT')),
                  recordLine('Деньги, рубли',
                      recordMoney(_data!['wallet']?['moneyRub'], 'RUB')),
                  recordLine('Реферальные средства',
                      recordMoney(_data!['wallet']?['referralMoney'], 'KZT')),
                  AdminRecordFeed(
                      path: '/admin/people/${widget.userId}/transactions')
                ]
              ]),
            if (_tab == 2)
              recordSection(context, 'Реферальная система', [
                recordLine('Код приглашения', _data!['referrals']['code']),
                recordLine('Приглашено людей', _data!['referrals']['invited']),
                AdminInviteList(userId: widget.userId),
                recordLine(
                    'Кто пригласил', _data!['referrals']['referrer']?['name']),
                if (_data!['referrals']['referrer'] != null)
                  TextButton(
                      onPressed: () => Navigator.pushNamed(context,
                          '/person/${_data!['referrals']['referrer']['id']}'),
                      child: const Text('Открыть пригласившего'))
              ]),
            if (_tab == 3)
              recordSection(context, 'Проверки личности', [
                const Text(
                    'Все попытки, причины ошибок и доступные записи находятся в истории проверок.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(
                        context, '/identity-history',
                        arguments: {'userId': widget.userId}),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Открыть историю проверок'))
              ]),
            if (d != null)
              recordSection(context, 'Работа водителя', [
                recordLine('Рейтинг',
                    '${d['rating']?['ratingAvg'] ?? 5} • оценок: ${d['rating']?['ratingCount'] ?? 0}'),
                recordLine(
                    'Оценка активности', d['serviceStats']?['activityScore']),
                recordLine('Топливный бонус до',
                    recordTime(d['fuelBonus']?['bonusActiveUntil'])),
                OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final reason = await recordReason(context,
                                'Включить топливный бонус на 24 часа?');
                            if (reason != null) {
                              await _action(
                                  '/admin/drivers/${d['id']}/fuel-bonus',
                                  {'hours': 24, 'reason': reason});
                            }
                          },
                    icon: const Icon(Icons.local_gas_station_outlined),
                    label: const Text('Топливный бонус на 24 часа')),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      onPressed: _busy ? null : _editDriver,
                      icon: const Icon(Icons.tune),
                      label: const Text('Настройки водителя')),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _documents,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Документы водителя'))
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in {
                    'Городские поездки': d['acceptCityFixed'] == true ||
                        d['acceptCityAuction'] == true,
                    'Межгород': d['acceptIntercity'] == true,
                    'Доставка': d['acceptDelivery'] == true,
                    'Грузовые': d['acceptCargo'] == true
                  }.entries)
                    Chip(
                        avatar: Icon(
                            entry.value
                                ? Icons.check_circle
                                : Icons.cancel_outlined,
                            size: 18),
                        label: Text(entry.key))
                ]),
                const SizedBox(height: 12),
                if (d['status'] == 'PENDING')
                  Wrap(spacing: 8, children: [
                    FilledButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final reason = await recordReason(
                                    context, 'Одобрить водителя?');
                                if (reason != null) {
                                  await _action(
                                      '/admin/drivers/${d['id']}/approve',
                                      {'reason': reason});
                                }
                              },
                        child: const Text('Одобрить')),
                    OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final reason = await recordReason(
                                    context, 'Отклонить анкету?');
                                if (reason != null) {
                                  await _action(
                                      '/admin/drivers/${d['id']}/reject',
                                      {'reason': reason});
                                }
                              },
                        child: const Text('Отклонить'))
                  ])
              ]),
          ]
        ]));
  }
}

class AdminTripRegisterPage extends StatelessWidget {
  const AdminTripRegisterPage({super.key});
  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'Заказы и поездки',
      subtitle:
          'Все режимы. Откройте заказ, чтобы посмотреть детали и доступные действия.',
      child: ListView(children: [
        AdminTripList(
            filter: (ModalRoute.of(context)?.settings.arguments as Map?)
                    ?.cast<String, dynamic>() ??
                {})
      ]));
}

class AdminTripList extends StatefulWidget {
  const AdminTripList({super.key, this.userId, this.filter = const {}});
  final String? userId;
  final Map<String, dynamic> filter;
  @override
  State<AdminTripList> createState() => _AdminTripListState();
}

class _AdminTripListState extends State<AdminTripList> {
  List<dynamic> _items = [];
  int _skip = 0, _total = 0;
  bool _loading = true;
  String? _error;
  String _status = '';
  @override
  void initState() {
    super.initState();
    _status = '${widget.filter['status'] ?? ''}';
    if (!['', 'ACTIVE', 'COMPLETED', 'CANCELLED', 'EXPIRED_GROUP']
        .contains(_status)) {
      _status = '';
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await AdminApiClient.instance.get(
          widget.userId == null
              ? '/admin/trip-register'
              : '/admin/people/${widget.userId}/trips',
          query: {
            ...widget.filter,
            'status': _status,
            'skip': _skip,
            'take': 20
          });
      if (mounted) {
        setState(() {
          _items = r.data['items'] as List;
          _total = (r.data['total'] as num).toInt();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = recordError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map row) async {
    await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: Text(recordModes[row['mode']] ?? 'Заказ'),
                content: SizedBox(
                    width: 600,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          recordLine('Состояние',
                              recordStatuses[row['status']] ?? row['status']),
                          recordLine('Откуда', row['origin']),
                          recordLine('Куда', row['destination']),
                          recordLine('Создан', recordTime(row['createdAt'])),
                          recordLine(
                              'Отправление', recordTime(row['departure'])),
                          recordLine('Стоимость',
                              recordMoney(row['price'], '${row['currency']}')),
                          recordLine('Пассажир',
                              '${row['passengerName'] ?? 'Не указан'} • ${row['passengerPhone'] ?? ''}'),
                          if (row['passengerId'] != null)
                            TextButton(
                                onPressed: () {
                                  Navigator.pop(dialog);
                                  Navigator.pushNamed(
                                      context, '/person/${row['passengerId']}');
                                },
                                child: const Text('Карточка пассажира')),
                          recordLine('Водитель',
                              '${row['driverName'] ?? 'Не назначен'} • ${row['driverPhone'] ?? ''}'),
                          if (row['driverUserId'] != null)
                            TextButton(
                                onPressed: () {
                                  Navigator.pop(dialog);
                                  Navigator.pushNamed(context,
                                      '/person/${row['driverUserId']}');
                                },
                                child: const Text('Карточка водителя')),
                          ExpansionTile(
                              title:
                                  const Text('Номер обращения для поддержки'),
                              children: [SelectableText('${row['id']}')])
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('Закрыть')),
                  if (![
                    'IN_PROGRESS',
                    'COMPLETED',
                    'CANCELLED',
                    'EXPIRED',
                    'REJECTED'
                  ].contains(row['status']))
                    OutlinedButton(
                        onPressed: () async {
                          final reason = await recordReason(context,
                              'Отменить заказ? Бонусы вернутся по правилам заказа.');
                          if (reason == null || !mounted) return;
                          try {
                            await AdminApiClient.instance.post(
                                '/admin/trip-register/${row['source']}/${row['id']}/cancel',
                                data: {'reason': reason});
                            if (dialog.mounted) Navigator.pop(dialog);
                            await _load();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(recordError(e))));
                            }
                          }
                        },
                        child: const Text('Отменить заказ'))
                ]));
  }

  @override
  Widget build(BuildContext context) =>
      recordSection(context, 'Заказы: $_total', [
        Wrap(spacing: 12, children: [
          DropdownButton<String>(
              value: _status,
              items: [
                const DropdownMenuItem(value: '', child: Text('Все состояния')),
                for (final s in [
                  'ACTIVE',
                  'COMPLETED',
                  'CANCELLED',
                  'EXPIRED_GROUP'
                ])
                  DropdownMenuItem(
                      value: s,
                      child: Text({
                            'ACTIVE': 'Активные',
                            'EXPIRED_GROUP': 'Истёкшие / отклонённые'
                          }[s] ??
                          recordStatuses[s]!))
              ],
              onChanged: (v) {
                _status = v ?? '';
                _skip = 0;
                _load();
              }),
          TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'))
        ]),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _items.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Заказов по выбранным условиям нет.')),
        for (final raw in _items)
          Builder(builder: (context) {
            final row = raw as Map;
            return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                leading: const Icon(Icons.route_outlined),
                title: Text('${row['origin']} → ${row['destination']}'),
                subtitle: Text(
                    '${recordModes[row['mode']] ?? row['mode']} • ${recordStatuses[row['status']] ?? row['status']}\n${recordTime(row['createdAt'])} • ${recordMoney(row['price'], '${row['currency']}')}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(row));
          }),
        Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Показано ${_items.length} из $_total'),
              OutlinedButton(
                  onPressed: _loading || _skip == 0
                      ? null
                      : () {
                          _skip = (_skip - 20).clamp(0, _total);
                          _load();
                        },
                  child: const Text('Назад')),
              OutlinedButton(
                  onPressed: _loading || _skip + 20 >= _total
                      ? null
                      : () {
                          _skip += 20;
                          _load();
                        },
                  child: const Text('Далее'))
            ])
      ]);
}

class AdminRecordFeed extends StatefulWidget {
  const AdminRecordFeed({super.key, required this.path});
  final String path;
  @override
  State<AdminRecordFeed> createState() => _AdminRecordFeedState();
}

class _AdminRecordFeedState extends State<AdminRecordFeed> {
  List<dynamic> _items = [];
  int _skip = 0, _total = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await AdminApiClient.instance
          .get(widget.path, query: {'skip': _skip, 'take': 20});
      if (mounted) {
        setState(() {
          _items = r.data['items'] as List;
          _total = (r.data['total'] as num).toInt();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = recordError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _items.isEmpty) const Text('Операций пока нет.'),
        for (final r in _items)
          ListTile(
              leading: Icon(r['direction'] == 'CREDIT'
                  ? Icons.south_west
                  : Icons.north_east),
              title: Text(
                  '${r['direction'] == 'CREDIT' ? 'Начисление' : 'Списание'} • ${recordMoney(r['amount'], '${r['currency']}')}'),
              subtitle: Text(
                  '${r['note'] ?? _transactionName('${r['type']}')}\n${recordTime(r['createdAt'])}')),
        Wrap(spacing: 8, children: [
          Text('Операций: $_total'),
          TextButton(
              onPressed: _skip == 0 || _loading
                  ? null
                  : () {
                      _skip -= 20;
                      _load();
                    },
              child: const Text('Назад')),
          TextButton(
              onPressed: _skip + 20 >= _total || _loading
                  ? null
                  : () {
                      _skip += 20;
                      _load();
                    },
              child: const Text('Далее'))
        ])
      ]);
}

String _transactionName(String type) =>
    {
      'ORDER_COMMISSION_DEBIT': 'Комиссия за поездку',
      'ORDER_BONUS_REFUND': 'Возврат бонусов за отменённый заказ',
      'REFERRAL_BONUS': 'Реферальный бонус',
      'TECHNICAL_BALANCE_ADJUSTMENT': 'Корректировка баланса администратором',
      'REFERRAL_ORDER_BONUS': 'Реферальный бонус за поездку',
      'TOPUP': 'Пополнение баланса',
      'DEBIT_INTERCITY_ACCEPTED_REQUEST': 'Комиссия за межгород',
      'DEBIT_INTERCITY_COMPLETED_REQUEST': 'Комиссия за межгород'
    }[type] ??
    'Операция по кошельку';

class AdminInviteList extends StatefulWidget {
  const AdminInviteList({super.key, required this.userId});
  final String userId;
  @override
  State<AdminInviteList> createState() => _AdminInviteListState();
}

class _AdminInviteListState extends State<AdminInviteList> {
  List<dynamic> _items = [];
  int _skip = 0, _total = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await AdminApiClient.instance.get(
          '/admin/people/${widget.userId}/referrals',
          query: {'skip': _skip, 'take': 20});
      if (mounted) {
        setState(() {
          _items = r.data['items'] as List;
          _total = (r.data['total'] as num).toInt();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = recordError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (!_loading && _items.isEmpty)
          const Text('Пока никого не пригласил.'),
        for (final u in _items)
          ListTile(
              title: Text('${u['name']}'),
              subtitle: Text('${u['phone']} • ${recordTime(u['createdAt'])}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/person/${u['id']}')),
        if (_total > 20)
          Wrap(spacing: 8, children: [
            Text('Всего приглашённых: $_total'),
            TextButton(
                onPressed: _skip == 0 || _loading
                    ? null
                    : () {
                        _skip -= 20;
                        _load();
                      },
                child: const Text('Назад')),
            TextButton(
                onPressed: _skip + 20 >= _total || _loading
                    ? null
                    : () {
                        _skip += 20;
                        _load();
                      },
                child: const Text('Далее'))
          ])
      ]);
}
