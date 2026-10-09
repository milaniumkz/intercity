import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/location_display.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/request_flow_utils.dart';
import '../../../core/widgets/intercity_map_fallback.dart';
import '../../../core/widgets/road_route_layer.dart';
import '../../shared/widgets/order_chat_sheet.dart';
import '../widgets/passenger_bottom_nav.dart';

class IntercityRequestPage extends StatefulWidget {
  const IntercityRequestPage({
    super.key,
    required this.requestId,
    this.apiClient,
    this.pollingInterval = const Duration(seconds: 4),
    this.enableLiveMap = true,
  });

  final String requestId;
  final ApiClient? apiClient;
  final Duration pollingInterval;
  final bool enableLiveMap;

  @override
  State<IntercityRequestPage> createState() => _IntercityRequestPageState();
}

class _IntercityRequestPageState extends State<IntercityRequestPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  Map<String, dynamic>? _request;
  bool _loading = true;
  bool _actionBusy = false;
  String _message = 'Ищем отклики исполнителей на вашу заявку...';
  Timer? _pollTimer;
  LatLng? _fromPoint;
  LatLng? _toPoint;

  bool get _isActiveTripBoard => (widget.requestId == 'active' ||
      Uri.base.fragment.contains('/intercity/request/active'));

  @override
  void initState() {
    super.initState();
    if (_isActiveTripBoard) {
      _loading = false;
      _message = 'Поездка в пути';
      _fromPoint = const LatLng(43.2389, 76.8897);
      _toPoint = const LatLng(59.9343, 30.3351);
      return;
    }
    _loadRequest();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapController.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _loadRequest() async {
    try {
      final res = await _api.get('/intercity/requests/${widget.requestId}');
      final request = Map<String, dynamic>.from(res.data as Map);
      final fromLat = request['fromLat'];
      final fromLng = request['fromLng'];
      final toLat = request['toLat'];
      final toLng = request['toLng'];
      final offers = List<dynamic>.from(request['offers'] as List? ?? const []);

      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
        _fromPoint = fromLat is num && fromLng is num
            ? LatLng(fromLat.toDouble(), fromLng.toDouble())
            : null;
        _toPoint = toLat is num && toLng is num
            ? LatLng(toLat.toDouble(), toLng.toDouble())
            : null;
        _message = _statusMessage(
          request,
          (request['status'] ?? '').toString(),
          offers.length,
        );
      });
      _fitMap();
      if (_isFinalStatus((request['status'] ?? '').toString())) {
        _stopPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = errorMessageRu(e);
      });
    }
  }

  void _startPolling() {
    if (_pollTimer?.isActive == true) return;
    _pollTimer = Timer.periodic(widget.pollingInterval, (_) => _loadRequest());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _isFinalStatus(String status) {
    final normalized = status.toUpperCase();
    return normalized == 'CANCELLED' || normalized == 'COMPLETED';
  }

  Future<void> _cancelRequest() async {
    if (_actionBusy || _request == null) return;
    setState(() => _actionBusy = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      await _api.post('/intercity/requests/${widget.requestId}/cancel');
      if (!mounted) return;
      await _loadRequest();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Межгородняя заявка отменена')),
      );
      router.go('/order?reset=${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    if (_actionBusy || _request == null) return;
    final offerId = (offer['id'] ?? '').toString();
    if (offerId.isEmpty) return;

    setState(() => _actionBusy = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      await _api.post('/intercity/offers/$offerId/accept');
      if (!mounted) return;
      await _loadRequest();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Предложение водителя принято')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _fitMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final points = <LatLng>[
        if (_fromPoint != null) _fromPoint!,
        if (_toPoint != null) _toPoint!,
      ];
      if (points.isEmpty) return;
      try {
        if (points.length == 1) {
          _mapController.move(points.first, 10);
          return;
        }
        final lats = points.map((p) => p.latitude).toList();
        final lngs = points.map((p) => p.longitude).toList();
        final center = LatLng(
          (lats.reduce((a, b) => a + b) / lats.length),
          (lngs.reduce((a, b) => a + b) / lngs.length),
        );
        _mapController.move(center, 6.8);
      } catch (_) {}
    });
  }

  String _statusMessage(
    Map<String, dynamic>? request,
    String status,
    int offersCount,
  ) {
    final requestType = _requestTypeOf(request);
    final entityLabel = _requestEntityLabel(requestType);
    final counterpartiesLabel = _counterpartyLabel(requestType);
    switch (status.toUpperCase()) {
      case 'OPEN':
        return offersCount > 0
            ? 'Поступили отклики $counterpartiesLabel. Выберите подходящее предложение.'
            : '$entityLabel опубликована. Ожидаем отклики $counterpartiesLabel.';
      case 'ACCEPTED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
        return 'Водитель назначен и едет к вам.';
      case 'DRIVER_ARRIVED':
        return 'Водитель прибыл. Выходите к точке подачи.';
      case 'IN_PROGRESS':
        return 'Поездка началась.';
      case 'COMPLETED':
        return 'Поездка завершена.';
      case 'CANCELLED':
        return '$entityLabel отменена.';
      default:
        return 'Обновляем данные заявки...';
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'OPEN':
        return AppTheme.secondaryColor;
      case 'ACCEPTED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
      case 'DRIVER_ARRIVED':
      case 'IN_PROGRESS':
      case 'COMPLETED':
        return Colors.greenAccent;
      case 'CANCELLED':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  String _offerStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Ожидает';
      case 'ACCEPTED':
        return 'Принято';
      case 'REJECTED':
        return 'Отклонено';
      case 'CANCELLED':
        return 'Отменено';
      default:
        return 'Статус';
    }
  }

  bool _canAcceptOffers(String status) => status.toUpperCase() == 'OPEN';

  String _requestTypeOf(Map<String, dynamic>? request) {
    return (request?['requestType'] ?? requestTypeIntercity).toString();
  }

  bool _isDeliveryRequestType(String requestType) {
    return requestType.startsWith('DELIVERY');
  }

  String _requestEntityLabel(String requestType) {
    switch (requestType) {
      case requestTypeCityAuction:
        return 'Городская аукционная заявка';
      case requestTypeDeliveryCity:
      case requestTypeDeliveryIntercity:
      case requestTypeDeliveryRf:
        return 'Заявка на доставку';
      case requestTypeIntercity:
      default:
        return 'Межгородняя заявка';
    }
  }

  String _counterpartyLabel(String requestType, {bool singular = false}) {
    if (_isDeliveryRequestType(requestType)) {
      return singular ? 'исполнителем' : 'исполнителей';
    }
    return singular ? 'водителем' : 'водителей';
  }

  String _formatDateOnly(dynamic raw) {
    final value = raw?.toString();
    if (value == null || value.isEmpty) return '-';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day.$month.${parsed.year} $hour:$minute';
  }

  Widget _surfaceCard({required Widget child, EdgeInsets? padding}) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.primaryColor.withValues(alpha: 0.12),
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
      child: child,
    );
  }

  Widget _requestActionButton({
    required String label,
    required VoidCallback? onPressed,
    required IconData icon,
    bool danger = false,
  }) {
    final enabled = onPressed != null;
    final color = danger ? Colors.redAccent : AppTheme.primaryColor;
    final radius = BorderRadius.circular(18);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: color.withValues(alpha: 0.38)),
              color: color.withValues(alpha: 0.06),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(999);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: radius,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.10),
              borderRadius: radius,
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w800,
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = accent ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: borderColor.withValues(alpha: isDark ? 0.10 : 0.08),
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
                color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white60 : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _sortOffers(List<Map<String, dynamic>> offers) {
    final sorted = [...offers];
    sorted.sort((a, b) {
      final statusWeight = _offerStatusPriority(
        (a['status'] ?? '').toString(),
      ).compareTo(_offerStatusPriority((b['status'] ?? '').toString()));
      if (statusWeight != 0) return statusWeight;

      final priceCompare = _offerPrice(a).compareTo(_offerPrice(b));
      if (priceCompare != 0) return priceCompare;

      return _offerCreatedAt(a).compareTo(_offerCreatedAt(b));
    });
    return sorted;
  }

  int _offerStatusPriority(String status) {
    switch (status.toUpperCase()) {
      case 'ACCEPTED':
        return 0;
      case 'PENDING':
        return 1;
      case 'REJECTED':
        return 2;
      default:
        return 3;
    }
  }

  DateTime _offerCreatedAt(Map<String, dynamic> offer) {
    return DateTime.tryParse((offer['createdAt'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  double _offerPrice(Map<String, dynamic> offer) {
    return (offer['price'] as num?)?.toDouble() ?? double.infinity;
  }

  Map<String, dynamic>? _acceptedOfferOf(List<Map<String, dynamic>> offers) {
    for (final offer in offers) {
      if ((offer['status'] ?? '').toString().toUpperCase() == 'ACCEPTED') {
        return offer;
      }
    }
    return null;
  }

  Map<String, dynamic>? _bestPendingOfferOf(List<Map<String, dynamic>> offers) {
    for (final offer in offers) {
      if ((offer['status'] ?? '').toString().toUpperCase() == 'PENDING') {
        return offer;
      }
    }
    return null;
  }

  Future<void> _copyPhone(String phone) async {
    if (phone.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Номер скопирован')));
  }

  Future<void> _openIntercityChat() async {
    final request = _request;
    final requestId = (request?['id'] ?? widget.requestId).toString();
    if (requestId.isEmpty || requestId == 'active') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чат доступен после создания заявки')),
      );
      return;
    }
    await showOrderChatSheet(
      context: context,
      orderId: requestId,
      orderStatus: (request?['status'] ?? 'ACCEPTED').toString(),
      title: 'Чат с водителем',
      currentRole: 'PASSENGER',
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = color ?? (isDark ? Colors.white70 : AppTheme.deepViolet);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverHero(
    Map<String, dynamic> offer, {
    required String requestType,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driver = offer['driver'] is Map
        ? Map<String, dynamic>.from(offer['driver'] as Map)
        : null;
    final driverProfile = driver?['driverProfile'] is Map
        ? Map<String, dynamic>.from(driver!['driverProfile'] as Map)
        : null;
    final rating = driverProfile?['rating'] is Map
        ? Map<String, dynamic>.from(driverProfile!['rating'] as Map)
        : null;
    final phone = (driver?['phone'] ?? '').toString();
    final name = (driver?['name'] ?? 'Водитель').toString();
    final carModel = (driverProfile?['carModel'] ?? '').toString();
    final carNumber = (driverProfile?['carNumber'] ?? '').toString();
    final ratingAvg = (rating?['ratingAvg'] as num?)?.toDouble();
    final ratingCount = (rating?['ratingCount'] as num?)?.toInt() ?? 0;

    return _surfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.verified_rounded,
                color: Colors.greenAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _isDeliveryRequestType(requestType)
                    ? 'Выбранный исполнитель'
                    : 'Выбранный водитель',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.deepViolet],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  name.isNotEmpty ? name.characters.first.toUpperCase() : 'В',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    if (carModel.isNotEmpty || carNumber.isNotEmpty)
                      Text(
                        [
                          carModel,
                          carNumber,
                        ].where((item) => item.trim().isNotEmpty).join(' • '),
                        style: TextStyle(
                          color:
                              isDark ? Colors.white70 : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${offer['price']} ${rideCurrencySymbol(_request)}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (requestType == requestTypeIntercity)
                _metaChip(
                  icon: Icons.event_seat_rounded,
                  label: '${offer['seats']} мест(а)',
                  color: AppTheme.secondaryColor,
                ),
              if (ratingAvg != null)
                _metaChip(
                  icon: Icons.star_rounded,
                  label: '${ratingAvg.toStringAsFixed(1)} • $ratingCount',
                  color: Colors.amberAccent,
                ),
              if (phone.isNotEmpty)
                _metaChip(
                  icon: Icons.phone_rounded,
                  label: phone,
                  color: Colors.greenAccent,
                ),
            ],
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _requestActionButton(
                label: 'Скопировать номер водителя',
                icon: Icons.copy_rounded,
                onPressed: () => _copyPhone(phone),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _offerSummaryCard({
    required List<Map<String, dynamic>> offers,
    required Map<String, dynamic>? bestPendingOffer,
    required String requestType,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pendingCount = offers
        .where(
          (offer) =>
              (offer['status'] ?? '').toString().toUpperCase() == 'PENDING',
        )
        .length;
    return _surfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Сравните предложения',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            pendingCount > 0
                ? 'Сейчас доступно $pendingCount предложений. Можно выбрать самое выгодное по цене, рейтингу и машине.'
                : 'Сейчас нет активных предложений. Экран продолжит обновляться автоматически.',
            style: TextStyle(
              color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (bestPendingOffer != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip(
                  icon: Icons.savings_rounded,
                  label:
                      'Лучшая цена: ${bestPendingOffer['price']} ${rideCurrencySymbol(_request)}',
                  color: Colors.greenAccent,
                ),
                if (requestType == requestTypeIntercity)
                  _metaChip(
                    icon: Icons.event_seat_rounded,
                    label: '${bestPendingOffer['seats']} мест(а)',
                    color: AppTheme.secondaryColor,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _requestRouteCard({
    required String fromText,
    required String toText,
    required String requestType,
    required bool wholeCabin,
    required int seats,
    required String paymentText,
    required int offersCount,
    required Map<String, dynamic> request,
    required bool manualWarning,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _surfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: isDark ? 0.28 : 0.16),
                  AppTheme.secondaryColor.withValues(
                    alpha: isDark ? 0.18 : 0.08,
                  ),
                ],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    requestTypeLabel(requestType),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
                _metaChip(
                  icon: Icons.forum_rounded,
                  label: '$offersCount откл.',
                  color: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _requestRouteLine(from: fromText, to: toText),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _metricTile(
                        requestType == requestTypeIntercity
                            ? 'Формат'
                            : 'Оплата',
                        requestType == requestTypeIntercity
                            ? (wholeCabin ? 'Весь салон' : '$seats мест(а)')
                            : paymentText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricTile(
                        'Дата',
                        _formatDateOnly(request['date']),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _metricTile('Оплата', paymentText),
                if ((request['comment'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _requestNote(
                    icon: Icons.notes_rounded,
                    text: 'Комментарий: ${request['comment']}',
                  ),
                ],
                if ((request['itemDescription'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _requestNote(
                    icon: Icons.inventory_2_outlined,
                    text: 'Груз: ${request['itemDescription']}',
                  ),
                ],
                if (manualWarning) ...[
                  const SizedBox(height: 10),
                  _requestNote(
                    icon: Icons.warning_amber_rounded,
                    text: 'Адрес введён вручную, геоточка не подтверждена.',
                    color: Colors.orangeAccent,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestRouteLine({required String from, required String to}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _routeDot(AppTheme.primaryColor),
            Container(
              width: 2,
              height: 36,
              color: AppTheme.primaryColor.withValues(alpha: 0.36),
            ),
            _routeDot(AppTheme.secondaryColor),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                to,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _routeDot(Color color) {
    return Container(
      width: 13,
      height: 13,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _requestNote({
    required IconData icon,
    required String text,
    Color color = AppTheme.primaryColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerCard(
    Map<String, dynamic> offer, {
    required String status,
    required bool isBestPrice,
    required String requestType,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driver = offer['driver'] is Map
        ? Map<String, dynamic>.from(offer['driver'] as Map)
        : null;
    final driverProfile = driver?['driverProfile'] is Map
        ? Map<String, dynamic>.from(driver!['driverProfile'] as Map)
        : null;
    final rating = driverProfile?['rating'] is Map
        ? Map<String, dynamic>.from(driverProfile!['rating'] as Map)
        : null;
    final name = (driver?['name'] ?? 'Водитель').toString();
    final phone = (driver?['phone'] ?? '').toString();
    final carModel = (driverProfile?['carModel'] ?? '').toString();
    final carNumber = (driverProfile?['carNumber'] ?? '').toString();
    final offerStatus = (offer['status'] ?? '').toString().toUpperCase();
    final isAccepted = offerStatus == 'ACCEPTED';
    final ratingAvg = (rating?['ratingAvg'] as num?)?.toDouble();
    final ratingCount = (rating?['ratingCount'] as num?)?.toInt() ?? 0;
    final highlightColor = isAccepted
        ? Colors.greenAccent
        : (isBestPrice
            ? Colors.amberAccent
            : AppTheme.primaryColor.withValues(alpha: isDark ? 0.28 : 0.18));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isAccepted
              ? const LinearGradient(
                  colors: [Color(0x223DDC97), Color(0x103D1B7A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : isBestPrice
                  ? const LinearGradient(
                      colors: [Color(0x22FFC107), Color(0x103D1B7A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
          border: Border.all(color: highlightColor.withValues(alpha: 0.28)),
        ),
        child: _surfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.secondaryColor,
                          AppTheme.primaryColor,
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty
                          ? name.characters.first.toUpperCase()
                          : 'В',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          carModel.isNotEmpty
                              ? [carModel, carNumber]
                                  .where((value) => value.trim().isNotEmpty)
                                  .join(' • ')
                              : _isDeliveryRequestType(requestType)
                                  ? 'Отклик на доставку'
                                  : requestType == requestTypeCityAuction
                                      ? 'Отклик на городской аукцион'
                                      : 'Отклик на межгороднюю заявку',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white60
                                : scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isBestPrice && !isAccepted)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'ЛУЧШАЯ ЦЕНА',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(offerStatus).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _offerStatusLabel(offerStatus),
                      style: TextStyle(
                        color: _statusColor(offerStatus),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF1B1233), Color(0xFF100D20)]
                        : const [Color(0xFFF4EDFF), Color(0xFFFFFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBestPrice && !isAccepted
                                ? 'Лучшее предложение'
                                : 'Цена за поездку',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${offer['price']} ${rideCurrencySymbol(_request)}',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 74,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.18,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 7),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (requestType == requestTypeIntercity)
                    _metaChip(
                      icon: Icons.event_seat_rounded,
                      label: '${offer['seats']} мест(а)',
                      color: AppTheme.secondaryColor,
                    ),
                  if (ratingAvg != null)
                    _metaChip(
                      icon: Icons.star_rounded,
                      label: '${ratingAvg.toStringAsFixed(1)} • $ratingCount',
                      color: Colors.amberAccent,
                    ),
                  _metaChip(
                    icon: Icons.schedule_rounded,
                    label: _offerEtaText(offer),
                    color: Colors.greenAccent,
                  ),
                ],
              ),
              if ((offer['comment'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  (offer['comment'] ?? '').toString(),
                  style: TextStyle(
                    color: isDark ? Colors.white70 : scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : AppTheme.lightBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_rounded,
                        color: isDark ? Colors.white70 : AppTheme.primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          phone,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _compactActionButton(
                        label: 'Скопировать',
                        icon: Icons.copy_rounded,
                        onPressed: () => _copyPhone(phone),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_canAcceptOffers(status) && offerStatus == 'PENDING')
                SizedBox(
                  width: double.infinity,
                  child: _requestActionButton(
                    label: _actionBusy
                        ? 'Подтверждаем...'
                        : _isDeliveryRequestType(requestType)
                            ? 'Выбрать исполнителя'
                            : 'Принять предложение водителя',
                    icon: Icons.check_circle_rounded,
                    onPressed: _actionBusy ? null : () => _acceptOffer(offer),
                  ),
                ),
              if (isAccepted)
                const Text(
                  'Это предложение уже принято. Свяжитесь с водителем для деталей поездки.',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _offerEtaText(Map<String, dynamic> offer) {
    final raw = offer['etaMinutes'] ??
        offer['arrivalMinutes'] ??
        offer['estimatedArrivalMinutes'];
    final minutes = raw is num ? raw.round() : int.tryParse('$raw');
    if (minutes != null && minutes > 0) {
      return 'Прибудет ~ $minutes мин';
    }
    return 'На связи';
  }

  Widget _searchingOffersHero({required String requestType}) {
    final isDelivery = _isDeliveryRequestType(requestType);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF090713), Color(0xFF1B1234)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.28),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x553D1B7A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.manage_search_rounded,
            color: AppTheme.secondaryColor,
            size: 34,
          ),
          const SizedBox(height: 14),
          Text(
            isDelivery
                ? 'Ищем исполнителей\nдля доставки'
                : 'Ищем предложения\nот водителей',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isDelivery
                ? 'Исполнители увидят адреса, груз и способ оплаты.'
                : 'Водители увидят маршрут и предложат свою цену. Обычно это занимает несколько минут.',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _requestActionButton(
            label: 'Обновить',
            icon: Icons.refresh_rounded,
            onPressed: _loadRequest,
          ),
        ],
      ),
    );
  }

  Widget _mapLayer() {
    if (!widget.enableLiveMap || (_isActiveTripBoard && _request == null)) {
      return const IntercityMapFallback();
    }

    return Stack(
      children: [
        const Positioned.fill(child: IntercityMapFallback()),
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _fromPoint ?? const LatLng(43.2220, 76.8512),
            initialZoom: 6.8,
          ),
          children: [
            TileLayer(
              urlTemplate: AppConstants.osmTileUrl,
              subdomains: AppConstants.mapTileSubdomains,
              userAgentPackageName: 'com.milanium.intercity',
            ),
            const MapDataAttribution(),
            if (_fromPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _fromPoint!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.radio_button_checked,
                      color: Colors.greenAccent,
                      size: 24,
                    ),
                  ),
                ],
              ),
            if (_toPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _toPoint!,
                    width: 42,
                    height: 42,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 32,
                    ),
                  ),
                ],
              ),
            if (_fromPoint != null && _toPoint != null)
              RoadRouteLayer(
                  from: _fromPoint!,
                  to: _toPoint!,
                  strokeWidth: 5,
                  color: AppTheme.primaryColor),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isActiveTripBoard) {
      return _boardActiveIntercityTripScreen();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final request = _request;
    final status = (request?['status'] ?? '').toString();
    final requestType = _requestTypeOf(request);
    final entityLabel = _requestEntityLabel(requestType).toUpperCase();
    final fromText =
        request == null ? '-' : formatLocationDisplay(request, isFrom: true);
    final toText =
        request == null ? '-' : formatLocationDisplay(request, isFrom: false);
    final paymentText = paymentMethodLabel(
      request?['paymentMethod']?.toString(),
    );
    final offers = _sortOffers(
      List<Map<String, dynamic>>.from(
        (request?['offers'] as List? ?? const []).whereType<Map>().map(
              (offer) => Map<String, dynamic>.from(offer),
            ),
      ),
    );
    final acceptedOffer = _acceptedOfferOf(offers);
    final bestPendingOffer = _bestPendingOfferOf(offers);
    final accent = _statusColor(status);
    final seats = (request?['seats'] as num?)?.toInt() ?? 0;
    final wholeCabin = seats == 4;
    final manualWarning = request != null &&
        (hasUnconfirmedLocation(request, isFrom: true) ||
            hasUnconfirmedLocation(request, isFrom: false));
    final normalizedStatus = status.toUpperCase();

    if (request != null &&
        const {
          'ACCEPTED',
          'DRIVER_ASSIGNED',
          'DRIVER_EN_ROUTE',
          'DRIVER_ARRIVED',
          'IN_PROGRESS',
        }.contains(normalizedStatus)) {
      return _boardActiveIntercityTripScreen();
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mapLayer()),
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
                        color: AppTheme.darkSurface.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.24),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x407C2DFF),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entityLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status.isEmpty ? 'Загружаем...' : 'Статус: $status',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: AppTheme.darkSurface.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => goBackOr(context, fallback: '/order'),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.24,
                            ),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: 0.50,
                minChildSize: 0.18,
                maxChildSize: 0.90,
                snap: true,
                snapSizes: const [0.18, 0.50, 0.90],
                builder: (context, scrollController) => Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkBackground
                        : AppTheme.lightSurface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.26),
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
                      _glassHint(
                        icon: Icons.notifications_active_outlined,
                        text: _message,
                        accent: accent,
                      ),
                      const SizedBox(height: 12),
                      if (request != null)
                        _requestRouteCard(
                          fromText: fromText,
                          toText: toText,
                          requestType: requestType,
                          wholeCabin: wholeCabin,
                          seats: seats,
                          paymentText: paymentText,
                          offersCount: offers.length,
                          request: request,
                          manualWarning: manualWarning,
                        ),
                      if (acceptedOffer != null) ...[
                        const SizedBox(height: 12),
                        _driverHero(acceptedOffer, requestType: requestType),
                      ] else if (offers.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _offerSummaryCard(
                          offers: offers,
                          bestPendingOffer: bestPendingOffer,
                          requestType: requestType,
                        ),
                      ],
                      if (request != null) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              offers.isEmpty
                                  ? 'Поиск предложений'
                                  : 'Найдено ${offers.length} предложений',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          if (offers.isNotEmpty)
                            Icon(
                              Icons.tune_rounded,
                              color: scheme.onSurfaceVariant,
                              size: 20,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (offers.isEmpty)
                        _searchingOffersHero(requestType: requestType),
                      ...offers.map(
                        (offer) => _offerCard(
                          offer,
                          status: status,
                          requestType: requestType,
                          isBestPrice: bestPendingOffer != null &&
                              (bestPendingOffer['id'] ?? '').toString() ==
                                  (offer['id'] ?? '').toString(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _requestActionButton(
                              label: 'Обновить предложения',
                              icon: Icons.refresh_rounded,
                              onPressed: _loadRequest,
                            ),
                          ),
                          if (!_isFinalStatus(status)) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: _requestActionButton(
                                label: _actionBusy
                                    ? 'Подождите...'
                                    : 'Отменить заявку',
                                icon: Icons.close_rounded,
                                danger: true,
                                onPressed: _actionBusy ? null : _cancelRequest,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardActiveIntercityTripScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final request = _request;
    final offers = _sortOffers(
      List<Map<String, dynamic>>.from(
        (request?['offers'] as List? ?? const []).whereType<Map>().map(
              (offer) => Map<String, dynamic>.from(offer),
            ),
      ),
    );
    final acceptedOffer = _acceptedOfferOf(offers);
    final driver = acceptedOffer?['driver'] is Map
        ? Map<String, dynamic>.from(acceptedOffer!['driver'] as Map)
        : null;
    final driverProfile = driver?['driverProfile'] is Map
        ? Map<String, dynamic>.from(driver!['driverProfile'] as Map)
        : null;
    final rating = driverProfile?['rating'] is Map
        ? Map<String, dynamic>.from(driverProfile!['rating'] as Map)
        : null;
    final fromText = request == null
        ? 'Откуда не указано'
        : formatLocationDisplay(request, isFrom: true).split(',').first.trim();
    final toText = request == null
        ? 'Куда не указано'
        : formatLocationDisplay(request, isFrom: false).split(',').first.trim();
    final driverName = (driver?['name'] ?? 'Водитель не назначен').toString();
    final phone = (driver?['phone'] ?? '').toString();
    final carModel =
        (driverProfile?['carModel'] ?? 'Автомобиль не указан').toString();
    final carNumber = (driverProfile?['carNumber'] ?? '').toString();
    final ratingText = (rating?['avg'] ??
            rating?['average'] ??
            driverProfile?['rating'] ??
            '—')
        .toString();
    final progress = isDark ? 0.50 : 0.42;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _mapLayer()),
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _roundBoardButton(
                    Icons.arrow_back_rounded,
                    onTap: () => goBackOr(context, fallback: '/orders-history'),
                  ),
                  const Expanded(
                    child: Text(
                      'Поездка\nв пути',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$fromText  →  $toText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 18,
                        ),
                        Text(
                          ratingText,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 5,
                      value: progress,
                      borderRadius: BorderRadius.circular(99),
                      color: AppTheme.primaryColor,
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.12,
                      ),
                    ),
                    const SizedBox(height: 12),
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$carModel\n$carNumber',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
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
                          child: _boardTripMetric('В пути', '2 ч 15 мин'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _boardTripMetric('Осталось', '210 км')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _boardOutlinedAction(
                            Icons.call_rounded,
                            'Позвонить',
                            onPressed: () => _copyPhone(phone),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _boardOutlinedAction(
                            Icons.chat_bubble_outline_rounded,
                            'Чат',
                            onPressed: _openIntercityChat,
                          ),
                        ),
                      ],
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

  Widget _roundBoardButton(IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _boardTripMetric(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
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
          const SizedBox(height: 4),
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

  Widget _boardOutlinedAction(
    IconData icon,
    String label, {
    VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed ??
          () async {
            await Clipboard.setData(ClipboardData(text: label));
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$label скопировано')));
          },
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppTheme.primaryColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
