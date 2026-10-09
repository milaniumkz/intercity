import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

class AdminTripReviewsPage extends StatefulWidget {
  const AdminTripReviewsPage({super.key});
  @override
  State<AdminTripReviewsPage> createState() => _AdminTripReviewsPageState();
}

class _AdminTripReviewsPageState extends State<AdminTripReviewsPage> {
  List<Map<String, dynamic>> _items = [];
  String _error = '';
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await AdminApiClient.instance.get('/admin/trip-reviews');
      if (!mounted) {
        return;
      }
      setState(() {
        _items = (response.data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _error = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось загрузить поездки: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _decide(Map<String, dynamic> trip, String decision) async {
    final note = TextEditingController();
    var saving = false;
    String? error;
    final route = DialogRoute<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text(decision == 'APPROVE'
                      ? 'Подтвердить поездку и начислить бонусы'
                      : 'Не учитывать поездку для бонусов'),
                  content: TextField(
                      controller: note,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: InputDecoration(
                          labelText: 'Обоснование решения', errorText: error)),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx, false),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (note.text.trim().length < 5) {
                                  update(() => error = 'Минимум 5 символов');
                                  return;
                                }
                                update(() => saving = true);
                                try {
                                  await AdminApiClient.instance.patch(
                                      '/admin/trip-reviews/${Uri.encodeComponent('${trip['id']}')}',
                                      data: {
                                        'decision': decision,
                                        'note': note.text.trim()
                                      });
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx, true);
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    update(() {
                                      saving = false;
                                      error = 'Решение не сохранено: $e';
                                    });
                                  }
                                }
                              },
                        child: Text(saving ? 'Сохранение…' : 'Сохранить'))
                  ],
                )));
    final saved = await Navigator.of(context).push(route);
    await route.completed;
    note.dispose();
    if (saved == true && mounted) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'Проверка поездок',
      subtitle:
          'Бонусы по спорным поездкам удержаны до решения. Недостаток GPS сам по себе не доказывает нарушение.',
      child: Column(children: [
        Row(children: [
          FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить')),
          const SizedBox(width: 12),
          Text(
              'Ожидают: ${_items.where((t) => t['status'] == 'REVIEW').length}')
        ]),
        if (_error.isNotEmpty)
          Text(_error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Expanded(
            child: ListView(
                children: _items.map((t) {
          final stats = t['summary'] as Map? ?? {};
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${t['kind'] == 'CITY' ? 'Город' : 'Межгород'} · ${t['tripId']}',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text('${t['fromAddress']} → ${t['toAddress']}'),
                        Text(
                            'Водитель: ${t['driverUserId']} · Пассажир: ${t['passengerId']}'),
                        Text(
                            'Статус: ${t['status']} · Завершено: ${t['completedAt']}'),
                        Text(
                            'Длительность: ${((stats['durationSec'] as num? ?? 0) / 60).toStringAsFixed(1)} мин · GPS: ${stats['samples'] ?? 0} точек · Движение: ${(stats['travelledMeters'] as num? ?? 0).toStringAsFixed(0)} м'),
                        Text((t['reasons'] as List? ?? []).join('\n'),
                            style: const TextStyle(color: Colors.orange)),
                        if (t['resolutionNote'] != null)
                          Text('Решение: ${t['resolutionNote']}'),
                        if (t['status'] == 'REVIEW')
                          Wrap(spacing: 8, children: [
                            OutlinedButton(
                                onPressed: () => _decide(t, 'APPROVE'),
                                child: const Text('Подтвердить')),
                            OutlinedButton(
                                onPressed: () => _decide(t, 'REJECT'),
                                child: const Text('Не учитывать'))
                          ]),
                      ])));
        }).toList()))
      ]));
}

class AdminTripReviewBell extends StatefulWidget {
  const AdminTripReviewBell({super.key});
  @override
  State<AdminTripReviewBell> createState() => _AdminTripReviewBellState();
}

class _AdminTripReviewBellState extends State<AdminTripReviewBell> {
  Timer? _timer;
  Set<String> _seen = {};
  int _count = 0;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_loading) {
      return;
    }
    _loading = true;
    try {
      final response = await AdminApiClient.instance
          .get('/admin/trip-reviews', query: {'status': 'REVIEW'});
      if (!mounted) {
        return;
      }
      final ids = (response.data as List)
          .whereType<Map>()
          .where((t) =>
              t['status'] == 'REVIEW' &&
              (t['kind'] == 'CITY' || t['kind'] == 'INTERCITY'))
          .map((t) => '${t['id']}')
          .toSet();
      final fresh = ids.difference(_seen);
      _seen = ids;
      setState(() => _count = ids.length);
      if (fresh.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Поездки на проверку: ${fresh.length}'),
            action: SnackBarAction(
                label: 'Открыть',
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/trip-reviews'))));
      }
    } catch (_) {/* Support permission may be unavailable. */} finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'Поездки на проверку',
      onPressed: () => Navigator.pushReplacementNamed(context, '/trip-reviews'),
      icon: Badge(
          isLabelVisible: _count > 0,
          label: Text('$_count'),
          child: const Icon(Icons.route_outlined)));
}
