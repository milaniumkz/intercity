import '../../../core/services/identity_voice.dart';
import 'identity_camera_frame.dart';
import '../../../core/services/push_notifications_service.dart';
import '../../../core/services/capture_cleanup.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/identity_session.dart';
import '../../../core/utils/error_message_ru.dart';

const identityConsentVersion = 'intercity-face-2026-11-v2';
const identityActions = {
  'TURN_LEFT': 'Слегка поверните голову налево',
  'TURN_RIGHT': 'Слегка поверните голову направо',
  'LOOK_UP': 'Посмотрите вверх, слегка подняв голову',
  'OPEN_MOUTH': 'Откройте рот',
  'BLINK': 'Моргните один раз',
};

class FaceVerificationPage extends StatefulWidget {
  const FaceVerificationPage(
      {super.key,
      this.phone,
      this.driver = false,
      this.next = '/startup',
      this.apiClient});
  final String? phone;
  final bool driver;
  final String next;
  final ApiClient? apiClient;
  @override
  State<FaceVerificationPage> createState() => _FaceVerificationPageState();
}

class _FaceVerificationPageState extends State<FaceVerificationPage>
    with WidgetsBindingObserver {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _newPassword = TextEditingController(),
      _confirm = TextEditingController();
  CameraController? _camera;
  final _voice = IdentityVoice();
  String _lastCue = '';
  int _countdown = 0;
  Timer? _timer, _poll;
  Map<String, dynamic>? _challenge;
  bool _consent = false, _busy = false, _recording = false, _cancelled = false;
  double _seconds = 0;
  String _message = '', _state = 'READY';
  String? _resetToken;
  late bool _driver = widget.driver;
  bool get _recovery => widget.phone != null;
  int get _recordingSeconds =>
      2 +
      ((_challenge?['actions'] as List?)?.length ?? (_recovery ? 3 : 2)) * 6;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_recovery) {
      _busy = true;
      unawaited(_loadExisting());
    }
  }

  Future<void> _loadExisting() async {
    try {
      final r = await _api.get('/auth/identity/status');
      if (!mounted) return;
      _driver = r.data['driver'] == true || widget.driver;
      if (r.data['enrolled'] == true) {
        _result({'status': 'VERIFIED'});
        return;
      }
      if (r.data['pendingEnrollment'] == true) {
        setState(() => _state = 'REVIEW');
        _poll?.cancel();
        _poll = Timer(const Duration(seconds: 8), _loadExisting);
      } else {
        setState(() => _state = 'READY');
      }
    } catch (e) {
      if (mounted) setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _poll?.cancel();
    _voice.dispose();
    unawaited(_camera?.dispose());
    _newPassword.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        _recording) {
      _cancelled = true;
      _timer?.cancel();
      unawaited(_stop(discard: true));
    }
  }

  String get _instruction {
    if (_seconds < 2) {
      return 'Смотрите прямо в камеру. Глаза открыты, рот закрыт';
    }
    final phase = ((_seconds - 2) / 6).floor();
    if (phase >= ((_challenge?['actions'] as List?)?.length ?? 2) ||
        (_seconds - 2) % 6 >= 4) {
      return 'Снова смотрите прямо в камеру';
    }
    final actions = _challenge?['actions'] as List? ?? [];
    return phase < actions.length ? identityActions[actions[phase]] ?? '' : '';
  }

  Future<void> _start() async {
    if (!_consent || _busy) return;
    _voice.play('prepare');
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = '';
      _cancelled = false;
      _state = 'READY';
    });
    try {
      final response = await _api
          .post('/auth/identity/${_recovery ? 'recovery' : 'enroll'}', data: {
        'consentVersion': identityConsentVersion,
        if (_recovery) 'phone': widget.phone,
        if (!_recovery) 'driverConsent': _driver,
      });
      _challenge = Map<String, dynamic>.from(response.data as Map);
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('unavailable', 'Камера не найдена');
      }
      final device = cameras.firstWhere(
          (d) => d.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first);
      final previous = _camera;
      _camera = null;
      await previous?.dispose();
      final camera = CameraController(device, ResolutionPreset.high,
          enableAudio: false, fps: 30, videoBitrate: 1500000);
      _camera = camera;
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _busy = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = error is CameraException
              ? (error.code == 'unavailable'
                  ? 'Камера не найдена. Откройте приложение на устройстве с камерой.'
                  : 'Не удалось открыть камеру. Разрешите доступ к камере в настройках браузера или приложения и повторите.')
              : errorMessageRu(error);
        });
      }
    }
  }

  Future<void> _record() async {
    final camera = _camera;
    if (_busy || camera == null) return;
    _voice.play('ready');
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final expires = DateTime.tryParse('${_challenge?['expiresAt']}');
      if (expires == null ||
          expires.difference(DateTime.now()).inSeconds < 45) {
        final response = await _api
            .post('/auth/identity/${_recovery ? 'recovery' : 'enroll'}', data: {
          'consentVersion': identityConsentVersion,
          if (_recovery) 'phone': widget.phone,
          if (!_recovery) 'driverConsent': _driver
        });
        _challenge = Map<String, dynamic>.from(response.data as Map);
      }
      for (var n = 3; n > 0; n--) {
        if (!mounted || _camera != camera) return;
        setState(() => _countdown = n);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted || _camera != camera) return;
      setState(() => _countdown = 0);
      await camera.startVideoRecording();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() {
        _busy = false;
        _recording = true;
        _seconds = 0;
      });
      _lastCue = 'front';
      _voice.play('front');
      final clock = Stopwatch()..start();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_recording) return;
        setState(() => _seconds = clock.elapsedMilliseconds / 1000);
        final actions = _challenge?['actions'] as List? ?? [];
        final phase = ((_seconds - 2) / 6).floor();
        final cue =
            _seconds < 2 || (_seconds - 2) % 6 >= 4 || phase >= actions.length
                ? 'front'
                : '${actions[phase]}';
        if (cue != _lastCue && _seconds < _recordingSeconds) {
          _lastCue = cue;
          _voice.play(cue);
        }
        if (_seconds >= _recordingSeconds) {
          _timer?.cancel();
          unawaited(_stop());
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = errorMessageRu(e);
        });
      }
    }
  }

  Future<void> _stop({bool discard = false}) async {
    if (!_recording) return;
    _timer?.cancel();
    _voice.stop();
    if (!discard) _voice.play('done');
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final camera = _camera!;
      final file = await camera.stopVideoRecording();
      await camera.dispose();
      _camera = null;
      if (discard || _cancelled) {
        await deleteCapturedVideo(file.path);
        if (mounted) {
          setState(() => _message =
              'Запись прервана. Оставайтесь на экране до завершения и повторите проверку.');
        }
        return;
      }
      final bytes = await file.readAsBytes();
      await deleteCapturedVideo(file.path);
      if (bytes.length > 16 * 1024 * 1024) {
        throw Exception(
            'Видео слишком большое. Повторите запись в обычном качестве');
      }
      if (!mounted) return;
      setState(() => _message =
          'Проверяем подлинность записи и лицо. Это может занять около минуты.');
      final c = _challenge!;
      final response = await _api.post(
          '/auth/identity/${_recovery ? 'recovery' : 'enroll'}/${c['challengeId']}/video',
          data: FormData.fromMap({
            'challengeToken': c['challengeToken'],
            'video': MultipartFile.fromBytes(bytes,
                filename: file.name.isEmpty ? 'camera.mp4' : file.name),
          }),
          options: Options(
              contentType: 'multipart/form-data',
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 100)));
      if (mounted) _result(Map<String, dynamic>.from(response.data as Map));
    } catch (error) {
      if (error is DioException &&
          error.type == DioExceptionType.receiveTimeout &&
          mounted) {
        _result({
          'status': 'PROCESSING',
          'message': 'Запись ещё обрабатывается. Ожидайте результата.'
        });
      } else if (mounted) {
        setState(() => _message = errorMessageRu(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _result(Map<String, dynamic> result) {
    _poll?.cancel();
    setState(() {
      _state = '${result['status']}';
      _message = '${result['message'] ?? ''}';
      _resetToken = result['resetToken']?.toString();
    });
    if (_state == 'REJECTED' || _state == 'FAILED') _voice.play('retry');
    if (_state == 'VERIFIED' && !_recovery) {
      IdentitySession.required.value = false;
      unawaited(PushNotificationsService.instance.syncTokenIfAuthorized());
      final next = widget.next.startsWith('/') &&
              !widget.next.startsWith('//') &&
              !widget.next.startsWith('/identity')
          ? widget.next
          : '/startup';
      context.go(_driver && next == '/startup' ? '/driver/verification' : next);
    } else if (_state == 'REVIEW' || _state == 'PROCESSING') {
      _poll = Timer(const Duration(seconds: 8), _check);
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    if (_challenge == null) {
      await _loadExisting();
      return;
    }
    try {
      final r = await _api.post('/auth/identity/challenge-status', data: {
        'challengeId': _challenge!['challengeId'],
        'challengeToken': _challenge!['challengeToken']
      });
      if (mounted) _result(Map<String, dynamic>.from(r.data as Map));
    } catch (error) {
      if (mounted) setState(() => _message = errorMessageRu(error));
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (_newPassword.text.length < 6 || _newPassword.text != _confirm.text) {
      setState(() => _message =
          'Новый пароль должен быть от 6 символов. Повтор пароля должен совпадать.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.post('/auth/identity/reset-password',
          data: {'resetToken': _resetToken, 'password': _newPassword.text});
      await _api.clearTokens();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Пароль изменён. Войдите с новым паролем.')));
      context.go('/login');
    } catch (error) {
      if (mounted) setState(() => _message = errorMessageRu(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
        canPop: !_recording,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _recording) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Сначала прервите запись кнопкой на экране.')));
          }
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(_recovery
                  ? 'Восстановление по лицу'
                  : 'Первичная видеопроверка'),
              automaticallyImplyLeading: _recovery,
              actions: [
                IconButton(
                  tooltip: _voice.muted
                      ? 'Включить голосовые подсказки'
                      : 'Выключить голосовые подсказки',
                  icon: Icon(_voice.muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: () {
                    setState(() => _voice.muted = !_voice.muted);
                    if (_voice.muted) {
                      _voice.stop();
                    } else {
                      _voice.play(_recording ? _lastCue : 'prepare');
                    }
                  },
                )
              ]),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            if (_message.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(_message,
                                      style: theme.textTheme.bodyMedium)),
                            if ((_state == 'REJECTED' || _state == 'FAILED') &&
                                _camera == null)
                              FilledButton.icon(
                                  onPressed: _busy ? null : _start,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Повторить видеопроверку')),
                            if (!_recovery &&
                                _camera == null &&
                                (_state == 'REJECTED' || _state == 'FAILED'))
                              const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text(
                                      'Количество первичных попыток не ограничено. Проверка проходит автоматически.')),
                            if (_voice.failed)
                              const Text(
                                  'Звук не запустился. Нажмите значок динамика и проверьте громкость устройства.'),
                            if (_recording && _camera != null) ...[
                              IdentityCameraFrame(
                                  camera: _camera!,
                                  recording: true,
                                  instruction: _instruction),
                              const SizedBox(height: 16),
                              Text(_instruction,
                                  style: theme.textTheme.titleLarge,
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              LinearProgressIndicator(
                                  value: (_seconds / _recordingSeconds)
                                      .clamp(0, 1)),
                              Text(
                                  'Запись: ${_seconds.floor()} / $_recordingSeconds секунд. Не закрывайте экран.'),
                              TextButton(
                                  onPressed: () {
                                    _cancelled = true;
                                    unawaited(_stop(discard: true));
                                  },
                                  child: const Text('Прервать запись')),
                            ] else if (_camera != null &&
                                _camera!.value.isInitialized) ...[
                              IdentityCameraFrame(
                                  camera: _camera!,
                                  recording: false,
                                  instruction: _countdown > 0
                                      ? 'Смотрите прямо • $_countdown'
                                      : 'Расположите лицо в овале'),
                              const SizedBox(height: 16),
                              Text(
                                  'Расположите лицо в овале. Свет должен падать на лицо, а не в камеру. Выполняйте голосовые подсказки. После нажатия начнётся запись на $_recordingSeconds секунд. Выполните ${(_challenge?['actions'] as List?)?.length ?? (_recovery ? 3 : 2)} коротких задания.'),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: _busy ? null : _record,
                                  icon: const Icon(Icons.fiber_manual_record),
                                  label: const Text('Начать запись')),
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final camera = _camera;
                                          _camera = null;
                                          await camera?.dispose();
                                          if (mounted) setState(() {});
                                        },
                                  child: const Text('Закрыть камеру')),
                            ] else if (_resetToken != null) ...[
                              const Text(
                                  'Личность подтверждена. Придумайте новый пароль. Разрешение действует 10 минут и только один раз.'),
                              TextField(
                                  controller: _newPassword,
                                  obscureText: true,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  decoration: const InputDecoration(
                                      labelText:
                                          'Новый пароль, от 6 символов')),
                              const SizedBox(height: 12),
                              TextField(
                                  controller: _confirm,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Повторите новый пароль')),
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: _busy ? null : _reset,
                                  child: const Text('Сохранить новый пароль')),
                            ] else if (_state == 'REVIEW' ||
                                _state == 'PROCESSING') ...[
                              const Icon(Icons.pending_actions, size: 56),
                              const SizedBox(height: 16),
                              const Text(
                                  'Автоматической проверке не хватило уверенности. Можно сразу записать новое видео или дождаться решения администратора. Материалы доступны для ручной проверки до 24 часов.'),
                              TextButton(
                                  onPressed: _busy ? null : _check,
                                  child: const Text('Проверить результат')),
                              if (_recovery && _state == 'REVIEW')
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          _poll?.cancel();
                                          setState(() {
                                            _state = 'READY';
                                            _challenge = null;
                                            _message = '';
                                            _resetToken = null;
                                          });
                                          unawaited(_start());
                                        },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Записать новое видео'),
                                ),
                            ] else ...[
                              Text(_recovery
                                  ? 'Новая запись сравнивается с вашим ранее сохранённым эталоном. Если лицо не совпадёт, смена пароля будет запрещена. Без первичного эталона восстановление по лицу недоступно.'
                                  : 'Привяжите лицо к аккаунту. Это поможет восстановить пароль, если вы его забудете. Номер телефона здесь — логин; SMS-подтверждение не используется.'),
                              const SizedBox(height: 12),
                              Text(_driver
                                  ? 'У водителя эталон также используется для сверки с фотографией в удостоверении личности. Данные автомобиля проверяются отдельно.'
                                  : 'У пассажира эталон используется только для восстановления пароля.'),
                              const SizedBox(height: 12),
                              Text(_recovery
                                  ? 'Эталон и материалы первичной проверки хранятся зашифрованными в закрытом хранилище InterCity. Новая запись обрабатывается на нашем сервере: при автоматическом результате она не сохраняется, при ручном рассмотрении хранится зашифрованной до 7 дней. При удалении аккаунта материалы удаляются из действующего хранилища. Резервные копии используются только для восстановления сервиса.'
                                  : 'Первичная видеозапись, эталон лица и контрольный снимок хранятся зашифрованными в закрытом хранилище InterCity до удаления аккаунта и используются для восстановления пароля. Видео обрабатывается на нашем сервере. Проверка проходит автоматически, при неудаче можно повторять запись без ограничения количества попыток. При удалении аккаунта материалы удаляются из действующего хранилища. Резервные копии используются только для восстановления сервиса.'),
                              const SizedBox(height: 12),
                              const Text(
                                  'Записывайте себя вживую: один человек, хорошее освещение, лицо без маски и тёмных очков. Выполняйте случайные задания по подсказкам. Фотографии и готовые ролики загружать нельзя.'),
                              const SizedBox(height: 12),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _consent,
                                  onChanged: _busy
                                      ? null
                                      : (v) =>
                                          setState(() => _consent = v == true),
                                  title: Text(_recovery
                                      ? 'Согласен на обработку новой записи для восстановления доступа'
                                      : _driver
                                          ? 'Согласен на обработку биометрических данных для восстановления пароля и сверки с удостоверением личности'
                                          : 'Согласен на обработку биометрических данных только для восстановления пароля')),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                  onPressed: _busy || !_consent ? null : _start,
                                  icon: const Icon(Icons.videocam_outlined),
                                  label: const Text('Начать видеопроверку')),
                            ],
                            if (_busy)
                              const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator())),
                            if (!_recovery && !_recording && !_busy)
                              TextButton(
                                  onPressed: () async {
                                    await _api.clearTokens();
                                    if (context.mounted) context.go('/login');
                                  },
                                  child: const Text('Выйти из аккаунта')),
                          ])))),
        ));
  }
}
