import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import '../../../core/services/identity_push.dart';
import 'admin_dashboard_page.dart';
import 'admin_people_page.dart';

const attentionCategories = {
  'identity': 'Видеопроверки',
  'identity-failed': 'Отказы видеопроверки',
  'topup-completed': 'Завершённые пополнения',
  'trip-review': 'Проверка поездок',
  'driver': 'Документы водителей',
  'topup': 'Пополнения',
  'payout': 'Выплаты',
  'complaint': 'Обращения',
  'technical': 'Технические проблемы'
};

class AdminAttentionBell extends StatefulWidget {
  const AdminAttentionBell({super.key});
  @override
  State<AdminAttentionBell> createState() => _AdminAttentionBellState();
}

class _AdminAttentionBellState extends State<AdminAttentionBell> {
  Timer? _timer;
  int _count = 0;
  String? _latest;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await AdminApiClient.instance
          .get('/admin/attention', query: {'unread': 'true', 'take': 1});
      if (!mounted) return;
      final rows = r.data['items'] as List? ?? [];
      final newest = rows.isEmpty ? null : '${rows.first['id']}';
      if (_latest != null && newest != null && newest != _latest) {
        IdentityPush.sound();
      }
      _latest = newest;
      setState(() => _count = (r.data['total'] as num? ?? 0).toInt());
    } catch (_) {
      /* Other admin sections remain usable during reconnect. */
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'Требуют внимания',
      onPressed: () => Navigator.pushNamed(context, '/attention'),
      icon: Badge(
          label: Text('$_count'),
          isLabelVisible: _count > 0,
          child: const Icon(Icons.notifications_active_outlined)));
}

class AdminAttentionPage extends StatefulWidget {
  const AdminAttentionPage({super.key});
  @override
  State<AdminAttentionPage> createState() => _AdminAttentionPageState();
}

class _AdminAttentionPageState extends State<AdminAttentionPage> {
  Timer? _timer;
  List<dynamic> _rows = [];
  String _category = '', _severity = '', _state = 'OPEN';
  bool _unread = false, _busy = false;
  String? _error;
  int _skip = 0, _total = 0, _request = 0;
  DateTimeRange? _period;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    final id = ++_request;
    try {
      final r = await AdminApiClient.instance.get('/admin/attention', query: {
        'state': _state,
        if (_category.isNotEmpty) 'category': _category,
        if (_severity.isNotEmpty) 'severity': _severity,
        if (_unread) 'unread': 'true',
        'skip': _skip,
        'take': 30,
        if (_period != null) ...{
          'from': _period!.start.toUtc().toIso8601String(),
          'to': _period!.end
              .add(const Duration(days: 1))
              .toUtc()
              .toIso8601String()
        }
      });
      if (mounted && id == _request) {
        setState(() {
          _rows = r.data['items'] as List? ?? [];
          _total = (r.data['total'] as num? ?? 0).toInt();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && id == _request) setState(() => _error = recordError(e));
    } finally {
      _busy = false;
    }
  }

  Future<void> _push() async {
    try {
      if (!await IdentityPush.permission()) throw Exception();
      final key =
          await AdminApiClient.instance.get('/admin/attention/push-key');
      final raw = await IdentityPush.subscribe(key.data['publicKey']);
      await AdminApiClient.instance
          .post('/admin/attention/push-subscribe', data: jsonDecode(raw));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Push-уведомления подключены')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Не удалось включить уведомления. Проверьте разрешение браузера.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'Требуют внимания',
      subtitle:
          'Проверки, деньги, обращения и технические проблемы. Создание обычных заказов сюда не попадает.',
      child: ListView(children: [
        recordSection(context, 'Фильтры и уведомления', [
          Wrap(spacing: 16, runSpacing: 12, children: [
            DropdownButton<String>(
                value: _category,
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Все категории')),
                  for (final e in attentionCategories.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value))
                ],
                onChanged: (v) {
                  setState(() {
                    _category = v ?? '';
                    _skip = 0;
                  });
                  _load();
                }),
            DropdownButton<String>(
                value: _severity,
                items: const [
                  DropdownMenuItem(value: '', child: Text('Вся критичность')),
                  DropdownMenuItem(
                      value: 'CRITICAL', child: Text('Критические')),
                  DropdownMenuItem(
                      value: 'WARNING', child: Text('Требуют внимания')),
                  DropdownMenuItem(value: 'INFO', child: Text('Информационные'))
                ],
                onChanged: (v) {
                  setState(() => _severity = v ?? '');
                  _load();
                }),
            DropdownButton<String>(
                value: _state,
                items: const [
                  DropdownMenuItem(
                      value: 'OPEN', child: Text('Ожидают действий')),
                  DropdownMenuItem(value: 'DONE', child: Text('Обработанные')),
                  DropdownMenuItem(value: 'ALL', child: Text('Все состояния'))
                ],
                onChanged: (v) {
                  setState(() => _state = v ?? 'OPEN');
                  _load();
                }),
            OutlinedButton(
                onPressed: () async {
                  final p = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (p != null) {
                    setState(() => _period = p);
                    _load();
                  }
                },
                child: const Text('Выбрать даты')),
            TextButton(
                onPressed: () {
                  setState(() => _period = null);
                  _load();
                },
                child: const Text('Убрать даты')),
            FilledButton.icon(
                onPressed: _push,
                icon: const Icon(Icons.notifications_active),
                label: const Text('Включить push-уведомления'))
          ]),
          SwitchListTile(
              title: const Text('Только непрочитанные'),
              value: _unread,
              onChanged: (v) {
                setState(() => _unread = v);
                _load();
              }),
          const Text(
              'Список обновляется автоматически каждые 5 секунд. Для фоновых push нужно разрешение браузера.'),
          if (_error != null) Text(_error!),
        ]),
        Text('Найдено: $_total'),
        for (final row in _rows)
          recordSection(context, '${row['title']}', [
            Text('${row['body']}'),
            if (row['pushError'] != null)
              Text('${row['pushError']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Text(
                '${recordTime(row['createdAt'])} · ${attentionCategories[row['category']] ?? row['category']} · ${row['resolvedAt'] == null ? 'Ожидает действий' : 'Обработано'}'),
            Wrap(spacing: 12, children: [
              FilledButton(
                  onPressed: () async {
                    final target = '${row['adminRoute']}';
                    if (target == '/attention') {
                      try {
                        final response = await AdminApiClient.instance
                            .get('/admin/attention/${row['id']}/details');
                        if (!context.mounted) return;
                        final details = response.data;
                        await showDialog<void>(
                            context: context,
                            builder: (d) => AlertDialog(
                                    title: Text('${details['title']}'),
                                    content: SingleChildScrollView(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text('${details['description']}'),
                                          const SizedBox(height: 12),
                                          SelectableText(
                                              '${details['technicalUrl']}')
                                        ])),
                                    actions: [
                                      if (details['userId'] != null)
                                        TextButton(
                                            onPressed: () {
                                              Navigator.pop(d);
                                              Navigator.pushNamed(
                                                  context, '/person',
                                                  arguments: {
                                                    'id': details['userId']
                                                  });
                                            },
                                            child: const Text('Пользователь')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(d),
                                          child: const Text('Закрыть'))
                                    ]));
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(recordError(e))));
                        }
                      }
                    } else {
                      Navigator.pushNamed(context, target);
                    }
                  },
                  child: const Text('Открыть')),
              OutlinedButton(
                  onPressed: row['read'] == true
                      ? null
                      : () async {
                          await AdminApiClient.instance.post(
                              '/admin/attention/${row['id']}/read',
                              data: {});
                          _load();
                        },
                  child: Text(row['read'] == true
                      ? 'Прочитано'
                      : 'Отметить прочитанным'))
            ]),
          ]),
        if (_rows.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('По выбранным условиям уведомлений нет.')),
        Row(children: [
          TextButton(
              onPressed: _skip == 0
                  ? null
                  : () {
                      _skip = (_skip - 30).clamp(0, 1 << 30);
                      _load();
                    },
              child: const Text('Назад')),
          TextButton(
              onPressed: _skip + 30 >= _total
                  ? null
                  : () {
                      _skip += 30;
                      _load();
                    },
              child: const Text('Далее'))
        ])
      ]));
}
