import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import '../widgets/identity_video.dart';
import 'admin_dashboard_page.dart';
import 'admin_people_page.dart';

const identityPurposes = {
  'ENROLL': 'Первичная видеопроверка',
  'RECOVERY': 'Восстановление пароля',
  'DRIVER_IDENTITY': 'Удостоверение личности',
  'VEHICLE': 'Техпаспорт автомобиля'
};

class AdminIdentityHistoryPage extends StatefulWidget {
  const AdminIdentityHistoryPage({super.key});
  @override
  State<AdminIdentityHistoryPage> createState() =>
      _AdminIdentityHistoryPageState();
}

class _AdminIdentityHistoryPageState extends State<AdminIdentityHistoryPage> {
  final _search = TextEditingController();
  Timer? _timer;
  String _status = 'FAILURES';
  String? _userId, _error;
  int _skip = 0, _total = 0, _request = 0;
  bool _loading = true, _initialized = false;
  List<dynamic> _items = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      _userId = args?['userId']?.toString();
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r =
          await AdminApiClient.instance.get('/admin/identity/history', query: {
        'status': _status,
        'search': _search.text,
        'skip': _skip,
        'take': 30,
        if (_userId != null) 'userId': _userId
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

  Future<void> _video(Map row) async {
    try {
      final bytes = await AdminApiClient.instance
          .readPrivateBytes('/admin/identity/reviews/${row['id']}/video');
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text(
                      '${row['user']?['name'] ?? 'Проверка'} • ${recordTime(row['createdAt'])}'),
                  content: SizedBox(
                      width: 720,
                      height: 520,
                      child: Column(children: [
                        Expanded(child: IdentityVideo(bytes: bytes)),
                        const SizedBox(height: 12),
                        Text('${row['reason'] ?? 'Ошибки не зафиксированы'}')
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Закрыть'))
                  ]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Запись недоступна: срок хранения истёк, файл отсутствует или нет права просмотра.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'История видеопроверок',
      subtitle:
          'Все попытки и причины ошибок. Новые неудачные записи хранятся зашифрованными до 7 дней.',
      child: ListView(children: [
        recordSection(context, 'Найти проверку', [
          TextField(
              controller: _search,
              decoration: const InputDecoration(
                  labelText: 'Имя или телефон', prefixIcon: Icon(Icons.search)),
              onChanged: (_) {
                _timer?.cancel();
                _timer = Timer(const Duration(milliseconds: 400), () {
                  _skip = 0;
                  _load();
                });
              }),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, children: [
            DropdownButton<String>(
                value: _status,
                items: [
                  const DropdownMenuItem(
                      value: 'FAILURES', child: Text('Неудачные попытки')),
                  const DropdownMenuItem(
                      value: 'ALL', child: Text('Все попытки')),
                  for (final s in [
                    'VERIFIED',
                    'REVIEW',
                    'FAILED',
                    'REJECTED',
                    'PROCESSING'
                  ])
                    DropdownMenuItem(value: s, child: Text(recordStatuses[s]!))
                ],
                onChanged: (v) {
                  _status = v ?? 'FAILURES';
                  _skip = 0;
                  _load();
                }),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить')),
            if (_userId != null)
              InputChip(
                  label: const Text('Выбранный пользователь'),
                  onDeleted: () {
                    _userId = null;
                    _skip = 0;
                    _load();
                  })
          ]),
          const SizedBox(height: 8),
          const Text(
              'Старые отклонённые записи могли не сохраняться. Зелёный овал при съёмке означает правильное положение лица, а не успешное подтверждение личности.')
        ]),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        recordSection(context, 'Найдено попыток: $_total', [
          if (!_loading && _items.isEmpty)
            const Text('Проверок по выбранным условиям нет.'),
          for (final raw in _items)
            Builder(builder: (context) {
              final row = raw as Map;
              return Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${row['user']?['name'] ?? 'Аккаунт не определён'} • ${row['user']?['phone'] ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                                '${identityPurposes[row['purpose']] ?? 'Проверка'} • ${recordStatuses[row['status']] ?? row['status']} • ${recordTime(row['createdAt'])}'),
                            const SizedBox(height: 8),
                            Text(
                                '${row['reason'] ?? 'Причина отказа отсутствует'}'),
                            const SizedBox(height: 10),
                            Wrap(spacing: 10, children: [
                              if (row['hasVideo'] == true)
                                FilledButton.icon(
                                    onPressed: () => _video(row),
                                    icon: const Icon(Icons.play_circle_outline),
                                    label: const Text('Посмотреть видео'))
                              else
                                const Chip(
                                    label: Text(
                                        'Видео не сохранено или удалено по сроку')),
                              if (row['userId'] != null)
                                TextButton.icon(
                                    onPressed: () => Navigator.pushNamed(
                                        context, '/person/${row['userId']}'),
                                    icon: const Icon(Icons.person_outline),
                                    label: const Text('Карточка пользователя'))
                            ])
                          ])));
            }),
          Wrap(spacing: 10, children: [
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
