import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/browser_location.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/request_flow_utils.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/intercity_map_fallback.dart';
import '../../../core/widgets/intercity_static_tile_map.dart';
import '../../passenger/widgets/passenger_bottom_nav.dart';

bool shouldApplyAddressSearchRadiusFilter({
  required String mode,
  required LatLng? anchor,
}) {
  return (mode == 'CITY' || mode == 'DELIVERY') && anchor != null;
}

class _MapCar extends StatelessWidget {
  const _MapCar({required this.angle});

  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              color: Colors.black.withValues(alpha: 0.18),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.26),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
          Container(
            width: 24,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFCFC9DF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white, width: 1.2),
            ),
          ),
          Positioned(
            top: 12,
            child: Container(
              width: 14,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: const Color(0xFF171426).withValues(alpha: 0.86),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPremiumCar extends StatelessWidget {
  const _MiniPremiumCar({this.width = 58});

  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 0.42;
    return SizedBox(
      width: width,
      height: height + 10,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: width * 0.82,
              height: height * 0.30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.black.withValues(alpha: 0.16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            child: CustomPaint(
              size: Size(width, height),
              painter: _MiniPremiumCarPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPremiumCarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFD7D2E5)],
      ).createShader(Offset.zero & size);
    final bodyPath = ui.Path()
      ..moveTo(size.width * 0.08, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.16,
        size.height * 0.32,
        size.width * 0.34,
        size.height * 0.32,
      )
      ..lineTo(size.width * 0.48, size.height * 0.10)
      ..lineTo(size.width * 0.76, size.height * 0.18)
      ..quadraticBezierTo(
        size.width * 0.92,
        size.height * 0.34,
        size.width * 0.96,
        size.height * 0.70,
      )
      ..close();
    canvas.drawPath(bodyPath, body);
    canvas.drawPath(
      bodyPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.43,
          size.height * 0.20,
          size.width * 0.26,
          size.height * 0.25,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF161323).withValues(alpha: 0.82),
    );
    final wheel = Paint()..color = const Color(0xFF15131F);
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.76),
      size.height * 0.16,
      wheel,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.76),
      size.height * 0.16,
      wheel,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IntercityMapPainter extends CustomPainter {
  const _IntercityMapPainter({
    required this.lineColor,
    required this.routeColor,
  });

  final Color lineColor;
  final Color routeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var x = -size.width; x < size.width * 2; x += 42) {
      canvas.drawLine(
        Offset(x.toDouble(), 0),
        Offset(x + size.height * 0.55, size.height),
        gridPaint,
      );
    }
    for (var y = 20.0; y < size.height; y += 46) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 34), gridPaint);
    }

    final route = ui.Path()
      ..moveTo(size.width * 0.20, size.height * 0.72)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.58,
        size.width * 0.30,
        size.height * 0.44,
        size.width * 0.52,
        size.height * 0.36,
      )
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.30,
        size.width * 0.62,
        size.height * 0.18,
        size.width * 0.78,
        size.height * 0.12,
      );
    final glowPaint = Paint()
      ..color = routeColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final routePaint = Paint()
      ..color = routeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(route, glowPaint);
    canvas.drawPath(route, routePaint);
  }

  @override
  bool shouldRepaint(covariant _IntercityMapPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.routeColor != routeColor;
  }
}

class _BoardCityRoutePainter extends CustomPainter {
  const _BoardCityRoutePainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final route = ui.Path()
      ..moveTo(size.width * 0.25, size.height * 0.56)
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.40,
        size.width * 0.45,
        size.height * 0.62,
        size.width * 0.56,
        size.height * 0.42,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.28,
        size.width * 0.74,
        size.height * 0.36,
        size.width * 0.82,
        size.height * 0.22,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppTheme.primaryColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppTheme.primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.56),
      9,
      Paint()..color = AppTheme.primaryColor,
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.22),
      9,
      Paint()..color = AppTheme.primaryColor,
    );

    final carCenter = Offset(size.width * 0.62, size.height * 0.36);
    canvas.save();
    canvas.translate(carCenter.dx, carCenter.dy);
    canvas.rotate(0.75);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -18, 16, 36),
        const Radius.circular(7),
      ),
      Paint()..color = dark ? const Color(0xFFE9DDFF) : const Color(0xFF251B3B),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BoardCityRoutePainter oldDelegate) {
    return oldDelegate.dark != dark;
  }
}

bool shouldFallbackToGlobalAddressSearch({
  required bool localFailed,
  required String query,
  required List<Map<String, dynamic>> local,
  required bool allowGlobalFallback,
}) {
  if (!allowGlobalFallback) return false;
  return localFailed || local.isEmpty || query.trim().length >= 6;
}

bool shouldAutoApplyFirstAddressSearchResult({
  required bool requiresConfirmedCoordinates,
  required List<Map<String, dynamic>> results,
}) {
  if (results.isEmpty) return false;
  return !requiresConfirmedCoordinates || results.length == 1;
}

bool shouldUseNearestAnchoredAddressResult({
  required String query,
  required List<Map<String, dynamic>> local,
}) {
  if (local.isEmpty) return false;
  final normalized = query.trim().toLowerCase();
  final isAddressLike = RegExp(r'\d').hasMatch(normalized) ||
      normalized.contains('улиц') ||
      normalized.contains('просп') ||
      normalized.contains('мкр') ||
      normalized.contains('микрорайон') ||
      normalized.contains('дом');
  if (!isAddressLike) return false;

  final firstDistanceKm = (local.first['distanceKm'] as num?)?.toDouble();
  if (firstDistanceKm == null || firstDistanceKm > 75) {
    return false;
  }
  if (local.length == 1) {
    return true;
  }

  final secondDistanceKm = (local[1]['distanceKm'] as num?)?.toDouble();
  if (secondDistanceKm == null) {
    return true;
  }
  return secondDistanceKm >= firstDistanceKm + 150 ||
      secondDistanceKm >= firstDistanceKm * 4;
}

String resolveExplicitAddressSearchQuery({
  required String controllerText,
  required String lastInputValue,
}) {
  final controller = controllerText.trim();
  final lastInput = lastInputValue.trim();
  if (controller.isEmpty) return lastInput;
  if (lastInput.isEmpty || controller == lastInput) return controller;
  if (lastInput.length > controller.length &&
      lastInput.startsWith(controller)) {
    return lastInput;
  }
  if (controller.length > lastInput.length &&
      controller.startsWith(lastInput)) {
    return controller;
  }
  return controller;
}

bool shouldIgnoreTransientAddressChangeDuringExplicitSearch({
  required bool explicitSearchInProgress,
  required DateTime now,
  required DateTime? guardUntil,
}) {
  if (explicitSearchInProgress) return true;
  return guardUntil != null && now.isBefore(guardUntil);
}

bool shouldRestoreConfirmedAddressAfterStaleSearchEcho({
  required String changedValue,
  required String? pendingQueryEcho,
  required String confirmedAddress,
  required bool hasConfirmedLocation,
}) {
  if (!hasConfirmedLocation) return false;
  final normalizedChanged = changedValue.trim();
  final normalizedPending = (pendingQueryEcho ?? '').trim();
  final normalizedConfirmed = confirmedAddress.trim();
  if (normalizedChanged.isEmpty ||
      normalizedPending.isEmpty ||
      normalizedConfirmed.isEmpty) {
    return false;
  }
  return normalizedChanged == normalizedPending &&
      normalizedChanged != normalizedConfirmed;
}

bool isTopRideSharingTrip(Map<String, dynamic> trip, {DateTime? now}) {
  final raw = (trip['topUntil'] ?? '').toString().trim();
  if (raw.isEmpty) return false;
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return false;
  return parsed.isAfter(now ?? DateTime.now());
}

class OrderScreen extends StatefulWidget {
  const OrderScreen({
    super.key,
    this.resetToken,
    this.routeStage,
    this.enableLiveMap = true,
    this.autoLocateOnStart = true,
    this.initialStep,
  });

  final String? resetToken;
  final String? routeStage;
  final bool enableLiveMap;
  final bool autoLocateOnStart;
  final int? initialStep;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final ApiClient _api = ApiClient();
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _manualAddressController =
      TextEditingController();
  final TextEditingController _deliveryItemController = TextEditingController();
  final TextEditingController _deliveryWeightController =
      TextEditingController();
  final TextEditingController _deliveryDimensionsController =
      TextEditingController();
  final TextEditingController _deliveryRecipientController =
      TextEditingController();
  final Distance _distance = const Distance();
  static const double _maxAutofillLocationAccuracyMeters = 250;

  LatLng _mapCenter = const LatLng(43.2220, 76.8512);
  LatLng? _userLocation;
  LatLng? _fromLocation;
  LatLng? _toLocation;
  String _fromAddress = '';
  String _toAddress = '';
  String? _currentCityId;
  String _currentCityName = '';
  List<Map<String, dynamic>> _cityOptions = const [];
  bool _cityOptionsLoading = false;
  String? _intercityFromCityId;
  String? _intercityToCityId;
  String _intercityFromCityName = '';
  String _intercityToCityName = '';
  LatLng? _intercityFromCityPoint;
  LatLng? _intercityToCityPoint;
  bool _loading = false;
  bool _fromAddressSearching = false;
  bool _toAddressSearching = false;
  bool _locating = false;
  int _modeIndex = 0; // 0 city, 1 intercity, 2 delivery
  int _cityModeIndex = 0; // 0 fixed, 1 auction
  int _deliveryModeIndex = 0; // 0 city, 1 intercity, 2 rf
  int? _mapHomeSelectedIndex;
  int _orderStep = 0; // 0 mode, 1 route, 2 options, 3 confirm
  String _paymentMethod = paymentMethodCash;
  String _vehicleClass = vehicleClassEconomy;
  bool _intercityWholeCabin = false;
  int _intercitySeats = 1;
  int _intercityBaggage = 1;
  String _intercityPets = 'Нет';
  int _intercityChildSeats = 0;
  bool _intercitySmokingAllowed = false;
  bool _manualAddressForFrom = true;
  DateTime _intercityTripDate = _defaultIntercityTripDate();
  List<Map<String, dynamic>> _intercityReadyTrips = const [];
  bool _intercityReadyTripsLoading = false;
  bool _passengerMapHomeEnabled = true;
  bool _passengerMapHomeSettingsLoaded = false;

  List<Map<String, dynamic>> _fromSuggestions = const [];
  List<Map<String, dynamic>> _toSuggestions = const [];
  bool _suppressFromAddressChange = false;
  bool _suppressToAddressChange = false;
  bool _fromExplicitSearchInProgress = false;
  bool _toExplicitSearchInProgress = false;
  DateTime? _fromExplicitSearchGuardUntil;
  DateTime? _toExplicitSearchGuardUntil;
  String? _fromPendingStaleQueryEcho;
  String? _toPendingStaleQueryEcho;
  String _lastFromInputValue = '';
  String _lastToInputValue = '';

  Timer? _fromSearchDebounce;
  Timer? _toSearchDebounce;
  Timer? _boardDebounce;
  Timer? _intercityTripsDebounce;
  int _fromSuggestionRequestId = 0;
  int _toSuggestionRequestId = 0;
  int _boardRequestId = 0;
  int _intercityTripsRequestId = 0;
  bool _boardSeeded = false;

  String _statusText = '';
  double? _boardPrice;
  String _rideCurrency = 'KZT';
  String get _currencySymbol {
    if (_requestType() == requestTypeIntercity) {
      for (final city in _cityOptions) {
        if (city['id'] == _intercityFromCityId ||
            city['name'] == _intercityFromCityName) {
          return rideCurrencySymbol(city);
        }
      }
    }
    return rideCurrencySymbol({'currency': _rideCurrency});
  }

  double? _boardDistance;
  int? _boardDuration;

  bool get _statusIsError => _statusText.toLowerCase().contains('ошиб');
  bool get _statusIsSuccess =>
      _statusText.toLowerCase().contains('заявка создана') ||
      _statusText.toLowerCase().contains('заказ создан');
  String get _createActionHint {
    if (_isMarketRequest &&
        (_fromLocation == null || _toLocation == null) &&
        _canCreateWithManualAddresses) {
      return 'Текстовые адреса указаны. Заявку можно опубликовать даже без подтверждённых координат, водитель увидит ручной адрес.';
    }
    if (_loading) {
      return 'Подождите, обновляем маршрут и расчёт.';
    }
    if (_requiresConfirmedCoordinates &&
        _fromLocation == null &&
        _toLocation == null) {
      return 'Укажите точки "Откуда" и "Куда", чтобы продолжить.';
    }
    if (_requiresConfirmedCoordinates && _fromLocation == null) {
      return 'Сначала укажите точку "Откуда".';
    }
    if (_requiresConfirmedCoordinates && _toLocation == null) {
      return 'Сначала укажите точку "Куда".';
    }
    if (_requestType() == requestTypeCityFixed) {
      return 'Маршрут и стоимость готовы. Можно создавать заказ.';
    }
    if (_requestType() == requestTypeCityAuction) {
      return 'Маршрут или ручные адреса готовы. Можно публиковать аукцион по городу.';
    }
    if (_requestType() == requestTypeIntercity) {
      if (!_hasIntercitySearchCity(isFrom: true) ||
          !_hasIntercitySearchCity(isFrom: false)) {
        return 'Сначала выберите города "Откуда" и "Куда", затем точные адреса внутри этих городов.';
      }
      return 'Маршрут межгорода готов. Можно публиковать заявку на выбранные дату и время.';
    }
    return 'Маршрут или ручные адреса готовы. Можно публиковать заявку на доставку.';
  }

  static DateTime _defaultIntercityTripDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 9);
  }

  void _resetOrderStep() {
    _orderStep = 0;
  }

  bool get _routeStepReady {
    if (_requestType() == requestTypeIntercity &&
        !(_fromLocation != null && _toLocation != null) &&
        (!_hasIntercitySearchCity(isFrom: true) ||
            !_hasIntercitySearchCity(isFrom: false))) {
      return false;
    }
    if (_requiresConfirmedCoordinates) {
      return (_fromLocation != null && _toLocation != null) ||
          _hasManualAddressPair;
    }
    return (_fromLocation != null && _toLocation != null) ||
        _canCreateWithManualAddresses;
  }

  bool _canContinueFromStep(bool canCreate) {
    if (_loading) return false;
    switch (_orderStep) {
      case 0:
        return true;
      case 1:
        return _routeStepReady;
      case 2:
        return true;
      default:
        return canCreate;
    }
  }

  void _nextOrderStep() {
    if (_orderStep >= 3) return;
    setState(() => _orderStep += 1);
  }

  void _previousOrderStep() {
    if (_orderStep <= 0) return;
    setState(() => _orderStep -= 1);
  }

  String _stepActionLabel() {
    if (_orderStep < 3) return 'Далее';
    if (_requestType() == requestTypeCityFixed) return 'Создать заказ';
    if (_mode() == 'DELIVERY') return 'Опубликовать доставку';
    return 'Опубликовать заявку';
  }

  String _stepHint() {
    switch (_orderStep) {
      case 0:
        return _mode() == 'CITY'
            ? 'Выберите фиксированный тариф или аукцион.'
            : 'Выберите направление заказа.';
      case 1:
        return _createActionHint;
      case 2:
        return _requestType() == requestTypeCityFixed
            ? 'Выберите класс автомобиля и способ оплаты.'
            : 'Проверьте параметры и способ оплаты.';
      default:
        return _createActionHint;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSearchCityPreference();
    _loadCityOptions();
    _loadPassengerRuntimeSettings();
    unawaited(_restoreBoardDraft());
    if (widget.autoLocateOnStart) {
      _initMapCenterByLocation();
    }
  }

  Future<void> _loadPassengerRuntimeSettings() async {
    try {
      final res = await _api.get('/app/runtime-settings');
      final data = res.data;
      if (!mounted || data is! Map) return;
      setState(() {
        _passengerMapHomeEnabled = data['passengerMapHomeEnabled'] != false;
        _passengerMapHomeSettingsLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _passengerMapHomeSettingsLoaded = true);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_boardSeeded) return;
    if (widget.initialStep != null) {
      _boardSeeded = true;
      _seedBoardOrder();
    }
  }

  void _seedBoardOrder() {
    _orderStep = (widget.initialStep ?? _orderStep).clamp(0, 3);
    _restoreBoardDraft();
  }

  bool _routeStage(String marker) {
    return widget.routeStage == marker || routeHas(context, '$marker=1');
  }

  bool get _useIntercityBoardUi => _modeIndex != 2;

  void _goOrderBoard(String marker) {
    final dark = routeHas(context, 'dark=1') ? '?dark=1' : '';
    context.go('/order/$marker$dark');
  }

  Future<void> _saveBoardDraft() async {
    final from = _fromLocation;
    final to = _toLocation;
    final draft = <String, dynamic>{
      'modeIndex': _modeIndex,
      'cityModeIndex': _cityModeIndex,
      'deliveryModeIndex': _deliveryModeIndex,
      'fromAddress': _fromAddress,
      'toAddress': _toAddress,
      'fromText': _fromController.text,
      'toText': _toController.text,
      'fromLat': from?.latitude,
      'fromLng': from?.longitude,
      'toLat': to?.latitude,
      'toLng': to?.longitude,
      'intercityFromCityId': _intercityFromCityId,
      'intercityToCityId': _intercityToCityId,
      'intercityFromCityName': _intercityFromCityName,
      'intercityToCityName': _intercityToCityName,
      'intercityFromCityLat': _intercityFromCityPoint?.latitude,
      'intercityFromCityLng': _intercityFromCityPoint?.longitude,
      'intercityToCityLat': _intercityToCityPoint?.latitude,
      'intercityToCityLng': _intercityToCityPoint?.longitude,
      'boardPrice': _boardPrice,
      'rideCurrency': _rideCurrency,
      'boardDistance': _boardDistance,
      'boardDuration': _boardDuration,
    };
    await AppPreferences.setOrderDraft(jsonEncode(draft));
  }

  Future<void> _restoreBoardDraft() async {
    if (_fromLocation != null || _toLocation != null) return;
    final raw = await AppPreferences.getOrderDraft();
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final draft = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final fromLat = (draft['fromLat'] as num?)?.toDouble();
      final fromLng = (draft['fromLng'] as num?)?.toDouble();
      final toLat = (draft['toLat'] as num?)?.toDouble();
      final toLng = (draft['toLng'] as num?)?.toDouble();
      final intercityFromCityLat =
          (draft['intercityFromCityLat'] as num?)?.toDouble();
      final intercityFromCityLng =
          (draft['intercityFromCityLng'] as num?)?.toDouble();
      final intercityToCityLat =
          (draft['intercityToCityLat'] as num?)?.toDouble();
      final intercityToCityLng =
          (draft['intercityToCityLng'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        _modeIndex = (draft['modeIndex'] as num?)?.toInt() ?? _modeIndex;
        _cityModeIndex =
            (draft['cityModeIndex'] as num?)?.toInt() ?? _cityModeIndex;
        _deliveryModeIndex =
            (draft['deliveryModeIndex'] as num?)?.toInt() ?? _deliveryModeIndex;
        _fromAddress = (draft['fromAddress'] ?? '').toString();
        _toAddress = (draft['toAddress'] ?? '').toString();
        _setAddressFieldValue(
          isFrom: true,
          value: (draft['fromText'] ?? _fromAddress).toString(),
        );
        _setAddressFieldValue(
          isFrom: false,
          value: (draft['toText'] ?? _toAddress).toString(),
        );
        if (fromLat != null && fromLng != null) {
          _fromLocation = LatLng(fromLat, fromLng);
        }
        if (toLat != null && toLng != null) {
          _toLocation = LatLng(toLat, toLng);
        }
        _intercityFromCityId =
            (draft['intercityFromCityId'] ?? _intercityFromCityId)?.toString();
        _intercityToCityId =
            (draft['intercityToCityId'] ?? _intercityToCityId)?.toString();
        _intercityFromCityName =
            (draft['intercityFromCityName'] ?? _intercityFromCityName)
                .toString();
        _intercityToCityName =
            (draft['intercityToCityName'] ?? _intercityToCityName).toString();
        if (intercityFromCityLat != null && intercityFromCityLng != null) {
          _intercityFromCityPoint =
              LatLng(intercityFromCityLat, intercityFromCityLng);
        }
        if (intercityToCityLat != null && intercityToCityLng != null) {
          _intercityToCityPoint =
              LatLng(intercityToCityLat, intercityToCityLng);
        }
        _boardPrice = (draft['boardPrice'] as num?)?.toDouble();
        _rideCurrency = rideCurrencyCode({'currency': draft['rideCurrency']});
        _boardDistance = (draft['boardDistance'] as num?)?.toDouble();
        _boardDuration = (draft['boardDuration'] as num?)?.toInt();
        if (_routeStage('intercity_options') &&
            _fromController.text.trim().length >= 2 &&
            _toController.text.trim().length >= 2 &&
            _fromLocation != null &&
            _toLocation != null) {
          _statusText = '';
        }
      });
      if (_fromLocation != null && _toLocation != null && _boardPrice == null) {
        await _board();
      }
    } catch (_) {
      await AppPreferences.clearOrderDraft();
    }
  }

  void _showBoardMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectBoardEntry({
    required int modeIndex,
    int cityModeIndex = 0,
    int deliveryModeIndex = 0,
    required String route,
  }) {
    setState(() {
      _modeIndex = modeIndex;
      _cityModeIndex = cityModeIndex;
      _deliveryModeIndex = deliveryModeIndex;
      _orderStep = route == 'order' ? 1 : 0;
      _boardPrice = null;
      _boardDistance = null;
      _boardDuration = null;
      if (!paymentMethodsForRequestType(_requestType())
          .contains(_paymentMethod)) {
        _paymentMethod = paymentMethodCash;
      }
    });
    if (route == 'order') {
      return;
    }
    _goOrderBoard(route);
  }

  void _selectMapHomeFare(int index) {
    setState(() {
      _mapHomeSelectedIndex = index;
      _modeIndex = index == 2
          ? 1
          : index == 3
              ? 2
              : 0;
      _cityModeIndex = index == 1 ? 1 : 0;
      _deliveryModeIndex = 0;
      _orderStep = 1;
      _boardPrice = null;
      _boardDistance = null;
      _boardDuration = null;
      if (!paymentMethodsForRequestType(_requestType())
          .contains(_paymentMethod)) {
        _paymentMethod = paymentMethodCash;
      }
    });
    _ensureBoardPickupPoint();
    _scheduleAutoBoard();
  }

  void _continueMapHomeFare() {
    final selected = _mapHomeSelectedIndex ?? 0;
    if (selected == 2) {
      _goOrderBoard('intercity_start');
      return;
    }
    if (selected == 1) {
      _goOrderBoard('auction');
      return;
    }
    _goOrderBoard('address');
  }

  void _ensureBoardPickupPoint() {
    if (_fromLocation != null && _fromController.text.trim().isNotEmpty) {
      return;
    }
    final point = _userLocation ?? _mapCenter;
    final label = _userLocation != null
        ? 'Моё местоположение'
        : 'Точка подачи выбрана на карте';
    setState(() {
      _fromLocation = point;
      _fromAddress = label;
      _setAddressFieldValue(isFrom: true, value: label);
    });
    unawaited(_saveBoardDraft());
  }

  Future<void> _applyBoardDestinationSuggestion(
    Map<String, dynamic> item,
  ) async {
    _ensureBoardPickupPoint();
    await _applySuggestion(item, isFrom: false);
    if (!mounted) return;
    await _saveBoardDraft();
    if (_cityModeIndex == 1) {
      _goOrderBoard('auction');
      return;
    }
    if (_fromLocation != null && _toLocation != null) {
      await _board();
      if (!mounted) return;
      _goOrderBoard('routeprice');
      return;
    }
    _goOrderBoard('address');
  }

  Future<void> _pickBoardAddressOnMap({
    required bool isFrom,
    String? returnStage,
  }) async {
    await _showMapPointPicker(isFrom: isFrom);
    if (!mounted || returnStage == null) return;
    final hasPoint = isFrom ? _fromLocation != null : _toLocation != null;
    if (hasPoint) _goOrderBoard(returnStage);
  }

  Future<void> _searchManualBoardAddress() async {
    final value = _manualAddressController.text.trim();
    if (value.length < 3) {
      _showBoardMessage('Введите улицу и номер дома');
      return;
    }
    _setAddressFieldValue(isFrom: _manualAddressForFrom, value: value);
    await _searchAndSetAddress(
      isFrom: _manualAddressForFrom,
      navigateAfterApply: false,
    );
    if (!mounted) return;
    final hasPoint =
        _manualAddressForFrom ? _fromLocation != null : _toLocation != null;
    if (hasPoint) {
      if (_manualAddressForFrom || _cityModeIndex == 1) {
        _goOrderBoard(_cityModeIndex == 1 ? 'auction' : 'address');
      } else {
        await _continueBoardFixedOrder();
      }
    }
  }

  Future<void> _applyManualSuggestion(Map<String, dynamic> item) async {
    await _applySuggestion(item, isFrom: _manualAddressForFrom);
    if (!mounted) return;
    if (_manualAddressForFrom || _cityModeIndex == 1) {
      _goOrderBoard(_cityModeIndex == 1 ? 'auction' : 'address');
      return;
    }
    await _continueBoardFixedOrder();
  }

  Future<void> _continueBoardAuctionOrder() async {
    _cityModeIndex = 1;
    if (_fromController.text.trim().length < 3 && _fromLocation == null) {
      setState(() {
        _manualAddressForFrom = true;
        _manualAddressController.text = _fromController.text;
        _statusText = 'Сначала укажите адрес подачи.';
      });
      _goOrderBoard('manual');
      return;
    }
    if (_toController.text.trim().length < 3 && _toLocation == null) {
      setState(() {
        _manualAddressForFrom = false;
        _manualAddressController.text = _toController.text;
        _statusText = 'Теперь укажите адрес назначения.';
      });
      _goOrderBoard('manual');
      return;
    }
    await _create();
  }

  Future<void> _useCurrentLocationAsBoardPickup() async {
    await _initMapCenterByLocation();
    if (_userLocation == null) {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Не удалось определить GPS. Выберите точку подачи на карте.';
      });
      await _pickBoardAddressOnMap(isFrom: true, returnStage: 'address');
      return;
    }
    setState(() {
      _fromLocation = _userLocation;
      if (_fromAddress.trim().isEmpty) {
        _fromAddress = 'Моё местоположение';
        _setAddressFieldValue(isFrom: true, value: _fromAddress);
      }
    });
  }

  Future<void> _applyBoardMapPoint() async {
    _ensureBoardPickupPoint();
    final point = _mapCenter;
    if (_toLocation == null) {
      setState(() {
        _toLocation = point;
        _toAddress = 'Точка назначения выбрана на карте';
        _setAddressFieldValue(isFrom: false, value: _toAddress);
      });
    }
    await _board();
    _goOrderBoard(_toLocation == null ? 'address' : 'routeprice');
  }

  Future<void> _continueBoardFixedOrder() async {
    _ensureBoardPickupPoint();
    if (_toLocation == null && _toController.text.trim().length >= 3) {
      await _searchAndSetAddress(isFrom: false, navigateAfterApply: false);
    }
    if (_toLocation == null) {
      setState(() {
        _statusText =
            'Сначала укажите адрес назначения или выберите точку на карте.';
      });
      _goOrderBoard('address');
      return;
    }
    await _board();
    if (_boardPrice == null) {
      setState(() {
        _statusText =
            'Не удалось рассчитать стоимость. Проверьте адрес назначения или выберите точку на карте.';
      });
      _goOrderBoard('address');
      return;
    }
    _goOrderBoard('routeprice');
  }

  Future<void> _continueBoardIntercityStart() async {
    _modeIndex = 1;
    if (!_hasIntercitySearchCity(isFrom: true) ||
        !_hasIntercitySearchCity(isFrom: false)) {
      setState(() {
        _statusText =
            'Сначала выберите города отправления и назначения, потом точные адреса.';
      });
      return;
    }
    if (_fromController.text.trim().length < 2 ||
        _toController.text.trim().length < 2) {
      setState(() {
        _statusText =
            'Укажите точные адреса отправления и назначения: через поиск или на карте.';
      });
      return;
    }
    final resolved = await _resolveIntercityDraftBeforeCreate();
    if (!mounted || !resolved) return;
    _goOrderBoard('intercity_options');
  }

  Future<void> _continueBoardIntercityManual() async {
    _modeIndex = 1;
    final resolved = await _resolveIntercityDraftBeforeCreate();
    if (!mounted) return;
    if (!resolved) {
      _goOrderBoard('intercity_manual');
      return;
    }
    _goOrderBoard('intercity_options');
  }

  void _applyManualBoardAddress() {
    final value = _manualAddressController.text.trim();
    if (value.isEmpty) {
      _showBoardMessage('Введите адрес вручную');
      return;
    }
    setState(() {
      if (_manualAddressForFrom) {
        _fromAddress = value;
        _fromController.text = value;
        _fromLocation = null;
      } else {
        _toAddress = value;
        _toController.text = value;
        _toLocation = null;
      }
    });
    unawaited(_saveBoardDraft());
    if (_cityModeIndex == 1) {
      if (_fromController.text.trim().length >= 3 &&
          _toController.text.trim().length >= 3) {
        _goOrderBoard('auction');
      } else {
        _showBoardMessage('Заполните адреса "Откуда" и "Куда"');
        _goOrderBoard('auction');
      }
      return;
    }
    _goOrderBoard('fixed');
  }

  String get _displayFromAddress {
    final value = _locationText(isFrom: true).trim();
    return value.isNotEmpty ? value : 'Укажите адрес подачи';
  }

  String get _displayToAddress {
    final value = _locationText(isFrom: false).trim();
    return value.isNotEmpty ? value : 'Укажите адрес назначения';
  }

  String get _displayPrice {
    final price = _boardPrice;
    if (price == null) return 'После расчёта';
    return '${price.toStringAsFixed(0)} $_currencySymbol';
  }

  String _displayClassPrice(double multiplier) {
    final price = _boardPrice;
    if (price == null) return 'После расчёта';
    return '${(price * multiplier).round()} $_currencySymbol';
  }

  String get _displayRouteMeta {
    final duration = _boardDuration;
    final distance = _boardDistance;
    final parts = <String>[];
    if (duration != null) parts.add('$duration мин');
    if (distance != null) parts.add('${distance.toStringAsFixed(1)} км');
    return parts.isEmpty ? 'После выбора точек' : parts.join(' · ');
  }

  void _selectVehicleClassAndContinue(String value) {
    setState(() => _vehicleClass = value);
    _goOrderBoard('payment');
  }

  void _selectPaymentAndContinue(String value) {
    if (!_paymentMethodEnabled(value)) return;
    setState(() => _paymentMethod = value);
    _goOrderBoard('confirm');
  }

  Future<void> _loadSearchCityPreference() async {
    try {
      final storedCityId = await AppPreferences.getCurrentCityId();
      final storedCityName = await AppPreferences.getCurrentCityName();
      if (!mounted) return;
      setState(() {
        _currentCityId =
            storedCityId?.trim().isEmpty ?? true ? null : storedCityId!.trim();
        _currentCityName = (storedCityName ?? '').trim();
        _intercityFromCityId ??= _currentCityId;
        if (_intercityFromCityName.trim().isEmpty) {
          _intercityFromCityName = _currentCityName;
        }
      });
      if (_currentCityId == null) {
        await _seedSearchCityFromProfile();
      }
    } catch (_) {
      await _seedSearchCityFromProfile();
    }
  }

  Future<void> _seedSearchCityFromProfile() async {
    try {
      final res = await _api.get('/me');
      final user = Map<String, dynamic>.from(res.data as Map);
      final cityId = (user['cityId'] ?? '').toString().trim();
      final city = user['city'];
      final cityName =
          city is Map ? (city['name'] ?? '').toString().trim() : '';
      if (cityId.isEmpty) return;
      await AppPreferences.setCurrentCityId(cityId);
      if (cityName.isNotEmpty) {
        await AppPreferences.setCurrentCityName(cityName);
      }
      if (!mounted) return;
      setState(() {
        _currentCityId = cityId;
        _currentCityName = cityName;
        _intercityFromCityId ??= cityId;
        if (_intercityFromCityName.trim().isEmpty) {
          _intercityFromCityName = cityName;
        }
      });
    } catch (_) {
      // Non-blocking. Search can still fall back to anchor-only behavior.
    }
  }

  Future<void> _syncSearchCityFromCoords(LatLng point) async {
    if (!_shouldRestrictSearchToCurrentCity) return;
    try {
      final res = await _api.get(
        '/geo/reverse',
        queryParameters: {'lat': point.latitude, 'lng': point.longitude},
      );
      final cityId = (res.data['cityId'] ?? '').toString().trim();
      final cityName = (res.data['city'] ?? '').toString().trim();
      if (cityId.isEmpty) return;
      await AppPreferences.setCurrentCityId(cityId);
      if (cityName.isNotEmpty) {
        await AppPreferences.setCurrentCityName(cityName);
      }
      if (!mounted) return;
      setState(() {
        _currentCityId = cityId;
        _currentCityName = cityName;
        _intercityFromCityId ??= cityId;
        if (_intercityFromCityName.trim().isEmpty) {
          _intercityFromCityName = cityName;
        }
      });
    } catch (_) {
      // Non-blocking. Search still has anchor + radius fallback.
    }
  }

  Future<void> _callBoardDriver() async {
    String phone = '';
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Телефон водителя появится после назначения'),
        ),
      );
      return;
    }
    final opened = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: phone));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened ? 'Открываем звонок водителю' : 'Телефон водителя скопирован',
        ),
      ),
    );
  }

  Future<void> _copyBoardDriverMessage() async {
    await Clipboard.setData(
      const ClipboardData(text: 'Здравствуйте, я по поездке InterCity.'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщение водителю скопировано')),
    );
  }

  Future<void> _loadCityOptions() async {
    setState(() => _cityOptionsLoading = true);
    try {
      final res = await _api.get('/geo/cities');
      final cities = List<dynamic>.from(res.data as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      cities.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            ),
      );
      if (!mounted) return;
      setState(() {
        _cityOptions = cities;
        if (_currentCityId == null) {
          final defaultCity = cities.cast<Map<String, dynamic>?>().firstWhere(
                (city) =>
                    (city?['name'] ?? '').toString().trim().toLowerCase() ==
                    'алматы',
                orElse: () => cities.isEmpty ? null : cities.first,
              );
          final defaultCityId = (defaultCity?['id'] ?? '').toString().trim();
          final defaultCityName =
              (defaultCity?['name'] ?? '').toString().trim();
          if (defaultCityId.isNotEmpty) {
            _currentCityId = defaultCityId;
            _currentCityName = defaultCityName;
            _intercityFromCityId ??= defaultCityId;
            if (_intercityFromCityName.trim().isEmpty) {
              _intercityFromCityName = defaultCityName;
            }
            final lat = defaultCity?['lat'];
            final lng = defaultCity?['lng'];
            if (lat is num && lng is num) {
              _mapCenter = LatLng(lat.toDouble(), lng.toDouble());
            }
          }
        }
        if (_intercityFromCityId == null &&
            _currentCityId != null &&
            cities.any((city) => city['id'] == _currentCityId)) {
          _intercityFromCityId = _currentCityId;
          _intercityFromCityName = _currentCityName;
        }
      });
    } catch (_) {
      // Non-blocking. Manual address entry still works.
    } finally {
      if (mounted) setState(() => _cityOptionsLoading = false);
    }
  }

  @override
  void didUpdateWidget(covariant OrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken &&
        (widget.resetToken?.isNotEmpty ?? false)) {
      _clearRoute();
    }
  }

  @override
  void dispose() {
    _fromSearchDebounce?.cancel();
    _toSearchDebounce?.cancel();
    _boardDebounce?.cancel();
    _intercityTripsDebounce?.cancel();
    _fromController.dispose();
    _toController.dispose();
    _commentController.dispose();
    _manualAddressController.dispose();
    _deliveryItemController.dispose();
    _deliveryWeightController.dispose();
    _deliveryDimensionsController.dispose();
    _deliveryRecipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_routeStage('offline')) {
      if (routeHas(context, 'dark=1')) {
        return Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (_) => _boardOfflineScreen()),
        );
      }
      return _boardOfflineScreen();
    }
    if (_routeStage('notfound')) {
      if (routeHas(context, 'dark=1')) {
        return Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (_) => _boardAddressNotFoundScreen()),
        );
      }
      return _boardAddressNotFoundScreen();
    }
    if (_routeStage('mode')) {
      return _boardCityModeChoiceScreen();
    }
    if (_routeStage('address')) {
      return _boardAddressSearchScreen();
    }
    if (_routeStage('map')) {
      return _boardMapPointScreen();
    }
    if (_routeStage('fixed')) {
      return _boardCityFixedOrderScreen();
    }
    if (_routeStage('routeprice')) {
      return _boardRoutePriceScreen();
    }
    if (_routeStage('class')) {
      return _boardClassChoiceScreen();
    }
    if (_routeStage('payment')) {
      return _boardPaymentMethodScreen();
    }
    if (_routeStage('searching')) {
      return _boardDriverSearchScreen();
    }
    if (_routeStage('auction')) {
      return _boardAuctionCreateScreen();
    }
    if (_routeStage('offers_wait')) {
      return _boardOffersWaitScreen();
    }
    if (_routeStage('offers_list')) {
      return _boardOffersListScreen();
    }
    if (_routeStage('offer_confirm')) {
      return _boardOfferConfirmScreen();
    }
    if (_routeStage('confirm')) {
      return _boardOrderConfirmScreen();
    }
    if (_routeStage('intercity_start')) {
      return _boardIntercityStartScreen();
    }
    if (_routeStage('intercity_options')) {
      return _boardIntercityOptionsScreen();
    }
    if (_routeStage('intercity_manual')) {
      return _boardIntercityManualAddressScreen();
    }
    if (_routeStage('intercity_wait')) {
      return _boardIntercityWaitScreen();
    }
    if (_routeStage('intercity_details')) {
      return _boardIntercityDetailsScreen();
    }
    if (_routeStage('manual')) {
      return _boardManualAddressScreen();
    }
    if (_passengerMapHomeEnabled &&
        !_routeStage('address') &&
        !_routeStage('routeprice') &&
        !_routeStage('class') &&
        !_routeStage('payment') &&
        !_routeStage('searching') &&
        !_routeStage('auction') &&
        !_routeStage('offers_wait') &&
        !_routeStage('offers_list') &&
        !_routeStage('offer_confirm') &&
        !_routeStage('confirm') &&
        !_routeStage('intercity_start') &&
        !_routeStage('intercity_options') &&
        !_routeStage('intercity_manual') &&
        !_routeStage('intercity_wait') &&
        !_routeStage('intercity_details') &&
        !_routeStage('manual')) {
      return _passengerMapHomeScreen();
    }

    if (_useIntercityBoardUi) {
      return _boardCityModeChoiceScreen();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canCreate = ((_fromLocation != null && _toLocation != null) ||
            _canCreateWithManualAddresses ||
            _hasManualAddressPair) &&
        !_loading;

    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (_orderStep > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: _topBar(),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  _orderStep == 0 ? 8 : 0,
                  16,
                  18,
                ),
                children: [
                  if (_orderStep == 0)
                    _passengerHomeHero()
                  else if (_orderStep == 1)
                    _routeStepTitle()
                  else ...[
                    _stepHeader(),
                    const SizedBox(height: 12),
                  ],
                  ..._orderStepContent(),
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(minHeight: 4),
                    ),
                  ],
                ],
              ),
            ),
            if (_orderStep > 0)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0B0817)
                        : const Color(0xFFFEFCFF),
                    border: Border(
                      top: BorderSide(
                        color: AppTheme.primaryColor.withValues(
                          alpha: isDark ? 0.10 : 0.08,
                        ),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (!_canContinueFromStep(canCreate))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _glassHint(
                            icon: Icons.info_outline_rounded,
                            text: _stepHint(),
                            accent: Colors.orangeAccent,
                          ),
                        ),
                      _orderActionButtons(canCreate: canCreate),
                      if (_orderStep < 3) ...[
                        const SizedBox(height: 5),
                        Text(
                          'Шаг ${_orderStep + 1} из 4',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  ThemeData _boardUtilityTheme() {
    if (routeHas(context, 'dark=1')) {
      return AppTheme.darkTheme;
    }
    return Theme.of(context);
  }

  Widget _boardOfflineScreen() {
    final theme = _boardUtilityTheme();
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => goBackOr(context, fallback: '/order'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Нет подключения',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 38),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 230,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.04),
                            AppTheme.secondaryColor.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                      child: CustomPaint(
                        painter: _IntercityMapPainter(
                          lineColor: AppTheme.primaryColor.withValues(
                            alpha: 0.08,
                          ),
                          routeColor: AppTheme.primaryColor.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE5D2FF), AppTheme.secondaryColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.22,
                            ),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            color: Colors.white,
                            size: 62,
                          ),
                          Positioned(
                            right: 22,
                            bottom: 24,
                            child: Icon(
                              Icons.cancel_rounded,
                              color: AppTheme.primaryColor,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Нет подключения к интернету',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Проверьте соединение и попробуйте снова. Некоторые функции могут быть недоступны офлайн.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
              ),
              const SizedBox(height: 42),
              ICGradientButton(
                label: 'Попробовать снова',
                icon: Icons.refresh_rounded,
                onPressed: () => context.go('/order?address=1'),
              ),
              const SizedBox(height: 12),
              _boardUtilityAction(
                icon: Icons.offline_bolt_rounded,
                label: 'Продолжить офлайн',
                onTap: () => context.go('/order/manual'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardAddressNotFoundScreen() {
    final theme = _boardUtilityTheme();
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => goBackOr(context, fallback: '/order'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Адрес не найден',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 38),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 210,
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.04),
                            AppTheme.secondaryColor.withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: CustomPaint(
                        painter: _IntercityMapPainter(
                          lineColor: AppTheme.primaryColor.withValues(
                            alpha: 0.08,
                          ),
                          routeColor: AppTheme.primaryColor.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE5D2FF), AppTheme.secondaryColor],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.22,
                            ),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.travel_explore_rounded,
                        color: Colors.white,
                        size: 58,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              Text(
                'Мы не нашли этот адрес',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Проверьте написание или уточните детали, чтобы мы могли помочь.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
              ),
              const SizedBox(height: 44),
              ICGradientButton(
                label: 'Уточнить адрес',
                icon: Icons.my_location_rounded,
                onPressed: () => context.go('/order?address=1'),
              ),
              const SizedBox(height: 12),
              _boardUtilityAction(
                icon: Icons.map_rounded,
                label: 'Выбрать на карте',
                onTap: () => context.go('/order/map'),
              ),
              const SizedBox(height: 10),
              _boardUtilityAction(
                icon: Icons.edit_rounded,
                label: 'Ввести вручную',
                onTap: () => context.go('/order/manual'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardUtilityAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = _boardUtilityTheme();
    return Material(
      color: theme.brightness == Brightness.dark
          ? const Color(0xFF11101D)
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeStepTitle() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mode() == 'INTERCITY' ? 'Куда едем?' : 'Куда поедем?',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _mode() == 'INTERCITY'
                ? 'Создайте заявку, и водители предложат свою цену.'
                : 'Укажите адреса или выберите точку на карте.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _passengerHomeHero() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 390,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF11101D), Color(0xFF090814)]
              : const [Color(0xFFF6F2FF), Color(0xFFFFFFFF)],
        ),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.08),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _decorativeMap(isDark: isDark)),
          Positioned(
            top: 16,
            left: 16,
            child: _homeIconButton(Icons.menu_rounded),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: _homeIconButton(Icons.account_circle_rounded),
          ),
          const Positioned(top: 106, left: 84, child: _MapCar(angle: -0.6)),
          const Positioned(top: 176, right: 62, child: _MapCar(angle: 0.8)),
          Positioned(
            left: 24,
            bottom: 104,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withValues(alpha: 0.20),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF11101D).withValues(alpha: 0.96)
                    : Colors.white.withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
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
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Куда поедем?',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _nextOrderStep,
                    child: _homeSearchField(theme),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passengerMapHomeScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: Stack(
        children: [
          Positioned.fill(child: _decorativeMap(isDark: isDark)),
          Positioned(
            left: 16,
            right: 16,
            top: MediaQuery.of(context).padding.top + 12,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _fromAddress.trim().isEmpty
                                ? 'Определяем точку подачи'
                                : _compactAddress(_fromAddress),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _mapHomeRoundButton(
                  icon: Icons.my_location_rounded,
                  onTap: _locating ? null : _initMapCenterByLocation,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: _mapHomeBottomSheet(theme, isDark: isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapHomeBottomSheet(ThemeData theme, {required bool isDark}) {
    final selected = _mapHomeSelectedIndex;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surface.withValues(alpha: isDark ? 0.94 : 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  selected == null ? 'Выберите тариф' : 'Оформление заказа',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
              ),
              if (!_passengerMapHomeSettingsLoaded)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _mapHomeFareCard(
                  index: 0,
                  title: 'Город',
                  subtitle: 'Фиксированная цена',
                  icon: Icons.apartment_rounded,
                ),
                _mapHomeFareCard(
                  index: 1,
                  title: 'Такси',
                  subtitle: 'Водители дают цену',
                  icon: Icons.local_taxi_rounded,
                ),
                _mapHomeFareCard(
                  index: 2,
                  title: 'Межгород',
                  subtitle: 'Между городами',
                  icon: Icons.route_rounded,
                ),
                _mapHomeFareCard(
                  index: 3,
                  title: 'Доставка',
                  subtitle: 'Посылки и грузы',
                  icon: Icons.inventory_2_rounded,
                ),
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            _mapHomeAddressRow(
              label: 'Откуда',
              value: _fromAddress.trim().isEmpty
                  ? 'Моё местоположение'
                  : _compactAddress(_fromAddress),
              icon: Icons.radio_button_checked_rounded,
              onTap: () => _pickBoardAddressOnMap(isFrom: true),
            ),
            const SizedBox(height: 8),
            _mapHomeAddressRow(
              label: 'Куда',
              value: _toAddress.trim().isEmpty
                  ? (selected == 2
                      ? 'Выберите город и адрес'
                      : 'Укажите адрес назначения')
                  : _compactAddress(_toAddress),
              icon: Icons.location_on_rounded,
              onTap: _continueMapHomeFare,
            ),
            const SizedBox(height: 12),
            ICGradientButton(
              label: _toAddress.trim().isEmpty ? 'Указать куда' : 'Продолжить',
              icon: Icons.arrow_forward_rounded,
              onPressed: _continueMapHomeFare,
            ),
          ],
        ],
      ),
    );
  }

  Widget _mapHomeRoundButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: AppTheme.primaryColor),
      ),
    );
  }

  Widget _mapHomeFareCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final selected = _mapHomeSelectedIndex == index;
    return GestureDetector(
      onTap: () => _selectMapHomeFare(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 132,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? null
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.22 : 0.64,
                ),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.20)
                : theme.colorScheme.outline.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppTheme.primaryColor,
              size: 24,
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: 0.76)
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapHomeAddressRow({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.20 : 0.54,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardCityModeChoiceScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'ЗАКАЗ',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Что нужно заказать?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Выберите сценарий, дальше откроется нужная форма.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.08,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _boardEntryCard(
                      title: 'Город',
                      subtitle: 'Обычное такси',
                      icon: Icons.local_taxi_rounded,
                      selected: true,
                      onTap: () => _selectBoardEntry(
                        modeIndex: 0,
                        cityModeIndex: 0,
                        route: 'address',
                      ),
                    ),
                    _boardEntryCard(
                      title: 'Аукцион',
                      subtitle: 'Водители дают цену',
                      icon: Icons.gavel_rounded,
                      onTap: () => _selectBoardEntry(
                        modeIndex: 0,
                        cityModeIndex: 1,
                        route: 'auction',
                      ),
                    ),
                    _boardEntryCard(
                      title: 'Межгород',
                      subtitle: 'Между городами',
                      icon: Icons.route_rounded,
                      onTap: () => _selectBoardEntry(
                        modeIndex: 1,
                        route: 'intercity_start',
                      ),
                    ),
                    _boardEntryCard(
                      title: 'Доставка',
                      subtitle: 'Посылки и грузы',
                      icon: Icons.inventory_2_rounded,
                      onTap: () => _selectBoardEntry(
                        modeIndex: 2,
                        deliveryModeIndex: 0,
                        route: 'order',
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ICGradientButton(
                  label: 'Городское такси',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _selectBoardEntry(
                    modeIndex: 0,
                    cityModeIndex: 0,
                    route: 'address',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardEntryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = selected ? Colors.white : theme.colorScheme.onSurface;
    final mutedColor = selected
        ? Colors.white.withValues(alpha: 0.78)
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected
                ? const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected
                ? null
                : (isDark ? const Color(0xFF11101D) : Colors.white),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.18)
                  : AppTheme.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.16)
                      : AppTheme.primaryColor.withValues(alpha: 0.10),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : AppTheme.primaryColor,
                ),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardAddressSearchScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 28),
                Text(
                  'Куда поедем?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF171426) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.trip_origin_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Откуда',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _displayFromAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed:
                            _locating ? null : _useCurrentLocationAsBoardPickup,
                        child: Text(_locating ? '...' : 'GPS'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF171426) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF7C7590),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _toController,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Поиск адреса',
                            hintStyle: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (value) =>
                              _onAddressChanged(value, isFrom: false),
                          onSubmitted: (_) =>
                              _searchAndSetAddress(isFrom: false),
                        ),
                      ),
                      if (_toController.text.trim().isNotEmpty)
                        IconButton(
                          tooltip: 'Очистить',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _clearAddressField(isFrom: false),
                          icon: Icon(
                            Icons.close_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Указать на карте',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _pickBoardAddressOnMap(
                          isFrom: false,
                          returnStage: 'fixed',
                        ),
                        icon: const Icon(
                          Icons.map_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Найти адрес',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _searchAndSetAddress(isFrom: false),
                        icon: const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_toSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF171426) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      children: _toSuggestions.take(5).map((item) {
                        final title = _compactAddress(
                          (item['displayName'] ?? '').toString(),
                        );
                        return _boardAddressRow(
                          icon: Icons.place_outlined,
                          title: title.isEmpty ? 'Найденный адрес' : title,
                          subtitle: 'Выбрать адрес',
                          onTap: () => _applyBoardDestinationSuggestion(item),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                if (_statusText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _boardAddressRow(
                  icon: Icons.my_location_rounded,
                  title: 'Моё местоположение',
                  subtitle: 'Использовать как адрес подачи',
                  strongIcon: true,
                  onTap: _locating ? null : _useCurrentLocationAsBoardPickup,
                ),
                const SizedBox(height: 10),
                _boardAddressRow(
                  icon: Icons.map_rounded,
                  title: 'Выбрать точку на карте',
                  subtitle: 'Если адрес не находится',
                  onTap: () => _pickBoardAddressOnMap(
                    isFrom: false,
                    returnStage: 'fixed',
                  ),
                ),
                const SizedBox(height: 16),
                _boardSectionHeader(
                  'Недавние и избранные адреса',
                  trailing: 'Профиль',
                  onTrailingTap: () => context.go('/profile'),
                ),
                const SizedBox(height: 8),
                _boardAddressRow(
                  icon: Icons.info_outline_rounded,
                  title: 'Адресов пока нет',
                  subtitle: 'Введите адрес выше или выберите точку на карте',
                  onTap: () => _pickBoardAddressOnMap(
                    isFrom: false,
                    returnStage: 'fixed',
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Добавить адрес в избранное',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardMapPointScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: IntercityMapFallback(dark: isDark)),
            FlutterMap(
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: 16.5,
                onTap: (_, point) => setState(() => _mapCenter = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConstants.osmTileUrl,
                  subdomains: AppConstants.mapTileSubdomains,
                  userAgentPackageName: 'com.milanium.intercity',
                ),
                if (_userLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _userLocation!,
                        width: 24,
                        height: 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _mapCenter,
                      width: 54,
                      height: 54,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.primaryColor,
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF090713).withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.10),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _displayToAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.28),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppTheme.primaryColor,
                      size: 42,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 54,
                    color: AppTheme.primaryColor.withValues(alpha: 0.46),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20,
              bottom: 182,
              child: _mapActionButton(
                icon: Icons.near_me_rounded,
                onTap: _locating
                    ? null
                    : () async {
                        await _initMapCenterByLocation(fillFromIfEmpty: false);
                        if (_userLocation != null) {
                          setState(() => _mapCenter = _userLocation!);
                        }
                      },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _displayToAddress,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _displayFromAddress,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ICGradientButton(
                      label: 'Выбрать эту точку',
                      onPressed: _applyBoardMapPoint,
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

  Widget _boardCityFixedOrderScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasRoute = _fromLocation != null && _toLocation != null;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  _homeIconButton(Icons.arrow_back_rounded),
                  const Expanded(
                    child: Text(
                      'Заказ поездки',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF141326),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                children: [
                  _boardRouteLine(
                    label: 'Откуда',
                    address: _displayFromAddress,
                    first: true,
                  ),
                  const SizedBox(height: 12),
                  _boardRouteLine(
                    label: 'Куда',
                    address: _displayToAddress,
                    first: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: hasRoute
                          ? _routeMapPreview(isDark)
                          : _decorativeMap(isDark: isDark),
                    ),
                    if (!hasRoute)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.16,
                              ),
                            ),
                          ),
                          child: Text(
                            'Укажите точку назначения',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Цена рассчитается автоматически',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_user_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Стоимость поездки по фиксированному тарифу будет известна после указания конечной точки.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ICGradientButton(
                    label: 'Продолжить',
                    onPressed: _continueBoardFixedOrder,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardRoutePriceScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasDestination =
        _toLocation != null && _toController.text.trim().isNotEmpty;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  _homeIconButton(Icons.arrow_back_rounded),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _goOrderBoard('address'),
                    child: const Text('Изменить'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  Text(
                    'Ваш маршрут',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      children: [
                        _boardRouteLine(
                          label: 'Откуда',
                          address: _displayFromAddress,
                          first: true,
                        ),
                        const SizedBox(height: 12),
                        _boardRouteLine(
                          label: 'Куда',
                          address: _displayToAddress,
                          first: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      height: 330,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _routeMapPreview(isDark)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Расчётная цена',
                                style: TextStyle(
                                  color: Color(0xFF7C7590),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _displayPrice,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _displayRouteMeta,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.primaryColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                child: ICGradientButton(
                  label: hasDestination ? 'Далее' : 'Указать куда',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    if (!hasDestination) {
                      setState(() {
                        _statusText =
                            'Сначала выберите адрес назначения из подсказок или на карте.';
                      });
                      _goOrderBoard('address');
                      return;
                    }
                    _goOrderBoard('class');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardClassChoiceScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 28),
                Text(
                  'Выберите класс',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Выберите уровень комфорта',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                _boardClassRow(
                  'Эконом',
                  'Для повседневных поездок',
                  _displayClassPrice(1),
                  Icons.local_taxi_rounded,
                  _vehicleClass == vehicleClassEconomy,
                  onTap: () =>
                      _selectVehicleClassAndContinue(vehicleClassEconomy),
                ),
                const SizedBox(height: 12),
                _boardClassRow(
                  'Оптимал',
                  'Больше пространства и комфорта',
                  _displayClassPrice(1.18),
                  Icons.directions_car_filled_rounded,
                  _vehicleClass == vehicleClassOptimal,
                  onTap: () =>
                      _selectVehicleClassAndContinue(vehicleClassOptimal),
                ),
                const SizedBox(height: 12),
                _boardClassRow(
                  'Комфорт',
                  'Максимальный комфорт в каждой детали',
                  _displayClassPrice(1.38),
                  Icons.check_circle_rounded,
                  _vehicleClass == vehicleClassComfort,
                  onTap: () =>
                      _selectVehicleClassAndContinue(vehicleClassComfort),
                ),
                const SizedBox(height: 12),
                _boardClassRow(
                  'Бизнес',
                  'Премиальный уровень и сервис',
                  _displayClassPrice(1.72),
                  Icons.workspace_premium_rounded,
                  _vehicleClass == vehicleClassBusiness,
                  onTap: () =>
                      _selectVehicleClassAndContinue(vehicleClassBusiness),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Фиксированная цена · Без скрытых платежей',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardPaymentMethodScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 28),
                Text(
                  'Способ оплаты',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Выберите удобный способ',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 26),
                _boardPaymentRow(
                  title: 'Наличными',
                  subtitle: 'Оплата водителю',
                  icon: Icons.payments_rounded,
                  selected: _paymentMethod == paymentMethodCash,
                  onTap: () => _selectPaymentAndContinue(paymentMethodCash),
                ),
                const SizedBox(height: 14),
                _boardPaymentRow(
                  title: 'На карту',
                  subtitle: 'Онлайн-оплата',
                  icon: Icons.credit_card_rounded,
                  selected: _paymentMethod == paymentMethodCardTransfer,
                  onTap: () =>
                      _selectPaymentAndContinue(paymentMethodCardTransfer),
                ),
                const SizedBox(height: 14),
                _boardPaymentRow(
                  title: 'Бонусами',
                  subtitle: 'До 100% стоимости поездки ($_currencySymbol)',
                  icon: Icons.stars_rounded,
                  selected: _paymentMethod == paymentMethodBonus,
                  onTap: () => _selectPaymentAndContinue(paymentMethodBonus),
                ),
                const SizedBox(height: 152),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ваши данные защищены и не передаются третьим лицам',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardOrderConfirmScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            _homeIconButton(Icons.arrow_back_rounded),
            const SizedBox(height: 26),
            Text(
              'Подтвердите заказ',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Проверьте детали поездки',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                children: [
                  _boardRouteLine(
                    label: 'Откуда',
                    address: _displayFromAddress,
                    first: true,
                  ),
                  const SizedBox(height: 12),
                  _boardRouteLine(
                    label: 'Куда',
                    address: _displayToAddress,
                    first: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _boardConfirmRow(
              'Класс',
              vehicleClassLabel(_vehicleClass),
              Icons.event_seat_rounded,
            ),
            _boardConfirmRow(
              'Способ оплаты',
              paymentMethodLabel(_paymentMethod),
              _paymentMethodIcon(_paymentMethod),
            ),
            _boardConfirmRow(
              'Время в пути',
              _boardDuration == null
                  ? 'После расчёта'
                  : '~ $_boardDuration мин',
              Icons.schedule,
            ),
            _boardConfirmRow(
              'Расстояние',
              _boardDistance == null
                  ? 'После расчёта'
                  : '${_boardDistance!.toStringAsFixed(1)} км',
              Icons.route_rounded,
            ),
            const Divider(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Цена поездки',
                    style: TextStyle(
                      color: Color(0xFF4E4962),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _displayPrice,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Нажимая «Заказать», вы принимаете условия пользовательского соглашения',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),
            if (_statusText.isNotEmpty) ...[
              ICPremiumInfoBanner(text: _statusText),
              const SizedBox(height: 12),
            ],
            ICGradientButton(
              label: 'Заказать',
              icon: Icons.check_rounded,
              loading: _loading,
              onPressed: _loading ? null : _create,
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardDriverSearchScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _decorativeMap(isDark: isDark)),
            Positioned.fill(
              child: CustomPaint(painter: _BoardCityRoutePainter(dark: isDark)),
            ),
            Positioned(
              left: 18,
              top: 12,
              child: _homeIconButton(Icons.arrow_back_rounded),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.20 : 0.08,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(
                            strokeWidth: 4,
                            color: AppTheme.primaryColor,
                            backgroundColor: AppTheme.primaryColor.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Поиск водителя...',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Обычно это занимает до 1 минуты',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF171426)
                            : const Color(0xFFF8F5FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Column(
                        children: [
                          _boardRouteLine(
                            label: 'Откуда',
                            address: _displayFromAddress,
                            first: true,
                          ),
                          const SizedBox(height: 12),
                          _boardRouteLine(
                            label: 'Куда',
                            address: _displayToAddress,
                            first: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _boardSearchStat(
                          vehicleClassLabel(_vehicleClass),
                          Icons.event_seat_rounded,
                        ),
                        const SizedBox(width: 10),
                        _boardSearchStat(_displayPrice, Icons.payments_rounded),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => _goOrderBoard('confirm'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        side: const BorderSide(color: AppTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Отменить заказ',
                        style: TextStyle(fontWeight: FontWeight.w900),
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

  Widget _boardAuctionCreateScreen() {
    _cityModeIndex = 1;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _homeIconButton(Icons.arrow_back_rounded),
                    const Expanded(
                      child: Text(
                        'Новый аукцион',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _homeIconButton(Icons.work_outline_rounded),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Куда едем?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Создайте запрос, а водители предложат свою цену',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 142,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _decorativeMap(isDark: isDark)),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BoardCityRoutePainter(dark: isDark),
                          ),
                        ),
                        Positioned(
                          left: 42,
                          top: 22,
                          child: _boardMapChip(
                            'Откуда',
                            Icons.trip_origin,
                            onTap: () {
                              setState(() => _manualAddressForFrom = true);
                              _manualAddressController.text =
                                  _fromController.text;
                              _goOrderBoard('manual');
                            },
                          ),
                        ),
                        Positioned(
                          right: 34,
                          bottom: 28,
                          child: _boardMapChip(
                            'Куда',
                            Icons.location_on,
                            onTap: () {
                              setState(() => _manualAddressForFrom = false);
                              _manualAddressController.text =
                                  _toController.text;
                              _goOrderBoard('manual');
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _boardAuctionField(
                  label: 'Откуда',
                  value: _displayFromAddress,
                  icon: Icons.trip_origin_rounded,
                  onTap: () {
                    setState(() => _manualAddressForFrom = true);
                    _manualAddressController.text = _fromController.text;
                    _goOrderBoard('manual');
                  },
                ),
                const SizedBox(height: 10),
                _boardAuctionField(
                  label: 'Куда',
                  value: _displayToAddress,
                  icon: Icons.location_on_rounded,
                  onTap: () {
                    setState(() => _manualAddressForFrom = false);
                    _manualAddressController.text = _toController.text;
                    _goOrderBoard('manual');
                  },
                ),
                const SizedBox(height: 10),
                _boardAuctionField(
                  label: 'Способ оплаты',
                  value: paymentMethodLabel(_paymentMethod),
                  icon: _paymentMethodIcon(_paymentMethod),
                  trailing: Icons.expand_more_rounded,
                  onTap: () => setState(
                    () => _paymentMethod = _nextPaymentMethod(_paymentMethod),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _commentController,
                  maxLength: 200,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Пожелания, багаж, особенности поездки...',
                    prefixIcon: Icon(
                      Icons.mode_comment_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.gavel_rounded,
                        color: AppTheme.primaryColor,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Водители предложат цену',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Вы увидите предложения и сможете выбрать лучшее.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_statusText.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ICPremiumInfoBanner(text: _statusText),
                ],
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Создать запрос',
                  loading: _loading,
                  onPressed: _loading ? null : _continueBoardAuctionOrder,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardMapChip(String label, IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardAuctionField({
    required String label,
    required String value,
    required IconData icon,
    IconData trailing = Icons.chevron_right_rounded,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Icon(trailing, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _boardManualAddressScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 28),
                Text(
                  'Мы не нашли\nэтот адрес',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Попробуйте изменить формулировку или введите адрес вручную',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(
                      alpha: isDark ? 0.10 : 0.06,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Адрес не найден на карте',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Проверьте написание или укажите ближайший ориентир.',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 46,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _boardSegment(
                          'Откуда',
                          _manualAddressForFrom,
                          onTap: () => setState(() {
                            _manualAddressForFrom = true;
                            _manualAddressController.text =
                                _fromController.text;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _boardSegment(
                          'Куда',
                          !_manualAddressForFrom,
                          onTap: () => setState(() {
                            _manualAddressForFrom = false;
                            _manualAddressController.text = _toController.text;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Введите адрес вручную',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _manualAddressController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchManualBoardAddress(),
                  decoration: InputDecoration(
                    hintText: 'Улица, дом, ориентир',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Указать на карте',
                          onPressed: () => _pickBoardAddressOnMap(
                            isFrom: _manualAddressForFrom,
                            returnStage:
                                _cityModeIndex == 1 ? 'auction' : 'fixed',
                          ),
                          icon: const Icon(
                            Icons.map_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Найти адрес',
                          onPressed: _searchManualBoardAddress,
                          icon: const Icon(
                            Icons.search_rounded,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if ((_manualAddressForFrom ? _fromSuggestions : _toSuggestions)
                    .isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      children: (_manualAddressForFrom
                              ? _fromSuggestions
                              : _toSuggestions)
                          .take(5)
                          .map((item) {
                        final title = _compactAddress(
                          (item['displayName'] ?? '').toString(),
                        );
                        return _boardAddressRow(
                          icon: Icons.place_outlined,
                          title: title.isEmpty ? 'Найденный адрес' : title,
                          subtitle: 'Выбрать точку',
                          onTap: () => _applyManualSuggestion(item),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickBoardAddressOnMap(
                    isFrom: _manualAddressForFrom,
                    returnStage: _cityModeIndex == 1 ? 'auction' : 'fixed',
                  ),
                  icon: const Icon(Icons.map_rounded),
                  label: Text(
                    _manualAddressForFrom
                        ? 'Указать точку подачи на карте'
                        : 'Указать точку назначения на карте',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Найти и продолжить',
                  onPressed: _searchManualBoardAddress,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _applyManualBoardAddress,
                  child: const Text('Оставить как текстовый адрес'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardSegment(String label, bool selected, {VoidCallback? onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _boardOffersWaitScreen() {
    final darkTheme = AppTheme.darkTheme;
    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _homeIconButton(Icons.arrow_back_rounded),
                    const Expanded(
                      child: Text(
                        'Поиск предложений',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Ищем предложения\nот водителей',
                  style: darkTheme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.03,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Это займет не более 30 секунд',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.36,
                          child: _decorativeMap(isDark: true),
                        ),
                      ),
                      const Positioned.fill(
                        child: CustomPaint(
                          painter: _BoardCityRoutePainter(dark: true),
                        ),
                      ),
                      Positioned(
                        left: 38,
                        top: 10,
                        child: _boardDarkMapBadge(
                          'Алматы',
                          Icons.trip_origin_rounded,
                        ),
                      ),
                      Positioned(
                        right: 32,
                        bottom: 142,
                        child: _boardDarkMapBadge(
                          'Астана',
                          Icons.location_on_rounded,
                        ),
                      ),
                      const Positioned(
                        left: 112,
                        bottom: 118,
                        child: _MiniPremiumCar(width: 112),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171426).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ваш маршрут',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Детали',
                              style: TextStyle(
                                color: AppTheme.secondaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _boardDarkRouteLine(_displayFromAddress, true),
                      const SizedBox(height: 8),
                      _boardDarkRouteLine(_displayToAddress, false),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _boardOfferSkeleton(),
                const SizedBox(height: 8),
                _boardOfferSkeleton(),
                const SizedBox(height: 8),
                _boardOfferSkeleton(),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Уведомим, как появятся предложения',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardDarkMapBadge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardDarkRouteLine(String text, bool first) {
    return Row(
      children: [
        Icon(
          first ? Icons.trip_origin_rounded : Icons.location_on_rounded,
          color: AppTheme.secondaryColor,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _boardOfferSkeleton() {
    return Container(
      height: 58,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 112,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 72,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 56,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardOffersListScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final offers = <({
      String name,
      String car,
      String eta,
      String price,
      double rating
    })>[];
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            children: [
              Row(
                children: [
                  _homeIconButton(Icons.arrow_back_rounded),
                  const Spacer(),
                  _homeIconButton(Icons.tune_rounded),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 18),
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Выберите лучшее\nпредложение',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.03,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Цены указаны за всю поездку',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _boardRouteLine(
                            label: 'Откуда',
                            address: _displayFromAddress,
                            first: true,
                          ),
                          const SizedBox(height: 12),
                          _boardRouteLine(
                            label: 'Куда',
                            address: _displayToAddress,
                            first: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        offers.isEmpty
                            ? 'Предложений пока нет'
                            : 'Найдено ${offers.length} предложений',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (offers.isEmpty)
                      _boardStatusCard(
                        icon: Icons.refresh_rounded,
                        title: 'Ждём ответы водителей',
                        text:
                            'Когда водитель ответит на вашу заявку, предложение появится здесь.',
                        action: 'Обновить',
                        onTap: () => _goOrderBoard('offers_wait'),
                      )
                    else
                      for (final offer in offers) ...[
                        _boardDriverOfferCard(
                          name: offer.name,
                          car: offer.car,
                          eta: offer.eta,
                          price: offer.price,
                          rating: offer.rating,
                          onTap: () => _goOrderBoard('offer_confirm'),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDriverOfferCard({
    required String name,
    required String car,
    required String eta,
    required String price,
    required double rating,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171426) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(
              alpha: isDark ? 0.18 : 0.10,
            ),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF2A193F), AppTheme.primaryColor],
                ),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.orange,
                        size: 15,
                      ),
                      Text(
                        rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    car,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    eta,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                const _MiniPremiumCar(width: 52),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardStatusCard({
    required IconData icon,
    required String title,
    required String text,
    required String action,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171426) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }

  Widget _boardOfferConfirmScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _homeIconButton(Icons.arrow_back_rounded),
                    const Expanded(
                      child: Text(
                        'Подтверждение выбора',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Подтвердите выбор',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Проверьте детали и подтвердите поездку',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B2DFF), Color(0xFF2A1248)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.24),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: AppTheme.primaryColor,
                          size: 34,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Алексей',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  '4.9',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Ожидаем подтверждение\nводителя',
                              style: TextStyle(
                                color: Color(0xFFE8DFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _MiniPremiumCar(width: 68),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Цена за поездку',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _displayPrice,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Фиксированная цена',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Divider(height: 28),
                      Text(
                        'Маршрут',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _boardRouteLine(
                        label: 'Откуда',
                        address: _displayFromAddress,
                        first: true,
                      ),
                      const SizedBox(height: 12),
                      _boardRouteLine(
                        label: 'Куда',
                        address: _displayToAddress,
                        first: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _boardAuctionField(
                  label: 'Способ оплаты',
                  value: paymentMethodLabel(_paymentMethod),
                  icon: _paymentMethodIcon(_paymentMethod),
                  trailing: Icons.expand_more_rounded,
                ),
                const SizedBox(height: 12),
                Container(
                  height: 70,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Спасибо!',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '8/200',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Нажимая «Подтвердить», вы соглашаетесь с условиями использования и политикой конфиденциальности',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                ICGradientButton(
                  label: 'Подтвердить',
                  onPressed: () => _goOrderBoard('searching'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardIntercityStartScreen() {
    _modeIndex = 1;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _homeIconButton(Icons.arrow_back_rounded),
                    const Expanded(
                      child: Text(
                        'Межгород',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  'Куда поедем?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Создайте запрос, и мы подберем лучших водителей на вашем маршруте.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 176,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _decorativeMap(isDark: isDark)),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BoardCityRoutePainter(dark: isDark),
                          ),
                        ),
                        const Positioned(
                          left: 34,
                          bottom: 32,
                          child: _MiniPremiumCar(width: 112),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _intercityCitySelectorCard(),
                const SizedBox(height: 12),
                _routeAddressPanel(),
                if (_statusText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ICPremiumInfoBanner(text: _statusText),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    children: [
                      _boardIntercityInfoRow(
                        icon: Icons.calendar_month_rounded,
                        label: 'Дата',
                        value: _formatIntercityDate(_intercityTripDate),
                        onTap: _pickIntercityDate,
                      ),
                      const Divider(height: 18),
                      _boardIntercityInfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'Время',
                        value:
                            '${_intercityTripDate.hour.toString().padLeft(2, '0')}:${_intercityTripDate.minute.toString().padLeft(2, '0')}',
                        onTap: _pickIntercityDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Пассажиры',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$_intercitySeats пассажир(а)',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _boardRoundControl(
                        Icons.remove_rounded,
                        onTap: () => setState(
                          () => _intercitySeats = (_intercitySeats - 1).clamp(
                            1,
                            4,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          '',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        '$_intercitySeats',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 14),
                      _boardRoundControl(
                        Icons.add_rounded,
                        onTap: () => setState(
                          () => _intercitySeats = (_intercitySeats + 1).clamp(
                            1,
                            4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _boardAuctionField(
                  label: 'Способ оплаты',
                  value: paymentMethodLabel(_paymentMethod),
                  icon: _paymentMethodIcon(_paymentMethod),
                  onTap: () => setState(
                    () => _paymentMethod = _nextPaymentMethod(_paymentMethod),
                  ),
                ),
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Далее',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _continueBoardIntercityStart,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardIntercityInfoRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primaryColor, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardRoundControl(IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.18),
          ),
        ),
        child: Icon(icon, color: AppTheme.primaryColor, size: 18),
      ),
    );
  }

  Widget _boardIntercityOptionsScreen() {
    _modeIndex = 1;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 26),
                Text(
                  'Дополнительные опции',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Выберите опции, которые важны для вашей поездки.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 20),
                _boardOptionTitle('Багаж'),
                Row(
                  children: [
                    Expanded(
                      child: _boardOptionChip(
                        'Без багажа',
                        _intercityBaggage == 0,
                        onTap: () => setState(() => _intercityBaggage = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardOptionChip(
                        '1 чемодан',
                        _intercityBaggage == 1,
                        onTap: () => setState(() => _intercityBaggage = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardOptionChip(
                        '2 чемодана',
                        _intercityBaggage == 2,
                        onTap: () => setState(() => _intercityBaggage = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _boardOptionTitle('Перевозка животных'),
                Row(
                  children: [
                    Expanded(
                      child: _boardIconOption(
                        icon: Icons.pets_rounded,
                        label: 'Нет',
                        selected: _intercityPets == 'Нет',
                        onTap: () => setState(() => _intercityPets = 'Нет'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardIconOption(
                        icon: Icons.cruelty_free_rounded,
                        label: 'Маленькие',
                        selected: _intercityPets == 'Маленькие',
                        onTap: () =>
                            setState(() => _intercityPets = 'Маленькие'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardIconOption(
                        icon: Icons.pets_rounded,
                        label: 'Средние',
                        selected: _intercityPets == 'Средние',
                        onTap: () => setState(() => _intercityPets = 'Средние'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardIconOption(
                        icon: Icons.pets_rounded,
                        label: 'Большие',
                        selected: _intercityPets == 'Большие',
                        onTap: () => setState(() => _intercityPets = 'Большие'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _boardOptionTitle('Детское кресло'),
                Row(
                  children: [
                    Expanded(
                      child: _boardOptionChip(
                        'Не нужно',
                        _intercityChildSeats == 0,
                        onTap: () => setState(() => _intercityChildSeats = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardOptionChip(
                        '1 кресло',
                        _intercityChildSeats == 1,
                        onTap: () => setState(() => _intercityChildSeats = 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardOptionChip(
                        '2 кресла',
                        _intercityChildSeats == 2,
                        onTap: () => setState(() => _intercityChildSeats = 2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _boardOptionTitle('Курение в салоне'),
                Row(
                  children: [
                    Expanded(
                      child: _boardOptionChip(
                        'Не курить',
                        !_intercitySmokingAllowed,
                        icon: Icons.smoke_free_rounded,
                        onTap: () =>
                            setState(() => _intercitySmokingAllowed = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _boardOptionChip(
                        'Можно курить',
                        _intercitySmokingAllowed,
                        onTap: () =>
                            setState(() => _intercitySmokingAllowed = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _boardOptionTitle('Комментарий для водителей'),
                TextField(
                  controller: _commentController,
                  maxLength: 200,
                  minLines: 3,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Пожелания, остановки, примечания...',
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
                if (_statusText.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ICPremiumInfoBanner(text: _statusText),
                ],
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Далее',
                  icon: Icons.arrow_forward_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _create,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardOptionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _boardOptionChip(
    String label,
    bool selected, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
          color: selected ? null : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: selected ? Colors.white : AppTheme.primaryColor,
                size: 16,
              ),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardIconOption({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                )
              : null,
          color: selected ? null : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : AppTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : AppTheme.primaryColor),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardIntercityManualAddressScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _homeIconButton(Icons.arrow_back_rounded),
                const SizedBox(height: 24),
                Text(
                  'Укажите адрес вручную',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Мы не нашли этот адрес на карте. Пожалуйста, уточните адрес для продолжения.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 22),
                _boardManualAddressBlock(
                  label: 'Откуда',
                  value: _displayFromAddress,
                  isFrom: true,
                  suggestions: _fromSuggestions
                      .map(
                        (item) => _compactAddress(
                          (item['displayName'] ?? '').toString(),
                        ),
                      )
                      .where((item) => item.trim().isNotEmpty)
                      .take(4)
                      .toList(),
                ),
                const SizedBox(height: 18),
                _boardManualAddressBlock(
                  label: 'Куда',
                  value: _displayToAddress,
                  isFrom: false,
                  suggestions: _toSuggestions
                      .map(
                        (item) => _compactAddress(
                          (item['displayName'] ?? '').toString(),
                        ),
                      )
                      .where((item) => item.trim().isNotEmpty)
                      .take(4)
                      .toList(),
                ),
                const SizedBox(height: 18),
                ICGradientButton(
                  label: 'Продолжить',
                  icon: Icons.arrow_forward_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _continueBoardIntercityManual,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardManualAddressBlock({
    required String label,
    required String value,
    required bool isFrom,
    required List<String> suggestions,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                Icons.cancel_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                size: 19,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.10),
            ),
          ),
          child: Column(
            children: [
              for (final item in suggestions) ...[
                _boardSuggestionLine(
                  item,
                  onTap: () async {
                    _setAddressFieldValue(isFrom: isFrom, value: item);
                    await _searchAndSetAddress(
                      isFrom: isFrom,
                      navigateAfterApply: false,
                    );
                  },
                ),
                if (item != suggestions.last) const Divider(height: 12),
              ],
              const Divider(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _pickBoardAddressOnMap(
                  isFrom: isFrom,
                  returnStage: 'intercity_manual',
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        color: AppTheme.primaryColor,
                        size: 19,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Показать на карте',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _boardSuggestionLine(String text, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.location_on_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardIntercityWaitScreen() {
    final darkTheme = AppTheme.darkTheme;
    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _homeIconButton(Icons.arrow_back_rounded),
                    const Expanded(
                      child: Text(
                        'Поиск водителей',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Ищем водителей\nна вашем маршруте',
                  style: darkTheme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.03,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Обычно это занимает 1-2 минуты',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.42,
                          child: _decorativeMap(isDark: true),
                        ),
                      ),
                      const Positioned.fill(
                        child: CustomPaint(
                          painter: _BoardCityRoutePainter(dark: true),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        top: 28,
                        child: _boardDarkRoutePoint(_displayFromAddress),
                      ),
                      Positioned(
                        right: 4,
                        top: 96,
                        child: _boardDarkRoutePoint(_displayToAddress),
                      ),
                      const Positioned(
                        left: 74,
                        bottom: 58,
                        child: _MiniPremiumCar(width: 148),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Поступившие предложения',
                  style: darkTheme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Предложений пока нет',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    'Когда водитель ответит на межгород-заявку, предложение появится здесь.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ICGradientButton(
                  label: 'Опубликовать заявку',
                  icon: Icons.send_rounded,
                  loading: _loading,
                  onPressed: _loading ? null : _create,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _boardDarkRoutePoint(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _boardIntercityDetailsScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Row(
                children: [
                  _homeIconButton(Icons.arrow_back_rounded),
                  const Expanded(
                    child: Text(
                      'Детали поездки',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 46),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 62,
                                height: 62,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFFE9DDFF),
                                      AppTheme.secondaryColor,
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Водитель не выбран',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          color: Colors.orange,
                                          size: 16,
                                        ),
                                        Expanded(
                                          child: Text(
                                            ' Предложение ещё не принято',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Text(
                                        'Опытный водитель',
                                        style: TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const _MiniPremiumCar(width: 92),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Автомобиль будет назначен',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'После принятия предложения водителем',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _boardDetailsCard(
                      title: 'Маршрут',
                      children: [
                        _boardRouteLine(
                          label: 'Откуда',
                          address: _displayFromAddress,
                          first: true,
                        ),
                        const SizedBox(height: 12),
                        _boardRouteLine(
                          label: 'Куда',
                          address: _displayToAddress,
                          first: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _boardDetailsCard(
                      title: 'Дата и время',
                      children: [
                        _boardIntercityInfoRow(
                          icon: Icons.calendar_month_rounded,
                          label: _formatIntercityDate(_intercityTripDate),
                          value:
                              '${_intercityTripDate.hour.toString().padLeft(2, '0')}:${_intercityTripDate.minute.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _boardDetailsCard(
                      title: 'Оплата',
                      children: [
                        _boardIntercityInfoRow(
                          icon: _paymentMethodIcon(_paymentMethod),
                          label: paymentMethodLabel(_paymentMethod),
                          value: '',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _boardDetailsCard(
                      title: 'Стоимость',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Включено: топливо, платные дороги, ожидание 15 мин',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            Text(
                              _displayPrice,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _callBoardDriver,
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Позвонить'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: AppTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyBoardDriverMessage,
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('Написать'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: AppTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ICGradientButton(
                label: 'Я в пути',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => context.go('/intercity/request/active'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDetailsCard({
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _boardSearchStat(String label, IconData icon) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF171426)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardConfirmRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardPaymentRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171426) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.primaryColor.withValues(alpha: 0.10),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF7C7590)),
          ],
        ),
      ),
    );
  }

  Widget _boardClassRow(
    String title,
    String subtitle,
    String price,
    IconData icon,
    bool selected, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171426) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.12),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.primaryColor.withValues(alpha: 0.10),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardRouteLine({
    required String label,
    required String address,
    required bool first,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          first ? Icons.trip_origin_rounded : Icons.location_on_rounded,
          color: AppTheme.primaryColor,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        if (!first)
          Icon(
            Icons.close_rounded,
            color: theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
      ],
    );
  }

  Widget _boardSectionHeader(
    String title, {
    required String trailing,
    VoidCallback? onTrailingTap,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTrailingTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Text(
              trailing,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _boardAddressRow({
    required IconData icon,
    required String title,
    required String subtitle,
    bool strongIcon = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color:
                  strongIcon ? AppTheme.primaryColor : const Color(0xFF7C7590),
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF7C7590),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _boardModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required bool crowned,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 214,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFF7F2FF), Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF171426), Color(0xFF11101D)],
                    )
                  : null,
          color: selected || isDark ? null : Colors.white,
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: isDark ? 0.20 : 0.14),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -6,
              bottom: -10,
              child: Icon(
                icon == Icons.gavel_rounded
                    ? Icons.gavel_rounded
                    : Icons.directions_car_filled_rounded,
                size: 132,
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            if (crowned)
              const Positioned(
                right: 0,
                top: 0,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const Spacer(),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: selected
                          ? const LinearGradient(
                              colors: [
                                AppTheme.secondaryColor,
                                AppTheme.primaryColor,
                              ],
                            )
                          : null,
                      color: selected
                          ? null
                          : AppTheme.primaryColor.withValues(alpha: 0.10),
                    ),
                    child: Icon(
                      selected
                          ? Icons.arrow_forward_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? Colors.white : AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorativeMap({required bool isDark}) {
    final center = _fromLocation ?? _userLocation ?? _mapCenter;
    return Stack(
      children: [
        Positioned.fill(
          child: IntercityStaticTileMap(
            key: ValueKey(
              'passenger-osm-${center.latitude.toStringAsFixed(4)}-${center.longitude.toStringAsFixed(4)}-$isDark',
            ),
            center: center,
            zoom: 16.5,
            dark: isDark,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF090713).withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ],
    );
  }

  Widget _routeMapPreview(bool isDark) {
    final from = _fromLocation;
    final to = _toLocation;
    if (from == null || to == null) {
      return _decorativeMap(isDark: isDark);
    }
    final center = LatLng(
      (from.latitude + to.latitude) / 2,
      (from.longitude + to.longitude) / 2,
    );
    final km = _distance.as(LengthUnit.Kilometer, from, to);
    final zoom = km < 1
        ? 16.5
        : km < 4
            ? 15.5
            : km < 12
                ? 13.5
                : 11.5;
    return Stack(
      children: [
        Positioned.fill(child: IntercityMapFallback(dark: isDark)),
        FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: zoom),
          children: [
            TileLayer(
              urlTemplate: AppConstants.osmTileUrl,
              subdomains: AppConstants.mapTileSubdomains,
              userAgentPackageName: 'com.milanium.intercity',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [from, to],
                  color: AppTheme.primaryColor,
                  strokeWidth: 5,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: from,
                  width: 38,
                  height: 38,
                  child: const Icon(
                    Icons.trip_origin_rounded,
                    color: AppTheme.primaryColor,
                    size: 32,
                  ),
                ),
                Marker(
                  point: to,
                  width: 44,
                  height: 44,
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppTheme.primaryColor,
                    size: 40,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (isDark)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF090713).withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _homeIconButton(IconData icon) {
    final theme = Theme.of(context);
    VoidCallback? onTap;
    if (icon == Icons.arrow_back_rounded) {
      onTap = () => goBackOr(context, fallback: '/order');
    } else if (icon == Icons.close_rounded) {
      onTap = () => context.go('/order');
    } else if (icon == Icons.account_circle_rounded) {
      onTap = () => context.go('/profile');
    } else if (icon == Icons.menu_rounded) {
      onTap = () => context.go('/profile/settings');
    } else if (icon == Icons.near_me_rounded) {
      onTap = _initMapCenterByLocation;
    } else if (icon == Icons.tune_rounded) {
      onTap = () => context.go('/profile/settings');
    } else if (icon == Icons.work_outline_rounded) {
      onTap = () => context.go('/driver/home');
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _homeSearchField(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.36,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Укажите адрес поездки',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderActionButtons({required bool canCreate}) {
    final nextButton = _premiumOrderButton(
      label: _stepActionLabel(),
      icon: _orderStep < 3 ? Icons.arrow_forward_rounded : Icons.check_rounded,
      onPressed: _canContinueFromStep(canCreate)
          ? (_orderStep < 3 ? _nextOrderStep : _create)
          : null,
    );

    if (_orderStep <= 0) {
      return SizedBox(height: 50, width: double.infinity, child: nextButton);
    }

    final backButton = _premiumOrderButton(
      label: 'Назад',
      icon: Icons.arrow_back_rounded,
      onPressed: _previousOrderStep,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              SizedBox(height: 50, width: double.infinity, child: nextButton),
              const SizedBox(height: 8),
              SizedBox(height: 46, width: double.infinity, child: backButton),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(height: 50, width: 108, child: backButton),
            const SizedBox(width: 10),
            Expanded(child: SizedBox(height: 50, child: nextButton)),
          ],
        );
      },
    );
  }

  Widget _stepHeader() {
    final theme = Theme.of(context);
    const titles = ['Режим', 'Маршрут', 'Тариф и оплата', 'Подтверждение'];
    const subtitles = [
      'Выберите тип поездки',
      'Укажите откуда и куда',
      'Настройте условия заказа',
      'Проверьте детали перед отправкой',
    ];
    return _surfaceCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (index) {
              final active = index <= _orderStep;
              return Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: active
                        ? AppTheme.primaryColor
                        : theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            titles[_orderStep],
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitles[_orderStep],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _orderStepContent() {
    switch (_orderStep) {
      case 0:
        return [
          _modeSelector(),
          if (_mode() == 'CITY') ...[
            const SizedBox(height: 10),
            _cityFlowCard(),
          ],
          if (_mode() == 'DELIVERY') ...[
            const SizedBox(height: 10),
            _deliveryTypeCard(),
          ],
        ];
      case 1:
        return _routeStepContent();
      case 2:
        return _optionsStepContent();
      default:
        return _confirmStepContent();
    }
  }

  List<Widget> _routeStepContent() {
    return [
      if (_requestType() == requestTypeIntercity) ...[
        _intercityCitySelectorCard(),
        const SizedBox(height: 8),
      ],
      if (_requestType() != requestTypeIntercity) ...[
        _addressSearchHeroCard(),
        const SizedBox(height: 12),
      ],
      _routeAddressPanel(),
      if (_requestType() == requestTypeCityFixed && !_routeStepReady) ...[
        const SizedBox(height: 8),
        _glassHint(
          icon: Icons.info_outline_rounded,
          text: 'Для расчёта стоимости нужны точки на карте.',
        ),
      ],
    ];
  }

  Widget _addressSearchHeroCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 158,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : const Color(0xFFF8F5FF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: _decorativeMap(isDark: isDark)),
          Positioned(
            left: 30,
            top: 40,
            child: _mapPinBubble('Откуда', Icons.trip_origin_rounded),
          ),
          Positioned(
            right: 28,
            bottom: 34,
            child: _mapPinBubble('Куда', Icons.location_on_rounded),
          ),
        ],
      ),
    );
  }

  Widget _mapPinBubble(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 17),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF171329),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeAddressPanel() {
    final theme = Theme.of(context);
    return _surfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _compactAddressField(
            label: 'Откуда',
            controller: _fromController,
            suggestions: _fromSuggestions,
            onChanged: (v) => _onAddressChanged(v, isFrom: true),
            onSearchTap: () => _searchAndSetAddress(isFrom: true),
            onSuggestionTap: (item) =>
                _applySuggestionAndContinue(item, isFrom: true),
            icon: Icons.trip_origin_rounded,
          ),
          const SizedBox(height: 10),
          _compactAddressField(
            label: 'Куда',
            controller: _toController,
            suggestions: _toSuggestions,
            onChanged: (v) => _onAddressChanged(v, isFrom: false),
            onSearchTap: () => _searchAndSetAddress(isFrom: false),
            onSuggestionTap: (item) =>
                _applySuggestionAndContinue(item, isFrom: false),
            icon: Icons.location_on_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _routeActionTile(
                  icon: Icons.my_location_rounded,
                  title: 'Моё местоположение',
                  subtitle: 'Определить на карте',
                  onTap: _locating
                      ? null
                      : () async {
                          await _initMapCenterByLocation();
                          if (_userLocation != null) {
                            setState(() {
                              _fromLocation = _userLocation;
                              _fromAddress = 'Моё местоположение';
                              _fromController.text = _fromAddress;
                            });
                          }
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _routeActionTile(
                  icon: Icons.map_rounded,
                  title: 'Выбрать точку',
                  subtitle: 'На карте',
                  onTap: () => _showMapPointPicker(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Недавние адреса',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _glassHint(
            icon: Icons.history_rounded,
            text: 'Недавние адреса появятся после ваших поездок.',
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Адрес добавлен в избранное')),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Добавить адрес в избранное'),
          ),
        ],
      ),
    );
  }

  Widget _compactAddressField({
    required String label,
    required TextEditingController controller,
    required List<Map<String, dynamic>> suggestions,
    required void Function(String) onChanged,
    required VoidCallback onSearchTap,
    required void Function(Map<String, dynamic>) onSuggestionTap,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isFromField = label == 'Откуда';
    final searching = isFromField ? _fromAddressSearching : _toAddressSearching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.10 : 0.34,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.primaryColor),
              suffixIcon: IconButton(
                tooltip: searching ? 'Идёт поиск' : 'Найти адрес',
                onPressed: onSearchTap,
                icon: searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppTheme.primaryColor,
                        size: 16,
                      ),
              ),
              labelText: label,
              hintText: label == 'Откуда'
                  ? 'Введите адрес подачи'
                  : 'Введите адрес назначения',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => onSearchTap(),
          ),
        ),
        if (searching) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'Идёт поиск адреса...',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...suggestions.take(5).map((s) {
            return _savedAddressRow(
              (s['displayName'] ?? '').toString(),
              'Найденный адрес',
              onTap: () => onSuggestionTap(s),
            );
          }),
        ],
      ],
    );
  }

  Widget _routeActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _savedAddressRow(
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _quickRouteCard() {
    final theme = Theme.of(context);
    final fromText = _fromAddress.trim().isEmpty
        ? 'Моё местоположение'
        : _fromAddress.trim();
    final toText = _toAddress.trim().isEmpty ? 'Куда едем?' : _toAddress.trim();
    return ICCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _quickRouteRow(
            icon: Icons.radio_button_checked_rounded,
            label: 'Откуда',
            value: fromText,
            color: AppTheme.primaryColor,
            theme: theme,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1.5,
                height: 20,
                color: AppTheme.primaryColor.withValues(alpha: 0.30),
              ),
            ),
          ),
          _quickRouteRow(
            icon: Icons.location_on_rounded,
            label: 'Куда',
            value: toText,
            color: AppTheme.primaryColor,
            theme: theme,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating
                      ? null
                      : () async {
                          await _initMapCenterByLocation();
                          if (_userLocation != null) {
                            setState(() {
                              _fromLocation = _userLocation;
                              _fromAddress = 'Моё местоположение';
                              _fromController.text = _fromAddress;
                            });
                          }
                        },
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Моё местоположение'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => _showMapPointPicker(isFrom: false),
                  child: const Icon(Icons.map_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickRouteRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ThemeData theme,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
      ],
    );
  }

  Widget _intercityCitySelectorCard() {
    final theme = Theme.of(context);
    return _surfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_city_rounded,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Сначала выберите города',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_cityOptionsLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.open_in_full_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Нажмите на город, откроется полноэкранный поиск по карте. После выбора города адрес улицы будет искаться рядом с ним.',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              _intercityCityButton(
                label: 'Город откуда',
                value: _intercityCityName(isFrom: true),
                icon: Icons.trip_origin_rounded,
                onTap: () => _openIntercityCitySearch(isFrom: true),
              ),
              const SizedBox(height: 10),
              _intercityCityButton(
                label: 'Город куда',
                value: _intercityCityName(isFrom: false),
                icon: Icons.location_on_rounded,
                onTap: () => _openIntercityCitySearch(isFrom: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intercityCityButton({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final text = value.trim().isEmpty ? 'Выбрать город' : value.trim();
    final selected = value.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const Icon(Icons.search_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _openIntercityCitySearch({required bool isFrom}) async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final controller = TextEditingController(
          text: _intercityCityName(isFrom: isFrom),
        );
        Timer? debounce;
        var loading = false;
        var results = <Map<String, dynamic>>[];
        var message = controller.text.trim().isEmpty
            ? 'Введите город, например Алматы, Астана, Усть-Каменогорск.'
            : 'Начните вводить город.';

        Future<void> runSearch(
          String query,
          void Function(void Function()) setSheetState,
        ) async {
          final normalized = query.trim();
          if (normalized.length < 2) {
            setSheetState(() {
              results = [];
              message = 'Введите минимум 2 символа.';
              loading = false;
            });
            return;
          }
          setSheetState(() {
            loading = true;
            message = '';
          });
          try {
            final found = await _searchCitiesOnMap(normalized);
            if (!mounted) return;
            setSheetState(() {
              results = found;
              message =
                  found.isEmpty ? 'Город не найден. Уточните запрос.' : '';
              loading = false;
            });
          } catch (e) {
            if (!mounted) return;
            setSheetState(() {
              results = [];
              message = 'Не удалось выполнить поиск. Попробуйте ещё раз.';
              loading = false;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Scaffold(
              backgroundColor: theme.colorScheme.surface,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          Expanded(
                            child: Text(
                              isFrom ? 'Город отправления' : 'Город назначения',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Поиск города по карте',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: controller.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    controller.clear();
                                    debounce?.cancel();
                                    setSheetState(() {
                                      results = [];
                                      message = 'Введите город.';
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onChanged: (value) {
                          debounce?.cancel();
                          debounce = Timer(
                            const Duration(milliseconds: 450),
                            () {
                              runSearch(value, setSheetState);
                            },
                          );
                          setSheetState(() {});
                        },
                        onSubmitted: (value) => runSearch(value, setSheetState),
                      ),
                      const SizedBox(height: 14),
                      if (loading) const LinearProgressIndicator(),
                      if (!loading && message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: _glassHint(
                            icon: Icons.info_outline_rounded,
                            text: message,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = results[index];
                            final title = _cityTitleFromGeo(item);
                            final subtitle =
                                (item['displayName'] ?? '').toString();
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.16,
                                  ),
                                ),
                              ),
                              leading: const CircleAvatar(
                                backgroundColor: AppTheme.primaryColor,
                                child: Icon(
                                  Icons.location_city_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                debounce?.cancel();
                                Navigator.of(context).pop(item);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;
    final point = _pointFromGeoItem(selected);
    final name = _cityTitleFromGeo(selected);
    _clearAddressField(isFrom: isFrom);
    setState(() {
      if (isFrom) {
        _intercityFromCityId = null;
        _intercityFromCityName = name;
        _rideCurrency = rideCurrencyCode(selected);
        if (!_paymentMethodEnabled(_paymentMethod)) {
          _paymentMethod = paymentMethodCash;
        }
        _intercityFromCityPoint = point;
        _setAddressFieldValue(isFrom: true, value: '');
      } else {
        _intercityToCityId = null;
        _intercityToCityName = name;
        _intercityToCityPoint = point;
        _setAddressFieldValue(isFrom: false, value: '');
      }
      _statusText = 'Город выбран. Теперь укажите точный адрес в этом городе.';
    });
    if (point != null) {
      _moveMap(point, 11);
    }
    unawaited(_saveBoardDraft());
    _scheduleIntercityReadyTripsSearch();
  }

  List<Widget> _optionsStepContent() {
    return [
      if (_requestType() == requestTypeIntercity || _mode() == 'DELIVERY') ...[
        _scheduleCard(),
        const SizedBox(height: 12),
      ],
      if (_requestType() == requestTypeIntercity) ...[
        _intercityAuctionCard(),
        const SizedBox(height: 12),
        _intercityOptionsCard(),
        const SizedBox(height: 12),
        _intercityReadyTripsCard(),
        const SizedBox(height: 12),
      ],
      if (_supportsVehicleClass) ...[
        _vehicleClassCard(),
        const SizedBox(height: 12),
        _priceCard(),
        const SizedBox(height: 12),
      ],
      if (_mode() == 'DELIVERY') ...[
        _deliveryFieldsCard(),
        const SizedBox(height: 12),
      ],
      _paymentMethodCard(),
      if (_requestType() == requestTypeCityAuction ||
          _mode() == 'DELIVERY') ...[
        const SizedBox(height: 12),
        _glassHint(
          icon: Icons.gavel_rounded,
          text: _requestType() == requestTypeCityAuction
              ? 'Стоимость заранее не указывается: водители предложат цену после публикации.'
              : 'Исполнитель увидит заявку и условия доставки.',
        ),
      ],
    ];
  }

  List<Widget> _confirmStepContent() {
    return [
      _confirmOrderCard(),
      const SizedBox(height: 12),
      _commentCard(),
      if (_statusText.isNotEmpty) ...[
        const SizedBox(height: 10),
        _glassHint(
          icon: _statusIsSuccess
              ? Icons.check_circle_outline_rounded
              : Icons.notifications_active_outlined,
          text: _statusText,
          accent: _statusIsError
              ? Colors.redAccent
              : (_statusIsSuccess ? Colors.greenAccent : null),
        ),
      ],
    ];
  }

  Widget _confirmOrderCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fromText = _fromController.text.trim().isEmpty
        ? 'Адрес подачи не указан'
        : _fromController.text.trim();
    final toText = _toController.text.trim().isEmpty
        ? 'Адрес назначения не указан'
        : _toController.text.trim();
    final price = _boardPrice == null
        ? 'Цена рассчитается автоматически'
        : '${_boardPrice!.toStringAsFixed(0)} $_currencySymbol';
    return _surfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Подтвердите заказ',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Проверьте детали поездки',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFFBF9FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                _routePointLine(
                  dotColor: AppTheme.primaryColor,
                  title: 'Откуда',
                  value: fromText,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 3, bottom: 3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 20,
                      color: AppTheme.primaryColor.withValues(alpha: 0.22),
                    ),
                  ),
                ),
                _routePointLine(
                  dotColor: AppTheme.secondaryColor,
                  title: 'Куда',
                  value: toText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _confirmDetailRow(
            'Класс',
            vehicleClassLabel(_vehicleClass),
            Icons.airline_seat_recline_extra_rounded,
          ),
          _confirmDetailRow(
            'Способ оплаты',
            paymentMethodLabel(_paymentMethod),
            _paymentMethodIcon(_paymentMethod),
          ),
          _confirmDetailRow(
            'Время в пути',
            _boardDuration == null ? 'После расчёта' : '~ $_boardDuration мин',
            Icons.schedule_rounded,
          ),
          _confirmDetailRow(
            'Расстояние',
            _boardDistance == null
                ? 'После расчёта'
                : '${_boardDistance!.toStringAsFixed(0)} км',
            Icons.route_rounded,
          ),
          const Divider(height: 24),
          Row(
            children: [
              Text(
                'Цена поездки',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                price,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _glassHint(
            icon: Icons.verified_user_rounded,
            text:
                'Нажимая “Заказать”, вы принимаете условия пользовательского соглашения.',
          ),
        ],
      ),
    );
  }

  Widget _confirmDetailRow(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentCard() {
    final theme = Theme.of(context);
    return _surfaceCard(
      child: TextField(
        controller: _commentController,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        decoration: _inputDecoration(
          label: _mode() == 'DELIVERY'
              ? 'Комментарий к доставке'
              : _isMarketRequest
                  ? 'Комментарий к заявке'
                  : 'Комментарий к заказу',
          hint: _mode() == 'DELIVERY'
              ? 'Подъезд, этаж, получатель, особенности'
              : _isMarketRequest
                  ? 'Ориентир, пожелания, детали встречи'
                  : 'Подъезд, ориентир, пожелания водителю',
          icon: Icons.notes_outlined,
        ),
        maxLines: 2,
      ),
    );
  }

  Widget _topBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modeTitle = switch (_mode()) {
      'CITY' => _cityModeIndex == 0 ? 'Город • Легковой' : 'Город • Аукцион',
      'INTERCITY' => 'Межгород',
      _ => 'Доставка',
    };
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkSurface.withValues(alpha: 0.78)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.secondaryColor.withValues(alpha: 0.20),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x33000000)
                      : AppTheme.primaryColor.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                const ICLogoMark(size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'InterCity',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Заказ • $modeTitle',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        _mapActionButton(
          icon: Icons.person_outline_rounded,
          onTap: () => context.push('/profile'),
        ),
      ],
    );
  }

  Widget _mapActionButton({
    required IconData? icon,
    required VoidCallback? onTap,
    Widget? child,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.56),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          alignment: Alignment.center,
          child: child ??
              Icon(icon, color: onTap == null ? Colors.white38 : Colors.white),
        ),
      ),
    );
  }

  Widget _surfaceCard({required Widget child, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          if (!isDark)
            const BoxShadow(
              color: Color(0x142C174C),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
        ],
      ),
      child: child,
    );
  }

  // ignore: unused_element
  Widget _routeBoardCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fromText = _fromController.text.trim().isEmpty
        ? 'Откуда'
        : _fromController.text.trim();
    final toText =
        _toController.text.trim().isEmpty ? 'Куда' : _toController.text.trim();
    final priceText = _boardPrice == null
        ? (_requestType() == requestTypeCityFixed
            ? 'Цена рассчитается автоматически'
            : 'Водители предложат цену')
        : '${_boardPrice!.toStringAsFixed(0)} $_currencySymbol';
    final meta = _boardDistance == null
        ? requestTypeLabel(_requestType())
        : '${_boardDistance!.toStringAsFixed(1)} км • ${_boardDuration ?? 0} мин';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF171029), Color(0xFF0B0817)]
              : const [Colors.white, Color(0xFFF6F1FF)],
        ),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.18),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x182C174C),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _routePointLine(
                  dotColor: AppTheme.primaryColor,
                  title: 'Откуда',
                  value: fromText,
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.swap_vert_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 2, bottom: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 22,
                color: AppTheme.primaryColor.withValues(alpha: 0.22),
              ),
            ),
          ),
          _routePointLine(
            dotColor: AppTheme.secondaryColor,
            title: 'Куда',
            value: toText,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8F6FF),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        priceText,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routePointLine({
    required Color dotColor,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _premiumOrderButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: 16),
  }) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(18);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.52,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Ink(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: enabled
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: enabled ? null : Colors.white.withValues(alpha: 0.08),
              boxShadow: enabled
                  ? const [
                      BoxShadow(
                        color: Color(0x667C2DFF),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: enabled ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      labelStyle: TextStyle(
        color: isDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant,
      ),
      hintStyle: TextStyle(
        color: isDark ? Colors.white38 : theme.colorScheme.onSurfaceVariant,
      ),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.03)
          : AppTheme.lightBackground,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.10 : 0.16),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.2),
      ),
    );
  }

  Widget _glassHint({
    required IconData icon,
    required String text,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final borderColor = accent ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.42,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: borderColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accent = AppTheme.primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent
                : AppTheme.primaryColor.withValues(alpha: isDark ? 0.14 : 0.16),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : theme.colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeSelector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const items = <Map<String, String>>[
      {
        'chip': 'ГОРОД',
        'title': 'Город',
        'subtitle': 'Легковой по городу или аукцион',
        'icon': 'taxi',
      },
      {
        'chip': 'МЕЖГОРОД',
        'title': 'Межгород',
        'subtitle': 'Заявки и готовые поездки',
        'icon': 'route',
      },
      {
        'chip': 'ДОСТАВКА',
        'title': 'Доставка',
        'subtitle': 'По городу, межгород, РФ',
        'icon': 'delivery',
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Выберите режим',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 0,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.16),
                ),
              ),
              child: Text(
                items[_modeIndex]['title']!,
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final threeColumnWidth = (constraints.maxWidth - (spacing * 2)) / 3;
            final cardWidth = threeColumnWidth >= 104
                ? threeColumnWidth
                : (constraints.maxWidth - spacing) / 2;
            final compactCard = cardWidth < 120;
            final cardHeight = compactCard ? 112.0 : 104.0;
            final cardPadding = compactCard ? 8.0 : 12.0;
            final iconBoxSize = compactCard ? 26.0 : 34.0;
            final iconSize = compactCard ? 16.0 : 18.0;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(items.length, (i) {
                final selected = _modeIndex == i;
                final icon = switch (items[i]['icon']) {
                  'route' => Icons.route_rounded,
                  'delivery' => Icons.inventory_2_rounded,
                  _ => Icons.local_taxi_rounded,
                };
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _modeIndex = i;
                      _resetOrderStep();
                      _boardPrice = null;
                      _boardDistance = null;
                      _boardDuration = null;
                      if (!paymentMethodsForRequestType(
                        _requestType(),
                      ).contains(_paymentMethod)) {
                        _paymentMethod = paymentMethodCash;
                      }
                    });
                    _scheduleAutoBoard();
                    _scheduleIntercityReadyTripsSearch();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: cardWidth,
                    height: cardHeight,
                    padding: EdgeInsets.all(cardPadding),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: selected
                          ? const LinearGradient(
                              colors: [
                                AppTheme.primaryColor,
                                AppTheme.deepViolet,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: selected
                          ? null
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: isDark ? 0.20 : 0.54),
                      border: Border.all(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.18)
                            : theme.colorScheme.outline.withValues(alpha: 0.34),
                      ),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x553D1B7A),
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.16)
                                : AppTheme.primaryColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            icon,
                            size: iconSize,
                            color:
                                selected ? Colors.white : AppTheme.primaryColor,
                          ),
                        ),
                        SizedBox(height: compactCard ? 5 : 10),
                        Text(
                          items[i]['chip']!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            fontSize: compactCard ? 10 : 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i]['subtitle']!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.72)
                                : theme.colorScheme.onSurfaceVariant,
                            fontSize: compactCard ? 9 : 10.5,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            );
          },
        ),
        if (_mode() != 'CITY') ...[
          const SizedBox(height: 8),
          _glassHint(
            icon: Icons.tune_rounded,
            text: 'Режим: ${items[_modeIndex]['title']!}',
          ),
        ],
      ],
    );
  }

  // ignore: unused_element
  Widget _addressField({
    required String label,
    required TextEditingController controller,
    required List<Map<String, dynamic>> suggestions,
    required void Function(String) onChanged,
    required VoidCallback onSearchTap,
    required void Function(Map<String, dynamic>) onSuggestionTap,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = label == 'Откуда' ? Colors.greenAccent : Colors.redAccent;
    final intercityCity = _requestType() == requestTypeIntercity
        ? _intercityCityName(isFrom: label == 'Откуда')
        : '';
    final helper = _requestType() == requestTypeIntercity
        ? (intercityCity.isEmpty
            ? 'Сначала выберите город выше'
            : 'Улица, дом в городе $intercityCity')
        : _supportsManualAddress
            ? 'Поиск или ручной адрес'
            : 'Улица и номер дома';
    return _surfaceCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              if (helper.isNotEmpty)
                Flexible(
                  child: Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Material(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSearchTap,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      Icons.search_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFFBF9FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
                      hintText: _requestType() == requestTypeIntercity
                          ? (intercityCity.isEmpty
                              ? 'Выберите город выше'
                              : 'Введите улицу и дом')
                          : _supportsManualAddress
                              ? 'Поиск или ручной адрес'
                              : 'Введите улицу и номер дома',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: onChanged,
                    onSubmitted: (_) => onSearchTap(),
                  ),
                ),
                if (controller.text.trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Очистить ${label.toLowerCase()}',
                    onPressed: () =>
                        _clearAddressField(isFrom: label == 'Откуда'),
                    icon: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                IconButton(
                  tooltip: 'Найти адрес',
                  onPressed: onSearchTap,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showMapPointPicker(isFrom: label == 'Откуда'),
              icon: const Icon(Icons.map_rounded),
              label: const Text('Указать на карте'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.28),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Найденные адреса',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                ),
                borderRadius: BorderRadius.circular(18),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : AppTheme.lightBackground,
              ),
              child: Column(
                children: suggestions.take(3).map((s) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Material(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => onSuggestionTap(s),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.10,
                                  ),
                                ),
                                child: Icon(
                                  Icons.place_outlined,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.primaryColor,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (s['displayName'] ?? '').toString(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cityFlowCard({bool compact = false}) {
    final theme = Theme.of(context);
    return _surfaceCard(
      padding: compact ? const EdgeInsets.all(10) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберите режим поездки по городу',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 15 : 17,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _cityModeTile(
                  title: 'Легковой по городу',
                  subtitle: 'Фиксированный тариф',
                  icon: Icons.local_taxi_rounded,
                  selected: _cityModeIndex == 0,
                  onTap: () {
                    setState(() {
                      _cityModeIndex = 0;
                      _resetOrderStep();
                    });
                    _paymentMethod = paymentMethodCash;
                    _scheduleAutoBoard();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _cityModeTile(
                  title: 'Аукцион',
                  subtitle: 'Водители предложат цену',
                  icon: Icons.gavel_rounded,
                  selected: _cityModeIndex == 1,
                  onTap: () {
                    setState(() {
                      _cityModeIndex = 1;
                      _resetOrderStep();
                    });
                    _boardPrice = null;
                    _scheduleAutoBoard();
                  },
                ),
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            _glassHint(
              icon: _cityModeIndex == 0
                  ? Icons.payments_rounded
                  : Icons.gavel_rounded,
              text: _cityModeIndex == 0
                  ? 'Система сама рассчитает стоимость по маршруту и выбранному классу.'
                  : 'Цена заранее не считается: водители увидят маршрут и предложат свою цену.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _cityModeTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(minHeight: 148),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : isDark
                  ? const LinearGradient(
                      colors: [AppTheme.darkSurface, AppTheme.darkBackground],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
          color: selected || isDark ? null : AppTheme.lightSurface,
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.22)
                : AppTheme.secondaryColor.withValues(alpha: 0.18),
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x4D7C2DFF),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              bottom: -18,
              child: Icon(
                icon == Icons.gavel_rounded
                    ? Icons.gavel_rounded
                    : Icons.directions_car_filled_rounded,
                size: 68,
                color: (selected ? Colors.white : AppTheme.primaryColor)
                    .withValues(alpha: selected ? 0.12 : 0.05),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: selected ? Colors.white : AppTheme.primaryColor,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      selected
                          ? Icons.arrow_forward_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? Colors.white : AppTheme.primaryColor,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        selected ? Colors.white : theme.colorScheme.onSurface,
                    fontSize: 15,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.72)
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _deliveryTypeCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const types = [
      ('По городу', requestTypeDeliveryCity),
      ('Межгород', requestTypeDeliveryIntercity),
      ('По РФ', requestTypeDeliveryRf),
    ];
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Выберите тип доставки',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Груз по городу, между городами или по РФ',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: types.map((entry) {
                final selected = _requestType() == entry.$2;
                final isLast = types.last == entry;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: isLast ? 0 : 6),
                    child: _deliveryTypeRow(
                      label: entry.$1,
                      requestType: entry.$2,
                      selected: selected,
                      onTap: () {
                        setState(
                          () => _deliveryModeIndex = types.indexOf(entry),
                        );
                        _scheduleIntercityReadyTripsSearch();
                      },
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

  Widget _deliveryTypeRow({
    required String label,
    required String requestType,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? null
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.18)
                : AppTheme.primaryColor.withValues(alpha: 0.12),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppTheme.primaryColor.withValues(alpha: 0.10),
              ),
              child: Icon(
                _deliveryTypeIcon(requestType),
                color: selected ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _deliveryTypeSubtitle(requestType),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? Colors.white70
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color:
                  selected ? Colors.white : theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  IconData _deliveryTypeIcon(String requestType) {
    switch (requestType) {
      case requestTypeDeliveryIntercity:
        return Icons.alt_route_rounded;
      case requestTypeDeliveryRf:
        return Icons.public_rounded;
      case requestTypeDeliveryCity:
      default:
        return Icons.local_shipping_rounded;
    }
  }

  String _deliveryTypeSubtitle(String requestType) {
    switch (requestType) {
      case requestTypeDeliveryIntercity:
        return 'Перевозка груза между городами';
      case requestTypeDeliveryRf:
        return 'Доставка по России';
      case requestTypeDeliveryCity:
      default:
        return 'Курьерская доставка по городу';
    }
  }

  Widget _vehicleClassCard() {
    final theme = Theme.of(context);
    const options = [
      vehicleClassEconomy,
      vehicleClassOptimal,
      vehicleClassComfort,
      vehicleClassBusiness,
    ];
    return _surfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выберите класс',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Выберите уровень комфорта',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...options.map((item) {
            final selected = _vehicleClass == item;
            return Padding(
              padding: EdgeInsets.only(bottom: item == options.last ? 0 : 10),
              child: _vehicleClassListTile(
                vehicleClass: item,
                selected: selected,
                onTap: () {
                  setState(() => _vehicleClass = item);
                  _scheduleAutoBoard();
                },
              ),
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                color: AppTheme.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Фиксированная цена без скрытых платежей',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vehicleClassListTile({
    required String vehicleClass,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final price = switch (vehicleClass) {
      vehicleClassEconomy => 1780,
      vehicleClassOptimal => 2280,
      vehicleClassComfort => 2980,
      vehicleClassBusiness => 3980,
      _ => 1780,
    };
    final subtitle = switch (vehicleClass) {
      vehicleClassEconomy => 'Для повседневных поездок',
      vehicleClassOptimal => 'Больше пространства и комфорта',
      vehicleClassComfort => 'Максимальный комфорт в каждой детали',
      vehicleClassBusiness => 'Премиальный уровень и сервис',
      _ => 'Комфортная поездка',
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.08)
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFFBF9FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.12),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selected
                    ? const LinearGradient(
                        colors: [
                          AppTheme.secondaryColor,
                          AppTheme.primaryColor,
                        ],
                      )
                    : null,
                color: selected
                    ? null
                    : AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
              child: Icon(
                _vehicleClassIcon(vehicleClass),
                color: selected ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleClassLabel(vehicleClass),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$price $_currencySymbol',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _compactVehicleClassTile({
    required String vehicleClass,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected
              ? null
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.24)
                : AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _vehicleClassIcon(vehicleClass),
              color: selected ? Colors.white : AppTheme.primaryColor,
              size: 18,
            ),
            const SizedBox(height: 5),
            Text(
              vehicleClassLabel(vehicleClass),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _vehicleClassIcon(String vehicleClass) {
    switch (vehicleClass) {
      case vehicleClassBusiness:
        return Icons.workspace_premium_rounded;
      case vehicleClassComfort:
        return Icons.verified_rounded;
      case vehicleClassOptimal:
        return Icons.directions_car_filled_rounded;
      case vehicleClassEconomy:
      default:
        return Icons.local_taxi_rounded;
    }
  }

  Widget _paymentMethodCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = _paymentMethodEnabled(_paymentMethod);
    return _surfaceCard(
      padding: const EdgeInsets.all(10),
      child: InkWell(
        onTap: _showPaymentMethodSheet,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8F6FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: Icon(
                  _paymentMethodIcon(_paymentMethod),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Оплата',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      paymentMethodLabel(_paymentMethod),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.error,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Изменить',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentMethodSheet() async {
    final methods = paymentMethodsForRequestType(_requestType())
        .where(_paymentMethodEnabled)
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите способ оплаты',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                ...methods.map((method) {
                  final selected = _paymentMethod == method;
                  final enabled = _paymentMethodEnabled(method);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _paymentSheetOption(
                      method: method,
                      selected: selected,
                      enabled: enabled,
                      onTap: () {
                        if (!enabled) {
                          setState(
                            () => _statusText =
                                'Выберите наличные или безналичную оплату.',
                          );
                          Navigator.of(sheetContext).pop();
                          return;
                        }
                        setState(() => _paymentMethod = method);
                        _scheduleAutoBoard();
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _paymentSheetOption({
    required String method,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.10)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : theme.colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _paymentMethodIcon(method),
              color: enabled
                  ? AppTheme.primaryColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paymentMethodLabel(method),
                    style: TextStyle(
                      color: enabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _paymentMethodSubtitle(method),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected
                  ? AppTheme.primaryColor
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  bool _paymentMethodEnabled(String method) =>
      paymentMethodsForRequestType(_requestType()).contains(method);

  String _nextPaymentMethod(String current) {
    final methods = paymentMethodsForRequestType(_requestType())
        .where(_paymentMethodEnabled)
        .toList();
    final index = methods.indexOf(current);
    return methods[(index + 1) % methods.length];
  }

  IconData _paymentMethodIcon(String method) {
    switch (method) {
      case paymentMethodCardTransfer:
        return Icons.credit_card_rounded;
      case paymentMethodBonus:
        return Icons.stars_rounded;
      case paymentMethodCash:
      default:
        return Icons.payments_rounded;
    }
  }

  String _paymentMethodSubtitle(String method) {
    switch (method) {
      case paymentMethodCardTransfer:
        return 'Онлайн-оплата картой, водителю после завершения';
      case paymentMethodBonus:
        return 'Оплата бонусами до 100% стоимости поездки';
      case paymentMethodCash:
      default:
        return 'Оплата водителю наличными';
    }
  }

  Widget _scheduleCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: _loading ? null : _pickIntercityDate,
      borderRadius: BorderRadius.circular(16),
      child: _surfaceCard(
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                color: isDark ? Colors.white : AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mode() == 'DELIVERY'
                        ? 'Дата и время забора'
                        : 'Желаемые дата и время',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatIntercityDate(_intercityTripDate),
                    style: TextStyle(
                      color: isDark
                          ? Colors.white70
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white70 : AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _deliveryFieldsCard() {
    final theme = Theme.of(context);
    return _surfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Параметры груза',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Описание, вес, размер и контакт получателя',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _deliveryMiniHint(
                        icon: Icons.shield_outlined,
                        text: 'Без скрытых платежей',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _deliveryMiniHint(
                        icon: Icons.payments_rounded,
                        text: 'Наличные или карта',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _deliveryItemController,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: _inputDecoration(
                    label: 'Что доставить',
                    hint: 'Например: документы, коробка, посылка',
                    icon: Icons.inventory_2_outlined,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deliveryWeightController,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          label: 'Вес, кг',
                          hint: 'Если известен',
                          icon: Icons.scale_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _deliveryDimensionsController,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: _inputDecoration(
                          label: 'Размеры',
                          hint: 'Например: 40x30x20',
                          icon: Icons.straighten_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deliveryRecipientController,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: _inputDecoration(
                    label: 'Контакт получателя',
                    hint: 'Имя и телефон, если нужно',
                    icon: Icons.contact_phone_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryMiniHint({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant;
    final hasPrice = _boardPrice != null;
    if (_requestType() == requestTypeIntercity) {
      final routeReady = _fromLocation != null && _toLocation != null;
      final distanceText = _boardDistance != null
          ? '${_boardDistance!.toStringAsFixed(1)} км'
          : 'маршрут рассчитывается';
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0x26FF9800), Color(0x10FFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              routeReady ? 'Аукцион межгорода' : 'Межгород',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              routeReady
                  ? (_intercityWholeCabin
                      ? 'Маршрут подтверждён: весь салон, расстояние $distanceText.'
                      : 'Маршрут подтверждён: $_intercitySeats мест(а), расстояние $distanceText.')
                  : 'Укажите точки "Откуда" и "Куда", чтобы подготовить заявку.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 6),
            Text(
              'Фиксированной цены здесь нет. После публикации заявки водители увидят маршрут и предложат свою цену.',
              style: TextStyle(color: muted),
            ),
          ],
        ),
      );
    }
    if (_requestType() == requestTypeCityAuction || _mode() == 'DELIVERY') {
      final routeReady = _fromLocation != null && _toLocation != null;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0x2618C5A9), Color(0x12FFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _requestType() == requestTypeCityAuction
                  ? 'Городской аукцион'
                  : requestTypeLabel(_requestType()),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              routeReady || _canCreateWithManualAddresses
                  ? 'Цена заранее не считается. После публикации заявки водители увидят маршрут, оплату и предложат свои условия.'
                  : 'Укажите адреса или введите их вручную, чтобы опубликовать заявку.',
              style: TextStyle(color: muted),
            ),
            if (_mode() == 'DELIVERY') ...[
              const SizedBox(height: 6),
              Text(
                'Доступно: ${paymentMethodsForRequestType(_requestType()).map(paymentMethodLabel).join(', ')}.',
                style: TextStyle(color: muted),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: hasPrice
            ? const LinearGradient(
                colors: [Color(0xFF261044), Color(0xFF100B1F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: hasPrice
            ? null
            : isDark
                ? Colors.white.withValues(alpha: 0.04)
                : AppTheme.lightBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasPrice
              ? AppTheme.primaryColor
              : AppTheme.primaryColor.withValues(alpha: isDark ? 0.10 : 0.12),
        ),
        boxShadow: hasPrice
            ? const [
                BoxShadow(
                  color: Color(0x333D1B7A),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: hasPrice
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _priceMetricPill(
                          'Расстояние',
                          '${(_boardDistance ?? 0).toStringAsFixed(1)} км',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _priceMetricPill(
                          'В пути',
                          '${_boardDuration ?? 0} мин',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Расчётная цена',
                          style: TextStyle(
                            color: Color(0xFF7C7590),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_boardPrice!.toStringAsFixed(0)} $_currencySymbol',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            color: Color(0xFF161126),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Стоимость уже учитывает выбранный класс авто.',
                          style: TextStyle(
                            color: Color(0xFF7C7590),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Введите адреса "Откуда" и "Куда", чтобы увидеть стоимость поездки',
                style: TextStyle(color: muted),
              ),
            ),
    );
  }

  Widget _priceMetricPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _intercityOptionsCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant;
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Параметры заявки',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _optionPill(
                label: 'Весь салон',
                selected: _intercityWholeCabin,
                onTap: () {
                  setState(() => _intercityWholeCabin = true);
                  _scheduleAutoBoard();
                },
              ),
              _optionPill(
                label: 'Количество мест',
                selected: !_intercityWholeCabin,
                onTap: () {
                  setState(() => _intercityWholeCabin = false);
                  _scheduleAutoBoard();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _loading ? null : _pickIntercityDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : AppTheme.lightBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: isDark ? Colors.white : AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Желаемые дата и время',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatIntercityDate(_intercityTripDate),
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white70 : AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_intercityWholeCabin)
            Text(
              'Водители будут предлагать цену за весь салон.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          if (!_intercityWholeCabin)
            Row(
              children: [
                Text(
                  'Мест:',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  onPressed: _intercitySeats > 1
                      ? () {
                          setState(() => _intercitySeats--);
                          _scheduleAutoBoard();
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppTheme.primaryColor,
                ),
                Container(
                  width: 44,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : AppTheme.lightBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    '$_intercitySeats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _intercitySeats < 4
                      ? () {
                          setState(() => _intercitySeats++);
                          _scheduleAutoBoard();
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppTheme.primaryColor,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _intercityAuctionCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0x263DDC97), Color(0x123D1B7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.gavel_rounded,
                color: Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Как работает аукцион межгорода',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _auctionStep(
            '1',
            'Вы публикуете заявку',
            'Указываете маршрут, желаемую дату и количество мест.',
          ),
          const SizedBox(height: 8),
          _auctionStep(
            '2',
            'Водители видят заявку',
            'Они отправляют свои предложения по цене.',
          ),
          const SizedBox(height: 8),
          _auctionStep(
            '3',
            'Вы ждёте отклик',
            'Можно публиковать заявку заранее: водители увидят маршрут и дату поездки.',
          ),
        ],
      ),
    );
  }

  Widget _intercityReadyTripsCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : theme.colorScheme.onSurfaceVariant;
    final fromCity = _intercityCityName(isFrom: true);
    final toCity = _intercityCityName(isFrom: false);
    final seatsNeeded = _intercityWholeCabin ? 4 : _intercitySeats;

    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.alt_route_rounded,
                color: AppTheme.secondaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Готовые поездки водителей',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Как в попутках: можно не только ждать аукцион, но и сразу выбрать подходящего водителя на ${_formatIntercityDate(_intercityTripDate)}.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (fromCity.isEmpty || toCity.isEmpty)
            Text(
              'Сначала укажите города "Откуда" и "Куда", чтобы увидеть готовые поездки.',
              style: TextStyle(
                color: isDark
                    ? Colors.white60
                    : theme.colorScheme.onSurfaceVariant,
              ),
            )
          else if (_intercityReadyTripsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else if (_intercityReadyTrips.isEmpty)
            Text(
              'На выбранные дату и направление готовых поездок пока нет. В этом случае аукцион остаётся лучшим вариантом.',
              style: TextStyle(
                color: isDark
                    ? Colors.white60
                    : theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: _intercityReadyTrips.take(4).map((trip) {
                final seatsAvailable =
                    (trip['seatsAvailable'] as num?)?.toInt() ?? 0;
                final pricePerSeat =
                    (trip['pricePerSeat'] as num?)?.toDouble() ?? 0;
                final isTop = isTopRideSharingTrip(trip);
                final canBook = seatsAvailable >= seatsNeeded && !_loading;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          gradient: LinearGradient(
                            colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.secondaryColor,
                                    AppTheme.primaryColor,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.26,
                                    ),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.directions_car_filled_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${trip['fromCity']} → ${trip['toCity']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  height: 1.08,
                                ),
                              ),
                            ),
                            if (isTop)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.amberAccent.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'В ТОПЕ',
                                  style: TextStyle(
                                    color: Colors.amberAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _readyTripMetric(
                                    icon: Icons.schedule_rounded,
                                    label: 'Выезд',
                                    value: _formatIntercityDate(
                                      DateTime.tryParse(
                                            (trip['departureTime'] ?? '')
                                                .toString(),
                                          )?.toLocal() ??
                                          _intercityTripDate,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _readyTripMetric(
                                    icon: Icons.payments_rounded,
                                    label: 'Цена',
                                    value:
                                        '${pricePerSeat.toStringAsFixed(0)} ${rideCurrencySymbol(trip)}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _readyTripMetric(
                                    icon: Icons.event_seat_rounded,
                                    label: 'Места',
                                    value: '$seatsAvailable свободно',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _readyTripMetric(
                                    icon: Icons.workspace_premium_rounded,
                                    label: 'Статус',
                                    value: isTop ? 'Приоритет' : 'Обычная',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: _premiumOrderButton(
                                label: canBook
                                    ? 'Выбрать поездку ($seatsNeeded мест)'
                                    : 'Недостаточно мест',
                                icon: Icons.event_seat_rounded,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                onPressed:
                                    canBook ? () => _bookReadyTrip(trip) : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _readyTripMetric({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
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

  Future<void> _pickIntercityDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _intercityTripDate.isBefore(today) ? today : _intercityTripDate,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: 'Выберите дату поездки',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
      locale: const Locale('ru'),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_intercityTripDate),
      helpText: 'Ориентировочное время',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (!mounted) return;
    final nextHour = time?.hour ?? _intercityTripDate.hour;
    final nextMinute = time?.minute ?? _intercityTripDate.minute;
    setState(() {
      _intercityTripDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        nextHour,
        nextMinute,
      );
    });
    _scheduleIntercityReadyTripsSearch();
  }

  String _formatIntercityDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.${value.year} $hour:$minute';
  }

  void _scheduleIntercityReadyTripsSearch() {
    _intercityTripsDebounce?.cancel();
    if (_mode() != 'INTERCITY') {
      if (_intercityReadyTrips.isNotEmpty || _intercityReadyTripsLoading) {
        setState(() {
          _intercityReadyTrips = const [];
          _intercityReadyTripsLoading = false;
        });
      }
      return;
    }

    final fromCity = _intercityCityName(isFrom: true);
    final toCity = _intercityCityName(isFrom: false);
    if (fromCity.isEmpty || toCity.isEmpty) {
      setState(() {
        _intercityReadyTrips = const [];
        _intercityReadyTripsLoading = false;
      });
      return;
    }

    final requestId = ++_intercityTripsRequestId;
    _intercityTripsDebounce = Timer(
      const Duration(milliseconds: 450),
      () async {
        if (!mounted || _mode() != 'INTERCITY') return;
        setState(() => _intercityReadyTripsLoading = true);
        try {
          final res = await _api.get(
            '/ridesharing/trips/search',
            queryParameters: {
              'fromCity': fromCity,
              'toCity': toCity,
              'date': DateTime(
                _intercityTripDate.year,
                _intercityTripDate.month,
                _intercityTripDate.day,
              ).toIso8601String(),
            },
          );
          if (!mounted || requestId != _intercityTripsRequestId) return;
          final trips = List<dynamic>.from(
            res.data as List,
          ).map((item) => Map<String, dynamic>.from(item as Map)).toList();
          trips.sort((a, b) {
            final aTop = isTopRideSharingTrip(a);
            final bTop = isTopRideSharingTrip(b);
            if (aTop != bTop) return bTop ? 1 : -1;
            final aMinutes = _minutesFromTrip(a['departureTime']);
            final bMinutes = _minutesFromTrip(b['departureTime']);
            final preferred =
                _intercityTripDate.hour * 60 + _intercityTripDate.minute;
            final aDelta = (aMinutes - preferred).abs();
            final bDelta = (bMinutes - preferred).abs();
            if (aDelta != bDelta) return aDelta.compareTo(bDelta);
            final aParsed = DateTime.tryParse(
              (a['departureTime'] ?? '').toString(),
            );
            final bParsed = DateTime.tryParse(
              (b['departureTime'] ?? '').toString(),
            );
            if (aParsed == null || bParsed == null) return 0;
            return aParsed.compareTo(bParsed);
          });
          setState(() {
            _intercityReadyTrips = trips;
            _intercityReadyTripsLoading = false;
          });
        } catch (_) {
          if (!mounted || requestId != _intercityTripsRequestId) return;
          setState(() {
            _intercityReadyTrips = const [];
            _intercityReadyTripsLoading = false;
          });
        }
      },
    );
  }

  int _minutesFromTrip(dynamic raw) {
    final value = raw?.toString();
    final parsed = value == null ? null : DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return 0;
    return parsed.hour * 60 + parsed.minute;
  }

  Future<void> _bookReadyTrip(Map<String, dynamic> trip) async {
    final seats = _intercityWholeCabin ? 4 : _intercitySeats;
    setState(() => _loading = true);
    try {
      await _api.post(
        '/ridesharing/trips/${trip['id']}/book',
        data: {'seats': seats},
      );
      if (!mounted) return;
      setState(() {
        _statusText =
            'Поездка забронирована на ${_formatIntercityDate(DateTime.tryParse((trip['departureTime'] ?? '').toString())?.toLocal() ?? _intercityTripDate)}. Водитель увидит вашу бронь.';
      });
      _scheduleIntercityReadyTripsSearch();
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _statusText =
            'Не удалось забронировать поездку. Проверьте данные и попробуйте ещё раз.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _auctionStep(String step, String title, String subtitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark
                      ? Colors.white70
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _mode() {
    switch (_modeIndex) {
      case 0:
        return 'CITY';
      case 1:
        return 'INTERCITY';
      default:
        return 'DELIVERY';
    }
  }

  String _requestType() {
    switch (_mode()) {
      case 'CITY':
        return _cityModeIndex == 0
            ? requestTypeCityFixed
            : requestTypeCityAuction;
      case 'INTERCITY':
        return requestTypeIntercity;
      case 'DELIVERY':
      default:
        switch (_deliveryModeIndex) {
          case 1:
            return requestTypeDeliveryIntercity;
          case 2:
            return requestTypeDeliveryRf;
          default:
            return requestTypeDeliveryCity;
        }
    }
  }

  bool get _supportsManualAddress =>
      supportsManualAddressForRequestType(_requestType());
  bool get _requiresConfirmedCoordinates =>
      requiresConfirmedCoordinates(_requestType());
  bool get _supportsSystemPrice =>
      supportsSystemPriceForRequestType(_requestType());
  bool get _supportsVehicleClass =>
      supportsVehicleClassForRequestType(_requestType());
  bool get _isMarketRequest =>
      isMarketRequestType(_effectiveCreateRequestType());

  String _effectiveCreateRequestType() {
    if (_requestType() == requestTypeCityFixed &&
        (_fromLocation == null || _toLocation == null || _boardPrice == null) &&
        _hasManualAddressPair) {
      return requestTypeCityAuction;
    }
    return _requestType();
  }

  bool get _canCreateWithManualAddresses {
    if (!_supportsManualAddress) return false;
    if (_requestType() == requestTypeIntercity &&
        (!_hasIntercitySearchCity(isFrom: true) ||
            !_hasIntercitySearchCity(isFrom: false))) {
      return false;
    }
    return _fromController.text.trim().length >= 3 &&
        _toController.text.trim().length >= 3;
  }

  bool get _hasManualAddressPair =>
      _fromController.text.trim().length >= 3 &&
      _toController.text.trim().length >= 3;

  void _clearRoute() {
    _boardDebounce?.cancel();
    _boardRequestId++;
    _fromSuggestionRequestId++;
    _toSuggestionRequestId++;
    _setAddressFieldValue(isFrom: true, value: '');
    _setAddressFieldValue(isFrom: false, value: '');
    setState(() {
      _fromLocation = null;
      _toLocation = null;
      _fromAddress = '';
      _toAddress = '';
      _commentController.clear();
      _fromSuggestions = const [];
      _toSuggestions = const [];
      _statusText = '';
      _boardPrice = null;
      _boardDistance = null;
      _boardDuration = null;
      _intercityTripDate = _defaultIntercityTripDate();
      _intercityBaggage = 1;
      _intercityPets = 'Нет';
      _intercityChildSeats = 0;
      _intercitySmokingAllowed = false;
      _intercityReadyTrips = const [];
      _intercityReadyTripsLoading = false;
      _paymentMethod = paymentMethodCash;
      _vehicleClass = vehicleClassEconomy;
      _deliveryItemController.clear();
      _deliveryWeightController.clear();
      _deliveryDimensionsController.clear();
      _deliveryRecipientController.clear();
    });
    unawaited(AppPreferences.clearOrderDraft());
    if (_userLocation != null) {
      _moveMap(_userLocation!, 14);
    }
  }

  void _resetBoardState({required bool isFrom}) {
    _boardDebounce?.cancel();
    _boardRequestId++;
    if (isFrom) {
      _fromSuggestionRequestId++;
    } else {
      _toSuggestionRequestId++;
    }
    setState(() {
      if (isFrom) {
        _fromLocation = null;
        _fromAddress = '';
        _fromSuggestions = const [];
      } else {
        _toLocation = null;
        _toAddress = '';
        _toSuggestions = const [];
      }
      _boardPrice = null;
      _boardDistance = null;
      _boardDuration = null;
      _statusText = '';
    });
    unawaited(_saveBoardDraft());
  }

  void _clearAddressField({required bool isFrom}) {
    if (isFrom) {
      _fromSearchDebounce?.cancel();
      _lastFromInputValue = '';
      _fromPendingStaleQueryEcho = null;
      _suppressFromAddressChange = true;
      _fromController.clear();
      _suppressFromAddressChange = false;
    } else {
      _toSearchDebounce?.cancel();
      _lastToInputValue = '';
      _toPendingStaleQueryEcho = null;
      _suppressToAddressChange = true;
      _toController.clear();
      _suppressToAddressChange = false;
    }
    _resetBoardState(isFrom: isFrom);
    setState(() {
      _intercityReadyTrips = const [];
      _intercityReadyTripsLoading = false;
    });
    unawaited(_saveBoardDraft());
  }

  Future<void> _initMapCenterByLocation({bool fillFromIfEmpty = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          final fallback = _currentCityPointFromOptions();
          setState(
            () {
              if (fallback != null) {
                _mapCenter = fallback;
              }
              _statusText =
                  'Разрешите геолокацию или выберите точку подачи на карте.';
            },
          );
        }
        return;
      }

      Position? pos;
      BrowserLocation? browserPos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          pos = last;
        } else {
          browserPos = await getBrowserLocation();
          if (browserPos == null) rethrow;
        }
      }

      final point = pos != null
          ? LatLng(pos.latitude, pos.longitude)
          : LatLng(browserPos!.latitude, browserPos.longitude);
      final accuracy = pos?.accuracy ?? browserPos?.accuracy ?? 9999;
      final isPrecise = _isPrecisePassengerAccuracy(accuracy);
      if (!mounted) return;

      setState(() {
        if (isPrecise) {
          _userLocation = point;
          _mapCenter = point;
        }
      });

      if (!isPrecise) {
        setState(
          () => _statusText =
              'Браузер вернул неточное местоположение (${_locationAccuracyText(accuracy)}). Выберите точку на карте или введите адрес вручную.',
        );
        return;
      }

      _moveMap(point, 16.5);
      await _syncSearchCityFromCoords(point);

      if (fillFromIfEmpty && _fromLocation == null) {
        _fromLocation = point;
        await _fillAddressByCoords(isFrom: true, point: point);
        await _saveBoardDraft();
        _scheduleAutoBoard();
      }
    } catch (e) {
      if (mounted) {
        final fallback = _currentCityPointFromOptions();
        setState(() {
          if (fallback != null) {
            _mapCenter = fallback;
          }
          _statusText =
              'Не удалось определить GPS. Введите адрес или выберите точку на карте.';
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveMap(LatLng point, double zoom) {
    _mapCenter = point;
  }

  bool _isPrecisePassengerAccuracy(double accuracy) {
    return accuracy.isFinite &&
        accuracy > 0 &&
        accuracy <= _maxAutofillLocationAccuracyMeters;
  }

  String _locationAccuracyText(double accuracy) {
    if (!accuracy.isFinite || accuracy <= 0) return 'неизвестная точность';
    if (accuracy >= 1000) return '${(accuracy / 1000).toStringAsFixed(1)} км';
    return '${accuracy.round()} м';
  }

  LatLng _initialMapPickerCenter({required bool isFrom}) {
    if (isFrom) {
      return _fromLocation ?? _userLocation ?? _mapCenter;
    }
    return _toLocation ?? _fromLocation ?? _userLocation ?? _mapCenter;
  }

  Future<void> _showMapPointPicker({required bool isFrom}) async {
    LatLng selected = _initialMapPickerCenter(isFrom: isFrom);
    final pickerMapController = MapController();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) {
          final theme = Theme.of(context);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: IntercityMapFallback(),
                            ),
                            FlutterMap(
                              mapController: pickerMapController,
                              options: MapOptions(
                                initialCenter: selected,
                                initialZoom: 16.5,
                                onTap: (_, point) {
                                  setDialogState(() => selected = point);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: AppConstants.osmTileUrl,
                                  subdomains: AppConstants.mapTileSubdomains,
                                  userAgentPackageName:
                                      'com.milanium.intercity',
                                ),
                                if (_userLocation != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _userLocation!,
                                        width: 24,
                                        height: 24,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: selected,
                                      width: 54,
                                      height: 54,
                                      child: Icon(
                                        isFrom
                                            ? Icons.radio_button_checked
                                            : Icons.location_on,
                                        color: isFrom
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        size: isFrom ? 32 : 42,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: _surfaceCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isFrom
                                          ? 'Укажите точку отправления'
                                          : 'Укажите точку назначения',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Нажмите на карту и подтвердите выбор.',
                                      style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 14,
                        top: 104,
                        child: _mapActionButton(
                          icon: _locating ? null : Icons.my_location_rounded,
                          onTap: _locating
                              ? null
                              : () async {
                                  await _initMapCenterByLocation(
                                    fillFromIfEmpty: false,
                                  );
                                  final next = _userLocation ?? selected;
                                  setDialogState(() => selected = next);
                                  try {
                                    pickerMapController.move(next, 16.5);
                                  } catch (_) {}
                                },
                          child: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: SizedBox(
                          height: 56,
                          child: _premiumOrderButton(
                            label: 'Далее',
                            icon: Icons.check_rounded,
                            onPressed: () async {
                              await _applyMapPoint(
                                isFrom: isFrom,
                                point: selected,
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _applyMapPoint({
    required bool isFrom,
    required LatLng point,
  }) async {
    setState(() {
      if (isFrom) {
        _fromLocation = point;
        _fromSuggestions = const [];
      } else {
        _toLocation = point;
        _toSuggestions = const [];
      }
      _mapCenter = point;
    });
    await _fillAddressByCoords(isFrom: isFrom, point: point);
    await _saveBoardDraft();
    _scheduleAutoBoard();
    _scheduleIntercityReadyTripsSearch();
    if (!isFrom &&
        _requestType() == requestTypeIntercity &&
        _fromLocation != null &&
        _toLocation != null) {
      await _board();
      if (mounted) _goOrderBoard('intercity_options');
    }
  }

  Future<void> _fillAddressByCoords({
    required bool isFrom,
    required LatLng point,
  }) async {
    try {
      final res = await ApiClient().get(
        '/geo/reverse',
        queryParameters: {'lat': point.latitude, 'lng': point.longitude},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final compactAddress = _resolvedAddressFromReverseData(
        data,
        isFrom: isFrom,
      );
      if (!mounted) return;
      setState(() {
        if (isFrom) {
          _fromAddress = compactAddress;
          _rideCurrency = rideCurrencyCode(data);
          if (!_paymentMethodEnabled(_paymentMethod)) {
            _paymentMethod = paymentMethodCash;
          }
          _setAddressFieldValue(isFrom: true, value: compactAddress);
        } else {
          _toAddress = compactAddress;
          _setAddressFieldValue(isFrom: false, value: compactAddress);
        }
      });
      unawaited(_saveBoardDraft());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isFrom) {
          _fromAddress = 'Точка подачи выбрана';
          _setAddressFieldValue(isFrom: true, value: _fromAddress);
        } else {
          _toAddress = 'Точка назначения выбрана';
          _setAddressFieldValue(isFrom: false, value: _toAddress);
        }
      });
      unawaited(_saveBoardDraft());
    }
  }

  String _resolvedAddressFromReverseData(
    Map<String, dynamic> data, {
    required bool isFrom,
  }) {
    final rawAddress = (data['address'] ?? '').toString().trim();
    final compactAddress = _compactAddress(rawAddress);
    if (compactAddress.isNotEmpty &&
        compactAddress.toLowerCase() != 'адрес не определен' &&
        !_looksLikeCoordinates(compactAddress)) {
      return compactAddress;
    }

    final city = (data['city'] ?? '').toString().trim();
    if (city.isNotEmpty && city.toLowerCase() != 'unknown') {
      return city;
    }

    return isFrom ? 'Точка подачи выбрана' : 'Точка назначения выбрана';
  }

  bool _looksLikeCoordinates(String value) {
    return RegExp(
      r'^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$',
    ).hasMatch(value.trim());
  }

  void _setAddressFieldValue({required bool isFrom, required String value}) {
    if (isFrom) {
      _lastFromInputValue = value.trim();
      _suppressFromAddressChange = true;
      try {
        _fromController.text = value;
      } finally {
        _suppressFromAddressChange = false;
      }
      return;
    }

    _lastToInputValue = value.trim();
    _suppressToAddressChange = true;
    try {
      _toController.text = value;
    } finally {
      _suppressToAddressChange = false;
    }
  }

  void _onAddressChanged(String value, {required bool isFrom}) {
    if (isFrom ? _suppressFromAddressChange : _suppressToAddressChange) {
      return;
    }
    final normalizedValue = value.trim();
    final pendingStaleQueryEcho =
        isFrom ? _fromPendingStaleQueryEcho : _toPendingStaleQueryEcho;
    final confirmedAddress = isFrom ? _fromAddress : _toAddress;
    final hasConfirmedLocation =
        isFrom ? _fromLocation != null : _toLocation != null;
    if (shouldRestoreConfirmedAddressAfterStaleSearchEcho(
      changedValue: normalizedValue,
      pendingQueryEcho: pendingStaleQueryEcho,
      confirmedAddress: confirmedAddress,
      hasConfirmedLocation: hasConfirmedLocation,
    )) {
      if (isFrom) {
        _fromPendingStaleQueryEcho = null;
      } else {
        _toPendingStaleQueryEcho = null;
      }
      _setAddressFieldValue(isFrom: isFrom, value: confirmedAddress);
      return;
    }
    if (pendingStaleQueryEcho != null &&
        normalizedValue != pendingStaleQueryEcho.trim()) {
      if (isFrom) {
        _fromPendingStaleQueryEcho = null;
      } else {
        _toPendingStaleQueryEcho = null;
      }
    }
    final explicitSearchInProgress =
        isFrom ? _fromExplicitSearchInProgress : _toExplicitSearchInProgress;
    final explicitSearchGuardUntil =
        isFrom ? _fromExplicitSearchGuardUntil : _toExplicitSearchGuardUntil;
    if (shouldIgnoreTransientAddressChangeDuringExplicitSearch(
      explicitSearchInProgress: explicitSearchInProgress,
      now: DateTime.now(),
      guardUntil: explicitSearchGuardUntil,
    )) {
      if (isFrom) {
        _lastFromInputValue = normalizedValue;
      } else {
        _lastToInputValue = normalizedValue;
      }
      return;
    }
    final lastValue = isFrom ? _lastFromInputValue : _lastToInputValue;
    if (normalizedValue == lastValue) {
      return;
    }
    if (isFrom) {
      _lastFromInputValue = normalizedValue;
    } else {
      _lastToInputValue = normalizedValue;
    }
    final timer = isFrom ? _fromSearchDebounce : _toSearchDebounce;
    timer?.cancel();

    _resetBoardState(isFrom: isFrom);

    if (normalizedValue.length < 3) {
      return;
    }

    final newTimer = Timer(const Duration(milliseconds: 500), () {
      _loadAddressSuggestions(normalizedValue, isFrom: isFrom);
    });
    if (isFrom) {
      _fromSearchDebounce = newTimer;
    } else {
      _toSearchDebounce = newTimer;
    }
    _scheduleIntercityReadyTripsSearch();
  }

  Future<void> _loadAddressSuggestions(
    String query, {
    required bool isFrom,
  }) async {
    final requestId =
        isFrom ? ++_fromSuggestionRequestId : ++_toSuggestionRequestId;
    if (mounted) {
      setState(() {
        if (isFrom) {
          _fromAddressSearching = true;
        } else {
          _toAddressSearching = true;
        }
      });
    }
    try {
      final isIntercity = _requestType() == requestTypeIntercity;
      final anchor = isIntercity
          ? _intercitySearchCityPoint(isFrom: isFrom)
          : await _ensureSearchAnchor(isFrom: isFrom);
      final filtered = await _searchAddresses(
        query,
        anchor: anchor,
        cityIdOverride: _intercitySearchCityId(isFrom: isFrom),
        allowGlobalFallback:
            !isIntercity || !_hasIntercitySearchCity(isFrom: isFrom),
      );
      if (!mounted) return;
      final currentText =
          (isFrom ? _fromController.text : _toController.text).trim();
      final latestRequestId =
          isFrom ? _fromSuggestionRequestId : _toSuggestionRequestId;
      if (currentText != query || latestRequestId != requestId) return;
      setState(() {
        if (isFrom) {
          _fromSuggestions = filtered;
        } else {
          _toSuggestions = filtered;
        }
        if (filtered.isEmpty) {
          final city = _requestType() == requestTypeIntercity
              ? _intercityCityName(isFrom: isFrom)
              : '';
          _statusText = city.isEmpty
              ? 'Адрес не найден. Уточните запрос или выберите точку на карте.'
              : 'Адрес в городе $city не найден. Уточните улицу/дом или выберите точку на карте.';
        } else {
          _statusText = '';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusText =
            'Не удалось выполнить поиск адреса. Нажмите «Найти» или выберите точку на карте.';
      });
    } finally {
      if (mounted) {
        setState(() {
          if (isFrom) {
            _fromAddressSearching = false;
          } else {
            _toAddressSearching = false;
          }
        });
      }
    }
  }

  LatLng? _searchAnchor({required bool isFrom}) {
    if (_shouldRestrictSearchToCurrentCity) {
      final currentAnchor = _userLocation ?? _currentCityPointFromOptions();
      if (currentAnchor != null) return currentAnchor;
    }
    final explicitAnchor = isFrom
        ? (_fromLocation ?? _userLocation)
        : (_userLocation ?? _fromLocation);
    if (explicitAnchor != null) return explicitAnchor;
    if (_shouldRestrictSearchToCurrentCity) {
      return _currentCityPointFromOptions();
    }
    return null;
  }

  LatLng? _currentCityPointFromOptions() {
    final currentCityId = _currentCityId;
    if (currentCityId == null) return null;
    final city = _cityOptions.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id']?.toString() == currentCityId,
          orElse: () => null,
        );
    final lat = city?['lat'];
    final lng = city?['lng'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<LatLng?> _ensureSearchAnchor({required bool isFrom}) async {
    if (_mode() == 'INTERCITY') {
      return null;
    }
    if (_shouldRestrictSearchToCurrentCity &&
        _currentCityId == null &&
        _cityOptions.isEmpty &&
        !_cityOptionsLoading) {
      await _loadCityOptions();
    }
    final existingAnchor = _searchAnchor(isFrom: isFrom);
    if (existingAnchor != null) {
      return existingAnchor;
    }
    if (_userLocation == null) {
      await _initMapCenterByLocation();
    }
    return _searchAnchor(isFrom: isFrom);
  }

  String? _intercitySearchCityId({required bool isFrom}) {
    if (_requestType() != requestTypeIntercity) return null;
    final cityId = isFrom ? _intercityFromCityId : _intercityToCityId;
    final normalized = cityId?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  LatLng? _intercitySearchCityPoint({required bool isFrom}) {
    if (_requestType() != requestTypeIntercity) return null;
    return isFrom ? _intercityFromCityPoint : _intercityToCityPoint;
  }

  bool _hasIntercitySearchCity({required bool isFrom}) {
    if (_requestType() != requestTypeIntercity) return true;
    final addressText =
        (isFrom ? _fromController.text : _toController.text).trim();
    final location = isFrom ? _fromLocation : _toLocation;
    if (location != null && addressText.length >= 2) return true;
    return _intercitySearchCityId(isFrom: isFrom) != null ||
        _intercityCityName(isFrom: isFrom).isNotEmpty ||
        _intercitySearchCityPoint(isFrom: isFrom) != null;
  }

  String _intercityCityName({required bool isFrom}) {
    final directName =
        (isFrom ? _intercityFromCityName : _intercityToCityName).trim();
    if (directName.isNotEmpty) return directName;
    final cityId = _intercitySearchCityId(isFrom: isFrom);
    if (cityId == null) return '';
    final city = _cityOptions.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id']?.toString() == cityId,
          orElse: () => null,
        );
    return (city?['name'] ?? '').toString().trim();
  }

  Map<String, dynamic> _buildGeoSearchParams(
    String query, {
    LatLng? anchor,
    String? cityIdOverride,
  }) {
    final params = <String, dynamic>{'q': query};
    if (anchor != null) {
      params['lat'] = anchor.latitude;
      params['lng'] = anchor.longitude;
    }
    final cityId = cityIdOverride ??
        (_shouldRestrictSearchToCurrentCity ? _currentCityId : null);
    if (cityId != null && cityId.trim().isNotEmpty) {
      params['cityId'] = cityId.trim();
    }
    return params;
  }

  bool get _shouldRestrictSearchToCurrentCity {
    return _mode() == 'CITY' ||
        (_mode() == 'DELIVERY' && _deliveryModeIndex == 0);
  }

  Future<List<Map<String, dynamic>>> _searchAddresses(
    String query, {
    required LatLng? anchor,
    String? cityIdOverride,
    bool allowGlobalFallback = true,
  }) async {
    if (_shouldRestrictSearchToCurrentCity &&
        _currentCityId == null &&
        anchor != null) {
      await _syncSearchCityFromCoords(anchor);
    }

    if (anchor == null) {
      return _fetchAddressSearchResults(
        query,
        anchor: null,
        cityIdOverride: cityIdOverride,
      );
    }

    var localFailed = false;
    List<Map<String, dynamic>> anchored;
    try {
      anchored = await _fetchAddressSearchResults(
        query,
        anchor: anchor,
        cityIdOverride: cityIdOverride,
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      localFailed = true;
      anchored = const [];
    }

    if (!localFailed &&
        !_shouldRestrictSearchToCurrentCity &&
        shouldUseNearestAnchoredAddressResult(query: query, local: anchored)) {
      return [anchored.first];
    }

    if (!shouldFallbackToGlobalAddressSearch(
      localFailed: localFailed,
      query: query,
      local: anchored,
      allowGlobalFallback: allowGlobalFallback &&
          cityIdOverride == null &&
          !_shouldRestrictSearchToCurrentCity,
    )) {
      return anchored;
    }

    final global = await _fetchAddressSearchResults(
      query,
      anchor: null,
      cityIdOverride: cityIdOverride ?? '',
    );
    final combined = _shouldPreferGlobalResults(query) || localFailed
        ? [...global, ...anchored]
        : [...anchored, ...global];
    return _dedupeAddressResults(combined);
  }

  Future<List<Map<String, dynamic>>> _fetchAddressSearchResults(
    String query, {
    required LatLng? anchor,
    String? cityIdOverride,
  }) async {
    try {
      final res = await _api.get(
        '/geo/search',
        queryParameters: _buildGeoSearchParams(
          query,
          anchor: anchor,
          cityIdOverride: cityIdOverride,
        ),
      );
      final results = _filterSuggestionsByRadius(
        List<dynamic>.from(res.data as List),
        anchor: anchor,
      );
      if (results.isNotEmpty) return results;
    } catch (_) {}
    return _fetchOsmAddressSearchResults(query, anchor: anchor);
  }

  Future<List<Map<String, dynamic>>> _fetchOsmAddressSearchResults(
    String query, {
    required LatLng? anchor,
  }) async {
    final normalized = query.trim();
    if (normalized.length < 3) return const [];
    try {
      final params = <String, dynamic>{
        'q': normalized,
        'format': 'jsonv2',
        'addressdetails': 1,
        'limit': 8,
        'countrycodes': 'kz',
        'accept-language': 'ru',
      };
      if (anchor != null) {
        params['lat'] = anchor.latitude;
        params['lon'] = anchor.longitude;
        final radiusKm = _maxSuggestionRadiusMeters() / 1000;
        final latDelta = radiusKm / 111;
        final lngDelta = radiusKm / (111 * _safeCosLatitude(anchor.latitude));
        params['viewbox'] =
            '${anchor.longitude - lngDelta},${anchor.latitude + latDelta},'
            '${anchor.longitude + lngDelta},${anchor.latitude - latDelta}';
        params['bounded'] = 1;
      }
      final res = await Dio().get<dynamic>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: params,
        options: Options(headers: const {'Accept': 'application/json'}),
      );
      final raw = res.data is List ? List<dynamic>.from(res.data as List) : [];
      final parsed = raw
          .whereType<Map>()
          .map((item) {
            final lat = double.tryParse((item['lat'] ?? '').toString());
            final lng = double.tryParse((item['lon'] ?? '').toString());
            if (lat == null || lng == null) return null;
            return <String, dynamic>{
              'displayName': (item['display_name'] ?? '').toString(),
              'lat': lat,
              'lng': lng,
              'source': 'osm',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
      return _filterSuggestionsByRadius(parsed, anchor: anchor);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _searchCitiesOnMap(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final localFallback = _localCitySearchResults(normalized);
    try {
      final res = await _api.post(
        '/geo/search',
        data: {'q': normalized, 'type': 'city'},
      );
      final parsed = List<dynamic>.from(res.data as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['lat'] is num && item['lng'] is num)
          .toList();
      return _dedupeCityResults([...parsed, ...localFallback])
          .take(12)
          .toList();
    } catch (_) {
      return localFallback;
    }
  }

  List<Map<String, dynamic>> _localCitySearchResults(String query) {
    final normalized = query.trim().toLowerCase().replaceAll('ё', 'е');
    if (normalized.length < 2) return const [];
    final matches = _cityOptions.where((city) {
      final name = (city['name'] ?? '').toString().toLowerCase().replaceAll(
            'ё',
            'е',
          );
      final region = (city['region'] ?? '').toString().toLowerCase().replaceAll(
            'ё',
            'е',
          );
      return name.contains(normalized) || region.contains(normalized);
    }).map((city) {
      final name = (city['name'] ?? '').toString().trim();
      final region = (city['region'] ?? '').toString().trim();
      return <String, dynamic>{
        ...city,
        'displayName':
            [name, region].where((part) => part.trim().isNotEmpty).join(', '),
      };
    }).toList();
    matches.sort((a, b) {
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      final aStarts = aName.startsWith(normalized);
      final bStarts = bName.startsWith(normalized);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aName.compareTo(bName);
    });
    return matches.take(12).toList();
  }

  List<Map<String, dynamic>> _dedupeCityResults(
    List<Map<String, dynamic>> items,
  ) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final item in items) {
      final key = [
        (item['name'] ?? '').toString().trim().toLowerCase(),
        (item['region'] ?? '').toString().trim().toLowerCase(),
        (item['displayName'] ?? '').toString().trim().toLowerCase(),
      ].where((part) => part.isNotEmpty).join('|');
      if (key.isEmpty || !seen.add(key)) continue;
      unique.add(item);
      if (unique.length >= 12) break;
    }
    return unique;
  }

  LatLng? _pointFromGeoItem(Map<String, dynamic> item) {
    if (item['lat'] is! num || item['lng'] is! num) return null;
    return LatLng(
      (item['lat'] as num).toDouble(),
      (item['lng'] as num).toDouble(),
    );
  }

  String _cityTitleFromGeo(Map<String, dynamic> item) {
    final raw = (item['displayName'] ?? item['name'] ?? '').toString().trim();
    if (raw.isEmpty) return 'Город';
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return raw;
    final first = parts.first;
    final second = parts.length > 1 ? parts[1] : '';
    if (second.isEmpty ||
        RegExp(r'^\d').hasMatch(second) ||
        second.toLowerCase().contains('улиц')) {
      return first;
    }
    return '$first, $second';
  }

  bool _shouldPreferGlobalResults(String query) {
    final normalized = query.trim().toLowerCase();
    return RegExp(r'\d').hasMatch(normalized) ||
        normalized.contains('улиц') ||
        normalized.contains('просп') ||
        normalized.contains('мкр') ||
        normalized.contains('микрорайон') ||
        normalized.contains('дом');
  }

  List<Map<String, dynamic>> _dedupeAddressResults(
    List<Map<String, dynamic>> items,
  ) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final item in items) {
      final key =
          '${item['lat']}:${item['lng']}:${(item['displayName'] ?? '').toString().trim()}';
      if (!seen.add(key)) continue;
      unique.add(item);
      if (unique.length >= 8) break;
    }
    return unique;
  }

  double _maxSuggestionRadiusMeters() {
    switch (_mode()) {
      case 'CITY':
        return 50000;
      case 'DELIVERY':
        return 70000;
      case 'INTERCITY':
        return 50000;
      default:
        return 50000;
    }
  }

  List<Map<String, dynamic>> _filterSuggestionsByRadius(
    List<dynamic> raw, {
    LatLng? anchor,
  }) {
    final parsed = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (!shouldApplyAddressSearchRadiusFilter(mode: _mode(), anchor: anchor)) {
      return parsed.take(8).toList();
    }
    final center = anchor;
    if (center == null) return parsed.take(8).toList();

    final withDistance = parsed
        .where((item) => item['lat'] is num && item['lng'] is num)
        .map((item) {
          final p = LatLng(
            (item['lat'] as num).toDouble(),
            (item['lng'] as num).toDouble(),
          );
          final meters = _distance.as(LengthUnit.Meter, center, p);
          return {'item': item, 'meters': meters};
        })
        .where((e) => (e['meters'] as double) <= _maxSuggestionRadiusMeters())
        .toList();

    if (withDistance.isEmpty) {
      return const [];
    }

    withDistance.sort(
      (a, b) => (a['meters'] as double).compareTo(b['meters'] as double),
    );
    return withDistance
        .take(5)
        .map((e) => Map<String, dynamic>.from(e['item'] as Map))
        .toList();
  }

  Future<void> _searchAndSetAddress({
    required bool isFrom,
    bool navigateAfterApply = true,
  }) async {
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(Duration.zero);
    final intercityCityId = _intercitySearchCityId(isFrom: isFrom);
    final isIntercity = _requestType() == requestTypeIntercity;
    final query = resolveExplicitAddressSearchQuery(
      controllerText: isFrom ? _fromController.text : _toController.text,
      lastInputValue: isFrom ? _lastFromInputValue : _lastToInputValue,
    );
    if (query.isEmpty) return;
    final debounce = isFrom ? _fromSearchDebounce : _toSearchDebounce;
    debounce?.cancel();
    final activeSearchGuardUntil = DateTime.now().add(
      const Duration(minutes: 1),
    );
    if (isFrom) {
      _fromSuggestionRequestId++;
      _fromExplicitSearchInProgress = true;
      _fromExplicitSearchGuardUntil = activeSearchGuardUntil;
    } else {
      _toSuggestionRequestId++;
      _toExplicitSearchInProgress = true;
      _toExplicitSearchGuardUntil = activeSearchGuardUntil;
    }
    setState(() => _loading = true);
    try {
      final anchor = isIntercity
          ? _intercitySearchCityPoint(isFrom: isFrom)
          : await _ensureSearchAnchor(isFrom: isFrom);
      final results = await _searchAddresses(
        query,
        anchor: anchor,
        cityIdOverride: intercityCityId,
        allowGlobalFallback:
            !isIntercity || !_hasIntercitySearchCity(isFrom: isFrom),
      );
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        final intercityCityName = _intercityCityName(isFrom: isFrom);
        final cityHint = intercityCityName.isNotEmpty
            ? ' в городе $intercityCityName'
            : (_shouldRestrictSearchToCurrentCity &&
                    _currentCityName.trim().isNotEmpty)
                ? ' в городе $_currentCityName'
                : '';
        setState(() {
          _statusText = _supportsManualAddress
              ? 'Адрес$cityHint не найден. Вы можете уточнить запрос, выбрать точку на карте или оставить текстовый адрес вручную. Водитель увидит, что геоточка не подтверждена.'
              : 'Адрес$cityHint не найден. Для расчёта стоимости нужно выбрать точку на карте или перейти в режим "Аукцион".';
        });
        return;
      }
      if (!shouldAutoApplyFirstAddressSearchResult(
        requiresConfirmedCoordinates: _requiresConfirmedCoordinates,
        results: results,
      )) {
        setState(() {
          if (isFrom) {
            _fromSuggestions = results;
          } else {
            _toSuggestions = results;
          }
          _statusText =
              'Найдено несколько адресов. Выберите нужный вариант из списка, чтобы подтвердить точку.';
        });
        return;
      }
      await _applySuggestion(results.first, isFrom: isFrom);
      if (isFrom) {
        _fromPendingStaleQueryEcho = query;
      } else {
        _toPendingStaleQueryEcho = query;
        if (navigateAfterApply &&
            _requestType() == requestTypeCityFixed &&
            _toLocation != null) {
          await _board();
          if (mounted) _goOrderBoard('routeprice');
        }
        if (navigateAfterApply &&
            _requestType() == requestTypeIntercity &&
            _fromLocation != null &&
            _toLocation != null) {
          await _board();
          if (mounted) _goOrderBoard('intercity_options');
        }
      }
    } catch (e) {
      setState(
        () => _statusText =
            'Не удалось найти адрес. Проверьте интернет или уточните запрос.',
      );
    } finally {
      final settledSearchGuardUntil = DateTime.now().add(
        const Duration(seconds: 2),
      );
      if (isFrom) {
        _fromExplicitSearchInProgress = false;
        _fromExplicitSearchGuardUntil = settledSearchGuardUntil;
      } else {
        _toExplicitSearchInProgress = false;
        _toExplicitSearchGuardUntil = settledSearchGuardUntil;
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _resolveIntercityDraftBeforeCreate() async {
    if (_fromLocation != null && _toLocation != null) {
      return true;
    }

    final fromQuery = _fromController.text.trim();
    final toQuery = _toController.text.trim();
    if (fromQuery.length < 2 || toQuery.length < 2) {
      setState(() {
        _statusText = _mode() == 'DELIVERY'
            ? 'Укажите адрес забора и адрес доставки.'
            : 'Укажите города или адреса "Откуда" и "Куда".';
      });
      return false;
    }

    final resolvedFrom = _fromLocation != null
        ? true
        : await _resolveIntercityAddressFromText(
            query: fromQuery,
            isFrom: true,
          );
    if (!mounted) return false;

    final resolvedTo = _toLocation != null
        ? true
        : await _resolveIntercityAddressFromText(query: toQuery, isFrom: false);
    if (!mounted) return false;

    if (!resolvedFrom || !resolvedTo) {
      if (_supportsManualAddress && _canCreateWithManualAddresses) {
        setState(() {
          _statusText =
              'Маршрут не подтверждён координатами. Заявка будет опубликована с ручными адресами.';
        });
        return true;
      }
      setState(() {
        _statusText =
            'Не удалось определить маршрут. Выберите адрес из поиска или укажите точки на карте.';
      });
      return false;
    }

    return (_fromLocation != null && _toLocation != null) ||
        (_supportsManualAddress && _canCreateWithManualAddresses);
  }

  Future<bool> _resolveIntercityAddressFromText({
    required String query,
    required bool isFrom,
  }) async {
    final cityId = _intercitySearchCityId(isFrom: isFrom);
    final results = await _searchAddresses(
      query,
      anchor: _intercitySearchCityPoint(isFrom: isFrom),
      cityIdOverride: cityId,
      allowGlobalFallback: !_hasIntercitySearchCity(isFrom: isFrom),
    );
    if (results.isEmpty) {
      return false;
    }

    await _applySuggestion(results.first, isFrom: isFrom);
    return isFrom ? _fromLocation != null : _toLocation != null;
  }

  Future<void> _applySuggestionAndContinue(
    Map<String, dynamic> item, {
    required bool isFrom,
  }) async {
    await _applySuggestion(item, isFrom: isFrom);
    if (!mounted || isFrom) return;

    if (_requestType() == requestTypeCityFixed && _toLocation != null) {
      await _board();
      if (mounted) _goOrderBoard('routeprice');
      return;
    }

    if (_requestType() == requestTypeIntercity &&
        _fromLocation != null &&
        _toLocation != null) {
      await _board();
      if (mounted) _goOrderBoard('intercity_options');
    }
  }

  Future<void> _applySuggestion(
    Map<String, dynamic> item, {
    required bool isFrom,
  }) async {
    final point = LatLng(
      (item['lat'] as num).toDouble(),
      (item['lng'] as num).toDouble(),
    );
    final displayName = (item['displayName'] ?? '').toString();
    final compactAddress = _compactAddress(displayName);
    setState(() {
      if (isFrom) {
        _fromLocation = point;
        _fromAddress = compactAddress;
        _setAddressFieldValue(isFrom: true, value: compactAddress);
        _fromSuggestions = const [];
      } else {
        _toLocation = point;
        _toAddress = compactAddress;
        _setAddressFieldValue(isFrom: false, value: compactAddress);
        _toSuggestions = const [];
      }
    });
    _moveMap(point, 16.5);
    await _saveBoardDraft();
    _scheduleAutoBoard();
    _scheduleIntercityReadyTripsSearch();
  }

  String _compactAddress(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where(
          (part) =>
              !RegExp(r'^\d{5,6}$').hasMatch(part) &&
              part.toLowerCase() != 'казахстан' &&
              !_isCurrentCityAddressPart(part),
        )
        .toList();

    if (parts.isEmpty) return value.trim();

    final useful = <String>[];
    for (final part in parts) {
      final lower = part.toLowerCase();
      final isRegionLike = lower.contains('облысы') ||
          lower.contains('область') ||
          lower.contains('район') ||
          lower.contains('к.ә.');
      if (isRegionLike && useful.isNotEmpty) {
        continue;
      }
      useful.add(part);
      if (_mode() == 'CITY' && useful.length >= 3) break;
      if (_mode() != 'CITY' && useful.length >= 4) break;
    }

    return useful.join(', ');
  }

  double _safeCosLatitude(double latitude) {
    final cos = math.cos(latitude * math.pi / 180).abs();
    return cos < 0.25 ? 0.25 : cos;
  }

  bool _isCurrentCityAddressPart(String part) {
    final lower = part.trim().toLowerCase();
    final current = _currentCityName.trim().toLowerCase();
    if (current.isNotEmpty && lower == current) return true;
    const knownCities = {
      'алматы',
      'астана',
      'шымкент',
      'караганда',
      'актобе',
      'тараз',
      'павлодар',
      'усть-каменогорск',
      'семей',
      'костанай',
      'кызылорда',
      'атырау',
      'актау',
      'уральск',
      'петропавловск',
      'туркестан',
      'кокшетау',
      'талдыкорган',
    };
    return knownCities.contains(lower);
  }

  void _scheduleAutoBoard() {
    _boardDebounce?.cancel();
    if (_fromLocation == null || _toLocation == null) return;
    _boardDebounce = Timer(const Duration(milliseconds: 700), _board);
  }

  Map<String, dynamic> _buildBoardPayload({
    required LatLng from,
    required LatLng to,
    required String mode,
  }) {
    return <String, dynamic>{
      'fromLat': from.latitude,
      'fromLng': from.longitude,
      'toLat': to.latitude,
      'toLng': to.longitude,
      'mode': mode,
      'requestType': _requestType(),
      'paymentMethod': _paymentMethod,
      'vehicleClass': _supportsVehicleClass ? _vehicleClass : null,
    };
  }

  String _locationSource({required bool isFrom}) {
    final location = isFrom ? _fromLocation : _toLocation;
    return location == null ? 'MANUAL' : 'GEOCODED';
  }

  String _locationText({required bool isFrom}) {
    final explicit = (isFrom ? _fromAddress : _toAddress).trim();
    if (explicit.isNotEmpty) return explicit;
    final fallback =
        (isFrom ? _fromController.text : _toController.text).trim();
    return fallback;
  }

  String _joinCityAndAddress(String city, String address) {
    final normalizedCity = city.trim();
    final normalizedAddress = address.trim();
    if (normalizedCity.isEmpty) return normalizedAddress;
    if (normalizedAddress.isEmpty) return normalizedCity;
    if (normalizedAddress.toLowerCase().contains(
          normalizedCity.toLowerCase(),
        )) {
      return normalizedAddress;
    }
    return '$normalizedCity, $normalizedAddress';
  }

  String? _marketRequestComment() {
    final userComment = _commentController.text.trim();
    if (_requestType() != requestTypeIntercity) {
      return userComment.isEmpty ? null : userComment;
    }

    final options = <String>[
      'Багаж: $_intercityBaggage чемодан(а)',
      'Животные: $_intercityPets',
      'Детские кресла: $_intercityChildSeats',
      'Курение: ${_intercitySmokingAllowed ? 'можно' : 'не курить'}',
    ];
    if (userComment.isNotEmpty) {
      options.add('Комментарий: $userComment');
    }
    return options.join('; ');
  }

  Map<String, dynamic> _buildMarketRequestPayload() {
    final effectiveType = _effectiveCreateRequestType();
    final isIntercity = effectiveType == requestTypeIntercity;
    final fromCity = isIntercity ? _intercityCityName(isFrom: true) : '';
    final toCity = isIntercity ? _intercityCityName(isFrom: false) : '';
    final fromText = isIntercity
        ? _joinCityAndAddress(fromCity, _locationText(isFrom: true))
        : _locationText(isFrom: true);
    final toText = isIntercity
        ? _joinCityAndAddress(toCity, _locationText(isFrom: false))
        : _locationText(isFrom: false);
    return <String, dynamic>{
      'requestType': effectiveType,
      'fromCity': isIntercity && fromCity.isNotEmpty ? fromCity : fromText,
      'toCity': isIntercity && toCity.isNotEmpty ? toCity : toText,
      'fromAddressLabel': _fromLocation != null ? fromText : null,
      'toAddressLabel': _toLocation != null ? toText : null,
      'fromManualAddress': _fromLocation == null ? fromText : null,
      'toManualAddress': _toLocation == null ? toText : null,
      'fromLat': _fromLocation?.latitude,
      'fromLng': _fromLocation?.longitude,
      'toLat': _toLocation?.latitude,
      'toLng': _toLocation?.longitude,
      'fromAddressSource': _locationSource(isFrom: true),
      'toAddressSource': _locationSource(isFrom: false),
      'paymentMethod': _paymentMethod,
      'comment': _marketRequestComment(),
      'date': _intercityTripDate.toUtc().toIso8601String(),
      'hasUnconfirmedLocation': _fromLocation == null || _toLocation == null,
      if (effectiveType == requestTypeIntercity) ...{
        'seats': _intercityWholeCabin ? 4 : _intercitySeats,
        'price': 0,
      },
      if (_mode() == 'DELIVERY') ...{
        'itemDescription': _deliveryItemController.text.trim(),
        'itemWeightKg': double.tryParse(_deliveryWeightController.text.trim()),
        'itemDimensions': _deliveryDimensionsController.text.trim().isEmpty
            ? null
            : _deliveryDimensionsController.text.trim(),
        'recipientContact': _deliveryRecipientController.text.trim().isEmpty
            ? null
            : _deliveryRecipientController.text.trim(),
      },
    };
  }

  bool _validateBeforeCreate() {
    if (_requestType() == requestTypeCityFixed) {
      if ((_fromLocation == null ||
              _toLocation == null ||
              _boardPrice == null) &&
          _hasManualAddressPair) {
        _statusText =
            'Точные точки не подтверждены. Заказ будет опубликован как городской аукцион, водитель увидит ручные адреса.';
        return true;
      }
      if (_fromLocation == null || _toLocation == null) {
        _statusText = 'Заполните адреса или выберите обе точки на карте.';
        return false;
      }
      if (_boardPrice == null) {
        _statusText = 'Не удалось рассчитать стоимость по маршруту.';
        return false;
      }
      return true;
    }

    if (_mode() == 'DELIVERY' && _deliveryItemController.text.trim().isEmpty) {
      _statusText = 'Для доставки нужно указать описание груза.';
      return false;
    }

    if (_requestType() == requestTypeIntercity &&
        (!_hasIntercitySearchCity(isFrom: true) ||
            !_hasIntercitySearchCity(isFrom: false))) {
      _statusText =
          'Сначала выберите города "Откуда" и "Куда", потом точные адреса.';
      return false;
    }

    if (_fromController.text.trim().length < 2 ||
        _toController.text.trim().length < 2) {
      _statusText = 'Заполните адреса "Откуда" и "Куда".';
      return false;
    }
    return true;
  }

  Future<void> _board() async {
    if (_fromLocation == null || _toLocation == null) return;
    final boardId = ++_boardRequestId;
    final fromSnapshot = _fromLocation!;
    final toSnapshot = _toLocation!;
    final modeSnapshot = _mode();
    final requestTypeSnapshot = _requestType();
    final paymentMethodSnapshot = _paymentMethod;
    setState(() => _loading = true);
    try {
      if (!_supportsSystemPrice) {
        final route = _distance.as(
          LengthUnit.Kilometer,
          fromSnapshot,
          toSnapshot,
        );
        if (!mounted) return;
        if (_boardRequestId != boardId ||
            _fromLocation != fromSnapshot ||
            _toLocation != toSnapshot ||
            _requestType() != requestTypeSnapshot ||
            _paymentMethod != paymentMethodSnapshot) {
          return;
        }
        final marketDateText = _formatIntercityDate(_intercityTripDate);
        setState(() {
          _boardDistance = route;
          _boardDuration = null;
          _boardPrice = null;
          if (requestTypeSnapshot == requestTypeIntercity) {
            _statusText = _intercityWholeCabin
                ? 'Маршрут подтверждён на $marketDateText. Весь салон выбран. После публикации заявки начнётся аукцион предложений от водителей.'
                : 'Маршрут подтверждён на $marketDateText. Вы выбрали $_intercitySeats мест(а). После публикации заявки начнётся аукцион предложений от водителей.';
          } else if (requestTypeSnapshot == requestTypeCityAuction) {
            _statusText =
                'Маршрут подтверждён. Это городской аукцион: цену предложат водители.';
          } else {
            _statusText =
                'Маршрут доставки подтверждён на $marketDateText. После публикации заявки исполнители увидят способ оплаты и предложат условия.';
          }
        });
        await _saveBoardDraft();
        return;
      }

      final res = await _api.post(
        '/orders/preview',
        data: _buildBoardPayload(
          from: fromSnapshot,
          to: toSnapshot,
          mode: modeSnapshot,
        ),
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      if (_boardRequestId != boardId ||
          _fromLocation != fromSnapshot ||
          _toLocation != toSnapshot ||
          _mode() != modeSnapshot ||
          _paymentMethod != paymentMethodSnapshot ||
          _requestType() != requestTypeSnapshot) {
        return;
      }
      setState(() {
        _boardDistance = (data['distance'] as num?)?.toDouble();
        _boardDuration = (data['duration'] as num?)?.toInt();
        _boardPrice = _roundRidePrice((data['price'] as num?)?.toDouble());
        _rideCurrency = rideCurrencyCode(data);
        if (!_paymentMethodEnabled(_paymentMethod)) {
          _paymentMethod = paymentMethodCash;
        }
        _statusText = _boardPrice != null
            ? 'Стоимость рассчитана автоматически.'
            : 'Не удалось рассчитать стоимость.';
      });
      await _saveBoardDraft();
    } catch (e) {
      if (!mounted) return;
      if (_boardRequestId != boardId) return;
      setState(() {
        _boardPrice = null;
        _boardDistance = null;
        _boardDuration = null;
        _statusText =
            'Не удалось рассчитать маршрут. Выберите адрес из подсказок или укажите точку на карте.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _roundRidePrice(double? value) {
    if (value == null || !value.isFinite || value <= 0) return null;
    const step = 50.0;
    return ((value / step).ceil() * step).toDouble();
  }

  Future<void> _create() async {
    setState(() => _loading = true);
    try {
      if (!_validateBeforeCreate()) return;
      if (_isMarketRequest) {
        final resolved = await _resolveIntercityDraftBeforeCreate();
        if (!mounted) return;
        if (!resolved) {
          return;
        }
        final response = await _api.post(
          '/intercity/requests',
          data: _buildMarketRequestPayload(),
        );
        if (!mounted) return;
        final requestId = (response.data['id'] ?? '').toString();
        final tripDateText = _formatIntercityDate(_intercityTripDate);
        setState(() {
          final effectiveType = _effectiveCreateRequestType();
          _statusText = effectiveType == requestTypeIntercity
              ? 'Заявка опубликована на $tripDateText. Ожидайте предложения от водителей.'
              : effectiveType == requestTypeCityAuction
                  ? 'Городской аукцион опубликован. Ожидайте предложения водителей.'
                  : 'Заявка на доставку опубликована. Ожидайте предложения исполнителей.';
        });
        if (!mounted) return;
        _clearRoute();
        context.go('/market/request/$requestId');
      } else {
        if (_fromLocation == null || _toLocation == null) return;
        final response = await _api.post(
          '/orders',
          data: <String, dynamic>{
            'fromLat': _fromLocation!.latitude,
            'fromLng': _fromLocation!.longitude,
            'fromAddress': _fromAddress,
            'toLat': _toLocation!.latitude,
            'toLng': _toLocation!.longitude,
            'toAddress': _toAddress,
            'mode': _mode(),
            'requestType': _requestType(),
            'paymentMethod': _paymentMethod,
            'vehicleClass': _vehicleClass,
            'comment': _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          },
        );
        final orderId = (response.data['id'] ?? '').toString();
        if (!mounted) return;
        _clearRoute();
        context.go('/order/searching/$orderId');
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _statusText =
            'Не удалось отправить заказ. Проверьте адреса, оплату и попробуйте ещё раз.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
