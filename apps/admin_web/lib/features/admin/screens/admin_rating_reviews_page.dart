import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

class AdminRatingReviewsPage extends StatefulWidget {
  const AdminRatingReviewsPage({super.key});
  @override
  State<AdminRatingReviewsPage> createState() => _AdminRatingReviewsPageState();
}

class _AdminRatingReviewsPageState extends State<AdminRatingReviewsPage> {
  List<Map<String, dynamic>> _items = [];
  String _error = '';
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await AdminApiClient.instance.get('/admin/complaints');
      if (!mounted) return;
      setState(() {
        _items = (res.data as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['type'] == 'LOW_DRIVER_RATING')
            .toList();
        _error = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> item, String decision) async {
    final note = TextEditingController();
    var saving = false;
    String? error;
    var rating = (item['order']?['driverRating'] as num?)?.toInt() ?? 2;
    final route = DialogRoute<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                  title: Text(decision == 'REJECT'
                      ? 'Не учитывать оценку'
                      : decision == 'CHANGE'
                          ? 'Изменить оценку'
                          : 'Подтвердить оценку'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (decision == 'CHANGE')
                      DropdownButton<int>(
                          value: rating,
                          items: List.generate(
                              5,
                              (i) => DropdownMenuItem(
                                  value: i + 1, child: Text('${i + 1} звёзд'))),
                          onChanged: (v) => setDialog(() => rating = v!)),
                    TextField(
                        controller: note,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 2000,
                        decoration: InputDecoration(
                            labelText: 'Обоснование решения',
                            hintText:
                                'Минимум 5 символов: проверенные обстоятельства',
                            errorText: error)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed:
                            saving ? null : () => Navigator.pop(ctx, false),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final explanation = note.text.trim();
                                if (explanation.length < 5) {
                                  setDialog(() => error =
                                      'Укажите пояснение не менее 5 символов');
                                  return;
                                }
                                setDialog(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await AdminApiClient.instance.patch(
                                      '/admin/complaints/${item['id']}',
                                      data: {
                                        'ratingDecision': decision,
                                        'rating': rating,
                                        'resolutionNote': explanation,
                                      });
                                  if (ctx.mounted) Navigator.pop(ctx, true);
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  final data = e is DioException
                                      ? e.response?.data
                                      : null;
                                  final message =
                                      data is Map ? data['message'] : null;
                                  setDialog(() {
                                    saving = false;
                                    error = message is List
                                        ? message.join('\n')
                                        : message?.toString() ??
                                            'Не удалось сохранить решение. Попробуйте ещё раз.';
                                  });
                                }
                              },
                        child: Text(saving ? 'Сохранение…' : 'Сохранить'))
                  ],
                )));
    final approved = await Navigator.of(context).push(route);
    await route.completed;
    note.dispose();
    if (approved != true || !mounted) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Решение сохранено')));
    }
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'Разбор оценок',
      subtitle:
          'Оценки 1–2 не учитываются до решения. Автоматическая рекомендация требует проверки фактов.',
      child: Column(children: [
        Row(children: [
          FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить')),
          const SizedBox(width: 12),
          Text('Ожидают: ${_items.where((e) => e['status'] == 'NEW').length}')
        ]),
        if (_error.isNotEmpty)
          Text(_error, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        Expanded(
            child: ListView(
                children: _items.map((item) {
          Map<String, dynamic> detail = {};
          try {
            detail =
                Map<String, dynamic>.from(jsonDecode('${item['text']}') as Map);
          } catch (_) {}
          final order = item['order'] is Map ? item['order'] as Map : const {};
          final driver = item['driver']?['user']?['name'] ?? 'Водитель';
          final passenger = item['user']?['name'] ?? 'Пассажир';
          final resolved = item['status'] == 'RESOLVED';
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$passenger → $driver · ${detail['rating']} ★',
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                            'Статус: ${order['driverRatingStatus'] ?? 'PENDING'} · Заказ ${item['orderId']}'),
                        const SizedBox(height: 8),
                        Text('${detail['reason'] ?? item['text']}'),
                        const SizedBox(height: 8),
                        Text('${detail['automation']?['text'] ?? ''}',
                            style: const TextStyle(color: Colors.orange)),
                        Text(
                            '${order['fromAddress'] ?? ''} → ${order['toAddress'] ?? ''}'),
                        Text(
                            '${order['price'] ?? ''} ${order['currency'] ?? ''} · ${order['distanceKm'] ?? '—'} км · ${order['durationMin'] ?? '—'} мин'),
                        Text('Завершение: ${order['completedAt'] ?? '—'}'),
                        if (item['resolutionNote'] != null)
                          Text('Решение: ${item['resolutionNote']}'),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton(
                              onPressed: () => _decide(item, 'APPROVE'),
                              child: Text(resolved
                                  ? 'Подтвердить повторно'
                                  : 'Учитывать')),
                          OutlinedButton(
                              onPressed: () => _decide(item, 'CHANGE'),
                              child: const Text('Изменить')),
                          OutlinedButton(
                              onPressed: () => _decide(item, 'REJECT'),
                              child: const Text('Не учитывать')),
                        ]),
                      ])));
        }).toList())),
      ]));
}

/// The queue persists on the server, including while the administrator is away.
class AdminRatingReviewBell extends StatefulWidget {
  const AdminRatingReviewBell({super.key});
  @override
  State<AdminRatingReviewBell> createState() => _AdminRatingReviewBellState();
}

class _AdminRatingReviewBellState extends State<AdminRatingReviewBell> {
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
    if (_loading) return;
    _loading = true;
    try {
      final res = await AdminApiClient.instance
          .get('/admin/complaints', query: {'status': 'NEW'});
      if (!mounted) return;
      final ids = (res.data as List)
          .whereType<Map>()
          .where((e) => e['type'] == 'LOW_DRIVER_RATING')
          .map((e) => '${e['id']}')
          .toSet();
      final fresh = ids.difference(_seen);
      _seen = ids;
      setState(() => _count = ids.length);
      if (fresh.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Новые оценки на разбор: ${fresh.length}'),
            action: SnackBarAction(
                label: 'Открыть',
                onPressed: () => Navigator.pushReplacementNamed(
                    context, '/rating-reviews'))));
      }
    } catch (_) {
      /* The queue remains available for authorized support staff. */
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'Оценки на разбор',
      onPressed: () =>
          Navigator.pushReplacementNamed(context, '/rating-reviews'),
      icon: Badge(
          isLabelVisible: _count > 0,
          label: Text('$_count'),
          child: const Icon(Icons.rate_review_outlined)));
}
