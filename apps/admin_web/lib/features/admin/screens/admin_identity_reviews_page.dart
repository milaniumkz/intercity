import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';
import '../../../core/services/identity_push.dart';
import '../widgets/identity_video.dart';
import 'admin_dashboard_page.dart';

class AdminIdentityReviewsPage extends StatefulWidget {
  const AdminIdentityReviewsPage({super.key});
  @override
  State<AdminIdentityReviewsPage> createState() =>
      _AdminIdentityReviewsPageState();
}

class _AdminIdentityReviewsPageState extends State<AdminIdentityReviewsPage> {
  List<dynamic> _rows = [];
  String _message = '';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final r = await AdminApiClient.instance.get('/admin/identity/reviews');
      if (mounted) setState(() => _rows = List<dynamic>.from(r.data as List));
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Не удалось загрузить проверки. Проверьте права доступа и соединение.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    try {
      if (!await IdentityPush.permission()) {
        if (mounted) {
          setState(() => _message =
              'Разрешите уведомления в настройках браузера. На iPhone откройте админку с главного экрана на поддерживаемой iOS.');
        }
        return;
      }
      final key = await AdminApiClient.instance.get('/admin/identity/push/key');
      final subscription =
          jsonDecode(await IdentityPush.subscribe('${key.data['publicKey']}'));
      await AdminApiClient.instance
          .post('/admin/identity/push/subscribe', data: subscription);
      if (mounted) {
        setState(() => _message =
            'Устройство подключено. Уведомления о новых проверках будут приходить и при закрытой вкладке, если это разрешено настройками браузера и ОС.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Не удалось подключить push. Проверьте разрешение уведомлений и повторите.');
      }
    }
  }

  Widget _image(Uint8List bytes) => InkWell(
        onTap: () => showDialog<void>(
            context: context,
            builder: (dialog) => Dialog(
                child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * .9,
                    height: MediaQuery.sizeOf(context).height * .85,
                    child: Stack(children: [
                      Positioned.fill(
                          child: InteractiveViewer(
                              minScale: .5,
                              maxScale: 8,
                              child: Image.memory(bytes, fit: BoxFit.contain))),
                      Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                              tooltip: 'Закрыть',
                              onPressed: () => Navigator.pop(dialog),
                              icon: const Icon(Icons.close))),
                    ])))),
        child: Column(children: [
          Image.memory(bytes, height: 200),
          const Text('Нажмите, чтобы увеличить')
        ]),
      );

  Future<void> _review(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    setState(() => _busy = true);
    try {
      final images = <String, Uint8List>{};
      final vehicleReview = item['purpose'] == 'VEHICLE';
      final documentReview =
          vehicleReview || item['purpose'] == 'DRIVER_IDENTITY';
      for (final kind in (vehicleReview
          ? ['candidate', 'back']
          : documentReview
              ? ['candidate', 'reference']
              : ['candidate', 'reference', 'video'])) {
        try {
          final bytes = await AdminApiClient.instance
              .readPrivateBytes('/admin/identity/reviews/$id/$kind');
          if (bytes.isNotEmpty) images[kind] = bytes;
        } catch (_) {/* Enrollment has no earlier reference. */}
      }
      if (!mounted) return;
      final reason = TextEditingController();
      final materialsReady = images['candidate'] != null &&
          (vehicleReview ||
              (documentReview
                  ? images['reference'] != null
                  : images['video'] != null &&
                      (item['purpose'] == 'ENROLL' ||
                          images['reference'] != null)));
      final vehicleFields = {
        for (final label in ['Марка', 'Модель', 'Год выпуска', 'Госномер'])
          label: TextEditingController()
      };
      bool viewed = false, saving = false;
      String error = '';
      final reviewRoute = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialog) => StatefulBuilder(builder: (context, update) {
                Future<void> decide(bool approve) async {
                  if (reason.text.trim().length < 10) {
                    update(() =>
                        error = 'Укажите основание решения, от 10 символов');
                    return;
                  }
                  if (approve && !viewed) {
                    update(() => error =
                        'Сначала просмотрите материалы и подтвердите проверку');
                    return;
                  }
                  update(() => saving = true);
                  try {
                    await AdminApiClient.instance
                        .post('/admin/identity/reviews/$id/decision', data: {
                      'approve': approve,
                      'reason': reason.text.trim(),
                      if (vehicleReview)
                        'vehicle': {
                          'brand': vehicleFields['Марка']!.text,
                          'model': vehicleFields['Модель']!.text,
                          'year':
                              int.tryParse(vehicleFields['Год выпуска']!.text),
                          'plateNumber': vehicleFields['Госномер']!.text
                        }
                    });
                    if (dialog.mounted) Navigator.pop(dialog);
                  } catch (_) {
                    if (dialog.mounted) {
                      update(() => error =
                          'Решение не сохранено. Проверка могла быть уже рассмотрена или истекла.');
                    }
                  } finally {
                    if (dialog.mounted) update(() => saving = false);
                  }
                }

                return AlertDialog(
                    title: Text('Проверка: ${item['user']?['name'] ?? ''}'),
                    content: SizedBox(
                        width: 1000,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  'Телефон: ${item['user']?['phone'] ?? ''}\nОснование: ${item['reason'] ?? ''}'),
                              if (!documentReview)
                                Text(
                                    'Задания в записи: ${(item['actions'] as List? ?? []).map((a) => const {
                                          'TURN_LEFT': 'поворот влево',
                                          'TURN_RIGHT': 'поворот вправо',
                                          'LOOK_UP': 'взгляд вверх',
                                          'OPEN_MOUTH': 'открыть рот',
                                          'BLINK': 'моргнуть один раз'
                                        }[a] ?? a).join(' → ')}'),
                              const SizedBox(height: 12),
                              Wrap(spacing: 16, runSpacing: 16, children: [
                                if (images['reference'] != null)
                                  SizedBox(
                                      width: 240,
                                      child: Column(children: [
                                        const Text('Первичный эталон'),
                                        _image(images['reference']!)
                                      ])),
                                if (images['candidate'] != null)
                                  SizedBox(
                                      width: 240,
                                      child: Column(children: [
                                        const Text('Новая запись / документ'),
                                        _image(images['candidate']!)
                                      ])),
                                if (images['back'] != null)
                                  SizedBox(
                                      width: 360,
                                      child: Column(children: [
                                        const Text(
                                            'Оборотная сторона техпаспорта'),
                                        _image(images['back']!)
                                      ])),
                                if (images['video'] != null)
                                  SizedBox(
                                      width: 360,
                                      height: 280,
                                      child: IdentityVideo(
                                          bytes: images['video']!)),
                              ]),
                              const SizedBox(height: 12),
                              Text(vehicleReview
                                  ? 'Перенесите из техпаспорта госномер, марку, модель и год выпуска. Владелец автомобиля не проверяется. Эти данные заменят сведения о машине в профиле.'
                                  : documentReview
                                      ? 'Сравните лицо на удостоверении с первичным видеоэталоном и проверьте читаемость документа. Это не государственная проверка подлинности удостоверения.'
                                      : item['purpose'] == 'ENROLL'
                                          ? 'Проверьте признаки живого человека и выполнение заданий в видео. Это первичная привязка к аккаунту, предыдущего эталона ещё нет.'
                                          : 'Убедитесь, что в записи живой человек выполняет случайные задания, лицо не подменяется и совпадает с эталоном. Сомнение не является основанием для одобрения.'),
                              if (vehicleReview)
                                ...vehicleFields.entries.map((field) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: TextField(
                                        controller: field.value,
                                        decoration: InputDecoration(
                                            labelText: field.key)))),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: viewed,
                                  onChanged: saving || !materialsReady
                                      ? null
                                      : (value) =>
                                          update(() => viewed = value == true),
                                  title: Text(documentReview
                                      ? 'Документы просмотрены, сведения подтверждены'
                                      : 'Материалы просмотрены, личность и подлинность записи подтверждены')),
                              TextField(
                                  controller: reason,
                                  maxLines: 3,
                                  maxLength: 1000,
                                  decoration: const InputDecoration(
                                      labelText: 'Обоснование решения')),
                              if (error.isNotEmpty)
                                Text(error,
                                    style: const TextStyle(color: Colors.red)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed:
                              saving ? null : () => Navigator.pop(dialog),
                          child: const Text('Закрыть')),
                      TextButton(
                          onPressed: saving ? null : () => decide(false),
                          child: const Text('Отказать')),
                      FilledButton(
                          onPressed:
                              saving || !viewed ? null : () => decide(true),
                          child: const Text('Подтвердить'))
                    ]);
              }));
      await Navigator.of(context, rootNavigator: true).push(reviewRoute);
      await reviewRoute.completed;
      reason.dispose();
      for (final field in vehicleFields.values) {
        field.dispose();
      }
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Не удалось открыть материалы проверки');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminShell(
      title: 'Проверка личности',
      subtitle:
          'Первичная идентификация, восстановление доступа и документы водителей',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          FilledButton.icon(
              onPressed: _push,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Включить push о новых проверках')),
          OutlinedButton(
              onPressed: _busy ? null : _load,
              child: const Text('Обновить очередь'))
        ]),
        const SizedBox(height: 12),
        if (_message.isNotEmpty) Text(_message),
        if (_busy) const LinearProgressIndicator(),
        if (!_busy && _rows.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Нет записей, ожидающих ручной проверки.')),
        for (final raw in _rows)
          Card(
              child: ListTile(
                  title: Text(
                      '${raw['user']?['name'] ?? 'Пользователь'} • ${raw['user']?['phone'] ?? ''}'),
                  subtitle: Text(
                      '${raw['purpose'] == 'RECOVERY' ? 'Восстановление пароля' : raw['purpose'] == 'ENROLL' ? 'Первичная идентификация' : 'Документы водителя'}\n${raw['reason'] ?? ''}'),
                  trailing: FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () =>
                              _review(Map<String, dynamic>.from(raw as Map)),
                      child: const Text('Проверить')))),
      ]));
}

class AdminIdentityReviewBell extends StatefulWidget {
  const AdminIdentityReviewBell({super.key});
  @override
  State<AdminIdentityReviewBell> createState() =>
      _AdminIdentityReviewBellState();
}

class _AdminIdentityReviewBellState extends State<AdminIdentityReviewBell> {
  Timer? _timer;
  int _count = 0;
  bool _loaded = false, _allowed = false;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await AdminApiClient.instance.get('/admin/identity/reviews');
      if (!mounted) return;
      final count = (r.data as List).length;
      if (_loaded && count > _count) {
        IdentityPush.sound();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('Поступила новая запись для проверки личности')));
      }
      setState(() {
        _count = count;
        _loaded = true;
        _allowed = true;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => !_allowed
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'Проверка личности: $_count',
          onPressed: () => Navigator.pushNamed(context, '/identity-reviews'),
          icon: Badge(
              isLabelVisible: _count > 0,
              label: Text('$_count'),
              child: const Icon(Icons.face_retouching_natural_outlined)));
}
