import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intercity_shared/intercity_shared.dart';

import '../../../core/api/admin_api_client.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _overviewLoader = _AdminOverviewLoader(() => AdminApiClient.instance);
  String _summary = 'Загрузка панели...';
  Map<String, dynamic>? _kpis;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snapshot = await _overviewLoader.load();
      setState(() {
        _summary = snapshot.summary;
        _kpis = snapshot.kpis;
      });
    } catch (e) {
      setState(() => _summary = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final degraded = _kpis?['notificationDispatchDegraded24h'] == true;
    return AdminShell(
      title: 'Панель',
      subtitle: 'Обзор операций и состояния уведомлений.',
      child: ListView(
        children: [
          _StatusBanner(
            message: _summary,
            tone: _summary.startsWith('Ошибка загрузки')
                ? BannerTone.error
                : BannerTone.info,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Оперативная сводка',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_kpis != null) ...[
                  _HealthStrip(
                    title: degraded
                        ? 'Рассылка ухудшилась за последние 24 часа'
                        : 'Рассылка работает стабильно за последние 24 часа',
                    healthy: !degraded,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatChip(
                          label: 'Активные заказы',
                          value: '${_kpis!['activeOrders'] ?? 0}'),
                      _StatChip(
                          label: 'Водители онлайн',
                          value: '${_kpis!['onlineDrivers'] ?? 0}'),
                      _StatChip(
                          label: 'Проблемные заказы',
                          value: '${_kpis!['problemOrders'] ?? 0}'),
                      _StatChip(
                          label: 'В очереди',
                          value:
                              '${_kpis!['notificationDispatchQueued'] ?? 0}'),
                      _StatChip(
                          label: 'В работе',
                          value:
                              '${_kpis!['notificationDispatchRunning'] ?? 0}'),
                      _StatChip(
                          label: 'С ошибкой',
                          value:
                              '${_kpis!['notificationDispatchFailed'] ?? 0}'),
                      _StatChip(
                          label: 'Успешно за 24ч',
                          value:
                              '${_kpis!['notificationDispatchDone24h'] ?? 0}'),
                      _StatChip(
                          label: 'Ошибок за 24ч',
                          value:
                              '${_kpis!['notificationDispatchFailed24h'] ?? 0}'),
                      _StatChip(
                          label: 'Успех за 24ч',
                          value:
                              '${_kpis!['notificationDispatchSuccessRate24h'] ?? 0}'),
                      _StatChip(
                          label: 'Повторы за 24ч',
                          value:
                              '${_kpis!['notificationDispatchRetries24h'] ?? 0}'),
                      _StatChip(
                          label: 'Успешные повторы',
                          value:
                              '${_kpis!['notificationDispatchRetryDone24h'] ?? 0}'),
                    ],
                  ),
                ] else
                  const Text('Данные KPI пока недоступны.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOverviewSnapshot {
  const _AdminOverviewSnapshot({
    required this.summary,
    required this.kpis,
  });

  final String summary;
  final Map<String, dynamic> kpis;
}

class _AdminOverviewLoader {
  const _AdminOverviewLoader(this._apiFactory);

  final AdminApi Function() _apiFactory;

  Future<_AdminOverviewSnapshot> load() async {
    final api = _apiFactory();
    final responses = await Future.wait<dynamic>([
      api.get('/admin/drivers/pending'),
      api.get('/admin/topups'),
      api.get('/admin/payouts'),
      api.get('/admin/orders'),
      api.get('/admin/dashboard/kpis'),
    ]);
    final pending = List<dynamic>.from((responses[0] as Response).data as List);
    final topups = List<dynamic>.from((responses[1] as Response).data as List);
    final payouts = List<dynamic>.from((responses[2] as Response).data as List);
    final orders = List<dynamic>.from((responses[3] as Response).data as List);
    final kpis = Map<String, dynamic>.from(
      ((responses[4] as Response).data as Map?) ?? const {},
    );
    return _AdminOverviewSnapshot(
      summary: 'Ожидают проверки ${pending.length}, '
          'пополнения ${topups.length}, '
          'выплаты ${payouts.length}, '
          'заказы ${orders.length}',
      kpis: kpis,
    );
  }
}

class AdminDriversPage extends StatefulWidget {
  const AdminDriversPage({super.key});

  @override
  State<AdminDriversPage> createState() => _AdminDriversPageState();
}

class _AdminDriversPageState extends State<AdminDriversPage> {
  List<dynamic> _pending = [];
  final _driverIdCtrl = TextEditingController();
  bool _checkers = false;
  bool _branding = false;
  String _priority = '';
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _driverIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  String? _driverIdOrError() {
    final id = _driverIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _message = 'Для этого действия нужен ID водителя');
      return null;
    }
    return id;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/drivers/pending');
      setState(() {
        _pending = List<dynamic>.from(res.data as List);
        _message = 'Загружено водителей на проверке: ${_pending.length}';
      });
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _approve(String id) =>
      _runAction('Подтвердить водителя', () async {
        await AdminApiClient.instance.post('/admin/drivers/$id/approve', data: {
          'reason': 'Подтверждено через admin_web',
        });
        await _load();
      });

  Future<void> _reject(String id) => _runAction('Отклонить водителя', () async {
        await AdminApiClient.instance.post('/admin/drivers/$id/reject', data: {
          'reason': 'Отклонено через admin_web',
        });
        await _load();
      });

  Future<void> _saveFlags() => _runAction('Сохранить флаги', () async {
        final id = _driverIdOrError();
        if (id == null) return;
        await AdminApiClient.instance.post('/admin/drivers/$id/flags', data: {
          'hasCheckers': _checkers,
          'hasBranding': _branding,
        });
        setState(() => _message = 'Флаги обновлены');
      });

  Future<void> _fuelBonus() => _runAction('Топливный бонус', () async {
        final id = _driverIdOrError();
        if (id == null) return;
        await AdminApiClient.instance
            .post('/admin/drivers/$id/fuel-bonus', data: {'hours': 24});
        setState(() => _message = 'Топливный бонус +24ч применён');
      });

  Future<void> _loadPriority() => _runAction('Получить приоритет', () async {
        final id = _driverIdOrError();
        if (id == null) return;
        final res =
            await AdminApiClient.instance.get('/admin/drivers/$id/priority');
        setState(() => _priority = res.data.toString());
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Водители',
      subtitle: 'Проверка новых водителей и ручное управление флагами.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Ожидают проверки',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: _pending.isEmpty
                ? const Text('Нет водителей, ожидающих проверки.')
                : Column(
                    children: _pending.map((d) {
                      final driver = d as Map<String, dynamic>;
                      final id = (driver['id'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text(
                              '${driver['user']?['phone'] ?? 'Телефон не указан'}'),
                          subtitle:
                              Text('ID $id\nСтатус ${driver['status'] ?? '-'}'),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: _busyAction == null
                                    ? () => _approve(id)
                                    : null,
                                child: const Text('Подтвердить'),
                              ),
                              OutlinedButton(
                                onPressed: _busyAction == null
                                    ? () => _reject(id)
                                    : null,
                                child: const Text('Отклонить'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Инструменты водителя',
            child: Column(
              children: [
                TextField(
                  controller: _driverIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID водителя',
                    helperText:
                        'Нужен для флагов, топливного бонуса и проверки приоритета',
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _checkers,
                  onChanged: (v) => setState(() => _checkers = v),
                  title: const Text('Есть шашки'),
                ),
                SwitchListTile(
                  value: _branding,
                  onChanged: (v) => setState(() => _branding = v),
                  title: const Text('Есть брендирование'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _busyAction == null ? _saveFlags : null,
                        child: const Text('Сохранить флаги')),
                    FilledButton.tonal(
                        onPressed: _busyAction == null ? _fuelBonus : null,
                        child: const Text('Топливо +24ч')),
                    OutlinedButton(
                        onPressed: _busyAction == null ? _loadPriority : null,
                        child: const Text('Получить приоритет')),
                  ],
                ),
                if (_priority.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Приоритет: $_priority'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<dynamic> _users = [];
  final _searchCtrl = TextEditingController();
  final _roleCtrl = TextEditingController(text: 'ALL');
  final _selectedUserIdCtrl = TextEditingController();
  final _deleteReasonCtrl =
      TextEditingController(text: 'Удаление через админку');
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _roleCtrl.dispose();
    _selectedUserIdCtrl.dispose();
    _deleteReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  void _selectUser(Map<String, dynamic> user) {
    _selectedUserIdCtrl.text = (user['id'] ?? '').toString();
    setState(() {
      _message = 'Выбран пользователь ${user['phone'] ?? user['id']}';
    });
  }

  Future<void> _deleteUser(String id) =>
      _runAction('Удаление пользователя', () async {
        final reason = _deleteReasonCtrl.text.trim();
        if (reason.isEmpty) {
          setState(() => _message = 'Укажите причину удаления');
          return;
        }
        await AdminApiClient.instance.delete(
            '/admin/users/$id?reason=${Uri.encodeQueryComponent(reason)}');
        if (_selectedUserIdCtrl.text.trim() == id) {
          _selectedUserIdCtrl.clear();
        }
        setState(() => _message = 'Пользователь удалён');
        await _load();
      });

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/users', query: {
        'take': 100,
        'search': _searchCtrl.text.trim(),
        'role': _roleCtrl.text.trim().isEmpty ? 'ALL' : _roleCtrl.text.trim(),
      });
      final map = Map<String, dynamic>.from((res.data as Map?) ?? const {});
      setState(() {
        _users = List<dynamic>.from((map['items'] as List?) ?? const []);
        _message = 'Загружено пользователей: ${map['total'] ?? _users.length}';
      });
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Пользователи',
      subtitle: 'Поиск пользователей, ролей и городов.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Фильтры',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск',
                    helperText: 'Телефон, имя или ID пользователя',
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Роль',
                    helperText: 'Используйте ALL, ADMIN, PASSENGER или DRIVER',
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Загрузить пользователей')),
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () {
                              _searchCtrl.clear();
                              _roleCtrl.text = 'ALL';
                              _load();
                            },
                      child: const Text('Сбросить фильтры'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Управление пользователем',
            child: Column(
              children: [
                TextField(
                  controller: _selectedUserIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ID выбранного пользователя',
                    helperText:
                        'Можно вставить вручную или нажать "Выбрать" в списке',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deleteReasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Причина удаления',
                    helperText:
                        'Обязательна для безопасного удаления пользователя',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _loading ? null : _load,
                      child: const Text('Обновить список'),
                    ),
                    OutlinedButton(
                      onPressed: _busyAction == null
                          ? () {
                              _selectedUserIdCtrl.clear();
                              setState(
                                  () => _message = 'Выбор пользователя очищен');
                            }
                          : null,
                      child: const Text('Сбросить выбор'),
                    ),
                    FilledButton(
                      onPressed: _busyAction == null
                          ? () {
                              final id = _selectedUserIdCtrl.text.trim();
                              if (id.isEmpty) {
                                setState(() =>
                                    _message = 'Сначала выберите пользователя');
                                return;
                              }
                              _deleteUser(id);
                            }
                          : null,
                      child: const Text('Удалить пользователя'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Список пользователей',
            child: _users.isEmpty
                ? const Text('Пользователи не найдены.')
                : Column(
                    children: _users.map((raw) {
                      final user = raw as Map<String, dynamic>;
                      final city = user['city'] as Map<String, dynamic>?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text(user['phone']?.toString() ?? '-'),
                          subtitle: Text(
                            'ID ${user['id']}\n'
                            '${user['name'] ?? 'Без имени'} • роль ${user['role'] ?? '-'} • город ${city?['name'] ?? user['cityId'] ?? '-'}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _busyAction == null
                                    ? () => _selectUser(user)
                                    : null,
                                child: const Text('Выбрать'),
                              ),
                              FilledButton.tonal(
                                onPressed: _busyAction == null
                                    ? () => _deleteUser(
                                        (user['id'] ?? '').toString())
                                    : null,
                                child: const Text('Удалить'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminCitiesPage extends StatefulWidget {
  const AdminCitiesPage({super.key});

  @override
  State<AdminCitiesPage> createState() => _AdminCitiesPageState();
}

class _AdminCitiesPageState extends State<AdminCitiesPage> {
  List<dynamic> _cities = [];
  final _cityIdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _latCtrl = TextEditingController(text: '43.2220');
  final _lngCtrl = TextEditingController(text: '76.8512');
  bool _isActive = true;
  String _countryCode = 'KZ';
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cityIdCtrl.dispose();
    _nameCtrl.dispose();
    _regionCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/cities');
      setState(() {
        _cities = List<dynamic>.from(res.data as List);
        _message = 'Загружено городов: ${_cities.length}';
      });
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create() => _runAction('Создать город', () async {
        await AdminApiClient.instance.post('/admin/cities', data: {
          'name': _nameCtrl.text.trim(),
          'region': _regionCtrl.text.trim(),
          'countryCode': _countryCode,
          'lat': double.parse(_latCtrl.text),
          'lng': double.parse(_lngCtrl.text),
        });
        await _load();
      });

  Future<void> _delete(String id) => _runAction('Удалить город', () async {
        await AdminApiClient.instance.delete('/admin/cities/$id');
        await _load();
      });

  Future<void> _update() => _runAction('Обновить город', () async {
        final id = _cityIdCtrl.text.trim();
        if (id.isEmpty) {
          setState(() => _message = 'Для обновления нужен ID города');
          return;
        }
        await AdminApiClient.instance.patch('/admin/cities/$id', data: {
          'name': _nameCtrl.text.trim(),
          'region': _regionCtrl.text.trim(),
          'countryCode': _countryCode,
          'lat': double.parse(_latCtrl.text),
          'lng': double.parse(_lngCtrl.text),
          'isActive': _isActive,
        });
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Города',
      subtitle: 'Управление городами и координатами.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Форма города',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              children: [
                TextField(
                    controller: _cityIdCtrl,
                    decoration: const InputDecoration(
                        labelText: 'ID города для обновления')),
                const SizedBox(height: 12),
                TextField(
                    controller: _nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Название города')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _countryCode,
                  key: ValueKey(_countryCode),
                  decoration:
                      const InputDecoration(labelText: 'Страна и валюта'),
                  items: const [
                    DropdownMenuItem(
                        value: 'KZ', child: Text('Казахстан — тенге (₸)')),
                    DropdownMenuItem(
                        value: 'RU', child: Text('Россия — рубли (₽)')),
                  ],
                  onChanged: (value) => setState(() => _countryCode = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _regionCtrl,
                    decoration: const InputDecoration(labelText: 'Регион')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: _latCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Широта'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: _lngCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Долгота'))),
                  ],
                ),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Город активен'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _busyAction == null ? _create : null,
                        child: const Text('Создать город')),
                    FilledButton.tonal(
                        onPressed: _busyAction == null ? _update : null,
                        child: const Text('Обновить город')),
                    OutlinedButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Обновить список')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Список городов',
            child: _cities.isEmpty
                ? const Text('Города не загружены.')
                : Column(
                    children: _cities.map((c) {
                      final city = c as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          onTap: () => setState(() {
                            _cityIdCtrl.text = city['id'].toString();
                            _nameCtrl.text = city['name'].toString();
                            _regionCtrl.text =
                                (city['region'] ?? '').toString();
                            _latCtrl.text = city['lat'].toString();
                            _lngCtrl.text = city['lng'].toString();
                            _countryCode =
                                (city['countryCode'] ?? 'KZ').toString();
                            _isActive = city['isActive'] == true;
                          }),
                          title: Text(
                              '${city['name']} • ${rideCurrencySymbol(city)}'),
                          subtitle: Text(
                              'ID ${city['id']} • ${city['region'] ?? '-'}\n${city['lat']}, ${city['lng']}'),
                          isThreeLine: true,
                          trailing: OutlinedButton(
                            onPressed: _busyAction == null
                                ? () => _delete(city['id'] as String)
                                : null,
                            child: const Text('Удалить'),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminTariffsPage extends StatefulWidget {
  const AdminTariffsPage({super.key});

  @override
  State<AdminTariffsPage> createState() => _AdminTariffsPageState();
}

class _AdminTariffsPageState extends State<AdminTariffsPage> {
  final _cityIdCtrl = TextEditingController();
  final _cityTariffIdCtrl = TextEditingController();
  final _cargoTariffIdCtrl = TextEditingController();
  final _deliveryTariffIdCtrl = TextEditingController();
  List<dynamic> _cities = [];
  final _tariffNameCtrl = TextEditingController(text: 'Стандарт');
  final _baseCtrl = TextEditingController(text: '500');
  final _kmCtrl = TextEditingController(text: '50');
  final _minCtrl = TextEditingController(text: '5');
  final _minimumCtrl = TextEditingController(text: '600');
  String get _tariffSymbol => rideCurrencySymbol(_cities
      .cast<Map?>()
      .firstWhere((city) => city?['id'] == _cityIdCtrl.text,
          orElse: () => null));
  List<dynamic> _city = [];
  List<dynamic> _cargo = [];
  List<dynamic> _delivery = [];
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cityIdCtrl.dispose();
    for (final controller in [
      _tariffNameCtrl,
      _baseCtrl,
      _kmCtrl,
      _minCtrl,
      _minimumCtrl
    ]) {
      controller.dispose();
    }
    _cityTariffIdCtrl.dispose();
    _cargoTariffIdCtrl.dispose();
    _deliveryTariffIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final citiesRes = await AdminApiClient.instance.get('/admin/cities');
      final cityRes = await AdminApiClient.instance.get('/admin/tariffs/city');
      final cargoRes =
          await AdminApiClient.instance.get('/admin/tariffs/cargo');
      final deliveryRes =
          await AdminApiClient.instance.get('/admin/tariffs/delivery');
      setState(() {
        _cities = List<dynamic>.from(citiesRes.data as List);
        _city = List<dynamic>.from(cityRes.data as List);
        _cargo = List<dynamic>.from(cargoRes.data as List);
        _delivery = List<dynamic>.from(deliveryRes.data as List);
        _message = 'Tariffs loaded';
      });
    } catch (e) {
      setState(() => _message = 'Load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createCargo() => _runAction('Create cargo tariff', () async {
        await AdminApiClient.instance.post('/admin/tariffs/cargo', data: {
          'name': 'Cargo Standard',
          'basePrice': 1500,
          'pricePerKm': 120,
          'pricePerKg': 5,
          'minPrice': 2000,
        });
        await _load();
      });

  Future<void> _createCity() => _saveCityTariff(update: false);

  Future<void> _saveCityTariff({required bool update}) =>
      _runAction('Сохранить городской тариф', () async {
        if (_cityIdCtrl.text.isEmpty) {
          setState(() => _message = 'Выберите город');
          return;
        }
        final payload = <String, dynamic>{'name': _tariffNameCtrl.text.trim()};
        for (final entry in {
          'basePrice': _baseCtrl,
          'pricePerKm': _kmCtrl,
          'pricePerMin': _minCtrl,
          'minPrice': _minimumCtrl
        }.entries) {
          final value = double.tryParse(entry.value.text.replaceAll(',', '.'));
          if (value == null || !value.isFinite || value < 0) {
            setState(() => _message = 'Укажите неотрицательные суммы тарифа');
            return;
          }
          payload[entry.key] = value;
        }
        if ((payload['name'] as String).isEmpty) {
          setState(() => _message = 'Введите название тарифа');
          return;
        }
        if (update) {
          if (!_city.any((tariff) =>
              tariff['id'] == _cityTariffIdCtrl.text &&
              tariff['cityId'] == _cityIdCtrl.text)) {
            setState(() => _message =
                'Выберите тариф города из списка для редактирования');
            return;
          }
          await AdminApiClient.instance.patch(
              '/admin/tariffs/city/${_cityTariffIdCtrl.text}',
              data: payload);
        } else {
          await AdminApiClient.instance.post('/admin/tariffs/city',
              data: {...payload, 'cityId': _cityIdCtrl.text});
        }
        await _load();
      });

  void _editCityTariff(Map<String, dynamic> tariff) => setState(() {
        _cityIdCtrl.text = tariff['cityId'].toString();
        _cityTariffIdCtrl.text = tariff['id'].toString();
        _tariffNameCtrl.text = tariff['name'].toString();
        _baseCtrl.text = tariff['basePrice'].toString();
        _kmCtrl.text = tariff['pricePerKm'].toString();
        _minCtrl.text = tariff['pricePerMin'].toString();
        _minimumCtrl.text = tariff['minPrice'].toString();
      });

  Future<void> _deleteCityTariff(String id) =>
      _runAction('Delete city tariff', () async {
        await AdminApiClient.instance.delete('/admin/tariffs/city/$id');
        await _load();
      });

  Future<void> _deleteCargoTariff(String id) =>
      _runAction('Delete cargo tariff', () async {
        await AdminApiClient.instance.delete('/admin/tariffs/cargo/$id');
        await _load();
      });

  Future<void> _deleteDeliveryTariff(String id) =>
      _runAction('Delete delivery tariff', () async {
        await AdminApiClient.instance.delete('/admin/tariffs/delivery/$id');
        await _load();
      });

  Future<void> _deactivateCityTariff() =>
      _runAction('Deactivate city tariff', () async {
        final id = _cityTariffIdCtrl.text.trim();
        if (id.isEmpty) {
          setState(() => _message = 'City tariff ID is required');
          return;
        }
        await AdminApiClient.instance
            .patch('/admin/tariffs/city/$id', data: {'isActive': false});
        await _load();
      });

  Future<void> _deactivateCargoTariff() =>
      _runAction('Deactivate cargo tariff', () async {
        final id = _cargoTariffIdCtrl.text.trim();
        if (id.isEmpty) {
          setState(() => _message = 'Cargo tariff ID is required');
          return;
        }
        await AdminApiClient.instance
            .patch('/admin/tariffs/cargo/$id', data: {'isActive': false});
        await _load();
      });

  Future<void> _deactivateDeliveryTariff() =>
      _runAction('Deactivate delivery tariff', () async {
        final id = _deliveryTariffIdCtrl.text.trim();
        if (id.isEmpty) {
          setState(() => _message = 'Delivery tariff ID is required');
          return;
        }
        await AdminApiClient.instance
            .patch('/admin/tariffs/delivery/$id', data: {'isActive': false});
        await _load();
      });

  Future<void> _createDelivery() =>
      _runAction('Create delivery tariff', () async {
        await AdminApiClient.instance.post('/admin/tariffs/delivery', data: {
          'name': 'Delivery Standard',
          'basePrice': 800,
          'pricePerKm': 80,
          'pricePerKg': 3,
          'minPrice': 1000,
          'doorToDoorFee': 300,
        });
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Тарифы',
      subtitle: 'Городские цены в рублях для России и в тенге для Казахстана.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Tariff actions',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_cityIdCtrl.text),
                  initialValue:
                      _cities.any((city) => city['id'] == _cityIdCtrl.text)
                          ? _cityIdCtrl.text
                          : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Город тарифа'),
                  items: _cities
                      .map((city) => DropdownMenuItem<String>(
                            value: city['id'].toString(),
                            child: Text(
                                '${city['name']} — ${rideCurrencySymbol(city as Map)}'),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    _cityIdCtrl.text = value!;
                    _cityTariffIdCtrl.clear();
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _tariffNameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Название тарифа')),
                for (final entry in {
                  'Базовая стоимость': _baseCtrl,
                  'Цена за км': _kmCtrl,
                  'Цена за минуту': _minCtrl,
                  'Минимальная стоимость': _minimumCtrl
                }.entries) ...[
                  const SizedBox(height: 12),
                  TextField(
                      controller: entry.value,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: entry.key, suffixText: _tariffSymbol)),
                ],
                const SizedBox(height: 12),
                TextField(
                    controller: _cityTariffIdCtrl,
                    decoration: const InputDecoration(
                        labelText: 'City tariff ID to deactivate')),
                const SizedBox(height: 12),
                TextField(
                    controller: _cargoTariffIdCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Cargo tariff ID to deactivate')),
                const SizedBox(height: 12),
                TextField(
                    controller: _deliveryTariffIdCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Delivery tariff ID to deactivate')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _busyAction == null ? _createCity : null,
                        child: const Text('Создать городской тариф')),
                    FilledButton.tonal(
                        onPressed: _busyAction == null
                            ? () => _saveCityTariff(update: true)
                            : null,
                        child: const Text('Сохранить изменения тарифа')),
                    FilledButton(
                        onPressed: _busyAction == null ? _createCargo : null,
                        child: const Text('Create cargo tariff')),
                    FilledButton(
                        onPressed: _busyAction == null ? _createDelivery : null,
                        child: const Text('Create delivery tariff')),
                    FilledButton.tonal(
                        onPressed:
                            _busyAction == null ? _deactivateCityTariff : null,
                        child: const Text('Deactivate city')),
                    FilledButton.tonal(
                        onPressed:
                            _busyAction == null ? _deactivateCargoTariff : null,
                        child: const Text('Deactivate cargo')),
                    FilledButton.tonal(
                        onPressed: _busyAction == null
                            ? _deactivateDeliveryTariff
                            : null,
                        child: const Text('Deactivate delivery')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
              title: 'Городские тарифы — нажмите для редактирования',
              child: _TariffList(
                  items: _city,
                  onDelete: _deleteCityTariff,
                  cityAware: true,
                  onEdit: _editCityTariff)),
          const SizedBox(height: 16),
          _SectionCard(
              title: 'Cargo tariffs',
              child: _TariffList(items: _cargo, onDelete: _deleteCargoTariff)),
          const SizedBox(height: 16),
          _SectionCard(
              title: 'Delivery tariffs',
              child: _TariffList(
                  items: _delivery, onDelete: _deleteDeliveryTariff)),
        ],
      ),
    );
  }
}

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  List<dynamic> _settings = [];
  final _keyCtrl = TextEditingController(text: 'searchRadiusKm');
  final _valueCtrl = TextEditingController(text: '5');
  String _message = '';
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/settings');
      setState(() {
        _settings = List<dynamic>.from(res.data as List);
        _message = 'Loaded ${_settings.length} settings';
      });
    } catch (e) {
      setState(() => _message = 'Load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AdminApiClient.instance.post('/admin/settings', data: {
        'key': _keyCtrl.text.trim(),
        'value': _valueCtrl.text.trim(),
      });
      await _load();
    } catch (e) {
      setState(() => _message = 'Save failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Settings',
      subtitle: 'Store runtime values without leaving the admin panel.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Settings editor',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              children: [
                TextField(
                    controller: _keyCtrl,
                    decoration: const InputDecoration(labelText: 'Key')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final preset in const {
                    'referralCommissionPercent': 'Бонус от комиссии, %',
                    'appStoreUrl': 'Ссылка App Store',
                    'googlePlayUrl': 'Ссылка Google Play',
                  }.entries)
                    ActionChip(
                        label: Text(preset.value),
                        onPressed: () {
                          _keyCtrl.text = preset.key;
                          final stored = _settings
                              .whereType<Map>()
                              .where((item) => item['key'] == preset.key);
                          _valueCtrl.text = stored.isEmpty
                              ? ''
                              : stored.first['value'].toString();
                        }),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: _valueCtrl,
                    decoration: const InputDecoration(labelText: 'Value')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _saving ? null : _save,
                        child: const Text('Save setting')),
                    OutlinedButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Refresh')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Current settings',
            child: _settings.isEmpty
                ? const Text('No settings found.')
                : Column(
                    children: _settings.map((s) {
                      final m = s as Map<String, dynamic>;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${m['key']}'),
                        subtitle: Text('${m['value']}'),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminTopupsPage extends StatefulWidget {
  const AdminTopupsPage({super.key});

  @override
  State<AdminTopupsPage> createState() => _AdminTopupsPageState();
}

class _AdminTopupsPageState extends State<AdminTopupsPage> {
  List<dynamic> _topups = [];
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/topups');
      setState(() {
        _topups = List<dynamic>.from(res.data as List);
        _message = 'Loaded ${_topups.length} topups';
      });
    } catch (e) {
      setState(() => _message = 'Load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _approve(String id) => _runAction('Approve topup', () async {
        await AdminApiClient.instance.post('/admin/topups/$id/approve', data: {
          'reason': 'Approved via admin_web',
        });
        await _load();
      });

  Future<void> _reject(String id) => _runAction('Reject topup', () async {
        await AdminApiClient.instance.post('/admin/topups/$id/reject', data: {
          'reason': 'Rejected via admin_web',
        });
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Topups',
      subtitle: 'Approve or reject wallet topups.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Requests',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: _topups.isEmpty
                ? const Text('No topup requests.')
                : Column(
                    children: _topups.map((t) {
                      final m = t as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text(
                              'Сумма ${m['amount']} ${rideCurrencySymbol(m)}'),
                          subtitle: Text('ID ${m['id']} • ${m['status']}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: _busyAction == null
                                    ? () => _approve(m['id'] as String)
                                    : null,
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: _busyAction == null
                                    ? () => _reject(m['id'] as String)
                                    : null,
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminPayoutsPage extends StatefulWidget {
  const AdminPayoutsPage({super.key});

  @override
  State<AdminPayoutsPage> createState() => _AdminPayoutsPageState();
}

class _AdminPayoutsPageState extends State<AdminPayoutsPage> {
  List<dynamic> _payouts = [];
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/payouts');
      setState(() {
        _payouts = List<dynamic>.from(res.data as List);
        _message = 'Loaded ${_payouts.length} payouts';
      });
    } catch (e) {
      setState(() => _message = 'Load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _approve(String id) => _runAction('Approve payout', () async {
        await AdminApiClient.instance.post('/admin/payouts/$id/approve', data: {
          'reason': 'Approved via admin_web',
        });
        await _load();
      });

  Future<void> _reject(String id) => _runAction('Reject payout', () async {
        await AdminApiClient.instance.post('/admin/payouts/$id/reject', data: {
          'reason': 'Rejected via admin_web',
        });
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Payouts',
      subtitle: 'Process driver payout requests.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Requests',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: _payouts.isEmpty
                ? const Text('No payout requests.')
                : Column(
                    children: _payouts.map((p) {
                      final m = p as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text(
                              'Сумма ${m['amount']} ${rideCurrencySymbol(m)}'),
                          subtitle: Text('ID ${m['id']} • ${m['status']}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: _busyAction == null
                                    ? () => _approve(m['id'] as String)
                                    : null,
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: _busyAction == null
                                    ? () => _reject(m['id'] as String)
                                    : null,
                                child: const Text('Reject'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  List<dynamic> _orders = [];
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/orders');
      setState(() {
        _orders = List<dynamic>.from(res.data as List);
        _message = 'Загружено заказов: ${_orders.length}';
      });
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setStatus(String id, String status) async {
    setState(() => _busyAction = 'status');
    try {
      await AdminApiClient.instance.patch('/admin/orders/$id', data: {
        'status': status,
        'reason': 'Ручное изменение статуса через admin_web',
      });
      setState(() => _message = 'Статус заказа $id изменён на $status');
      await _load();
    } catch (e) {
      setState(() => _message = 'Ошибка смены статуса: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _showTimeline(String id) async {
    try {
      final res = await AdminApiClient.instance
          .get('/admin/orders/$id/events', query: {'take': 100});
      final events = List<dynamic>.from(res.data as List);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Таймлайн заказа: $id'),
          content: SizedBox(
            width: 680,
            child: events.isEmpty
                ? const Text('Событий нет')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i] as Map<String, dynamic>;
                      return ListTile(
                        dense: true,
                        title: Text(
                            '${e['fromStatus'] ?? '-'} -> ${e['toStatus'] ?? '-'}'),
                        subtitle:
                            Text('${e['createdAt']} • ${e['source'] ?? '-'}'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть')),
          ],
        ),
      );
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки таймлайна: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Заказы',
      subtitle: 'Контроль статусов заказов и просмотр таймлайна.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Заказы',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: _orders.isEmpty
                ? const Text('Заказы не загружены.')
                : Column(
                    children: _orders.map((o) {
                      final m = o as Map<String, dynamic>;
                      final id = (m['id'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text('${m['mode']} • ${m['status']}'),
                          subtitle: Text(
                              'ID $id • цена ${m['price']} ${rideCurrencySymbol(m)}'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _showTimeline(id),
                                child: const Text('Таймлайн'),
                              ),
                              PopupMenuButton<String>(
                                enabled: _busyAction == null,
                                tooltip: 'Change status',
                                onSelected: (status) => _setStatus(id, status),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'SEARCHING_DRIVER',
                                      child: Text('SEARCHING_DRIVER')),
                                  PopupMenuItem(
                                      value: 'DRIVER_ASSIGNED',
                                      child: Text('DRIVER_ASSIGNED')),
                                  PopupMenuItem(
                                      value: 'DRIVER_EN_ROUTE',
                                      child: Text('DRIVER_EN_ROUTE')),
                                  PopupMenuItem(
                                      value: 'DRIVER_ARRIVED',
                                      child: Text('DRIVER_ARRIVED')),
                                  PopupMenuItem(
                                      value: 'IN_PROGRESS',
                                      child: Text('IN_PROGRESS')),
                                  PopupMenuItem(
                                      value: 'COMPLETED',
                                      child: Text('COMPLETED')),
                                  PopupMenuItem(
                                      value: 'CANCELLED',
                                      child: Text('CANCELLED')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  List<dynamic> _campaigns = [];
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final Map<String, Map<String, dynamic>> _jobsByCampaign = {};
  String _message = '';
  bool _loading = false;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAction(String action, Future<void> Function() task) async {
    setState(() => _busyAction = action);
    try {
      await task();
    } catch (e) {
      setState(() => _message = '$action failed: $e');
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final campaignsRes =
          await AdminApiClient.instance.get('/admin/notifications');
      final jobsRes = await AdminApiClient.instance
          .get('/admin/notifications/jobs', query: {'limit': 200});
      final campaigns = List<dynamic>.from(campaignsRes.data as List);
      final jobs = List<dynamic>.from(jobsRes.data as List);
      final map = <String, Map<String, dynamic>>{};
      for (final raw in jobs) {
        if (raw is! Map) continue;
        final job = Map<String, dynamic>.from(raw);
        final campaignId = (job['campaignId'] ?? '').toString();
        if (campaignId.isEmpty) continue;
        final prev = map[campaignId];
        if (prev == null) {
          map[campaignId] = job;
          continue;
        }
        final prevAt = (prev['queuedAt'] ?? '').toString();
        final curAt = (job['queuedAt'] ?? '').toString();
        if (curAt.compareTo(prevAt) > 0) {
          map[campaignId] = job;
        }
      }
      setState(() {
        _campaigns = campaigns;
        _jobsByCampaign
          ..clear()
          ..addAll(map);
        _message = 'Loaded ${_campaigns.length} campaigns';
      });
    } catch (e) {
      setState(() => _message = 'Load failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create() => _runAction('Create campaign', () async {
        if (_titleCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
          setState(() => _message = 'Title and body are required');
          return;
        }
        await AdminApiClient.instance.post('/admin/notifications', data: {
          'title': _titleCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'audience': 'ALL',
          'isSent': false,
        });
        _titleCtrl.clear();
        _bodyCtrl.clear();
        await _load();
      });

  Future<void> _queueSend(String campaignId) =>
      _runAction('Queue campaign', () async {
        await AdminApiClient.instance
            .post('/admin/notifications/$campaignId/send', data: {
          'reason': 'Поставлено в очередь через admin_web',
        });
        setState(() => _message = 'Кампания поставлена в очередь');
        await _load();
      });

  Future<void> _requeue(String jobId) =>
      _runAction('Повторить задачу', () async {
        await AdminApiClient.instance
            .post('/admin/notifications/jobs/$jobId/requeue', data: {
          'reason': 'Повторный запуск неуспешной задачи через admin_web',
        });
        setState(() => _message = 'Задача повторно поставлена в очередь');
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Уведомления',
      subtitle: 'Создание кампаний, очередь отправки и повторы ошибок.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Создание кампании',
            trailing: _RefreshButton(
                onPressed: _loading ? null : _load, loading: _loading),
            child: Column(
              children: [
                TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Заголовок')),
                const SizedBox(height: 12),
                TextField(
                  controller: _bodyCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Текст'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _busyAction == null ? _create : null,
                        child: const Text('Создать кампанию')),
                    OutlinedButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Обновить статусы')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Кампании',
            child: _campaigns.isEmpty
                ? const Text('Кампании не найдены.')
                : Column(
                    children: _campaigns.map((raw) {
                      final c = raw as Map<String, dynamic>;
                      final id = (c['id'] ?? '').toString();
                      final job = _jobsByCampaign[id];
                      final jobStatus =
                          (job?['status'] ?? '').toString().toUpperCase();
                      final jobId = (job?['id'] ?? '').toString();
                      final sent = c['isSent'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text('${c['title'] ?? ''}'),
                          subtitle: Text(
                              '${c['body'] ?? ''}\n${sent ? 'Отправлено' : 'Черновик'}${jobStatus.isNotEmpty ? ' • Задача $jobStatus' : ''}'),
                          isThreeLine: true,
                          trailing: sent
                              ? const Text('Отправлено')
                              : Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: _busyAction == null
                                          ? () => _queueSend(id)
                                          : null,
                                      child: const Text('В очередь'),
                                    ),
                                    if (jobStatus == 'FAILED' &&
                                        jobId.isNotEmpty)
                                      OutlinedButton(
                                        onPressed: _busyAction == null
                                            ? () => _requeue(jobId)
                                            : null,
                                        child: const Text('Повторить'),
                                      ),
                                  ],
                                ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminFinanceAuditPage extends StatefulWidget {
  const AdminFinanceAuditPage({super.key});

  @override
  State<AdminFinanceAuditPage> createState() => _AdminFinanceAuditPageState();
}

class _AdminFinanceAuditPageState extends State<AdminFinanceAuditPage> {
  List<dynamic> _items = [];
  final _userIdCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _sourceCtrl = TextEditingController();
  final _takeCtrl = TextEditingController(text: '100');
  String _message = '';
  bool _loading = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _typeCtrl.dispose();
    _sourceCtrl.dispose();
    _takeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = <String, dynamic>{
        'take': int.tryParse(_takeCtrl.text) ?? 100,
      };
      if (_userIdCtrl.text.trim().isNotEmpty) {
        q['userId'] = _userIdCtrl.text.trim();
      }
      if (_typeCtrl.text.trim().isNotEmpty) q['type'] = _typeCtrl.text.trim();
      if (_sourceCtrl.text.trim().isNotEmpty) {
        q['source'] = _sourceCtrl.text.trim().toUpperCase();
      }
      final res = await AdminApiClient.instance
          .get('/admin/wallet-transactions', query: q);
      setState(() {
        _items = List<dynamic>.from(res.data as List);
        _message = 'Загружено транзакций кошелька: ${_items.length}';
      });
    } catch (e) {
      setState(() => _message = 'Ошибка загрузки: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final q = <String, dynamic>{};
      if (_userIdCtrl.text.trim().isNotEmpty) {
        q['userId'] = _userIdCtrl.text.trim();
      }
      if (_typeCtrl.text.trim().isNotEmpty) q['type'] = _typeCtrl.text.trim();
      if (_sourceCtrl.text.trim().isNotEmpty) {
        q['source'] = _sourceCtrl.text.trim().toUpperCase();
      }
      final res = await AdminApiClient.instance
          .get('/admin/reports/wallet-transactions/csv', query: q);
      final map = Map<String, dynamic>.from(res.data as Map);
      final csv = (map['csv'] ?? '').toString();
      final rows = csv.isEmpty ? 0 : '\n'.allMatches(csv).length + 1;
      setState(() => _message = 'CSV готов: $rows строк');
    } catch (e) {
      setState(() => _message = 'Ошибка экспорта CSV: $e');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      title: 'Финансовый аудит',
      subtitle: 'Фильтрация транзакций кошелька и экспорт CSV.',
      child: ListView(
        children: [
          _StatusBanner(message: _message),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Фильтры',
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                        width: 260,
                        child: TextField(
                            controller: _userIdCtrl,
                            decoration: const InputDecoration(
                                labelText: 'ID пользователя'))),
                    SizedBox(
                        width: 220,
                        child: TextField(
                            controller: _typeCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Тип'))),
                    SizedBox(
                        width: 160,
                        child: TextField(
                            controller: _sourceCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Источник'))),
                    SizedBox(
                        width: 120,
                        child: TextField(
                            controller: _takeCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Лимит'))),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                        onPressed: _loading ? null : _load,
                        child: const Text('Обновить')),
                    OutlinedButton(
                        onPressed: _exporting ? null : _exportCsv,
                        child: const Text('Экспорт CSV')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Транзакции',
            child: _items.isEmpty
                ? const Text('Транзакции не загружены.')
                : Column(
                    children: _items.map((row) {
                      final m = row as Map<String, dynamic>;
                      final wallet = m['wallet'] as Map<String, dynamic>?;
                      final user = wallet?['user'] as Map<String, dynamic>?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          tileColor: const Color(0xFFF7FAFC),
                          title: Text(
                              '${m['type']} • ${m['direction']} ${m['amount']} ${rideCurrencySymbol(m)}'),
                          subtitle: Text(
                              '${m['balanceSource']} • ${user?['phone'] ?? '-'} • ${m['createdAt']}'),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const AdminShell(
      {super.key, required this.title, required this.child, this.subtitle});

  static const _items = [
    ('/dashboard', 'Панель', Icons.grid_view_rounded),
    ('/users', 'Пользователи', Icons.people_alt_outlined),
    ('/drivers', 'Водители', Icons.verified_user_outlined),
    ('/cities', 'Города', Icons.location_city_outlined),
    ('/tariffs', 'Тарифы', Icons.sell_outlined),
    ('/settings', 'Настройки', Icons.tune_rounded),
    ('/topups', 'Пополнения', Icons.account_balance_wallet_outlined),
    ('/payouts', 'Выплаты', Icons.payments_outlined),
    ('/notifications', 'Уведомления', Icons.notifications_active_outlined),
    ('/finance-audit', 'Финансовый аудит', Icons.receipt_long_outlined),
    ('/orders', 'Заказы', Icons.local_taxi_outlined),
  ];

  Future<void> _logout(BuildContext context) async {
    await AdminApiClient.instance.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final navigation = _SideNavigation(
          currentRoute: route,
          onLogout: () => _logout(context),
          onNavigate: (target) {
            if (route == target) {
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                Navigator.pop(context);
              }
              return;
            }
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.pop(context);
            }
            Navigator.pushReplacementNamed(context, target);
          },
        );

        final content = Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (!wide)
                IconButton(
                  tooltip: 'Выйти',
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout_rounded),
                ),
            ],
          ),
          drawer: wide ? null : Drawer(child: navigation),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF4F7FB), Color(0xFFEAF2F7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (wide) ...[
                      SizedBox(width: 280, child: navigation),
                      const SizedBox(width: 20),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(subtitle!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: const Color(0xFF516173))),
                          ],
                          const SizedBox(height: 20),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(28),
                                border:
                                    Border.all(color: const Color(0xFFD7E2EC)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: child,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        return content;
      },
    );
  }
}

class _SideNavigation extends StatelessWidget {
  final String? currentRoute;
  final VoidCallback onLogout;
  final ValueChanged<String> onNavigate;

  const _SideNavigation({
    required this.currentRoute,
    required this.onLogout,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0B2239),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INTERCITY Admin',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Операции, финансы и диспетчеризация в одном месте.',
              style: TextStyle(color: Color(0xFF9FB3C8)),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: AdminShell._items.map((item) {
                  final selected = currentRoute == item.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        selected: selected,
                        selectedTileColor: const Color(0xFF123B5B),
                        iconColor: Colors.white,
                        textColor: Colors.white,
                        selectedColor: Colors.white,
                        leading: Icon(item.$3),
                        title: Text(item.$2),
                        onTap: () => onNavigate(item.$1),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF31506E)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Выйти'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

enum BannerTone { info, error }

class _StatusBanner extends StatelessWidget {
  final String message;
  final BannerTone tone;

  const _StatusBanner({
    required this.message,
    this.tone = BannerTone.info,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final error =
        tone == BannerTone.error || message.toLowerCase().contains('ошибка');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF1F0) : const Color(0xFFEAF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: error ? const Color(0xFFF3B7B2) : const Color(0xFFB8D8EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(error
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const _RefreshButton({required this.onPressed, required this.loading});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
      label: Text(loading ? 'Загрузка' : 'Обновить'),
    );
  }
}

class _HealthStrip extends StatelessWidget {
  final String title;
  final bool healthy;

  const _HealthStrip({required this.title, required this.healthy});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: healthy ? const Color(0xFFEAFBF3) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              healthy
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color:
                  healthy ? const Color(0xFF15803D) : const Color(0xFFB45309),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E2EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF516173))),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TariffList extends StatelessWidget {
  final List<dynamic> items;
  final Future<void> Function(String id) onDelete;
  final bool cityAware;
  final void Function(Map<String, dynamic>)? onEdit;

  const _TariffList({
    required this.items,
    required this.onDelete,
    this.cityAware = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Тарифы не загружены.');
    }
    return Column(
      children: items.map((t) {
        final m = t as Map<String, dynamic>;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            tileColor: const Color(0xFFF7FAFC),
            onTap: onEdit == null ? null : () => onEdit!(m),
            title: Text('${m['name']}'),
            subtitle: Text(
              cityAware
                  ? 'ID ${m['id']} • активен ${m['isActive']} • город ${((m['city'] as Map?)?['name'] ?? m['cityId'])}\nБаза: ${m['basePrice']} ${rideCurrencySymbol(m)} • км: ${m['pricePerKm']} ${rideCurrencySymbol(m)} • мин: ${m['pricePerMin']} ${rideCurrencySymbol(m)} • минимум: ${m['minPrice']} ${rideCurrencySymbol(m)}'
                  : 'ID ${m['id']} • активен ${m['isActive']}',
            ),
            trailing: OutlinedButton(
              onPressed: () => onDelete(m['id'] as String),
              child: const Text('Удалить'),
            ),
          ),
        );
      }).toList(),
    );
  }
}
