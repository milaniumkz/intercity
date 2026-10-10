import '../../../core/services/payment_fallback_notifier.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/push_notifications_service.dart';
import '../../../core/services/sse_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/intercity_map_fallback.dart';
import '../../../core/widgets/road_route_layer.dart';
import '../../shared/widgets/order_chat_sheet.dart';
import '../widgets/driver_rating_dialog.dart';
import '../widgets/passenger_bottom_nav.dart';

typedef OrderRealtimeConnector = Future<SseConnection?> Function(
  String path, {
  Map<String, dynamic>? queryParameters,
});

class OrderSearchingPage extends StatefulWidget {
  const OrderSearchingPage({
    super.key,
    required this.orderId,
    this.apiClient,
    this.realtimeConnector = SseService.connect,
    this.pollingInterval = const Duration(seconds: 3),
    this.enableLiveMap = true,
    this.mapTileProvider,
  });

  final String orderId;
  final ApiClient? apiClient;
  final OrderRealtimeConnector realtimeConnector;
  final Duration pollingInterval;
  final bool enableLiveMap;
  final TileProvider? mapTileProvider;

  @override
  State<OrderSearchingPage> createState() => _OrderSearchingPageState();
}

class _OrderSearchingPageState extends State<OrderSearchingPage> {
  final _paymentNotifier = PaymentFallbackNotifier();
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  Map<String, dynamic>? _order;
  String _message = 'Ищем водителя рядом с точкой подачи...';
  bool _loading = true;
  bool _refreshing = false;
  bool _cancelling = false;
  Timer? _pollTimer;
  Timer? _offerTickTimer;
  SseConnection? _orderSse;
  StreamSubscription<Map<String, dynamic>>? _orderSseSub;
  DateTime? _lastSseRefreshAt;
  LatLng? _fromPoint;
  LatLng? _toPoint;
  LatLng? _driverPoint;
  bool _ratingDialogOpen = false;
  bool _completionRedirecting = false;
  String? _lastNotifiedStatus;
  bool _offerActionBusy = false;
  double? _pickupEtaMinutes;
  late final _roadRoutes = RoadRouteRepository(_api);

  bool get _isScreenBoardPreview => (widget.orderId == 'board' ||
      widget.orderId.startsWith('board') ||
      Uri.base.fragment.contains('/order/searching/board'));

  bool get _isActiveTripBoard => (widget.orderId == 'active' ||
      widget.orderId.startsWith('active') ||
      Uri.base.fragment.contains('/order/searching/active'));

  bool get _useBoardDesign => true;

  @override
  void initState() {
    super.initState();
    if (_isScreenBoardPreview || _isActiveTripBoard) {
      _loading = false;
      _message = _isActiveTripBoard
          ? 'Водитель везёт вас по маршруту'
          : 'Обычно это занимает до 1 минуты';
      _fromPoint = const LatLng(43.2635, 76.9458);
      _toPoint = const LatLng(43.3521, 77.0405);
      _driverPoint = const LatLng(43.2850, 76.9200);
      return;
    }
    _offerTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_order?['offers'] as List? ?? []).isNotEmpty) {
        setState(() {});
      }
    });
    _loadOrder();
    _startPollingFallback();
    unawaited(_connectOrderStream());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _offerTickTimer?.cancel();
    _orderSseSub?.cancel();
    _orderSse?.close();
    _mapController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  bool _increasingPrice = false;
  Future<void> _increaseAuctionPrice() async {
    if (_increasingPrice) return;
    setState(() => _increasingPrice = true);
    try {
      await _api.post('/orders/${widget.orderId}/increase-price');
      await _loadOrder();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessageRu(e))));
      }
    } finally {
      if (mounted) setState(() => _increasingPrice = false);
    }
  }

  Widget _auctionPriceIncreaseButton() => _premiumActionButton(
      label:
          'Цена ${_order?['price'] ?? ''} ${rideCurrencySymbol(_order ?? {})} · +100',
      icon: Icons.add_rounded,
      filled: true,
      onPressed: _increasingPrice ? null : _increaseAuctionPrice);

  Future<void> _cancelOrder() async {
    final order = _order;
    if (order == null || _cancelling) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withValues(alpha: 0.15),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Отменить заказ?',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Поиск водителя будет остановлен, после этого можно будет создать новый заказ.',
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _premiumActionButton(
                            label: 'Нет',
                            icon: Icons.arrow_back_rounded,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _premiumActionButton(
                            label: 'Да, отменить',
                            icon: Icons.close_rounded,
                            filled: true,
                            danger: true,
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _cancelling = true);
    try {
      await _api.post('/orders/${widget.orderId}/cancel');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заказ отменён. Можно создать новый.')),
      );
      context.go('/order?reset=${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageRu(e))));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _connectOrderStream() async {
    _orderSseSub?.cancel();
    await _orderSse?.close();
    final conn = await widget.realtimeConnector(
      '/realtime/orders/${widget.orderId}/stream',
    );
    if (!mounted) {
      await conn?.close();
      return;
    }
    if (conn == null) {
      _startPollingFallback();
      return;
    }
    _orderSse = conn;
    _orderSseSub = conn.stream.listen(
      (event) async {
        final eventType = (event['event'] ?? '').toString();
        if (eventType != 'order-event') return;
        final now = DateTime.now();
        final last = _lastSseRefreshAt;
        if (last != null && now.difference(last).inMilliseconds < 700) return;
        _lastSseRefreshAt = now;
        await _loadOrder();
      },
      onError: (_, __) {
        unawaited(_activatePollingFallback());
      },
      onDone: () {
        unawaited(_activatePollingFallback());
      },
    );
  }

  Future<void> _loadOrder() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final res = await _api.get('/orders/${widget.orderId}');
      final order = Map<String, dynamic>.from(res.data as Map);
      final status = _effectiveStatus(
        order,
        (order['status'] ?? '').toString(),
      );
      if (status == 'CANCELLED') {
        if (!mounted) return;
        _stopPollingFallback();
        context.go('/order?reset=${Uri.encodeComponent(widget.orderId)}');
        return;
      }
      // A late response must not overwrite cancellation being processed locally.
      if (_cancelling) return;
      final previousStatus = _lastNotifiedStatus;
      final points = _extractPoints(order);

      if (!mounted) return;
      unawaited(_paymentNotifier.notify(context, order, 'PASSENGER'));
      setState(() {
        _order = order;
        _loading = false;
        _message = _statusRu(status);
        _fromPoint = points.$1;
        _toPoint = points.$2;
        _driverPoint = points.$3;
      });

      _notifyPassengerStatusIfNeeded(order, status, previousStatus);

      if (_statusStep(status) < 1 || _statusStep(status) > 4) _fitMap();

      if (_isFinal(status)) {
        _stopPollingFallback();
        await _closeOrderStream();
        await _promptDriverRatingIfNeeded(order);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = errorMessageRu(e);
      });
    } finally {
      _refreshing = false;
    }
  }

  void _startPollingFallback() {
    if (_pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(widget.pollingInterval, (_) => _loadOrder());
  }

  void _stopPollingFallback() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _activatePollingFallback() async {
    await _closeOrderStream();
    if (!mounted) return;
    final status = (_order?['status'] ?? '').toString();
    if (_isFinal(status)) return;
    _startPollingFallback();
  }

  Future<void> _closeOrderStream() async {
    await _orderSseSub?.cancel();
    await _orderSse?.close();
    _orderSseSub = null;
    _orderSse = null;
  }

  Future<void> _promptDriverRatingIfNeeded(Map<String, dynamic> order) async {
    final status = (order['status'] ?? '').toString().toUpperCase();
    if (status != 'COMPLETED' || _ratingDialogOpen) return;
    if (order['driverRating'] != null || order['driverId'] == null) {
      _goToOrderComposer();
      return;
    }
    final orderId = (order['id'] ?? '').toString();
    if (orderId.isEmpty) return;

    final driverProfile = order['driver'] is Map
        ? Map<String, dynamic>.from(order['driver'] as Map)
        : null;
    final driverUser = driverProfile?['user'] is Map
        ? Map<String, dynamic>.from(driverProfile!['user'] as Map)
        : null;

    _ratingDialogOpen = true;
    try {
      final submitted = await showDriverRatingDialog(
        context: context,
        driverName: driverUser?['name']?.toString(),
        onSubmit: (_) async {},
        onSubmitWithReason: (rating, reason) async {
          try {
            await _api.post('/orders/$orderId/rate',
                data: {'rating': rating, 'reason': reason});
          } catch (error) {
            throw Exception(errorMessageRu(error));
          }
        },
      );
      if (!mounted || !submitted) return;
      _goToOrderComposer();
    } finally {
      _ratingDialogOpen = false;
    }
  }

  void _goToOrderComposer() {
    if (!mounted || _completionRedirecting) return;
    _completionRedirecting = true;
    context.go('/order?reset=${DateTime.now().millisecondsSinceEpoch}');
  }

  (LatLng?, LatLng?, LatLng?) _extractPoints(Map<String, dynamic> order) {
    LatLng? from;
    LatLng? to;
    LatLng? driver;

    final fromLat = order['fromLat'];
    final fromLng = order['fromLng'];
    final toLat = order['toLat'];
    final toLng = order['toLng'];
    if (fromLat is num && fromLng is num) {
      from = LatLng(fromLat.toDouble(), fromLng.toDouble());
    }
    if (toLat is num && toLng is num) {
      to = LatLng(toLat.toDouble(), toLng.toDouble());
    }

    final driverProfile = order['driver'];
    if (driverProfile is Map && driverProfile['online'] is Map) {
      final online = Map<String, dynamic>.from(driverProfile['online'] as Map);
      final dLat = online['lastLat'];
      final dLng = online['lastLng'];
      if (dLat is num && dLng is num) {
        driver = LatLng(dLat.toDouble(), dLng.toDouble());
      }
    }

    return (from, to, driver);
  }

  bool _isFinal(String status) {
    final s = status.toUpperCase();
    return s == 'COMPLETED' || s == 'CANCELLED';
  }

  int _offerSecondsRemaining(Map<String, dynamic> offer) {
    final until = DateTime.tryParse('${offer['expiresAt'] ?? ''}');
    if (until == null) return 30;
    return (until.difference(DateTime.now()).inMilliseconds / 1000)
        .ceil()
        .clamp(0, 30);
  }

  List<Map<String, dynamic>> _pendingOrderOffers(Map<String, dynamic>? order) {
    final offers = order?['offers'];
    if (offers is! List) return const [];
    return offers
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where(
          (offer) =>
              (offer['status'] ?? '').toString().toUpperCase() == 'PENDING' &&
              _offerSecondsRemaining(offer) > 0,
        )
        .toList()
      ..sort((a, b) {
        final ap = (a['price'] as num?)?.toDouble() ?? double.infinity;
        final bp = (b['price'] as num?)?.toDouble() ?? double.infinity;
        return ap.compareTo(bp);
      });
  }

  Future<void> _acceptOrderOffer(Map<String, dynamic> offer) async {
    final id = (offer['id'] ?? '').toString();
    if (id.isEmpty || _offerActionBusy) return;
    setState(() => _offerActionBusy = true);
    try {
      await _api.post('/orders/offers/$id/accept');
      await _loadOrder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageRu(e))));
    } finally {
      if (mounted) setState(() => _offerActionBusy = false);
    }
  }

  Future<void> _rejectOrderOffer(Map<String, dynamic> offer) async {
    final id = (offer['id'] ?? '').toString();
    if (id.isEmpty || _offerActionBusy) return;
    setState(() => _offerActionBusy = true);
    try {
      await _api.post('/orders/offers/$id/reject');
      await _loadOrder();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessageRu(e))));
    } finally {
      if (mounted) setState(() => _offerActionBusy = false);
    }
  }

  bool _hasAssignedDriver(Map<String, dynamic>? order) {
    if (order == null) return false;
    final driverId = order['driverId']?.toString().trim();
    return (driverId != null && driverId.isNotEmpty) || order['driver'] is Map;
  }

  String _effectiveStatus(Map<String, dynamic>? order, String status) {
    final s = status.toUpperCase();
    if (_hasAssignedDriver(order) &&
        (s.isEmpty ||
            s == 'CREATED' ||
            s == 'SEARCHING_DRIVER' ||
            s == 'ACCEPTED')) {
      return 'DRIVER_ASSIGNED';
    }
    if (s == 'ACCEPTED') return 'DRIVER_ASSIGNED';
    return s;
  }

  String _statusRu(String status) {
    switch (status.toUpperCase()) {
      case 'CREATED':
        return 'Заказ создан. Начинаем поиск водителя...';
      case 'SEARCHING_DRIVER':
        return 'Ищем ближайшего водителя...';
      case 'DRIVER_ASSIGNED':
        return 'Водитель назначен.';
      case 'DRIVER_EN_ROUTE':
        return 'Водитель едет к вам.';
      case 'DRIVER_ARRIVED':
        return 'Водитель прибыл к точке подачи.';
      case 'IN_PROGRESS':
        return 'Поездка началась.';
      case 'COMPLETED':
        return 'Поездка завершена.';
      case 'CANCELLED':
        return 'Заказ отменен.';
      default:
        return 'Обновляем статус заказа...';
    }
  }

  void _notifyPassengerStatusIfNeeded(
    Map<String, dynamic> order,
    String status,
    String? previousStatus,
  ) {
    final normalized = status.toUpperCase();
    if (previousStatus == normalized) return;
    _lastNotifiedStatus = normalized;
    if (previousStatus == null &&
        (normalized == 'CREATED' || normalized == 'SEARCHING_DRIVER')) {
      return;
    }

    final notice = _passengerStatusNotice(order, normalized);
    if (notice == null) return;
    unawaited(_playStatusMelody());
    unawaited(
      PushNotificationsService.instance.showOrderStatusNotification(
        orderId: (order['id'] ?? widget.orderId).toString(),
        title: notice.$1,
        body: notice.$2,
        notificationId: Object.hash(widget.orderId, normalized),
      ),
    );
  }

  (String, String)? _passengerStatusNotice(
    Map<String, dynamic> order,
    String status,
  ) {
    final driver = order['driver'] is Map
        ? Map<String, dynamic>.from(order['driver'] as Map)
        : null;
    final user = driver?['user'] is Map
        ? Map<String, dynamic>.from(driver!['user'] as Map)
        : null;
    final name = (user?['name'] ?? 'Водитель').toString();
    switch (status) {
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
        return ('Водитель назначен', '$name принял заказ и едет к вам.');
      case 'DRIVER_ARRIVED':
        return ('Водитель приехал', '$name уже на месте подачи.');
      case 'IN_PROGRESS':
        return ('Поездка началась', 'Хорошей поездки.');
      default:
        return null;
    }
  }

  Future<void> _playStatusMelody() async {
    for (var i = 0; i < 3; i++) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
  }

  int _statusStep(String status) {
    switch (status.toUpperCase()) {
      case 'SEARCHING_DRIVER':
      case 'CREATED':
        return 0;
      case 'DRIVER_ASSIGNED':
        return 1;
      case 'DRIVER_EN_ROUTE':
        return 2;
      case 'DRIVER_ARRIVED':
        return 3;
      case 'IN_PROGRESS':
        return 4;
      case 'COMPLETED':
        return 5;
      default:
        return 0;
    }
  }

  EdgeInsets get _orderMapPadding {
    final count = _pendingOrderOffers(_order).length;
    if (count == 0) return const EdgeInsets.fromLTRB(36, 76, 36, 36);
    final height =
        math.min(MediaQuery.sizeOf(context).height * .45, count * 200.0 + 66);
    return EdgeInsets.fromLTRB(36, height + 28, 36, 100);
  }

  Future<void> _fitMap() async {
    List<LatLng>? roadPoints;
    if (_statusStep('${_order?['status'] ?? ''}') == 0 &&
        _fromPoint != null &&
        _toPoint != null) {
      try {
        roadPoints = await _roadRoutes.route(_fromPoint!, _toPoint!);
      } catch (_) {}
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final step = _statusStep((_order?['status'] ?? '').toString());
      final points = <LatLng>[
        if (step >= 4 && _driverPoint != null)
          _driverPoint!
        else if (_fromPoint != null)
          _fromPoint!,
        if (step >= 1 && step <= 3 && _driverPoint != null)
          _driverPoint!
        else if (_toPoint != null)
          _toPoint!,
      ];
      if (points.isEmpty) return;
      try {
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(
              step == 0 ? (roadPoints ?? points) : points),
          padding: _orderMapPadding,
          maxZoom: 16,
        ));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isActiveTripBoard) {
      return _boardActiveTripScreen();
    }

    final order = _order;
    final driverProfile = order?['driver'] is Map
        ? Map<String, dynamic>.from(order!['driver'] as Map)
        : null;
    final driverUser = driverProfile?['user'] is Map
        ? Map<String, dynamic>.from(driverProfile!['user'] as Map)
        : null;
    final status = (order?['status'] ?? '').toString();
    final displayStatus = _effectiveStatus(order, status);
    final step = _statusStep(displayStatus);
    final isFinalOrder = _isFinal(displayStatus);
    final hasActiveOrder = order != null && !isFinalOrder;
    final accent = _statusAccent(displayStatus);
    final canCancelOrder = hasActiveOrder &&
        displayStatus.toUpperCase() != 'COMPLETED' &&
        displayStatus.toUpperCase() != 'CANCELLED';
    final pendingOffers = _pendingOrderOffers(order);
    final showAuctionOffers = pendingOffers.isNotEmpty && !isFinalOrder;

    if (_useBoardDesign) {
      if (order != null && _statusStep(displayStatus) >= 1) {
        return _boardActiveTripScreen();
      }
      return _boardSearchingScreen();
    }

    if (hasActiveOrder && !showAuctionOffers) {
      if (_statusStep(displayStatus) >= 1) {
        return _boardActiveTripScreen();
      }
      return _boardSearchingScreen();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      resizeToAvoidBottomInset: !showAuctionOffers,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mapLayer(step)),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.34),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0, 0.30, 1],
                    ),
                  ),
                ),
              ),
            ),
            if (!showAuctionOffers) ...[
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkSurface.withValues(alpha: 0.78)
                              : Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppTheme.secondaryColor.withValues(
                              alpha: 0.20,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? const Color(0x33000000)
                                  : AppTheme.primaryColor.withValues(
                                      alpha: 0.10,
                                    ),
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
                                children: [
                                  Text(
                                    hasActiveOrder
                                        ? _statusShort(displayStatus)
                                        : 'Поиск водителя',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _statusRu(displayStatus),
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
                    _roundActionButton(
                      icon: hasActiveOrder
                          ? Icons.refresh_rounded
                          : Icons.arrow_back_rounded,
                      onTap: hasActiveOrder
                          ? _loadOrder
                          : () => goBackOr(context, fallback: '/order'),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: 0.46,
                  minChildSize: 0.16,
                  maxChildSize: 0.88,
                  snap: true,
                  snapSizes: const [0.16, 0.46, 0.88],
                  builder: (context, scrollController) => Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0B0817)
                          : const Color(0xFFFEFCFF),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(34),
                      ),
                      border: Border.all(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.22),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 28,
                          offset: Offset(0, -8),
                        ),
                      ],
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryColor.withValues(
                                alpha: 0.42,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_loading)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: const LinearProgressIndicator(minHeight: 4),
                          ),
                        _statusHero(
                          step: step,
                          cancelled: status.toUpperCase() == 'CANCELLED',
                          accent: accent,
                        ),
                        const SizedBox(height: 12),
                        _glassHint(
                          icon: _statusIcon(displayStatus),
                          text: _message,
                          accent: accent,
                        ),
                        const SizedBox(height: 12),
                        if (order != null) _orderSummaryCard(order),
                        if (order != null) const SizedBox(height: 12),
                        if (order != null) _routeCard(order),
                        if (driverUser != null) const SizedBox(height: 12),
                        if (driverUser != null)
                          _driverCard(driverUser, driverProfile),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _premiumActionButton(
                                label: hasActiveOrder
                                    ? 'Обновить заказ'
                                    : 'Обновить статус',
                                icon: Icons.refresh_rounded,
                                filled: !canCancelOrder,
                                onPressed: _loadOrder,
                              ),
                            ),
                            if (!hasActiveOrder) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: _premiumActionButton(
                                  label: 'Мои заказы',
                                  icon: Icons.receipt_long_rounded,
                                  filled: true,
                                  onPressed: () =>
                                      context.push('/orders-history'),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_order?['requestType'] == 'CITY_AUCTION' &&
                            canCancelOrder) ...[
                          const SizedBox(height: 10),
                          _auctionPriceIncreaseButton(),
                        ],
                        if (canCancelOrder) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: _premiumActionButton(
                              label: _cancelling
                                  ? 'Отменяем заказ...'
                                  : 'Отменить заказ',
                              icon: Icons.close_rounded,
                              danger: true,
                              onPressed: _cancelling ? null : _cancelOrder,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              if (canCancelOrder)
                Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _auctionPriceIncreaseButton(),
                      const SizedBox(height: 8),
                      _premiumActionButton(
                          label: 'Отменить заказ',
                          icon: Icons.close_rounded,
                          danger: true,
                          onPressed: _cancelling ? null : _cancelOrder),
                    ])),
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: _auctionOffersOverlay(pendingOffers),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardSearchingScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final order = _order;
    final offers = _pendingOrderOffers(order);
    final showOffers = offers.isNotEmpty;
    final from = order == null
        ? 'Адрес подачи не указан'
        : _compactAddress((order['fromAddress'] ?? '-').toString());
    final to = order == null
        ? 'Адрес назначения не указан'
        : _compactAddress((order['toAddress'] ?? '-').toString());
    final canCancel = order != null &&
        !_isFinal(_effectiveStatus(order, (order['status'] ?? '').toString()));
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mapLayer(2)),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: showOffers
                          ? [
                              Colors.black.withValues(alpha: .08),
                              Colors.transparent,
                              Colors.black.withValues(alpha: .20)
                            ]
                          : isDark
                              ? [
                                  const Color(0xFF080612)
                                      .withValues(alpha: 0.10),
                                  const Color(0xFF080612)
                                      .withValues(alpha: 0.36),
                                  const Color(0xFF080612)
                                      .withValues(alpha: 0.96),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.10),
                                  Colors.white.withValues(alpha: 0.24),
                                  Colors.white.withValues(alpha: 0.96),
                                ],
                    ),
                  ),
                ),
              ),
            ),
            if (showOffers)
              Positioned(
                  top: 12,
                  left: 14,
                  right: 14,
                  child: _auctionOffersOverlay(offers)),
            if (!showOffers)
              Positioned(
                top: 12,
                left: 16,
                child: _roundActionButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => goBackOr(context, fallback: '/order'),
                ),
              ),
            if (showOffers && canCancel)
              Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _auctionPriceIncreaseButton(),
                    const SizedBox(height: 8),
                    _premiumActionButton(
                        label: 'Отменить заказ',
                        icon: Icons.close_rounded,
                        danger: true,
                        onPressed: _cancelling ? null : _cancelOrder),
                  ])),
            if (!showOffers)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF11101D) : Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.16),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x302C174C),
                        blurRadius: 30,
                        offset: Offset(0, 14),
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
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 4,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppTheme.primaryColor,
                              ),
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
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _boardRouteLine(from, to),
                      const SizedBox(height: 16),
                      if (_order?['requestType'] == 'CITY_AUCTION' &&
                          canCancel) ...[
                        _auctionPriceIncreaseButton(),
                        const SizedBox(height: 10),
                      ],
                      _premiumActionButton(
                        label: 'Отменить заказ',
                        icon: Icons.close_rounded,
                        onPressed: canCancel
                            ? _cancelOrder
                            : () => context.go('/order'),
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

  Widget _boardRouteLine(String from, String to) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.12 : 0.36,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          _boardRoutePoint('Откуда', from, Icons.trip_origin_rounded),
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 3, bottom: 3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 18,
                color: AppTheme.primaryColor.withValues(alpha: 0.24),
              ),
            ),
          ),
          _boardRoutePoint('Куда', to, Icons.location_on_rounded),
          if ((_order?['price'] as num? ?? 0) > 0) ...[
            const SizedBox(height: 12),
            Text(
              _formatPrice(_order?['price']),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ],
      ),
    );
  }

  Widget _boardRoutePoint(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
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

  Widget _boardActiveTripScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final order = _order;
    final status =
        _effectiveStatus(order, (order?['status'] ?? 'IN_PROGRESS').toString());
    final step = _statusStep(status);
    final driverProfile = order?['driver'] is Map
        ? Map<String, dynamic>.from(order!['driver'] as Map)
        : null;
    final driverUser = driverProfile?['user'] is Map
        ? Map<String, dynamic>.from(driverProfile!['user'] as Map)
        : null;
    final driverName =
        (driverUser?['name'] ?? 'Водитель не назначен').toString();
    final phone = (driverUser?['phone'] ?? '').toString();
    final car =
        (driverProfile?['carModel'] ?? 'Автомобиль не указан').toString();
    final carNumber = (driverProfile?['carNumber'] ?? '').toString();
    final rawRating = driverProfile?['rating'] ?? driverUser?['rating'];
    final average = rawRating is Map
        ? rawRating['ratingAvg'] ?? rawRating['average']
        : rawRating;
    final hasRatings = rawRating is! Map ||
        !rawRating.containsKey('ratingCount') ||
        (rawRating['ratingCount'] is num && rawRating['ratingCount'] > 0);
    final ratingNumber = !hasRatings
        ? null
        : average is num
            ? average.toDouble()
            : double.tryParse('$average');
    final rating = ratingNumber != null && ratingNumber.isFinite
        ? ratingNumber.clamp(0, 5).toStringAsFixed(2)
        : '—';
    final eta = order == null ? '3 мин' : _arrivalText(order);
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 0),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
                child: Stack(children: [
              Positioned.fill(child: _mapLayer(step)),
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    _roundActionButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => goBackOr(context, fallback: '/order'),
                    ),
                    Expanded(
                      child: Text(
                        _statusShort(status),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(width: 46),
                  ],
                ),
              ),
              if (step == 1 || step == 2)
                Positioned(
                  right: 16,
                  top: 76,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF11101D) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x242C174C),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Прибытие',
                          style:
                              TextStyle(fontSize: 11, color: Color(0xFF7C7590)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          eta,
                          key: const ValueKey('passenger-arrival-estimate'),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ])),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                key: const ValueKey('passenger-active-driver-card'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF11101D) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.14),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x302C174C),
                      blurRadius: 30,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
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
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                driverName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$car\n$carNumber',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
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
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              rating,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _driverAction(
                            icon: Icons.phone_rounded,
                            label: 'Позвонить',
                            onTap: () => _callPhone(phone),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _driverAction(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Чат',
                            onTap: () => _openOrderChat('Чат с водителем'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _driverAction(
                          icon: Icons.ios_share_rounded,
                          label: 'Поделиться',
                          filled: true,
                          onTap: _copyTripShareLink,
                        )),
                      ],
                    ),
                    if (order != null &&
                        !_isFinal((order['status'] ?? '').toString())) ...[
                      const SizedBox(height: 10),
                      _premiumActionButton(
                        label: _cancelling
                            ? 'Отменяем заказ...'
                            : 'Отменить заказ',
                        icon: Icons.close_rounded,
                        onPressed: _cancelling ? null : _cancelOrder,
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

  Future<void> _copyTripShareLink() async {
    final link = 'https://intercity.app/trip/${widget.orderId}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ссылка на поездку скопирована')),
    );
  }

  Widget _mapLayer(int step) {
    if (!widget.enableLiveMap) {
      return const SizedBox.expand();
    }
    if (_fromPoint == null) return const IntercityMapFallback();
    return Stack(
      children: [
        const Positioned.fill(child: IntercityMapFallback()),
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _fromPoint ?? const LatLng(43.2220, 76.8512),
            initialZoom: 14,
            onMapReady: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _fitMap();
              });
            },
          ),
          children: [
            _PassengerMapTiles(tileProvider: widget.mapTileProvider),
            const MapDataAttribution(),
            if (_fromPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _fromPoint!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 36,
                    ),
                  ),
                ],
              ),
            if (_toPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _toPoint!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.flag_circle,
                      color: Colors.red,
                      size: 30,
                    ),
                  ),
                ],
              ),
            if (_driverPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _driverPoint!,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            if (_driverPoint != null && _fromPoint != null && step <= 3)
              RoadRouteLayer(
                  from: _driverPoint!,
                  to: _fromPoint!,
                  strokeWidth: 4,
                  color: Colors.orange,
                  repository: _roadRoutes,
                  fitPadding: _orderMapPadding,
                  onDurationResolved: (minutes) {
                    if (!mounted) return;
                    setState(() => _pickupEtaMinutes = minutes);
                  }),
            if (_fromPoint != null &&
                _toPoint != null &&
                (step >= 4 || _driverPoint == null))
              RoadRouteLayer(
                  from: step >= 4 ? (_driverPoint ?? _fromPoint!) : _fromPoint!,
                  to: _toPoint!,
                  strokeWidth: 4,
                  color: AppTheme.primaryColor,
                  repository: _roadRoutes,
                  fitPadding: _orderMapPadding),
          ],
        ),
      ],
    );
  }

  Widget _roundActionButton({
    required IconData icon,
    required VoidCallback onTap,
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
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _surfaceCard({required Widget child, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.primaryColor.withValues(alpha: 0.10),
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

  Widget _premiumActionButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool filled = false,
    bool danger = false,
  }) {
    final enabled = onPressed != null;
    final color = danger ? Colors.redAccent : AppTheme.primaryColor;
    final borderRadius = BorderRadius.circular(18);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: borderRadius,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: filled && !danger
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: filled && danger ? Colors.redAccent : null,
              border: filled
                  ? null
                  : Border.all(color: color.withValues(alpha: 0.32)),
              boxShadow: filled && enabled
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: filled ? Colors.white : color),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: filled ? Colors.white : color,
                      fontWeight: FontWeight.w800,
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

  Widget _glassHint({
    required IconData icon,
    required String text,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = accent ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: isDark ? 0.18 : 0.42,
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

  Widget _statusHero({
    required int step,
    required bool cancelled,
    required Color accent,
  }) {
    final rawStatus = _effectiveStatus(
      _order,
      (_order?['status'] ?? '').toString(),
    );
    final searching = rawStatus == 'CREATED' || rawStatus == 'SEARCHING_DRIVER';
    final title = cancelled ? 'Заказ отменён' : _statusShort(rawStatus);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppTheme.deepViolet.withValues(alpha: 0.96),
            AppTheme.primaryColor.withValues(alpha: 0.86),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                child: searching
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      )
                    : Icon(
                        cancelled
                            ? Icons.close_rounded
                            : _statusIcon(rawStatus),
                        color: accent,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cancelled
                          ? 'История заказа сохранена.'
                          : searching
                              ? 'Обычно это занимает около 1 минуты'
                              : 'Водитель уже назначен на заказ',
                      style: const TextStyle(
                        color: Colors.white70,
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cancelled
                        ? 'Можно создать новый заказ на главном экране.'
                        : searching
                            ? 'Мы подберём водителя и покажем движение на карте.'
                            : 'Статус поездки обновляется автоматически.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _statusTimeline(step, cancelled),
        ],
      ),
    );
  }

  Widget _orderSummaryCard(Map<String, dynamic> order) {
    return _surfaceCard(
      child: Row(
        children: [
          Expanded(
            child: _metricTile(
              'Статус',
              _statusShort((order['status'] ?? '').toString()),
              icon: Icons.timeline_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              'Цена',
              _formatPrice(order['price']),
              icon: Icons.payments_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _metricTile(
              'Расстояние',
              _distanceText(order),
              icon: Icons.route_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, {IconData? icon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : AppTheme.lightBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.08 : 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppTheme.primaryColor),
            const SizedBox(height: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color:
                  isDark ? Colors.white54 : theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeCard(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Поездка в пути',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.04)
                  : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                _addressRow(
                  title: 'Откуда',
                  value: _compactAddress(
                    (order['fromAddress'] ?? '-').toString(),
                  ),
                  accent: AppTheme.primaryColor,
                  icon: Icons.trip_origin,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                _addressRow(
                  title: 'Куда',
                  value: _compactAddress(
                    (order['toAddress'] ?? '-').toString(),
                  ),
                  accent: AppTheme.secondaryColor,
                  icon: Icons.location_on_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricTile(
                  'К прибытию',
                  _arrivalText(order),
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricTile(
                  'Осталось',
                  _distanceText(order),
                  icon: Icons.near_me_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addressRow({
    required String title,
    required String value,
    required Color accent,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark
                      ? Colors.white54
                      : theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _driverCard(
    Map<String, dynamic> driverUser,
    Map<String, dynamic>? driverProfile,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = (driverUser['name'] ?? 'Водитель').toString();
    final phone = (driverUser['phone'] ?? '-').toString();
    final car = (driverProfile?['carModel'] ?? '-').toString();
    final carNumber = (driverProfile?['carNumber'] ?? '-').toString();
    final rating =
        (driverProfile?['rating'] ?? driverUser['rating'] ?? '4.9').toString();
    return _surfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(
                colors: [Color(0xFF271044), Color(0xFF100B1F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.30),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ваш водитель',
                        style: TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  rating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : const Color(0xFFF8F6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.secondaryColor.withValues(alpha: 0.20),
                          AppTheme.primaryColor.withValues(alpha: 0.10),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.local_taxi_rounded,
                      color: AppTheme.primaryColor,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _driverSpec(
                          label: 'Автомобиль',
                          value: car,
                          icon: Icons.directions_car_filled_rounded,
                        ),
                        const SizedBox(height: 10),
                        _driverSpec(
                          label: 'Госномер',
                          value: carNumber,
                          icon: Icons.pin_rounded,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _driverAction(
                    icon: Icons.phone_rounded,
                    label: 'Позвонить',
                    onTap: () => _callPhone(phone),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _driverAction(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Чат',
                    onTap: () => _openOrderChat('Чат с водителем'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _driverAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Маршрут',
                    filled: true,
                    onTap: _copyTripShareLink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _auctionOffersOverlay(List<Map<String, dynamic>> offers) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visibleHeight = (offers.length.clamp(1, 6) * 200.0) + 66;
    final maxHeight = math.min(screenHeight * 0.45, visibleHeight);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(190, 690)),
      child: Container(
        key: const ValueKey('passenger-top-auction-offers'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF261044), Color(0xFF100B1F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.42),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xAA000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Предложения водителей',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        offers.length == 1
                            ? 'Выберите водителя для поездки'
                            : '${offers.length} предложений · прокрутите для выбора',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: offers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) => _auctionOfferTile(offers[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _auctionOfferTile(Map<String, dynamic> offer) {
    final driver = offer['driver'] is Map
        ? Map<String, dynamic>.from(offer['driver'] as Map)
        : <String, dynamic>{};
    final user = driver['user'] is Map
        ? Map<String, dynamic>.from(driver['user'] as Map)
        : <String, dynamic>{};
    final rating = driver['rating'] is Map
        ? Map<String, dynamic>.from(driver['rating'] as Map)
        : <String, dynamic>{};
    final name = (user['name'] ?? 'Водитель').toString();
    final car = (driver['carModel'] ?? 'Авто не указано').toString();
    final carNumber = (driver['carNumber'] ?? '').toString();
    final ratingText =
        ((rating['ratingAvg'] as num?)?.toDouble() ?? 5.0).toStringAsFixed(1);
    final price = (offer['price'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(children: [
            const CircleAvatar(
                radius: 20, child: Icon(Icons.local_taxi_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(car,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text('$carNumber · ★ $ratingText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ])),
            const SizedBox(width: 8),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 105),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                        '${price.toStringAsFixed(0)} ${rideCurrencySymbol(_order)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.timer_outlined, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text('Ответьте за ${_offerSecondsRemaining(offer)} сек.',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
              value: _offerSecondsRemaining(offer) / 30,
              minHeight: 3,
              color: AppTheme.primaryColor,
              backgroundColor: Colors.white12),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _premiumActionButton(
                  label: 'Отклонить',
                  icon: Icons.close_rounded,
                  danger: true,
                  onPressed:
                      _offerActionBusy ? null : () => _rejectOrderOffer(offer),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _premiumActionButton(
                  label: 'Принять',
                  icon: Icons.check_rounded,
                  filled: true,
                  onPressed:
                      _offerActionBusy ? null : () => _acceptOrderOffer(offer),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showActionHint(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _callPhone(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (normalized.isEmpty || normalized == '-') {
      _showActionHint('Телефон водителя недоступен');
      return;
    }
    try {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: normalized),
        mode: LaunchMode.externalApplication,
      );
      if (opened) return;
    } catch (_) {
      // Browser builds may not support tel: links.
    }
    await Clipboard.setData(ClipboardData(text: normalized));
    _showActionHint('Не удалось открыть звонок. Номер скопирован: $normalized');
  }

  Future<void> _openOrderChat(String title) async {
    final order = _order;
    final orderId = (order?['id'] ?? '').toString();
    if (order == null || orderId.isEmpty) {
      _showActionHint('Чат доступен после создания заказа');
      return;
    }
    await showOrderChatSheet(
      context: context,
      orderId: orderId,
      orderStatus: _effectiveStatus(order, (order['status'] ?? '').toString()),
      title: title,
      currentRole: 'PASSENGER',
    );
  }

  Widget _driverAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final color = filled ? Colors.white : AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: filled
                ? const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  )
                : null,
            border: filled
                ? null
                : Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.22),
                  ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverSpec({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 18),
        const SizedBox(width: 8),
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _statusAccent(String status) {
    switch (status.toUpperCase()) {
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
      case 'DRIVER_ARRIVED':
        return Colors.greenAccent;
      case 'IN_PROGRESS':
        return AppTheme.secondaryColor;
      case 'COMPLETED':
        return Colors.greenAccent;
      case 'CANCELLED':
        return Colors.redAccent;
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'DRIVER_ASSIGNED':
        return Icons.person_pin_circle_outlined;
      case 'DRIVER_EN_ROUTE':
        return Icons.directions_car_filled_outlined;
      case 'DRIVER_ARRIVED':
        return Icons.notifications_active_outlined;
      case 'IN_PROGRESS':
        return Icons.route_rounded;
      case 'COMPLETED':
        return Icons.check_circle_outline_rounded;
      case 'CANCELLED':
        return Icons.error_outline_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  String _statusShort(String status) {
    switch (status.toUpperCase()) {
      case 'CREATED':
      case 'SEARCHING_DRIVER':
        return 'Ищем водителя';
      case 'DRIVER_ASSIGNED':
        return 'Водитель назначен';
      case 'DRIVER_EN_ROUTE':
        return 'Водитель едет';
      case 'DRIVER_ARRIVED':
        return 'Водитель на месте';
      case 'IN_PROGRESS':
        return 'Поездка началась';
      case 'COMPLETED':
        return 'Поездка завершена';
      case 'CANCELLED':
        return 'Заказ отменён';
      default:
        return 'Обновление статуса';
    }
  }

  String _formatPrice(dynamic value) {
    if (value is num) {
      return '${value.toStringAsFixed(0)} ${rideCurrencySymbol(_order)}';
    }
    return '-';
  }

  String _arrivalText(Map<String, dynamic> order) {
    final step = _statusStep((order['status'] ?? '').toString());
    if (step == 3) return 'На месте';
    if (step == 1 || step == 2) {
      if (_pickupEtaMinutes != null) {
        return '~ ${math.max(1, _pickupEtaMinutes!.ceil())} мин';
      }
      return _driverPoint == null ? 'Уточняем позицию' : 'Рассчитываем…';
    }
    return '—';
  }

  String _distanceText(Map<String, dynamic> order) {
    final km = _numValue(order, const ['distanceKm', 'routeDistanceKm']);
    if (km != null && km > 0) {
      return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} км';
    }

    final meters = _numValue(order, const ['distanceMeters', 'routeDistance']);
    if (meters != null && meters > 0) {
      final asKm = meters / 1000;
      return '${asKm.toStringAsFixed(asKm >= 10 ? 0 : 1)} км';
    }

    if (_fromPoint != null && _toPoint != null) {
      const distance = Distance();
      final calculated = distance.as(
        LengthUnit.Kilometer,
        _fromPoint!,
        _toPoint!,
      );
      return '${calculated.toStringAsFixed(calculated >= 10 ? 0 : 1)} км';
    }
    return '-';
  }

  double? _numValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  String _compactAddress(String value) {
    final parts = value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where(
          (part) =>
              !RegExp(r'^\d{5,6}$').hasMatch(part) &&
              part.toLowerCase() != 'казахстан',
        )
        .toList();

    if (parts.isEmpty) {
      return value.trim();
    }

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
      if (useful.length >= 3) break;
    }

    return useful.join(', ');
  }

  Widget _statusTimeline(int step, bool cancelled) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const labels = [
      'Поиск',
      'Назначен',
      'Едет',
      'Прибыл',
      'В пути',
      'Завершен',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cancelled)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: const Text(
              'Заказ отменен',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        if (!cancelled)
          Row(
            children: List.generate(labels.length, (i) {
              final active = i <= step;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (i > 0)
                          Expanded(
                            child: Container(
                              height: 3,
                              color: active
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.primaryColor
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (i < labels.length - 1)
                          Expanded(
                            child: Container(
                              height: 3,
                              color: (i < step)
                                  ? AppTheme.primaryColor
                                  : Colors.grey.shade300,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: active
                            ? theme.colorScheme.onSurface
                            : (isDark
                                ? Colors.white54
                                : theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
      ],
    );
  }
}

// Keep the tile layer stable while the proposal countdown updates each second.
class _PassengerMapTiles extends StatefulWidget {
  const _PassengerMapTiles({this.tileProvider});
  final TileProvider? tileProvider;
  @override
  State<_PassengerMapTiles> createState() => _PassengerMapTilesState();
}

class _PassengerMapTilesState extends State<_PassengerMapTiles> {
  late final tiles = TileLayer(
      tileProvider: widget.tileProvider ?? _PassengerRasterProvider(),
      urlTemplate: AppConstants.osmTileUrl,
      subdomains: AppConstants.mapTileSubdomains,
      userAgentPackageName: 'com.milanium.intercity');
  @override
  Widget build(BuildContext context) => tiles;
}

class _PassengerRasterProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      NetworkImage(getTileUrl(coordinates, options), headers: headers);
}
