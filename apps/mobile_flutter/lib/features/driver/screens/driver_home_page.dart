import '../../../core/services/text_to_speech_service.dart';
import '../../../core/utils/localization_service.dart';
import '../widgets/navigation_instruction.dart';
import '../utils/navigation_distance.dart';
import '../utils/pickup_departure_tracker.dart';
import '../widgets/driver_daily_bonus_card.dart';
import '../widgets/driver_offer_expiry_watcher.dart';
import '../widgets/driver_navigation_map.dart';
import '../../../core/services/driver_offer_sound.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/widgets/road_route_layer.dart';
import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/push_notifications_service.dart';
import '../../../core/services/sse_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/driver_access.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/request_flow_utils.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/intercity_static_tile_map.dart';
import '../../shared/widgets/order_chat_sheet.dart';
import '../utils/driver_offer_utils.dart';
import '../widgets/driver_bottom_nav.dart';
import '../widgets/driver_active_trip_view.dart';
import '../widgets/driver_dashboard_metrics.dart';

const bool kIntercityScreenBoard = bool.fromEnvironment(
  'INTERCITY_SCREEN_PREVIEW',
);

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key, this.routeStage, this.apiClient});

  final String? routeStage;
  final ApiClient? apiClient;

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage>
    with WidgetsBindingObserver {
  final _carModelCtrl = TextEditingController(text: 'Toyota Camry');
  final _carNumberCtrl = TextEditingController(text: 'A123BC');
  final _latCtrl = TextEditingController(text: '43.2220');
  final _lngCtrl = TextEditingController(text: '76.8512');
  final _cityIdCtrl = TextEditingController();
  final _boardOfferPriceCtrl = TextEditingController(text: '1600');
  bool _isOnline = false;
  bool _switchBusy = false;
  bool? _pendingOnlineValue;
  bool _rideStatusBusy = false;
  String? _rideStatusMessage;
  String? _driverStatus;
  Map<String, dynamic>? _driverProfile;
  Map<String, dynamic>? _driverWallet;
  bool _hasResolvedDriverProfile = false;
  bool _acceptIntercity = true;
  List<dynamic> _nearby = [];
  List<Map<String, dynamic>> _activeIntercityRequests = const [];
  List<Map<String, dynamic>> _myIntercityTrips = const [];
  Map<String, dynamic>? _activeOrder;
  String _message = '';
  String _offerCurrencySymbol = '₸';
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStream;
  double _driverHeading = 0;
  LatLng? _lastGpsPoint;
  DateTime? _lastGpsAt;
  double? _lastGpsAccuracy;
  bool _navigationVoiceWarningShown = false;
  Timer? _activeOrderPollTimer;
  Timer? _nearbyPollTimer;
  Timer? _offerCountdownTimer;
  Timer? _auctionOfferWaitTimer;
  bool _loadingNearby = false;
  bool _updatingLocation = false;
  final Set<String> _declinedNextOfferIds = <String>{};
  List<LatLng> _activeRoutePolyline = [];
  int _activeRouteRequest = 0;
  String? _activeRouteCacheKey;
  String? _activeRoutePendingKey;
  String? _activeRoutePhase;
  DateTime? _activeRouteStartedAt;
  final Set<String> _notifiedOfferIds = <String>{};
  String? _pendingOfferOrderId;
  StreamSubscription<Map<String, dynamic>>? _notificationTapSub;
  SseConnection? _driverSse;
  StreamSubscription<Map<String, dynamic>>? _driverSseSub;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _offerDialogOpen = false;
  bool _topupRequiredDialogOpen = false;
  String? _waitingAuctionOrderId;
  String? _waitingAuctionOfferId;
  DateTime? _waitingAuctionUntil;
  Timer? _offerAlarmTimer;
  String? _offerAlarmOrderId;
  final Set<String> _spokenOfferIds = <String>{};
  List<Map<String, dynamic>> _navSteps = const [];
  int _navStepIndex = 0;
  DateTime? _lastRealtimeRefreshAt;
  bool _initialized = false;
  final _navigationSpeech = createTextToSpeechService();
  final _spokenManeuvers = <String, int>{};
  Timer? _dashboardMetricsTimer;
  final _pickupDeparture = PickupDepartureTracker();
  final _bonusNotices = <String>{};

  bool get _isDriverApproved => isApprovedDriverStatus(_driverStatus);

  String get _driverStatusLabel {
    final s = (_driverStatus ?? '').toUpperCase();
    switch (s) {
      case 'ACTIVE':
      case 'APPROVED':
        return 'Статус водителя: одобрен';
      case 'PENDING':
        return 'Статус водителя: на проверке';
      case 'REJECTED':
        return 'Статус водителя: отклонен';
      case '':
        return 'Статус водителя: профиль не создан';
      default:
        return 'Статус водителя: $s';
    }
  }

  @override
  void initState() {
    super.initState();
    AppModeManager.rememberDriverMode();
    WidgetsBinding.instance.addObserver(this);
    _boardOfferPriceCtrl.addListener(_refreshBoardOfferPriceSelection);
    _dashboardMetricsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          _appLifecycleState != AppLifecycleState.resumed ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      unawaited(_loadDriverProfileState(metricsOnly: true));
      unawaited(_loadDriverWallet());
      if (_driverSse == null) unawaited(_connectDriverRealtime());
    });
    _notificationTapSub = PushNotificationsService
        .instance.onNotificationPayload
        .listen((payload) async {
      if (!mounted) return;
      final type = (payload['type'] ?? '').toString().toLowerCase();
      if (type != 'driver_offer' && type != 'order_offer') return;
      final orderId = (payload['orderId'] ?? '').toString();
      if (orderId.isEmpty) return;
      _pendingOfferOrderId = orderId;
      await _loadNearby(silent: true);
      await _showPendingOfferDialogIfNeeded();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_navigationSpeech.stop());
    _notificationTapSub?.cancel();
    _dashboardMetricsTimer?.cancel();
    _locationTimer?.cancel();
    _positionStream?.cancel();
    _activeOrderPollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _offerCountdownTimer?.cancel();
    _auctionOfferWaitTimer?.cancel();
    _offerAlarmTimer?.cancel();
    _driverSseSub?.cancel();
    _driverSse?.close();
    _carModelCtrl.dispose();
    _carNumberCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _cityIdCtrl.dispose();
    _boardOfferPriceCtrl.removeListener(_refreshBoardOfferPriceSelection);
    _boardOfferPriceCtrl.dispose();
    super.dispose();
  }

  void _refreshBoardOfferPriceSelection() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _appLifecycleState = state);
    if (state == AppLifecycleState.resumed &&
        _isOnline &&
        _activeOrder == null) {
      _loadDriverProfileState()
          .then((_) => _loadNearby(silent: true))
          .then((_) => _showPendingOfferDialogIfNeeded());
    }
  }

  ApiClient get _api => widget.apiClient ?? ApiClient();

  Future<void> _bootstrap() async {
    if (kIntercityScreenBoard &&
        (_routeStage('active') ||
            _routeStage('chosen') ||
            _routeStage('offer') ||
            _routeStage('auction') ||
            _routeStage('fixed'))) {
      _seedBoardDriverHome();
      return;
    }
    await _loadDriverProfileState();
    unawaited(_loadDriverWallet());
    unawaited(_loadIntercityMainState());
    await _restoreActiveOrderIfAny();
    try {
      await _fillLocationFromDevice();
      if (mounted) {
        setState(() {
          _message = _isOnline
              ? 'Местоположение определено. Можно принимать заказы.'
              : 'Местоположение определено. Включите режим "Онлайн".';
        });
      }
      if (_isOnline) {
        await _updateLocation(silent: true);
        await _loadNearby(silent: true);
      }
    } catch (_) {
      // optional on first start
    }
  }

  void _seedBoardDriverHome() {
    setState(() {
      _hasResolvedDriverProfile = true;
      _driverStatus = 'APPROVED';
      _isOnline = true;
      _acceptIntercity = true;
      _driverWallet = {'money': 0};
      _nearby = [];
      _message = '';
    });
  }

  bool _routeStage(String marker) {
    return widget.routeStage == marker || routeHas(context, '$marker=1');
  }

  bool get _useIntercityBoardUi => true;

  Future<void> _notifyDailyBonus(Map<String, dynamic> profile) async {
    final raw = profile['dailyBonus'];
    if (raw is! Map || raw['credited'] != true || raw['day'] == null) return;
    final driverId = profile['id']?.toString();
    if (driverId == null) return;
    final currency = raw['currency'] == 'RUB' ? 'RUB' : 'KZT';
    final day = raw['day'].toString();
    final key = '$driverId:$day:$currency';
    if (!_bonusNotices.add(key)) return;
    final shouldShow =
        await AppPreferences.claimDailyBonusNotice(driverId, day, currency);
    if (!mounted || !shouldShow) return;
    final amount = raw['creditedAmount'] ?? raw['rewardAmount'];
    final text =
        'Бонус начислен: +${formatWalletAmount(amount)} ${currency == 'RUB' ? '₽' : '₸'} на основной баланс';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadDriverProfileState({bool metricsOnly = false}) async {
    try {
      final res = await _api.get('/driver/profile');
      final profile = Map<String, dynamic>.from(res.data as Map);
      unawaited(_notifyDailyBonus(profile));
      if (metricsOnly) {
        if (mounted) setState(() => _driverProfile = profile);
        return;
      }
      final online = profile['online'] is Map
          ? Map<String, dynamic>.from(profile['online'] as Map)
          : null;
      if (!mounted) return;
      setState(() {
        _driverProfile = profile;
        _hasResolvedDriverProfile = true;
        _driverStatus = profile['status']?.toString();
        _isOnline = (online?['isOnline'] ?? false) == true;
        _acceptIntercity = (profile['acceptIntercity'] ?? true) == true;
        if (!_acceptIntercity) {
          _activeIntercityRequests = const [];
          _myIntercityTrips = const [];
        }
        final carModelRaw = (profile['carModel'] ?? '').toString();
        if (carModelRaw.isNotEmpty) {
          _carModelCtrl.text = carModelRaw;
        }
        final carNumberRaw = (profile['carNumber'] ?? '').toString();
        if (carNumberRaw.isNotEmpty) {
          _carNumberCtrl.text = carNumberRaw;
        }
        if (online?['lastLat'] != null) {
          _latCtrl.text = online!['lastLat'].toString();
        }
        if (online?['lastLng'] != null) {
          _lngCtrl.text = online!['lastLng'].toString();
        }
        if (online?['cityId'] != null) {
          _cityIdCtrl.text = online!['cityId'].toString();
        }
      });
      if (_isOnline) {
        _startLocationUpdates();
        if (_activeOrder == null) _startNearbyPolling();
      } else {
        unawaited(_disableDriverFeeds());
      }
      unawaited(_connectDriverRealtime());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasResolvedDriverProfile = true;
        _driverStatus = null;
        _isOnline = false;
        _message = errorMessageRu(e);
      });
    }
  }

  Future<void> _openDriverProfile() async {
    await context.push('/driver/profile');
    if (!mounted) return;
    await _loadDriverProfileState();
    if (_acceptIntercity) {
      await _loadIntercityMainState();
    } else {
      setState(() {
        _activeIntercityRequests = const [];
        _myIntercityTrips = const [];
      });
    }
    if (_isOnline) {
      await _loadNearby(silent: true);
    }
  }

  Future<void> _loadDriverWallet() async {
    try {
      final res = await _api.get('/wallet');
      if (!mounted) return;
      setState(() {
        _driverWallet = Map<String, dynamic>.from(res.data as Map);
      });
    } catch (_) {
      // Wallet is auxiliary on the main driver screen.
    }
  }

  Future<void> _setOnline(bool value) async {
    if (value) {
      unawaited(_navigationSpeech.speak(''));
      unawaited(DriverOfferSound.prepare());
      unawaited(PushNotificationsService.instance.enableDriverNotifications());
    }
    if (value && !_isDriverApproved) {
      setState(() => _message = driverAccessMessageRu(_driverStatus));
      return;
    }
    if (_switchBusy) return;
    setState(() {
      _switchBusy = true;
      _pendingOnlineValue = value;
    });
    try {
      if (value) {
        {
          final gpsAge = _lastGpsAt == null
              ? null
              : DateTime.now().difference(_lastGpsAt!);
          if (_lastGpsPoint == null ||
              (_lastGpsAccuracy ?? double.infinity) > 100 ||
              gpsAge == null ||
              gpsAge.isNegative ||
              gpsAge.inSeconds > 30) {
            await _fillLocationFromDevice();
          }
        }
        final locationSaved = await _updateLocation(silent: false);
        if (!locationSaved) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(_message.isEmpty
                    ? 'Не удалось сохранить местоположение. Вы остались вне линии.'
                    : _message)));
          }
          await _loadDriverProfileState();
          return;
        }
      }
      final onlineResponse = await _api.post(
        '/driver/online',
        data: {
          'isOnline': value,
          'cityId': _cityIdCtrl.text.isEmpty ? null : _cityIdCtrl.text,
        },
      );
      if (!mounted) return;
      setState(() {
        _isOnline = onlineResponse.data is Map &&
            onlineResponse.data['isOnline'] == true;
        _message = 'Статус онлайн: ${value ? 'включен' : 'выключен'}';
      });
      if (value) {
        unawaited(_enableDriverFeeds());
      } else {
        await _disableDriverFeeds();
      }
    } catch (e) {
      final message = errorMessageRu(e);
      if (mounted) {
        setState(() => _message = message);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
      await _showTopupRequiredDialogIfNeeded(message);
      await _loadDriverProfileState();
    } finally {
      if (mounted) {
        setState(() {
          _switchBusy = false;
          _pendingOnlineValue = null;
        });
      }
    }
  }

  bool _isTopupRequiredMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('пополните баланс') ||
        normalized.contains('нужен баланс не меньше');
  }

  Future<void> _showTopupRequiredDialogIfNeeded(String message) async {
    if (!mounted ||
        _topupRequiredDialogOpen ||
        !_isTopupRequiredMessage(message)) {
      return;
    }
    _topupRequiredDialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Пополните баланс'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/driver/wallet');
            },
            child: const Text('Пополнить'),
          ),
        ],
      ),
    );
    _topupRequiredDialogOpen = false;
  }

  String _formatDriverMoney(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse((value ?? '0').toString()) ?? 0;
    if (!amount.isFinite || amount <= 0) return '0';
    const step = 50.0;
    final rounded = (amount / step).ceil() * step;
    return rounded.toStringAsFixed(0);
  }

  String? _driverProfileValue(String key) {
    final value = _driverProfile?[key];
    return value?.toString();
  }

  Future<void> _disconnectDriverRealtime() async {
    await _driverSseSub?.cancel();
    await _driverSse?.close();
    _driverSseSub = null;
    _driverSse = null;
  }

  void _clearNearbyDiscoveryState() {
    _nearbyPollTimer?.cancel();
    _pendingOfferOrderId = null;
    _notifiedOfferIds.clear();
    _spokenOfferIds.clear();
    _stopOfferAlarm();
  }

  Future<void> _disableDriverFeeds() async {
    _locationTimer?.cancel();
    await _positionStream?.cancel();
    _positionStream = null;
    _clearNearbyDiscoveryState();
    // Keep the statistics stream alive when the driver goes offline.
  }

  Future<void> _enableDriverFeeds() async {
    _startLocationUpdates();
    _startNearbyPolling();
    unawaited(_connectDriverRealtime());
    await _loadNearby(silent: true);
  }

  Future<bool> _updateLocation({
    bool autoDetect = false,
    bool silent = false,
  }) async {
    if (_updatingLocation) return false;
    _updatingLocation = true;
    try {
      if (autoDetect) {
        await _fillLocationFromDevice();
      }
      await _api.post(
        '/driver/location',
        data: {
          'lat': double.parse(_latCtrl.text),
          'lng': double.parse(_lngCtrl.text),
          'cityId': _cityIdCtrl.text.isEmpty ? null : _cityIdCtrl.text,
        },
      );
      if (mounted && !silent) {
        setState(() => _message = 'Местоположение обновлено');
      }
      _updateNavigationProgress();
      return true;
    } catch (e) {
      final message = errorMessageRu(e);
      if (mounted && !silent) {
        setState(() => _message = message);
      }
      await _showTopupRequiredDialogIfNeeded(message);
      return false;
    } finally {
      _updatingLocation = false;
    }
  }

  Future<void> _fillLocationFromDevice() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Разрешите доступ к геолокации для водителя');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
    if (pos.accuracy > 100) {
      throw Exception('Не удалось получить точное местоположение водителя');
    }
    _applyDriverPosition(pos);
  }

  Future<void> _loadNearby({bool silent = false}) async {
    if (_isWaitingAuctionDecision) {
      if (mounted && !silent) {
        setState(() => _message = 'Ждём ответ пассажира по вашей цене.');
      }
      return;
    }
    if (_loadingNearby) return;
    _loadingNearby = true;
    try {
      final oldIds = _nearby
          .whereType<Map>()
          .map((e) => driverOfferIdentity(Map<String, dynamic>.from(e)))
          .where((id) => id.isNotEmpty)
          .toSet();
      final res = await _api.get('/driver/orders/nearby');
      final list = List<dynamic>.from(res.data as List);
      if (!mounted) return;
      final normalized = list
          .whereType<Map>()
          .map((e) => normalizeDriverOffer(Map<String, dynamic>.from(e)))
          .where((order) => offerSecondsLeft(order) > 0)
          .toList();
      setState(() {
        _nearby = normalized;
        if (!silent) {
          _message = _nearby.isEmpty
              ? 'Пока нет ближайших заказов. Оставайтесь онлайн.'
              : 'Ближайших заказов: ${_nearby.length}';
        }
      });
      if (_offerAlarmOrderId != null) {
        final hasAlarmOffer = normalized.any(
          (o) => (o['id'] ?? '').toString() == _offerAlarmOrderId,
        );
        if (!hasAlarmOffer) {
          _stopOfferAlarm();
        }
      }
      await _handleIncomingOffers(oldIds, normalized);
      _startOfferCountdownTicker();
      unawaited(_loadIntercityMainState());
    } catch (e) {
      final message = errorMessageRu(e);
      if (mounted && !silent) {
        setState(() => _message = message);
      }
      await _showTopupRequiredDialogIfNeeded(message);
    } finally {
      _loadingNearby = false;
    }
  }

  Future<void> _loadIntercityMainState() async {
    if (!_acceptIntercity) {
      if (mounted) {
        setState(() {
          _activeIntercityRequests = const [];
          _myIntercityTrips = const [];
        });
      }
      return;
    }
    try {
      final responses = await Future.wait([
        _api.get('/driver/intercity/active'),
        _api.get('/ridesharing/trips/my'),
      ]);
      if (!mounted) return;
      final active = List<dynamic>.from(responses[0].data as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final trips = List<dynamic>.from(responses[1].data as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((trip) {
        final status = (trip['status'] ?? '').toString().toUpperCase();
        return const ['OPEN', 'FULL'].contains(status);
      }).toList();
      setState(() {
        _activeIntercityRequests = active;
        _myIntercityTrips = trips;
      });
    } catch (_) {
      // Межгородний блок вспомогательный, не мешаем основному экрану.
    }
  }

  Future<void> _handleIncomingOffers(
    Set<String> oldIds,
    List<Map<String, dynamic>> normalized,
  ) async {
    final currentIds = normalized
        .map(driverOfferIdentity)
        .where((id) => id.isNotEmpty)
        .toSet();
    _notifiedOfferIds.removeWhere((id) => !currentIds.contains(id));
    _spokenOfferIds.removeWhere((id) => !currentIds.contains(id));
    if (!_isOnline ||
        _activeOrder != null ||
        _isWaitingAuctionDecision ||
        normalized.isEmpty) {
      return;
    }
    final newOffers = normalized.where((o) {
      final id = (o['id'] ?? '').toString();
      return id.isNotEmpty && !oldIds.contains(driverOfferIdentity(o));
    }).toList();
    if (newOffers.isEmpty) return;
    final first = newOffers.first;
    final firstId = (first['id'] ?? '').toString();
    if (firstId.isEmpty) return;
    final offerIdentity = driverOfferIdentity(first);
    if (_notifiedOfferIds.contains(offerIdentity)) return;
    _notifiedOfferIds.add(offerIdentity);
    unawaited(PushNotificationsService.instance
        .showDriverOfferNotification(
          orderId: firstId,
          fromAddress: (first['fromAddress'] ?? 'Точка подачи').toString(),
          toAddress: (first['toAddress'] ?? 'Точка назначения').toString(),
          secondsLeft: _offerSecondsLeft(first),
        )
        .catchError((Object _) {}));
    if (_appLifecycleState == AppLifecycleState.resumed) {
      if (_offerDialogOpen) {
        _pendingOfferOrderId = firstId;
      } else {
        unawaited(_showOfferAcceptDialog(first));
      }
      return;
    }
    _pendingOfferOrderId = firstId;
    _startOfferAlarm(firstId);
  }

  Future<void> _showPendingOfferDialogIfNeeded() async {
    if (!mounted || _offerDialogOpen || _activeOrder != null || !_isOnline) {
      return;
    }
    final pendingId = _pendingOfferOrderId;
    if (pendingId == null || pendingId.isEmpty) return;
    final order = _nearby
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere(
          (o) => (o['id'] ?? '').toString() == pendingId,
          orElse: () => <String, dynamic>{},
        );
    _pendingOfferOrderId = null;
    if (order.isEmpty || _offerSecondsLeft(order) <= 0) return;
    await _showOfferAcceptDialog(order);
  }

  void _stopOfferAlarm() {
    final orderId = _offerAlarmOrderId;
    if (orderId != null) {
      unawaited(PushNotificationsService.instance
          .cancelDriverOfferNotification(orderId));
    }
    unawaited(DriverOfferSound.stop());
    _offerAlarmTimer?.cancel();
    _offerAlarmTimer = null;
    _offerAlarmOrderId = null;
  }

  void _stopOfferAlarmIfMatches(String orderId) {
    if (_offerAlarmOrderId == orderId) {
      _stopOfferAlarm();
    }
  }

  void _startOfferAlarm(String orderId) {
    _offerAlarmTimer?.cancel();
    _offerAlarmOrderId = orderId;
    _offerAlarmTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (!mounted || !_isOnline || _activeOrder != null) {
        _stopOfferAlarm();
        return;
      }
      final offer = _nearby
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .firstWhere(
            (o) => (o['id'] ?? '').toString() == orderId,
            orElse: () => <String, dynamic>{},
          );
      if (offer.isEmpty) {
        _stopOfferAlarm();
        return;
      }
      final sec = _offerSecondsLeft(offer);
      if (sec <= 0) {
        _stopOfferAlarm();
        return;
      }
      try {
        await DriverOfferSound.play();
      } catch (_) {
        // Keep visual countdown/dialog if device blocks system sound.
      }
      if (_appLifecycleState == AppLifecycleState.resumed) {
        return;
      }
    });
  }

  Future<void> _showOfferAcceptDialog(Map<String, dynamic> order) async {
    _offerCurrencySymbol = rideCurrencySymbol(order);
    if (!mounted || _offerDialogOpen || _activeOrder != null || !_isOnline) {
      return;
    }
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;
    _offerDialogOpen = true;
    _playNewOfferSoundOnce(driverOfferIdentity(order));
    _startOfferAlarm(orderId);
    var secondsLeft = _offerSecondsLeft(order);
    final typeRaw =
        (order['requestType'] ?? order['orderType'] ?? order['type'] ?? '')
            .toString()
            .toLowerCase();
    final isAuction = typeRaw.contains('auction');
    final sourceType = (order['sourceType'] ?? '').toString().toUpperCase();
    final modeRaw = (order['mode'] ?? '').toString().toUpperCase();
    final isIntercityRequest =
        sourceType == 'INTERCITY_REQUEST' || modeRaw == 'INTERCITY';
    final requiresPriceOffer = isAuction || isIntercityRequest;
    final orderTypeLabel = isIntercityRequest
        ? 'Межгородняя заявка'
        : isAuction
            ? 'Аукционный заказ'
            : 'Фиксированный заказ';
    final orderTypeIcon = isIntercityRequest
        ? Icons.alt_route_rounded
        : isAuction
            ? Icons.gavel_rounded
            : Icons.local_taxi_rounded;
    final priceLabel = requiresPriceOffer
        ? 'Предложите цену'
        : '${order['price'] ?? '-'} ${rideCurrencySymbol(order)}';
    final fromAddress = (order['fromAddress'] ?? 'Точка подачи').toString();
    final toAddress = (order['toAddress'] ?? 'Точка назначения').toString();
    final paymentLabel = paymentMethodLabel(order['paymentMethod']?.toString());
    final vehicleLabel = vehicleClassLabel(
      order['vehicleClass']?.toString() ?? '',
    );
    final auctionPriceController = TextEditingController();
    final suggestedOfferPrices = _buildAuctionOfferPriceSuggestions(order);
    var completed = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DriverOfferExpiryWatcher(
                secondsLeft: () {
                  final liveOrder = _nearby
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .firstWhere(
                        (o) => (o['id'] ?? '').toString() == orderId,
                        orElse: () => <String, dynamic>{},
                      );
                  return liveOrder.isEmpty || !_isOnline || _activeOrder != null
                      ? 0
                      : _offerSecondsLeft(liveOrder);
                },
                onTick: (remaining) {
                  if (!completed && context.mounted) {
                    setDialogState(() => secondsLeft = remaining);
                  }
                },
                onExpired: () {
                  if (completed || !ctx.mounted) return;
                  completed = true;
                  _stopOfferAlarmIfMatches(orderId);
                  final route = ModalRoute.of(ctx);
                  if (route != null) {
                    if (route.isCurrent) {
                      Navigator.of(ctx).pop();
                    } else {
                      Navigator.of(ctx).removeRoute(route);
                    }
                  }
                },
                child: PopScope(
                  canPop: false,
                  child: Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: SafeArea(
                      child: AnimatedPadding(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                        ),
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF1B0D33),
                                  Color(0xFF0B0817),
                                  Color(0xFF120B24),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: (secondsLeft <= 10
                                        ? Colors.redAccent
                                        : AppTheme.secondaryColor)
                                    .withValues(alpha: 0.28),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x77000000),
                                  blurRadius: 26,
                                  offset: Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 166,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(24),
                                      gradient: RadialGradient(
                                        center: const Alignment(0.1, -0.1),
                                        radius: 1.1,
                                        colors: [
                                          AppTheme.primaryColor.withValues(
                                            alpha: 0.40,
                                          ),
                                          const Color(0xFF120B24),
                                          const Color(0xFF07050F),
                                        ],
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: _driverOrderRoutePreview(order,
                                              dark: true),
                                        ),
                                        Positioned(
                                          left: 16,
                                          top: 16,
                                          child: _offerBadge(
                                            icon: orderTypeIcon,
                                            label: orderTypeLabel,
                                          ),
                                        ),
                                        Positioned(
                                          right: 16,
                                          top: 16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                18,
                                              ),
                                            ),
                                            child: Text(
                                              '$secondsLeft сек',
                                              style: TextStyle(
                                                color: secondsLeft <= 10
                                                    ? Colors.redAccent
                                                    : Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 16,
                                          bottom: 16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                18,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppTheme.primaryColor
                                                      .withValues(alpha: 0.24),
                                                  blurRadius: 18,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  requiresPriceOffer
                                                      ? Icons.gavel_rounded
                                                      : Icons.payments_rounded,
                                                  color: AppTheme.primaryColor,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  priceLabel,
                                                  style: TextStyle(
                                                    color: isAuction
                                                        ? AppTheme.primaryColor
                                                        : Colors.black,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: requiresPriceOffer
                                                        ? 13
                                                        : 18,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const Positioned(
                                          right: 24,
                                          bottom: 18,
                                          child: Icon(
                                            Icons.directions_car_filled_rounded,
                                            color: Colors.white,
                                            size: 38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              orderTypeLabel,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 22,
                                                height: 1.05,
                                                letterSpacing: 0,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              requiresPriceOffer
                                                  ? 'Предложите свою цену пассажиру'
                                                  : 'Пассажир ждёт принятия заказа',
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                        ),
                                        child: Text(
                                          priceLabel,
                                          style: TextStyle(
                                            color: AppTheme.primaryColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize:
                                                requiresPriceOffer ? 12 : 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Column(
                                              children: [
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color:
                                                        AppTheme.primaryColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                Container(
                                                  width: 2,
                                                  height: 32,
                                                  color: AppTheme.primaryColor
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _routeText(
                                                title: 'Откуда',
                                                address: fromAddress,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              margin:
                                                  const EdgeInsets.only(top: 4),
                                              decoration: const BoxDecoration(
                                                color: AppTheme.secondaryColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: _routeText(
                                                title: 'Куда',
                                                address: toAddress,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if ((order['paymentMethod'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        _offerInfoChip(
                                          icon: Icons.credit_card_rounded,
                                          label: 'Оплата: $paymentLabel',
                                        ),
                                      if ((order['vehicleClass'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        _offerInfoChip(
                                          icon: Icons.event_seat_rounded,
                                          label: 'Класс: $vehicleLabel',
                                        ),
                                      if (order['distanceKm'] is num)
                                        _offerInfoChip(
                                          icon: Icons.near_me_rounded,
                                          label:
                                              'До подачи: ${((order['distanceKm'] as num).toDouble()).toStringAsFixed(1)} км',
                                        ),
                                      if ((order['comment'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        _offerInfoChip(
                                          icon:
                                              Icons.chat_bubble_outline_rounded,
                                          label:
                                              'Комментарий: ${order['comment']}',
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (requiresPriceOffer) ...[
                                    if (suggestedOfferPrices.isNotEmpty) ...[
                                      _auctionPriceSuggestions(
                                        prices: suggestedOfferPrices,
                                        controller: auctionPriceController,
                                        setDialogState: setDialogState,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    TextField(
                                      controller: auctionPriceController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: false,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Ваша цена',
                                        suffixText: rideCurrencySymbol(order),
                                        labelStyle: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                        suffixStyle: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withValues(
                                          alpha: 0.07,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          borderSide: BorderSide(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          borderSide: BorderSide(
                                            color: Colors.white.withValues(
                                              alpha: 0.12,
                                            ),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          borderSide: const BorderSide(
                                            color: AppTheme.primaryColor,
                                            width: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: (secondsLeft <= 10
                                                ? Colors.redAccent
                                                : AppTheme.primaryColor)
                                            .withValues(alpha: 0.20),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.timer_outlined,
                                              color: secondsLeft <= 10
                                                  ? Colors.redAccent
                                                  : Colors.white70,
                                              size: 17,
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                secondsLeft <= 10
                                                    ? 'Автопропуск через несколько секунд'
                                                    : 'Время на решение',
                                                style: TextStyle(
                                                  color: secondsLeft <= 10
                                                      ? Colors.redAccent
                                                      : Colors.white70,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '$secondsLeft сек',
                                              style: TextStyle(
                                                color: secondsLeft <= 10
                                                    ? Colors.redAccent
                                                    : Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: LinearProgressIndicator(
                                            minHeight: 6,
                                            value:
                                                (secondsLeft.clamp(0, 30)) / 30,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.08),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              secondsLeft <= 10
                                                  ? Colors.redAccent
                                                  : AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _dialogActionButton(
                                          label: 'Отклонить',
                                          onPressed: () async {
                                            if (completed) return;
                                            completed = true;
                                            _stopOfferAlarmIfMatches(orderId);
                                            if (Navigator.of(ctx).canPop()) {
                                              Navigator.of(ctx).pop();
                                            }
                                            if (isIntercityRequest) {
                                              _declinedNextOfferIds
                                                  .add(orderId);
                                              if (mounted) {
                                                setState(() {
                                                  _nearby.removeWhere(
                                                    (o) =>
                                                        (o['id'] ?? '')
                                                            .toString() ==
                                                        orderId,
                                                  );
                                                  _message = 'Заявка скрыта.';
                                                });
                                              }
                                            } else {
                                              await _rejectNearby(orderId);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _dialogActionButton(
                                          label: requiresPriceOffer
                                              ? 'Откликнуться'
                                              : 'Принять',
                                          filled: true,
                                          onPressed: () async {
                                            if (requiresPriceOffer) {
                                              final price = double.tryParse(
                                                    auctionPriceController.text
                                                        .replaceAll(',', '.'),
                                                  ) ??
                                                  0;
                                              if (price <= 0) {
                                                setDialogState(() {});
                                                if (mounted) {
                                                  setState(
                                                    () => _message =
                                                        'Укажите цену предложения.',
                                                  );
                                                }
                                                return;
                                              }
                                            }
                                            if (completed) return;
                                            completed = true;
                                            _stopOfferAlarmIfMatches(orderId);
                                            if (Navigator.of(ctx).canPop()) {
                                              Navigator.of(ctx).pop();
                                            }
                                            if (isAuction) {
                                              await _sendAuctionOffer(
                                                orderId,
                                                auctionPriceController.text,
                                              );
                                            } else if (isIntercityRequest) {
                                              await _sendIntercityOffer(
                                                orderId,
                                                auctionPriceController.text,
                                              );
                                            } else {
                                              await _accept(orderId);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ));
          },
        );
      },
    );
    auctionPriceController.dispose();
    _offerDialogOpen = false;
    _stopOfferAlarmIfMatches(orderId);
    if (mounted) unawaited(_showPendingOfferDialogIfNeeded());
  }

  Widget _offerBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(18);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: filled
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              border: filled
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: 0.16)),
              boxShadow: filled && enabled
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _routeText({required String title, required String address}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _offerInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.secondaryColor, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _buildAuctionOfferPriceSuggestions(Map<String, dynamic> order) {
    final explicitPrice = _readNumber(order, const [
      'recommendedPrice',
      'suggestedPrice',
      'estimatedPrice',
      'price',
    ]);
    final routeDistanceKm = _readNumber(order, const [
      'routeDistanceKm',
      'distanceRouteKm',
      'distanceKm',
    ]);
    final base = explicitPrice ??
        (routeDistanceKm == null
            ? 1200
            : math.max(900, 650 + routeDistanceKm * 140));
    final roundedBase = _roundPrice(base);
    final step = math.max(100, _roundPrice(roundedBase * 0.12)).toInt();
    return {
      roundedBase,
      _roundPrice(roundedBase + step),
      _roundPrice(roundedBase + step * 2),
      _roundPrice(roundedBase + step * 3),
    }.toList();
  }

  num? _readNumber(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is num && value.isFinite) return value;
      if (value is String) {
        final parsed = num.tryParse(value.replaceAll(',', '.'));
        if (parsed != null && parsed.isFinite) return parsed;
      }
    }
    return null;
  }

  int _roundPrice(num value) {
    return ((value / 50).round() * 50).clamp(500, 999999).toInt();
  }

  Widget _auctionPriceSuggestions({
    required List<int> prices,
    required TextEditingController controller,
    required StateSetter setDialogState,
  }) {
    final current = int.tryParse(controller.text.trim());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.secondaryColor,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Рекомендуемая цена',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < prices.length; i++)
                _auctionPriceButton(
                  price: prices[i],
                  label: i == 0 ? 'Рекоменд.' : '+${prices[i] - prices[0]}',
                  selected: current == prices[i],
                  onTap: () {
                    controller.text = prices[i].toString();
                    controller.selection = TextSelection.collapsed(
                      offset: controller.text.length,
                    );
                    setDialogState(() {});
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _auctionPriceButton({
    required int price,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$price $_offerCurrencySymbol',
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF171122),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: 0.76)
                    : AppTheme.primaryColor,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(String id) async {
    try {
      await _api.post('/driver/orders/$id/accept');
      _stopOfferAlarmIfMatches(id);
      setState(() => _message = 'Заказ $id принят');
      await _loadOrderById(id);
      _startActiveOrderPolling(id);
      _nearbyPollTimer?.cancel();
      await _loadNearby(silent: true);
    } catch (e) {
      if (!mounted) return;
      final message = errorMessageRu(e);
      setState(() => _message = message);
      if (message.contains('недоступ')) {
        await _loadNearby(silent: true);
      }
    }
  }

  Future<void> _sendAuctionOffer(String id, String rawPrice) async {
    try {
      final price = double.tryParse(rawPrice.replaceAll(',', '.')) ?? 0;
      if (price <= 0) {
        setState(() => _message = 'Укажите цену предложения.');
        return;
      }
      final res = await _api.post(
        '/orders/$id/offers',
        data: {'price': price},
      );
      _declinedNextOfferIds.add(id);
      _nearby.removeWhere((o) => (o['id'] ?? '').toString() == id);
      _stopOfferAlarmIfMatches(id);
      if (!mounted) return;
      final offer = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final offerId = (offer['id'] ?? '').toString();
      setState(() => _message = 'Цена отправлена. Ждём ответ пассажира.');
      _startAuctionOfferWait(id, offerId: offerId.isEmpty ? null : offerId);
    } catch (e) {
      if (!mounted) return;
      final message = errorMessageRu(e);
      setState(() => _message = message);
      if (message.contains('недоступ')) {
        await _loadNearby(silent: true);
      }
    }
  }

  Future<void> _sendIntercityOffer(String id, String rawPrice) async {
    try {
      final price = double.tryParse(rawPrice.replaceAll(',', '.')) ?? 0;
      if (price <= 0) {
        setState(() => _message = 'Укажите цену предложения.');
        return;
      }
      await _api.post(
        '/intercity/requests/$id/offers',
        data: {'price': price, 'seats': 1},
      );
      _declinedNextOfferIds.add(id);
      _nearby.removeWhere((o) => (o['id'] ?? '').toString() == id);
      _stopOfferAlarmIfMatches(id);
      if (!mounted) return;
      setState(() => _message = 'Отклик на межгород отправлен пассажиру.');
      await _loadNearby(silent: true);
      await _loadIntercityMainState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _rejectNearby(String id) async {
    try {
      final res = await _api.post('/driver/orders/$id/reject');
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final activity = data['activityScore'];
      final blockedUntil = data['blockedUntil'];
      if (!mounted) return;
      setState(() {
        _nearby = _nearby
            .where((item) => (item as Map<String, dynamic>)['id'] != id)
            .toList();
        _message = blockedUntil != null
            ? 'Вы отказались от предложения. Активность: ${activity ?? '-'} (блокировка на 12 часов)'
            : 'Вы отказались от предложения. Активность: ${activity ?? '-'}';
      });
      _stopOfferAlarmIfMatches(id);
      await _loadDriverProfileState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _loadOrderById(String id) async {
    try {
      final res = await _api.get('/orders/$id');
      if (!mounted) return;
      final order = Map<String, dynamic>.from(res.data as Map);
      final status = (order['status'] ?? '').toString().toUpperCase();
      setState(() => _activeOrder = order);
      await _syncActiveRoutePolyline(order);
      if (const ['COMPLETED', 'CANCELLED'].contains(status)) {
        _activeOrderPollTimer?.cancel();
        _activeRoutePolyline = [];
        _activeRouteCacheKey = null;
        _navSteps = const [];
        _navStepIndex = 0;
        _declinedNextOfferIds.clear();
        if (_isOnline) {
          _startNearbyPolling();
          await _loadNearby(silent: true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _loadActiveIntercityById(String id) async {
    try {
      final res = await _api.get('/driver/intercity/active');
      final active = List<dynamic>.from(res.data as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      final request = active.firstWhere(
        (item) => (item['id'] ?? '').toString() == id,
        orElse: () => <String, dynamic>{},
      );
      if (!mounted) return;
      if (request.isEmpty) {
        setState(() {
          _activeOrder = null;
          _activeRoutePolyline = [];
          _activeRouteCacheKey = null;
          _navSteps = const [];
          _navStepIndex = 0;
        });
        if (_isOnline) _startNearbyPolling();
        await _loadNearby(silent: true);
        await _loadIntercityMainState();
        return;
      }
      setState(() => _activeOrder = request);
      await _syncActiveRoutePolyline(request);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _syncActiveRoutePolyline(Map<String, dynamic> order) async {
    final status = (order['status'] ?? '').toString().toUpperCase();
    if (status == 'COMPLETED' || status == 'CANCELLED') {
      _activeRouteRequest++;
      if (mounted) {
        setState(() {
          _activeRoutePolyline = [];
          _activeRouteCacheKey = null;
          _navSteps = const [];
          _navStepIndex = 0;
        });
      }
      return;
    }

    double? fromLat;
    double? fromLng;
    double? toLat;
    double? toLng;

    if (status == 'IN_PROGRESS') {
      final from = _activeDriverPoint();
      final to = _orderPoint(order['toLat'], order['toLng']);
      if (from == null || to == null) return;
      fromLat = from.latitude;
      fromLng = from.longitude;
      toLat = to.latitude;
      toLng = to.longitude;
    } else {
      final driver = _activeDriverPoint();
      final passenger = _orderPoint(order['fromLat'], order['fromLng']);
      if (driver == null || passenger == null) return;
      fromLat = driver.latitude;
      fromLng = driver.longitude;
      toLat = passenger.latitude;
      toLng = passenger.longitude;
    }

    final cacheKey = [
      order['id'],
      status,
      fromLat.toStringAsFixed(4),
      fromLng.toStringAsFixed(4),
      toLat.toStringAsFixed(4),
      toLng.toStringAsFixed(4),
    ].join('|');
    if (_activeRouteCacheKey == cacheKey) return;
    if (_activeRoutePendingKey == cacheKey) return;
    final phase = '${order['id']}|$status|$toLat|$toLng';
    final now = DateTime.now();
    if (_activeRoutePhase == phase &&
        _activeRouteStartedAt != null &&
        now.difference(_activeRouteStartedAt!) < const Duration(seconds: 5)) {
      return;
    }
    _activeRoutePhase = phase;
    _activeRouteStartedAt = now;
    _activeRoutePendingKey = cacheKey;
    final request = ++_activeRouteRequest;

    try {
      final res = await _api.get(
        '/route',
        queryParameters: {
          'fromLat': fromLat,
          'fromLng': fromLng,
          'toLat': toLat,
          'toLng': toLng,
        },
      );
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final geometry = data['geometry'];
      final points = <LatLng>[];
      if (geometry is Map && geometry['coordinates'] is List) {
        for (final c in (geometry['coordinates'] as List)) {
          if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
            points.add(
              LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            );
          }
        }
      }
      if (points.length < 2) {
        throw const FormatException('Road route unavailable');
      }
      final steps = _extractNavSteps(data);
      if (!mounted || request != _activeRouteRequest) return;
      final hadSteps = _navSteps.isNotEmpty;
      setState(() {
        _activeRoutePolyline = points;
        _activeRouteCacheKey = cacheKey;
        _navSteps = steps;
        _navStepIndex = 0;
      });
      _updateNavigationProgress(announce: !hadSteps && steps.isNotEmpty);
    } catch (_) {
      if (mounted && request == _activeRouteRequest) {
        setState(() {
          _activeRoutePolyline = [];
          _activeRouteCacheKey = null;
          _navSteps = const [];
          _navStepIndex = 0;
        });
      }
    } finally {
      if (request == _activeRouteRequest) _activeRoutePendingKey = null;
    }
  }

  Future<void> _restoreActiveOrderIfAny() async {
    try {
      final res = await _api.get('/orders/my');
      final list = List<dynamic>.from(res.data as List);
      final active =
          list.cast<Map>().map((e) => Map<String, dynamic>.from(e)).firstWhere(
                (o) => const [
                  'DRIVER_ASSIGNED',
                  'DRIVER_EN_ROUTE',
                  'DRIVER_ARRIVED',
                  'IN_PROGRESS',
                ].contains((o['status'] ?? '').toString()),
                orElse: () => <String, dynamic>{},
              );
      if (active.isNotEmpty) {
        final id = active['id']?.toString();
        if (id != null && id.isNotEmpty) {
          await _loadOrderById(id);
          _startActiveOrderPolling(id);
        }
      }
    } catch (_) {
      // optional
    }
  }

  void _startActiveOrderPolling(String id) {
    _activeOrderPollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _activeOrderPollTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      await _loadOrderById(id);
      final status = (_activeOrder?['status'] ?? '').toString().toUpperCase();
      if (const ['COMPLETED', 'CANCELLED'].contains(status)) {
        _activeOrderPollTimer?.cancel();
        if (_isOnline) _startNearbyPolling();
      }
    });
  }

  Future<void> _setActiveOrderStatus(String status) async {
    final id = _activeOrder?['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      if (_activeOrderIsIntercity) {
        await _api.post(
          '/intercity/requests/$id/status',
          data: {'status': status},
        );
        if (status == 'COMPLETED' || status == 'CANCELLED') {
          setState(() {
            _activeOrder = null;
            _activeRoutePolyline = [];
            _activeRouteCacheKey = null;
            _navSteps = const [];
            _navStepIndex = 0;
          });
        } else {
          setState(() => _activeOrder = {...?_activeOrder, 'status': status});
          await _syncActiveRoutePolyline(_activeOrder!);
        }
        await _loadIntercityMainState();
      } else {
        await _api.post('/orders/$id/status', data: {'status': status});
        await _loadOrderById(id);
      }
      if (status == 'DRIVER_ARRIVED' && _navSteps.isNotEmpty) {
        _announceManeuver(_navSteps.last, 0);
      }
      setState(() => _message = 'Статус заказа обновлен');
      if (status == 'COMPLETED' || status == 'CANCELLED') {
        _activeOrderPollTimer?.cancel();
        _declinedNextOfferIds.clear();
        await _loadDriverProfileState();
        await _loadDriverWallet();
        if (_isOnline) _startNearbyPolling();
        await _loadNearby(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      final message = errorMessageRu(e);
      setState(() => _message = message);
      if (message.contains('Статус заказа')) {
        await _loadOrderById(id);
      }
    }
  }

  bool get _activeOrderIsIntercity {
    final order = _activeOrder;
    if (order == null) return false;
    final sourceType = (order['sourceType'] ?? '').toString().toUpperCase();
    final mode = (order['mode'] ?? '').toString().toUpperCase();
    final requestType = (order['requestType'] ?? '').toString().toUpperCase();
    return sourceType == 'INTERCITY_REQUEST' ||
        mode == 'INTERCITY' ||
        requestType == 'INTERCITY';
  }

  void _applyDriverPosition(Position position) {
    if (!mounted || position.accuracy > 100) return;
    final previous = _lastGpsPoint;
    final point = LatLng(position.latitude, position.longitude);
    _lastGpsPoint = point;
    _lastGpsAt = position.timestamp;
    _lastGpsAccuracy = position.accuracy;
    final activeOrder = _activeOrder;
    _pickupDeparture.update(
      id: activeOrder?['id']?.toString(),
      arrived: activeOrder?['status'] == 'DRIVER_ARRIVED',
      pickup: activeOrder == null
          ? null
          : _orderPoint(activeOrder['fromLat'], activeOrder['fromLng']),
      point: point,
      accuracy: position.accuracy,
      speed: position.speed,
      timestamp: position.timestamp,
      now: DateTime.now(),
    );
    var heading = _driverHeading;
    if (position.speed > 1 &&
        position.heading.isFinite &&
        position.heading >= 0) {
      heading = position.heading % 360;
    } else if (previous != null &&
        const Distance().as(LengthUnit.Meter, previous, point) > 5) {
      heading = const Distance().bearing(previous, point);
      heading = (heading + 360) % 360;
    }
    setState(() {
      _latCtrl.text = position.latitude.toStringAsFixed(6);
      _lngCtrl.text = position.longitude.toStringAsFixed(6);
      _driverHeading = heading;
    });
    _updateNavigationProgress();
    if (_activeOrder case final order?) {
      unawaited(_syncActiveRoutePolyline(order));
    }
  }

  Future<void> _startPositionStream() async {
    await _positionStream?.cancel();
    _positionStream = null;
    try {
      final permission = await Geolocator.checkPermission();
      if (!mounted ||
          !_isOnline ||
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      _positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high, distanceFilter: 2))
          .listen(_applyDriverPosition, onError: (Object _) {
        // The existing periodic GPS update remains available as a fallback.
      });
    } catch (_) {
      // Periodic location updates remain available if GPS streaming fails.
    }
  }

  void _startLocationUpdates() {
    unawaited(_startPositionStream());
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isOnline) return;
      _updateLocation(autoDetect: true, silent: true);
    });
  }

  void _startNearbyPolling() {
    if (!_isOnline || _activeOrder != null) return;
    _nearbyPollTimer?.cancel();
    _nearbyPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isOnline || _activeOrder != null) return;
      await _loadNearby(silent: true);
    });
  }

  Future<void> _connectDriverRealtime() async {
    await _disconnectDriverRealtime();
    final conn = await SseService.connect('/realtime/driver/me/stream');
    if (!mounted) {
      await conn?.close();
      return;
    }
    if (conn == null) return;
    _driverSse = conn;
    _driverSseSub = conn.stream.listen((event) async {
      final eventType = (event['event'] ?? '').toString();
      if (eventType != 'driver-event' && eventType != 'order-event') return;
      final raw = event['data'];
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      final type = (data['type'] ?? '').toString().toLowerCase();
      if (type == 'driver.rating.updated' ||
          type == 'driver.activity.updated' ||
          type == 'driver.bonus.updated') {
        await _loadDriverProfileState(metricsOnly: true);
        if (type == 'driver.bonus.updated') await _loadDriverWallet();
        return;
      }
      if (type == 'driver.location.updated') return;
      if (type == 'order.status.changed') {
        unawaited(_loadDriverProfileState(metricsOnly: true));
        unawaited(_loadDriverWallet());
      }
      if (type == 'driver.online.changed') {
        final payload = data['payload'] is Map
            ? Map<String, dynamic>.from(data['payload'] as Map)
            : <String, dynamic>{};
        final isOnline = payload['isOnline'] == true;
        final reason = (payload['reason'] ?? '').toString().toUpperCase();
        if (!isOnline && reason == 'OFFER_TIMEOUT') {
          setState(() {
            _isOnline = false;
            _nearby = const [];
          });
          await _disableDriverFeeds();
          await _loadDriverProfileState(metricsOnly: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Заказ пропущен: −3 балла активности. Вы сняты с линии.'),
            ));
          }
          return;
        }
        if (!isOnline && reason == 'ACTIVITY_BLOCKED') {
          if (mounted) {
            setState(() {
              _isOnline = false;
              _nearby = const [];
            });
          }
          await _disableDriverFeeds();
          await _loadDriverProfileState(metricsOnly: true);
          return;
        }
        if (!isOnline && reason == 'LOW_BALANCE') {
          final minBalance = (payload['minBalance'] ?? 100).toString();
          final balance = (payload['balance'] ?? 0).toString();
          final message =
              'Баланс меньше $minBalance ₸. Сейчас доступно $balance ₸. Пополните баланс, чтобы получать заказы.';
          if (mounted) {
            setState(() {
              _isOnline = false;
              _nearby = const [];
              _message = message;
            });
          }
          _nearbyPollTimer?.cancel();
          await _showTopupRequiredDialogIfNeeded(message);
          return;
        }
      }
      final now = DateTime.now();
      final last = _lastRealtimeRefreshAt;
      if (last != null && now.difference(last).inMilliseconds < 800) return;
      _lastRealtimeRefreshAt = now;
      if (!_isOnline) return;
      if (_activeOrder != null) {
        final activeId = (_activeOrder?['id'] ?? '').toString();
        if (activeId.isNotEmpty) {
          if (_activeOrderIsIntercity) {
            await _loadActiveIntercityById(activeId);
          } else {
            await _loadOrderById(activeId);
          }
        }
      } else {
        await _restoreActiveOrderIfAny();
        await _loadNearby(silent: true);
      }
    }, onDone: () {
      _driverSse = null;
    }, onError: (Object _) {
      unawaited(_disconnectDriverRealtime());
    });
  }

  String _orderStatusRu(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
      case 'DRIVER_ASSIGNED':
        return 'Назначен';
      case 'DRIVER_EN_ROUTE':
        return 'Еду к пассажиру';
      case 'DRIVER_ARRIVED':
        return 'Прибыл';
      case 'IN_PROGRESS':
        return 'В пути';
      case 'COMPLETED':
        return 'Завершен';
      case 'CANCELLED':
        return 'Отменен';
      default:
        return status;
    }
  }

  LatLng? _activeDriverPoint() {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng? _orderPoint(dynamic lat, dynamic lng) {
    if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    return null;
  }

  bool _canMoveToStatus(String next) {
    final current = (_activeOrder?['status'] ?? '').toString().toUpperCase();
    switch (next) {
      case 'DRIVER_ARRIVED':
        return current == 'ACCEPTED' ||
            current == 'DRIVER_EN_ROUTE' ||
            current == 'DRIVER_ASSIGNED';
      case 'IN_PROGRESS':
        return current == 'DRIVER_ARRIVED';
      case 'COMPLETED':
        return current == 'IN_PROGRESS';
      default:
        return false;
    }
  }

  ({String label, IconData icon, String nextStatus})? _primaryRideAction(
    String status,
  ) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
        return (
          label: 'На месте',
          icon: Icons.location_on_rounded,
          nextStatus: 'DRIVER_ARRIVED',
        );
      case 'DRIVER_ARRIVED':
        return (
          label: 'Начать поездку',
          icon: Icons.navigation_rounded,
          nextStatus: 'IN_PROGRESS',
        );
      case 'IN_PROGRESS':
        return (
          label: 'Завершить поездку',
          icon: Icons.check_rounded,
          nextStatus: 'COMPLETED',
        );
      default:
        return null;
    }
  }

  Color _driverStatusColor() {
    final s = (_driverStatus ?? '').toUpperCase();
    if (s == 'ACTIVE' || s == 'APPROVED') return Colors.green;
    if (s == 'REJECTED') return Colors.red;
    return Colors.orange;
  }

  double? _distanceToActiveDestinationKm() {
    final order = _activeOrder;
    if (order == null) return null;
    final driver = _activeDriverPoint();
    final to = _activeNavigationDestination(order);
    if (driver == null || to == null) return null;
    return _distanceKm(
      driver.latitude,
      driver.longitude,
      to.latitude,
      to.longitude,
    );
  }

  LatLng? _activeNavigationDestination(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toUpperCase();
    if (status == 'IN_PROGRESS') {
      return _orderPoint(order['toLat'], order['toLng']);
    }
    return _orderPoint(order['fromLat'], order['fromLng']) ??
        _orderPoint(order['toLat'], order['toLng']);
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180);

  List<Map<String, dynamic>> _extractNavSteps(Map<String, dynamic> data) {
    final raw = data['steps'];
    if (raw is! List) return const [];
    final steps = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final step = Map<String, dynamic>.from(item);
      final maneuver = step['maneuver'] is Map
          ? Map<String, dynamic>.from(step['maneuver'] as Map)
          : <String, dynamic>{};
      final location = maneuver['location'];
      if (location is! List || location.length < 2) continue;
      final lngRaw = location[0];
      final latRaw = location[1];
      if (latRaw is! num || lngRaw is! num) continue;
      steps.add({...step, 'maneuver': maneuver});
    }
    return steps;
  }

  LatLng? _navStepPoint(Map<String, dynamic> step) {
    final maneuver = step['maneuver'];
    if (maneuver is! Map) return null;
    final location = maneuver['location'];
    if (location is! List || location.length < 2) return null;
    final lngRaw = location[0];
    final latRaw = location[1];
    if (latRaw is! num || lngRaw is! num) return null;
    return LatLng(latRaw.toDouble(), lngRaw.toDouble());
  }

  String _navInstructionRu(Map<String, dynamic> step) => navigationAction(
      step, LocalizationService.currentLanguage == AppLanguage.kazakh);

  void _announceManeuver(Map<String, dynamic> step, double km) {
    final maneuver =
        step['maneuver'] is Map ? step['maneuver'] as Map : const {};
    if (maneuver['type'] == 'depart' ||
        _appLifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (_lastGpsPoint == null ||
        (_lastGpsAccuracy ?? double.infinity) > 40 ||
        _lastGpsAt == null ||
        DateTime.now().difference(_lastGpsAt!).inSeconds > 30) {
      return;
    }
    final arrival = maneuver['type'] == 'arrive';
    final stepPoint = _navStepPoint(step);
    if (arrival &&
        (stepPoint == null ||
            const Distance().as(LengthUnit.Meter, _lastGpsPoint!, stepPoint) >
                50)) {
      return;
    }
    if (km > (arrival ? 0.02 : 0.3)) return;
    final threshold = arrival
        ? 0
        : km <= 0.05
            ? 50
            : km <= 0.1
                ? 100
                : 300;
    final kazakh = LocalizationService.currentLanguage == AppLanguage.kazakh;
    final key =
        '${_activeOrder?['id']}:${_activeOrder?['status'] == 'IN_PROGRESS' ? 'trip' : 'pickup'}:${maneuver['location']}:${maneuver['type']}:${maneuver['modifier']}:$kazakh';
    final previous = _spokenManeuvers[key];
    if (previous != null && previous <= threshold) return;
    _spokenManeuvers[key] = threshold;
    if (_spokenManeuvers.length > 300) {
      _spokenManeuvers.remove(_spokenManeuvers.keys.first);
    }
    unawaited(() async {
      try {
        await _navigationSpeech.setLanguage(kazakh ? 'kk-KZ' : 'ru-RU');
        await _navigationSpeech.setSpeechRate(0.9);
        await _navigationSpeech.setPitch(1.05);
        await _navigationSpeech.setVolume(1);
        await _navigationSpeech
            .speak(navigationSpeech(step, threshold, kazakh));
      } catch (_) {
        if (mounted && !_navigationVoiceWarningShown) {
          _navigationVoiceWarningShown = true;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(kazakh
                  ? 'Дыбысты қосу үшін «Желіде» түймесін басып, браузерде дыбысқа рұқсат беріңіз.'
                  : 'Для озвучки нажмите «На линии» и разрешите звук в браузере.')));
        }
      }
    }());
  }

  String _formatDistanceRu(double km) {
    if (km < 1) {
      final meters = (km * 1000).round();
      return '$meters м';
    }
    return '${km.toStringAsFixed(1)} км';
  }

  void _updateNavigationProgress({bool announce = false}) {
    if (_activeOrder == null || _navSteps.isEmpty) return;
    final driver = _activeDriverPoint();
    if (driver == null) return;

    var index = _navStepIndex.clamp(0, _navSteps.length - 1);
    while (index < _navSteps.length - 1) {
      final step = _navSteps[index];
      final stepPoint = _navStepPoint(step);
      if (stepPoint == null) break;
      final roadKm =
          navigationRoadDistance(_activeRoutePolyline, driver, stepPoint);
      final km = roadKm ??
          _distanceKm(driver.latitude, driver.longitude, stepPoint.latitude,
              stepPoint.longitude);
      if (roadKm != null && roadKm >= -0.02) {
        _announceManeuver(step, km.clamp(0, double.infinity));
      }
      final maneuver =
          step['maneuver'] is Map ? step['maneuver'] as Map : const {};
      if (maneuver['type'] == 'depart' || km <= 0.012) {
        index += 1;
      } else {
        break;
      }
    }

    if (index == _navSteps.length - 1) {
      final point = _navStepPoint(_navSteps[index]);
      if (point != null) {
        final km = navigationRoadDistance(_activeRoutePolyline, driver, point);
        if (km != null && km >= -0.02) {
          _announceManeuver(_navSteps[index], km.clamp(0, double.infinity));
        }
      }
    }
    if (index != _navStepIndex && mounted) {
      setState(() => _navStepIndex = index);
    }
  }

  Map<String, dynamic>? _currentNavInfo() {
    if (_navSteps.isEmpty || _activeOrder == null) return null;
    final index = _navStepIndex.clamp(0, _navSteps.length - 1);
    final step = _navSteps[index];
    final driver = _activeDriverPoint();
    final stepPoint = _navStepPoint(step);
    double? distanceKm;
    if (driver != null && stepPoint != null) {
      distanceKm =
          navigationRoadDistance(_activeRoutePolyline, driver, stepPoint)
                  ?.clamp(0, double.infinity) ??
              _distanceKm(driver.latitude, driver.longitude, stepPoint.latitude,
                  stepPoint.longitude);
    }
    return {
      'index': index,
      'total': _navSteps.length,
      'instruction': _navInstructionRu(step),
      'distanceKm': distanceKm,
    };
  }

  Future<void> _openActiveOrderInNavigator() async {
    final order = _activeOrder;
    if (order == null) return;
    final destination = _activeNavigationDestination(order);
    if (destination == null) {
      if (mounted) setState(() => _message = 'Точка назначения недоступна');
      return;
    }
    final status = (order['status'] ?? '').toString().toUpperCase();
    final rawLabel = status == 'IN_PROGRESS'
        ? (order['toAddress'] ?? 'Точка назначения')
        : (order['fromAddress'] ?? 'Точка подачи');
    final label = Uri.encodeComponent(rawLabel.toString());
    final geoUri = Uri.parse(
      'geo:${destination.latitude},${destination.longitude}?q=${destination.latitude},${destination.longitude}($label)',
    );
    final mapsUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${destination.latitude},${destination.longitude}',
    );

    var opened = false;
    if (!kIsWeb) {
      try {
        opened = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened) {
      try {
        opened = await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      setState(
        () => _message =
            'Не удалось открыть карты. Проверьте, что на устройстве установлено приложение карт.',
      );
    }
  }

  int _offerSecondsLeft(Map<String, dynamic> order) {
    return offerSecondsLeft(order);
  }

  bool get _isWaitingAuctionDecision {
    final until = _waitingAuctionUntil;
    return _waitingAuctionOrderId != null &&
        until != null &&
        until.isAfter(DateTime.now());
  }

  int get _auctionWaitSecondsLeft {
    final until = _waitingAuctionUntil;
    if (until == null) return 0;
    return until.difference(DateTime.now()).inSeconds.clamp(0, 60);
  }

  void _startAuctionOfferWait(String orderId, {String? offerId}) {
    _auctionOfferWaitTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _offerCountdownTimer?.cancel();
    _stopOfferAlarm();
    setState(() {
      _waitingAuctionOrderId = orderId;
      _waitingAuctionOfferId = offerId;
      _waitingAuctionUntil = DateTime.now().add(const Duration(seconds: 60));
      _nearby = const [];
    });
    _auctionOfferWaitTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkAuctionOfferWait(),
    );
    unawaited(_checkAuctionOfferWait());
  }

  Future<void> _checkAuctionOfferWait() async {
    final orderId = _waitingAuctionOrderId;
    if (orderId == null || orderId.isEmpty) return;
    final offerId = _waitingAuctionOfferId;
    if (!_isWaitingAuctionDecision) {
      _finishAuctionOfferWait('Пассажир не ответил. Вы снова на линии.');
      return;
    }
    try {
      final res = await _api.get('/orders/$orderId');
      if (!mounted) return;
      final order = Map<String, dynamic>.from(res.data as Map);
      final status = (order['status'] ?? '').toString().toUpperCase();
      if (const ['CANCELLED', 'COMPLETED'].contains(status)) {
        _finishAuctionOfferWait(
          status == 'CANCELLED'
              ? 'Пассажир отменил заказ. Вы снова на линии.'
              : 'Заказ уже завершён. Вы снова на линии.',
        );
        return;
      }
      final driverId = (order['driverId'] ?? '').toString();
      if (driverId.isNotEmpty && status != 'SEARCHING_DRIVER') {
        _auctionOfferWaitTimer?.cancel();
        setState(() {
          _waitingAuctionOrderId = null;
          _waitingAuctionOfferId = null;
          _waitingAuctionUntil = null;
          _activeOrder = order;
          _message = 'Пассажир принял вашу цену.';
        });
        await _syncActiveRoutePolyline(order);
        _startActiveOrderPolling(orderId);
        return;
      }
      final myOffer = (order['offers'] as List? ?? const [])
          .whereType<Map>()
          .map((offer) => Map<String, dynamic>.from(offer))
          .where(
            (offer) =>
                offerId == null ||
                offerId.isEmpty ||
                (offer['id'] ?? '').toString() == offerId,
          )
          .firstOrNull;
      final myOfferStatus = (myOffer?['status'] ?? '').toString().toUpperCase();
      if (myOffer == null ||
          const ['REJECTED', 'CANCELLED', 'EXPIRED'].contains(myOfferStatus)) {
        _finishAuctionOfferWait(
          'Пассажир отклонил предложение. Вы снова на линии.',
        );
      } else {
        setState(
          () =>
              _message = 'Ждём ответ пассажира: $_auctionWaitSecondsLeft сек.',
        );
      }
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('404') ||
          text.contains('not found') ||
          text.contains('cancel')) {
        _finishAuctionOfferWait('Заказ уже недоступен. Вы снова на линии.');
      } else if (!_isWaitingAuctionDecision) {
        _finishAuctionOfferWait('Пассажир не ответил. Вы снова на линии.');
      }
    }
  }

  void _finishAuctionOfferWait(String message) {
    _auctionOfferWaitTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _waitingAuctionOrderId = null;
      _waitingAuctionOfferId = null;
      _waitingAuctionUntil = null;
      _message = message;
    });
    if (_isOnline && _activeOrder == null) {
      _startNearbyPolling();
      unawaited(_loadNearby(silent: true));
    }
  }

  void _playNewOfferSoundOnce(String orderId) {
    if (_appLifecycleState != AppLifecycleState.resumed) return;
    if (orderId.isEmpty) return;
    if (!_spokenOfferIds.add(orderId)) return;
    unawaited(DriverOfferSound.play());
  }

  void _startOfferCountdownTicker() {
    if (_offerCountdownTimer != null) return;
    _offerCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_nearby.isEmpty || _activeOrder != null) {
        _offerCountdownTimer?.cancel();
        _offerCountdownTimer = null;
        return;
      }
      final alive = _nearby
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((o) => _offerSecondsLeft(o) > 0)
          .toList();
      if (_offerAlarmOrderId != null &&
          !alive.any((o) => (o['id'] ?? '').toString() == _offerAlarmOrderId)) {
        _stopOfferAlarm();
      }
      if (alive.length != _nearby.length) {
        setState(() {
          _nearby = alive;
        });
      } else {
        setState(() {});
      }
    });
  }

  Widget _activeOrderMap() {
    final order = _activeOrder;
    if (order == null) return const SizedBox.shrink();
    final pickup = _orderPoint(order['fromLat'], order['fromLng']);
    final destination = _orderPoint(order['toLat'], order['toLng']);
    final target = order['status'] == 'IN_PROGRESS' ? destination : pickup;
    final start = _activeDriverPoint() ?? pickup;
    if (start == null || target == null) {
      return const Center(child: Text('Координаты маршрута уточняются'));
    }
    return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DriverNavigationMap(
            key: ValueKey('driver-navigation-${order['id']}'),
            driver: _activeDriverPoint(),
            target: target,
            routeStart: start,
            heading: _driverHeading,
            route: _activeRoutePolyline));
  }

  Widget _driverMapCarMarker({double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF171426),
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.directions_car, color: Colors.white, size: 22),
    );
  }

  Widget _luxCard({
    required Widget child,
    EdgeInsets? padding,
    Color? borderColor,
    Gradient? gradient,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : theme.colorScheme.surface,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: borderColor ??
              AppTheme.secondaryColor.withValues(alpha: isDark ? 0.12 : 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x44000000)
                : AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: isDark ? 16 : 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  Widget _infoBanner(String text, {Color? color}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final c = color ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withValues(alpha: 0.72)
            : c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark
                    ? Colors.white70
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumDriverButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: filled
                ? const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  )
                : null,
            color: filled
                ? null
                : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.72)),
            border: filled
                ? null
                : Border.all(
                    color: AppTheme.primaryColor.withValues(
                      alpha: isDark ? 0.35 : 0.22,
                    ),
                  ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.24),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? Colors.white : theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: filled ? Colors.white : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final enabled = onChanged != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 58,
          height: 32,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: value
                ? const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  )
                : null,
            color: value ? null : Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: value
                  ? Colors.white.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _driverMapRoundButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
      ),
    );
  }

  LatLng _idleMapCenter() {
    final driver = _activeDriverPoint();
    if (driver != null) return driver;
    return const LatLng(43.2220, 76.8512);
  }

  Widget _idleDriverMap() {
    final driver = _activeDriverPoint();
    final center = _idleMapCenter();

    return SizedBox(
      height: 420,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: IntercityStaticTileMap(
                key: ValueKey(
                  'idle-static-map-${center.latitude.toStringAsFixed(4)}-${center.longitude.toStringAsFixed(4)}',
                ),
                center: center,
                zoom: driver != null ? 16.5 : 16,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
            if (driver != null) Center(child: _driverMapCarMarker(size: 56)),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.secondaryColor.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline
                                ? 'Новые заказы появятся поверх карты'
                                : 'Включите онлайн, чтобы получать заказы',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isOnline
                                ? 'Вы увидите входящий заказ только во всплывающем окне.'
                                : 'После включения онлайн приложение само начнёт поиск по вашим режимам.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: Column(
                children: [
                  _driverMapRoundButton(
                    icon: Icons.refresh_rounded,
                    onTap: _loadingNearby ? null : () => _loadNearby(),
                  ),
                  const SizedBox(height: 10),
                  _driverMapRoundButton(
                    icon: Icons.my_location_rounded,
                    onTap: _updatingLocation
                        ? null
                        : () => _updateLocation(autoDetect: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleDriverMode() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_hasResolvedDriverProfile) {
      return ListView(
        children: [
          _luxCard(
            gradient: const LinearGradient(
              colors: [Color(0x267C2DFF), Color(0x14B17AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderColor: AppTheme.primaryColor.withValues(alpha: 0.22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Загружаем профиль водителя',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  'Проверяем статус профиля и настройки линии.',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (!_isDriverApproved) {
      return ListView(
        children: [
          _luxCard(
            gradient: const LinearGradient(
              colors: [Color(0x267C2DFF), Color(0x14B17AFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderColor: AppTheme.primaryColor.withValues(alpha: 0.22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Сначала активируйте профиль водителя',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _driverStatusLabel,
                  style: TextStyle(
                    color: _driverStatusColor(),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'После одобрения здесь останется только карта, переключатель онлайн и окно входящего заказа.',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white70
                        : theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _premiumDriverButton(
                        label: 'Открыть профиль',
                        icon: Icons.person_rounded,
                        filled: true,
                        onPressed: _openDriverProfile,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _premiumDriverButton(
                        label: 'Проверка',
                        icon: Icons.verified_user_rounded,
                        onPressed: () => context.push('/driver/verification'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoBanner(_message),
          ],
        ],
      );
    }

    if (_isWaitingAuctionDecision) {
      return ListView(
        children: [
          _luxCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF261044), Color(0xFF100B1F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderColor: AppTheme.primaryColor.withValues(alpha: 0.35),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.hourglass_top_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ждём ответ пассажира',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Осталось $_auctionWaitSecondsLeft сек.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: _auctionWaitSecondsLeft / 60,
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.secondaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Пока пассажир выбирает предложение, новые заказы вам не приходят. Если пассажир не ответит за минуту, вы автоматически вернётесь на линию.',
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: _premiumDriverButton(
                    label: 'Обновить статус',
                    icon: Icons.refresh_rounded,
                    filled: true,
                    onPressed: () => unawaited(_checkAuctionOfferWait()),
                  ),
                ),
              ],
            ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 12),
            _infoBanner(_message),
          ],
        ],
      );
    }

    return ListView(
      children: [
        _luxCard(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF211138), Color(0xFF0F0B1C)]
                : const [Color(0xFFFFFFFF), Color(0xFFF7F0FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderColor: AppTheme.primaryColor.withValues(alpha: 0.22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOnline ? 'Вы онлайн' : 'Вы офлайн',
                          style: TextStyle(
                            color: _isOnline
                                ? Colors.greenAccent
                                : theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Вы онлайн?',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isOnline
                              ? 'Вы на линии. Новые заказы будут приходить поверх карты.'
                              : 'Вы не на линии. Включите онлайн, чтобы начать приём заказов.',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _driverStatTile(
                      label: 'Баланс',
                      value:
                          '${formatWalletAmount(_driverWallet?['money'])} ₸ / ${formatWalletAmount(_driverWallet?['moneyRub'])} ₽',
                      icon: Icons.account_balance_wallet_rounded,
                      accent: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _driverStatTile(
                      label: 'Линия',
                      value: _isOnline ? 'На линии' : 'Офлайн',
                      icon: Icons.local_taxi_rounded,
                      accent: AppTheme.secondaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_acceptIntercity &&
            (_activeIntercityRequests.isNotEmpty ||
                _myIntercityTrips.isNotEmpty)) ...[
          _driverIntercityMainCard(),
          const SizedBox(height: 12),
        ],
        _idleDriverMap(),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoBanner(_message),
        ],
      ],
    );
  }

  Widget _driverIntercityMainCard() {
    final active = _activeIntercityRequests;
    final trips = _myIntercityTrips;
    final hasFreeSeats = trips.any((trip) {
      final status = (trip['status'] ?? '').toString().toUpperCase();
      final seats = (trip['seatsAvailable'] as num?)?.toInt() ?? 0;
      return status == 'OPEN' && seats > 0;
    });
    return _luxCard(
      borderColor: AppTheme.primaryColor.withValues(alpha: 0.24),
      gradient: const LinearGradient(
        colors: [Color(0x241B0D33), Color(0x14171426)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: const Icon(Icons.alt_route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Межгород на линии',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasFreeSeats
                          ? 'Есть свободные места — продолжаем искать пассажиров.'
                          : 'Свободных мест нет — новые пассажиры не подбираются.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...active.take(3).map(_activeIntercityRequestTile),
          ],
          if (trips.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...trips.take(3).map(_myIntercityTripTile),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _premiumDriverButton(
                  label: 'Открыть межгород',
                  icon: Icons.alt_route_rounded,
                  filled: true,
                  onPressed: () => context.push('/driver/trip-create'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _premiumDriverButton(
                  label: 'Обновить',
                  icon: Icons.refresh_rounded,
                  onPressed: _loadIntercityMainState,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activeIntercityRequestTile(Map<String, dynamic> request) {
    final passenger = request['passenger'] is Map
        ? Map<String, dynamic>.from(request['passenger'] as Map)
        : <String, dynamic>{};
    final seats = (request['seats'] as num?)?.toInt() ?? 1;
    final price = request['price'];
    return _intercityMiniTile(
      icon: Icons.person_pin_circle_rounded,
      title:
          '${request['fromAddress'] ?? request['fromCity'] ?? '-'} → ${request['toAddress'] ?? request['toCity'] ?? '-'}',
      subtitle: 'Пассажир: ${passenger['name'] ?? 'Пассажир'} • $seats мест(а)',
      trailing: price == null
          ? 'принято'
          : '${_formatDriverMoney(price)} ${rideCurrencySymbol(request)}',
      onTap: () async {
        setState(() {
          _activeOrder = request;
          _message = 'Межгородняя поездка открыта.';
        });
        await _syncActiveRoutePolyline(request);
      },
    );
  }

  Widget _myIntercityTripTile(Map<String, dynamic> trip) {
    final seatsAvailable = (trip['seatsAvailable'] as num?)?.toInt() ?? 0;
    final seatsTotal = (trip['seatsTotal'] as num?)?.toInt() ?? 0;
    final status = (trip['status'] ?? '').toString().toUpperCase();
    return _intercityMiniTile(
      icon: status == 'FULL'
          ? Icons.event_seat_rounded
          : Icons.airline_seat_recline_normal_rounded,
      title: '${trip['fromCity'] ?? '-'} → ${trip['toCity'] ?? '-'}',
      subtitle: status == 'FULL'
          ? 'Все места заняты, можно ехать'
          : 'Ищем пассажиров: свободно $seatsAvailable из $seatsTotal',
      trailing: status == 'FULL' ? 'заполнено' : '$seatsAvailable/$seatsTotal',
    );
  }

  Widget _intercityMiniTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.secondaryColor, size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trailing,
              style: const TextStyle(
                color: AppTheme.secondaryColor,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_routeStage('active')) {
      final activeOrderStatus =
          (_activeOrder?['status'] ?? '').toString().toUpperCase();
      if (_activeOrder != null &&
          !const ['COMPLETED', 'CANCELLED'].contains(activeOrderStatus)) {
        return _activeDriverTripScaffold(activeOrderStatus);
      }
      return _boardDriverHomeScreen();
    }
    if (_routeStage('chosen')) {
      return _boardDriverChosenScreen();
    }
    if (_routeStage('offer')) {
      return _boardDriverOfferPriceScreen();
    }
    if (_routeStage('auction')) {
      return _boardDriverAuctionOrderScreen();
    }
    if (_routeStage('fixed')) {
      return _boardDriverFixedOrderScreen();
    }
    if (_routeStage('driver_home') || _useIntercityBoardUi) {
      final activeOrderStatus =
          (_activeOrder?['status'] ?? '').toString().toUpperCase();
      final hasActiveOrder = _activeOrder != null &&
          !const ['COMPLETED', 'CANCELLED'].contains(activeOrderStatus);
      return hasActiveOrder
          ? _activeDriverTripScaffold(activeOrderStatus)
          : _boardDriverHomeScreen();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeOrderStatus =
        (_activeOrder?['status'] ?? '').toString().toUpperCase();
    final hasActiveOrder = _activeOrder != null &&
        !const ['COMPLETED', 'CANCELLED'].contains(activeOrderStatus);
    if (hasActiveOrder) return _activeDriverTripScaffold(activeOrderStatus);
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              _driverHeader(),
              const SizedBox(height: 14),
              Expanded(
                child: _buildIdleDriverMode(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeDriverTripScaffold(String activeOrderStatus) {
    final order = _activeOrder!;
    final action = _primaryRideAction(activeOrderStatus);
    final nav = _currentNavInfo();
    final remaining = _distanceToActiveDestinationKm();
    return DriverActiveTripView(
      map: _activeOrderMap(),
      message: _rideStatusMessage,
      onBack: () => goBackOr(context, fallback: '/driver/home'),
      passenger: _activePassengerName(order),
      from: (order['fromAddress'] ?? 'Точка подачи').toString(),
      to: (order['toAddress'] ?? 'Точка назначения').toString(),
      price: '${order['price'] ?? '-'} ${rideCurrencySymbol(order)}',
      status:
          '${_orderStatusRu(activeOrderStatus)}${remaining == null ? '' : ' · ${_formatDistanceRu(remaining)}'}',
      payment: paymentMethodLabel(order['paymentMethod']?.toString()),
      instruction: nav == null
          ? null
          : '${nav['instruction']}${nav['distanceKm'] is double ? ' · ${_formatDistanceRu(nav['distanceKm'] as double)}' : ''}',
      onRefresh: () => _loadOrderById(order['id'].toString()),
      onCall: () => _callPassenger(order),
      onChat: () => _openActiveOrderChat(order),
      onNavigate: _openActiveOrderInNavigator,
      onEnableVoice: () {
        _navigationVoiceWarningShown = false;
        unawaited(_navigationSpeech.speak(''));
      },
      actionLabel: action?.label,
      actionKey: '${order['id']}:${action?.nextStatus}',
      autoActionEligible: _appLifecycleState == AppLifecycleState.resumed &&
          (action?.nextStatus == 'IN_PROGRESS' &&
                  _pickupDeparture.orderId == order['id']?.toString() &&
                  _pickupDeparture.departed &&
                  _lastGpsAt != null &&
                  DateTime.now().difference(_lastGpsAt!).inSeconds <= 30 ||
              action?.nextStatus == 'DRIVER_ARRIVED' &&
                  _lastGpsPoint != null &&
                  (_lastGpsAccuracy ?? double.infinity) <= 40 &&
                  _lastGpsAt != null &&
                  DateTime.now().difference(_lastGpsAt!).inSeconds <= 30 &&
                  remaining != null &&
                  remaining <= 0.05),
      actionIcon: action?.icon,
      busy: _rideStatusBusy,
      onAction: action != null && _canMoveToStatus(action.nextStatus)
          ? () => _advanceRideStatus(action.nextStatus)
          : null,
    );
  }

  Future<void> _advanceRideStatus(String status) async {
    if (_rideStatusBusy) return;
    setState(() {
      _rideStatusBusy = true;
      _rideStatusMessage = null;
    });
    try {
      await _setActiveOrderStatus(status);
      if (mounted &&
          _activeOrder != null &&
          _activeOrder?['status'] != status) {
        setState(() => _rideStatusMessage = _message);
      }
    } finally {
      if (mounted) setState(() => _rideStatusBusy = false);
    }
  }

  void _goDriverBoard(String marker) {
    final dark = routeHas(context, 'dark=1') ? '?dark=1' : '';
    context.go('/driver/home/$marker$dark');
  }

  Map<String, dynamic>? _productionBoardOrder({String? requestType}) {
    if (_activeOrder != null) return _activeOrder;
    for (final raw in _nearby) {
      if (raw is! Map) continue;
      final order = Map<String, dynamic>.from(raw);
      final id = (order['id'] ?? '').toString();
      if (id.isEmpty || id.startsWith('order-')) continue;
      if (requestType != null &&
          (order['requestType'] ?? '').toString() != requestType) {
        continue;
      }
      return order;
    }
    return null;
  }

  String? _productionBoardOrderId({String? requestType}) {
    final id = (_productionBoardOrder(requestType: requestType)?['id'] ?? '')
        .toString();
    return id.isEmpty ? null : id;
  }

  Future<void> _acceptBoardFixedOrder() async {
    final id = _productionBoardOrderId(requestType: requestTypeCityFixed);
    if (id == null) {
      setState(() => _message = 'Нет реального заказа для принятия.');
      return;
    }
    await _accept(id);
    if (!mounted) return;
    _goDriverBoard('chosen');
  }

  Future<void> _sendBoardAuctionOffer() async {
    final id = _productionBoardOrderId(requestType: requestTypeCityAuction);
    if (id == null) {
      setState(() => _message = 'Нет реального аукционного заказа.');
      return;
    }
    await _sendAuctionOffer(id, _boardOfferPriceCtrl.text);
  }

  Future<void> _markBoardArrived() async {
    if (_activeOrder == null) {
      setState(() => _message = 'Статус обновлён: водитель на месте');
      _goDriverBoard('active');
      return;
    }
    await _setActiveOrderStatus('DRIVER_ARRIVED');
    if (!mounted) return;
    _goDriverBoard('active');
  }

  Future<void> _callBoardPassenger() async {
    if (mounted) setState(() => _message = 'Звонок пассажиру запрошен');
    final order = _activeOrder;
    if (order == null) {
      const phone = '+79991234567';
      await Clipboard.setData(const ClipboardData(text: phone));
      if (mounted) setState(() => _message = 'Номер скопирован: $phone');
      return;
    }
    await _callPassenger(order);
  }

  Future<void> _completeBoardTrip() async {
    if (_activeOrder == null) {
      setState(
        () => _message =
            'Нет активного заказа. Обновите экран и откройте реальный заказ.',
      );
      return;
    }
    await _setActiveOrderStatus('COMPLETED');
    if (!mounted) return;
    _goDriverBoard('driver_home');
  }

  Widget _boardMessageBanner() {
    if (_message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ICPremiumInfoBanner(text: _message),
    );
  }

  Future<void> _showDashboardPopover(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy + box.size.height + 8;
    unawaited(_loadDriverProfileState(metricsOnly: true));
    unawaited(_loadDriverWallet());
    Timer? refresh;
    try {
      await showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (dialogContext) => StatefulBuilder(builder: (ctx, rebuild) {
          refresh ??= Timer.periodic(const Duration(seconds: 2), (_) {
            if (ctx.mounted && mounted) rebuild(() {});
          });
          return Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top, 16, 16),
              child: Material(
                key: const ValueKey('driver-metrics-popover'),
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: 380,
                      maxHeight: MediaQuery.sizeOf(ctx).height - top - 16),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Показатели',
                                style: TextStyle(fontWeight: FontWeight.w700))),
                        IconButton(
                            tooltip: 'Закрыть',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded)),
                      ]),
                      _driverDashboardMetrics(onBalance: () {
                        Navigator.pop(ctx);
                        context.push('/driver/wallet');
                      }),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }),
      );
    } finally {
      refresh?.cancel();
    }
  }

  Widget _driverDashboardMetrics({VoidCallback? onBalance}) {
    final online = _driverProfile?['online'];
    final city = online is Map ? online['city'] : null;
    final rubles = city is Map && city['countryCode'] == 'RU';
    final balance =
        '${formatWalletAmount(_driverWallet?[rubles ? 'moneyRub' : 'money'])} ${rubles ? '₽' : '₸'}';
    final todayCompleted =
        int.tryParse((_driverProfileValue('todayCompletedOrders') ?? '0')) ?? 0;

    return DriverDashboardMetrics(
      balance: balance,
      today: todayCompleted,
      performance: _driverProfile?['performance'] is Map
          ? Map<String, dynamic>.from(_driverProfile!['performance'] as Map)
          : null,
      onBalance: onBalance,
    );
  }

  Widget _boardDriverHomeScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final text = isDark ? Colors.white : const Color(0xFF15162C);
    final displayOnline = _pendingOnlineValue ?? _isOnline;
    final muted = isDark ? Colors.white60 : const Color(0xFF77768A);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: _boardDriverBottomNav(isDark, 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _switchBusy
                        ? (displayOnline ? 'Подключение…' : 'Отключение…')
                        : (_isOnline ? 'Вы онлайн' : 'Вы офлайн'),
                    style: TextStyle(
                      color: text,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Builder(
                      builder: (anchorContext) => IconButton(
                            key:
                                const ValueKey('driver-metrics-popover-button'),
                            tooltip: 'Показатели водителя',
                            icon: const Icon(Icons.dashboard_outlined),
                            color: AppTheme.primaryColor,
                            onPressed: () =>
                                _showDashboardPopover(anchorContext),
                          )),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _switchBusy ? null : () => _setOnline(!_isOnline),
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48,
                      height: 28,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: displayOnline
                            ? AppTheme.primaryColor
                            : muted.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Align(
                        alignment: displayOnline
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.white,
                          child: _switchBusy
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DriverDailyBonusCard(
                  bonus: _driverProfile?['dailyBonus'] is Map
                      ? Map<String, dynamic>.from(
                          _driverProfile!['dailyBonus'] as Map)
                      : null),
              Expanded(
                  child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _boardDriverSoftMap(isDark),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDriverBottomNav(bool isDark, int index) {
    final items = [
      (Icons.home_rounded, 'Главная'),
      (Icons.local_taxi_rounded, 'Заказы'),
      (Icons.chat_bubble_outline_rounded, 'Сообщения'),
      (Icons.person_outline_rounded, 'Профиль'),
    ];
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B0D1A) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE8E3F6),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => _handleBoardDriverBottomNav(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      items[i].$1,
                      color: i == index
                          ? AppTheme.primaryColor
                          : (isDark ? Colors.white54 : const Color(0xFF8B8A9D)),
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        color: i == index
                            ? AppTheme.primaryColor
                            : (isDark
                                ? Colors.white54
                                : const Color(0xFF8B8A9D)),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleBoardDriverBottomNav(int index) {
    switch (index) {
      case 0:
        return;
      case 1:
        context.go('/driver/trip-create');
        return;
      case 2:
        if (_activeOrder == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Сообщения доступны после принятия заказа.'),
          ));
          return;
        }
        _openActiveOrderChat(_activeOrder!);
        return;
      case 3:
        context.go('/driver/profile');
        return;
    }
  }

  Widget _boardDriverSoftMap(bool isDark) {
    final center = _idleMapCenter();
    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            key: ValueKey(
              'driver-home-osm-${center.latitude.toStringAsFixed(5)}-${center.longitude.toStringAsFixed(5)}-$isDark',
            ),
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16.5,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.osmTileUrl,
                subdomains: AppConstants.mapTileSubdomains,
                userAgentPackageName: 'com.milanium.intercity',
                retinaMode: true,
              ),
              const MapDataAttribution(),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 58,
                    height: 58,
                    child: _driverLocationMarker(),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF080812).withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _driverMapRoundButton(
            icon: Icons.my_location_rounded,
            onTap: _updatingLocation
                ? null
                : () => _updateLocation(autoDetect: true),
          ),
        ),
      ],
    );
  }

  Widget _driverLocationMarker() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.30),
                blurRadius: 22,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9B5CFF), Color(0xFF6C2EEA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            color: Colors.white,
            size: 13,
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -38),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF161226),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Вы здесь',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _boardDriverFixedOrderScreen() {
    final theme = Theme.of(context);
    final order = _productionBoardOrder(requestType: requestTypeCityFixed);
    final from = (order?['fromAddress'] ?? 'Точка подачи').toString();
    final to = (order?['toAddress'] ?? 'Точка назначения').toString();
    final price = _formatDriverMoney(order?['price']);
    final payment = paymentMethodLabel(order?['paymentMethod']?.toString());
    final vehicleClass = vehicleClassLabel(order?['vehicleClass']?.toString());
    final distance = (order?['distanceKm'] as num?)?.toStringAsFixed(0);
    final duration = order?['durationMinutes'] is num
        ? '~ ${(order!['durationMinutes'] as num).toStringAsFixed(0)} мин'
        : 'Уточняется';
    final passengers =
        ((order?['passengers'] ?? order?['seats'] ?? 1) as num?)?.toInt() ?? 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0815),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _driverOrderRoutePreview(order, dark: true)),
            Positioned(
              top: 12,
              left: 16,
              child: _boardCloseButton(
                onTap: () => _goDriverBoard('driver_home'),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Фиксированный заказ',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$price ${rideCurrencySymbol(order)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _boardDriverRouteBlock(
                      from: from,
                      to: to,
                    ),
                    const SizedBox(height: 12),
                    _boardDriverInfoRow(
                      icon: Icons.directions_car_filled_rounded,
                      title: 'Класс',
                      value: vehicleClass,
                      trailing: vehicleClass,
                    ),
                    const SizedBox(height: 8),
                    _boardDriverInfoRow(
                      icon: Icons.credit_card_rounded,
                      title: 'Оплата',
                      value: payment,
                      trailing: '',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _boardMetric(
                            'Расстояние',
                            distance == null ? 'Уточняется' : '$distance км',
                          ),
                        ),
                        Expanded(
                          child: _boardMetric('Время в пути', duration),
                        ),
                        Expanded(
                          child: _boardMetric('Пассажиров', '$passengers'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _boardMessageBanner(),
                    ICGradientButton(
                      label: 'Принять заказ',
                      onPressed: _acceptBoardFixedOrder,
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Автопринятие через 00:28',
                        style: TextStyle(
                          color: Color(0xFF7C7590),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardDriverAuctionOrderScreen() {
    final theme = Theme.of(context);
    final order = _productionBoardOrder(requestType: requestTypeCityAuction);
    final from = (order?['fromAddress'] ?? 'Точка подачи').toString();
    final to = (order?['toAddress'] ?? 'Точка назначения').toString();
    final payment = paymentMethodLabel(order?['paymentMethod']?.toString());
    final distance = (order?['distanceKm'] as num?)?.toStringAsFixed(0);
    final duration = order?['durationMinutes'] is num
        ? '~ ${(order!['durationMinutes'] as num).toStringAsFixed(0)} мин'
        : 'Уточняется';
    final passengers =
        ((order?['passengers'] ?? order?['seats'] ?? 1) as num?)?.toInt() ?? 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0815),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _driverOrderRoutePreview(order, dark: true)),
            Positioned(
              top: 12,
              left: 16,
              child: _boardCloseButton(
                onTap: () => _goDriverBoard('driver_home'),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Аукционный заказ',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Предложите свою цену',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _boardDriverRouteBlock(
                      from: from,
                      to: to,
                    ),
                    const SizedBox(height: 12),
                    _boardDriverInfoRow(
                      icon: Icons.credit_card_rounded,
                      title: 'Оплата',
                      value: payment,
                      trailing: '',
                    ),
                    const SizedBox(height: 8),
                    _boardDriverInfoRow(
                      icon: Icons.payments_outlined,
                      title: 'Ваша цена',
                      value: 'Введите сумму',
                      trailing: rideCurrencySymbol(order),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _boardMetric(
                            'Расстояние',
                            distance == null ? 'Уточняется' : '$distance км',
                          ),
                        ),
                        Expanded(
                          child: _boardMetric('Время в пути', duration),
                        ),
                        Expanded(
                          child: _boardMetric('Пассажиров', '$passengers'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _boardMessageBanner(),
                    ICGradientButton(
                      label: 'Предложить цену',
                      onPressed: () => _goDriverBoard('offer'),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'До завершения аукциона 02:15',
                        style: TextStyle(
                          color: Color(0xFF7C7590),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardDriverOfferPriceScreen() {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0815),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _boardDriverNightMap()),
                  Positioned(
                    top: 12,
                    right: 16,
                    child: _boardCloseButton(
                      onTap: () => _goDriverBoard('auction'),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Предложите свою цену',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _boardOfferPriceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                            style: const TextStyle(
                              color: Color(0xFF141326),
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _offerCurrencySymbol,
                          style: const TextStyle(
                            color: Color(0xFF4E4962),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Быстрый выбор',
                    style: TextStyle(
                      color: Color(0xFF4E4962),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _boardPriceChip(
                        '1 400 $_offerCurrencySymbol',
                        _boardOfferPriceCtrl.text.trim() == '1400',
                        price: '1400',
                      ),
                      _boardPriceChip(
                        '1 600 $_offerCurrencySymbol',
                        _boardOfferPriceCtrl.text.trim() == '1600',
                        price: '1600',
                      ),
                      _boardPriceChip(
                        '1 800 $_offerCurrencySymbol',
                        _boardOfferPriceCtrl.text.trim() == '1800',
                        price: '1800',
                      ),
                      _boardPriceChip(
                        '2 000 $_offerCurrencySymbol',
                        _boardOfferPriceCtrl.text.trim() == '2000',
                        price: '2000',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 78,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'Например, учту пожелания\nк маршруту',
                        style: TextStyle(
                          color: Color(0xFFB2A9C7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _boardMessageBanner(),
                  ICGradientButton(
                    label: 'Отправить предложение',
                    onPressed: _sendBoardAuctionOffer,
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Пассажир увидит только вашу цену, без комментария',
                          style: TextStyle(
                            color: Color(0xFF7C7590),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardDriverChosenScreen() {
    final theme = Theme.of(context);
    final order = _activeOrder ?? _productionBoardOrder();
    final from = (order?['fromAddress'] ?? 'Точка подачи').toString();
    final to = (order?['toAddress'] ?? 'Точка назначения').toString();
    final price = _formatDriverMoney(order?['price']);
    final payment = paymentMethodLabel(order?['paymentMethod']?.toString());
    final vehicleClass = vehicleClassLabel(order?['vehicleClass']?.toString());
    final dateText =
        (order?['scheduledAt'] ?? order?['createdAt'] ?? 'Дата уточняется')
            .toString();
    final passengers =
        ((order?['passengers'] ?? order?['seats'] ?? 1) as num?)?.toInt() ?? 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0815),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 0.9,
                    colors: [Color(0xFF2B1155), Color(0xFF0A0815)],
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 34,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  ICLogoMark(size: 82),
                  SizedBox(height: 14),
                  Text(
                    'Пассажир выбрал вас!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Заказ принят',
                    style: TextStyle(
                      color: Color(0xFFE0D2FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _boardDriverRouteBlock(
                      from: from,
                      to: to,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _boardMiniInfo('Дата', dateText)),
                        Expanded(child: _boardMiniInfo('Время', '')),
                        Expanded(
                            child: _boardMiniInfo('Пассажиров', '$passengers')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _boardDriverInfoRow(
                      icon: Icons.directions_car_filled_rounded,
                      title: 'Класс',
                      value: vehicleClass,
                      trailing: '',
                    ),
                    const SizedBox(height: 8),
                    _boardDriverInfoRow(
                      icon: Icons.credit_card_rounded,
                      title: 'Оплата',
                      value: payment,
                      trailing: '',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$price ${rideCurrencySymbol(order)}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ожидайте пассажира в точке подачи',
                      style: TextStyle(
                        color: Color(0xFF7C7590),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _boardMessageBanner(),
                    Row(
                      children: [
                        Expanded(
                          child: _boardDriverAction(
                            Icons.navigation_rounded,
                            'Маршрут',
                            filled: false,
                            onTap: _openActiveOrderInNavigator,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _boardDriverAction(
                            Icons.call_rounded,
                            'Позвонить',
                            filled: false,
                            onTap: _callBoardPassenger,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _boardDriverAction(
                            Icons.my_location_rounded,
                            'Я на месте',
                            filled: true,
                            onTap: _markBoardArrived,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Отменить заказ',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _boardDriverActiveTripScreen() {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/home'),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF231D3C),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Поездка в пути',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF141326),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(Icons.more_vert_rounded, color: Color(0xFF231D3C)),
                ],
              ),
            ),
            _boardTripProgress(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  _boardPassengerCard(),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 248,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _boardDriverLightRouteMap()),
                          const Positioned(
                            bottom: 34,
                            left: 22,
                            child: Text(
                              'Астана',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBFAFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _boardMiniInfoPlain('К прибытию', '12:05'),
                        ),
                        Container(
                          width: 1,
                          height: 34,
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        ),
                        Expanded(
                          child: _boardMiniInfoPlain(
                            'Осталось',
                            '2 ч 15 мин · 215 км',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _boardMessageBanner(),
                  ICGradientButton(
                    label: 'Завершить поездку',
                    onPressed: _completeBoardTrip,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardTripProgress() {
    final steps = [
      (Icons.check_circle_rounded, 'Принят', true),
      (Icons.directions_car_filled_rounded, 'В пути', true),
      (Icons.airline_seat_recline_normal_rounded, 'Высадка', false),
      (Icons.flag_rounded, 'Завершено', false),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: steps[i].$3
                          ? AppTheme.primaryColor
                          : const Color(0xFFE8E1F5),
                    ),
                    child: Icon(
                      steps[i].$1,
                      color:
                          steps[i].$3 ? Colors.white : const Color(0xFFB2A9C7),
                      size: 15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    steps[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: steps[i].$3
                          ? AppTheme.primaryColor
                          : const Color(0xFF7C7590),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (i != steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 24),
                  color: i < 1
                      ? AppTheme.primaryColor.withValues(alpha: 0.80)
                      : const Color(0xFFE8E1F5),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _boardPassengerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFE8D9FF),
                child: Icon(Icons.person_rounded, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Мария Иванова',
                      style: TextStyle(
                        color: Color(0xFF141326),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB23F),
                          size: 16,
                        ),
                        SizedBox(width: 3),
                        Text(
                          '4.9',
                          style: TextStyle(
                            color: Color(0xFF141326),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _boardRoundAction(Icons.call_rounded, onTap: _callBoardPassenger),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _boardMiniInfoPlain('Пассажир', '1')),
              Expanded(child: _boardMiniInfoPlain('Класс', 'Комфорт')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boardRoundAction(IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
            ),
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _boardMiniInfoPlain(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7C7590),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF141326),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _boardDriverLightRouteMap() =>
      _driverOrderRoutePreview(_activeOrder ?? _productionBoardOrder(),
          dark: false, active: _activeOrder != null);

  Widget _boardMiniInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7C7590),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF141326),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardDriverAction(
    IconData icon,
    String label, {
    required bool filled,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: filled ? null : const Color(0xFFFBFAFF),
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFF9C4DFF), AppTheme.primaryColor],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.14),
                ),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? Colors.white : AppTheme.primaryColor),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : const Color(0xFF141326),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardPriceChip(String text, bool selected, {required String price}) {
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _boardOfferPriceCtrl.text = price),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          margin: const EdgeInsets.only(right: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF1E5FF) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.primaryColor.withValues(alpha: 0.12),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? AppTheme.primaryColor : const Color(0xFF141326),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardDriverNightMap() => _driverOrderRoutePreview(
      _productionBoardOrder(requestType: requestTypeCityAuction),
      dark: true);

  Widget _driverOrderRoutePreview(Map<String, dynamic>? order,
      {required bool dark, bool active = false}) {
    if (order == null) return _boardDriverSoftMap(dark);
    final pickup = _orderPoint(order['fromLat'], order['fromLng']);
    final destination = _orderPoint(order['toLat'], order['toLng']);
    final driver = _activeDriverPoint();
    final approach =
        active && driver != null && order['status'] != 'IN_PROGRESS';
    final from = active ? driver : pickup;
    final to = approach ? pickup : destination;
    if (from == null || to == null) {
      return Center(
          child: Text('Координаты маршрута уточняются',
              style: TextStyle(color: dark ? Colors.white70 : Colors.black54)));
    }
    if (active) {
      return DriverNavigationMap(
          key: ValueKey('driver-navigation-${order['id']}'),
          driver: driver,
          target: to,
          routeStart: from,
          heading: _driverHeading,
          route: _activeRoutePolyline);
    }
    return FlutterMap(
      key: ValueKey('driver-preview-${order['id']}-$from-$to'),
      options: MapOptions(
        initialCenter: from,
        initialCameraFit: CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([from, to]),
            padding: const EdgeInsets.all(36),
            maxZoom: 16),
      ),
      children: [
        TileLayer(
            urlTemplate: AppConstants.osmTileUrl,
            subdomains: AppConstants.mapTileSubdomains,
            userAgentPackageName: 'com.milanium.intercity'),
        RoadRouteLayer(from: from, to: to, color: AppTheme.primaryColor),
        MarkerLayer(markers: [
          Marker(
              point: from,
              width: 32,
              height: 32,
              child:
                  const Icon(Icons.trip_origin, color: AppTheme.primaryColor)),
          Marker(
              point: to,
              width: 32,
              height: 32,
              child: const Icon(Icons.location_on,
                  color: AppTheme.secondaryColor)),
        ]),
      ],
    );
  }

  Widget _boardCloseButton({VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ),
    );
  }

  Widget _boardDriverRouteBlock({required String from, required String to}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _boardRouteDot(),
              Container(
                width: 2,
                height: 42,
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
              ),
              _boardRouteDot(),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  from,
                  style: const TextStyle(
                    color: Color(0xFF141326),
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  to,
                  style: const TextStyle(
                    color: Color(0xFF141326),
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardRouteDot() {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: AppTheme.primaryColor,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _boardDriverInfoRow({
    required IconData icon,
    required String title,
    required String value,
    required String trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF7C7590),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF141326),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF141326),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7C7590),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF141326),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _driverHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkSurface.withValues(alpha: 0.82)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.secondaryColor.withValues(alpha: 0.20),
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            child: Row(
              children: [
                const ICLogoMark(size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Кабинет водителя',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isOnline ? 'Вы онлайн' : 'Вы офлайн',
                        style: TextStyle(
                          color: _isOnline
                              ? Colors.greenAccent
                              : (isDark
                                  ? Colors.white70
                                  : theme.colorScheme.onSurfaceVariant),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _isOnline
                        ? Colors.greenAccent.withValues(alpha: 0.14)
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.08,
                          ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _isOnline
                          ? Colors.greenAccent.withValues(alpha: 0.24)
                          : theme.colorScheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  child: _premiumSwitch(
                    value: _isOnline,
                    onChanged: _switchBusy ? null : _setOnline,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: isDark
              ? AppTheme.darkSurface.withValues(alpha: 0.82)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _openDriverProfile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.20),
                ),
              ),
              child: Icon(
                Icons.person_outline,
                color: isDark ? Colors.white : AppTheme.primaryColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _driverStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    VoidCallback? onInfoTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (onInfoTap != null) ...[
                      const SizedBox(width: 2),
                      InkWell(
                        onTap: onInfoTap,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.error_outline_rounded,
                            size: 14,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _activePassengerName(Map<String, dynamic> order) {
    final direct = order['passengerName'] ?? order['customerName'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }

    final passenger = order['passenger'];
    if (passenger is Map) {
      final user = passenger['user'];
      final name = passenger['name'] ?? (user is Map ? user['name'] : null);
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }

    final user = order['user'];
    if (user is Map) {
      final name = user['name'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }

    return 'Пассажир';
  }

  String _activePassengerPhone(Map<String, dynamic> order) {
    final direct = order['passengerPhone'] ?? order['customerPhone'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    final passenger = order['passenger'];
    if (passenger is Map) {
      final user = passenger['user'];
      final phone = passenger['phone'] ?? (user is Map ? user['phone'] : null);
      if (phone != null && phone.toString().trim().isNotEmpty) {
        return phone.toString().trim();
      }
    }
    return '';
  }

  Future<void> _callPassenger(Map<String, dynamic> order) async {
    final phone = _activePassengerPhone(
      order,
    ).replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) {
      if (mounted) setState(() => _message = 'Телефон пассажира недоступен');
      return;
    }
    try {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: phone),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // Browser builds may not support tel: links.
    }
    await Clipboard.setData(ClipboardData(text: phone));
    if (mounted) {
      setState(
        () => _message = 'Не удалось открыть звонок. Номер скопирован: $phone',
      );
    }
  }

  Future<void> _openActiveOrderChat(Map<String, dynamic> order) async {
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;
    await showOrderChatSheet(
      context: context,
      orderId: orderId,
      orderStatus: (order['status'] ?? '').toString(),
      title: 'Чат с пассажиром',
      currentRole: 'DRIVER',
    );
  }
}
