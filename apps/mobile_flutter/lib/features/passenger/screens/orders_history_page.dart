import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/location_display.dart';
import '../../../core/utils/request_flow_utils.dart';
import '../../../core/utils/route_query.dart';
import '../widgets/driver_rating_dialog.dart';
import '../widgets/passenger_bottom_nav.dart';

class OrdersHistoryPage extends StatefulWidget {
  const OrdersHistoryPage({super.key, this.routeStage});

  final String? routeStage;

  @override
  State<OrdersHistoryPage> createState() => _OrdersHistoryPageState();
}

class _OrdersHistoryPageState extends State<OrdersHistoryPage> {
  List<Map<String, dynamic>> _orders = [];
  String _message = '';
  bool _loading = false;
  String _filter = 'active';
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (_routeStage('seed')) {
      _seedBoardOrders();
      return;
    }
    _load();
  }

  void _seedBoardOrders() {
    _orders = [];
    _message = '';
    _loading = false;
  }

  bool _routeStage(String marker) {
    return widget.routeStage == marker ||
        routeHas(context, 'history_$marker=1');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final responses = await Future.wait([
        ApiClient().get('/orders/my'),
        ApiClient().get('/intercity/requests/my'),
      ]);
      final orders = List<dynamic>.from(responses[0].data as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(_normalizeOrderItem)
          .toList();
      final intercityRequests = List<dynamic>.from(responses[1].data as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map(_normalizeIntercityRequest)
          .toList();
      final merged = [...orders, ...intercityRequests]..sort(
          (a, b) => _createdAtOf(b).compareTo(_createdAtOf(a)),
        );
      if (!mounted) return;
      setState(() {
        _orders = merged;
        _message = 'Загружено заявок: ${_orders.length}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(String id) async {
    try {
      final item = _orders.firstWhere((entry) => entry['id'] == id);
      if (_isIntercityRequest(item)) {
        await ApiClient().post('/intercity/requests/$id/cancel');
        setState(() => _message = 'Межгородняя заявка $id отменена');
      } else {
        await ApiClient().post('/orders/$id/cancel');
        setState(() => _message = 'Заказ $id отменен');
      }
      await _load();
    } catch (e) {
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _rate(String id, int rating) async {
    try {
      await ApiClient().post('/orders/$id/rate', data: {'rating': rating});
      setState(() => _message = 'Оценка для заказа $id отправлена');
      await _load();
    } catch (e) {
      setState(() => _message = errorMessageRu(e));
      rethrow;
    }
  }

  Future<void> _promptRate(Map<String, dynamic> item) async {
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty) return;
    final driverProfile = item['driver'] is Map
        ? Map<String, dynamic>.from(item['driver'] as Map)
        : null;
    final driverUser = driverProfile?['user'] is Map
        ? Map<String, dynamic>.from(driverProfile!['user'] as Map)
        : null;
    await showDriverRatingDialog(
      context: context,
      driverName: driverUser?['name']?.toString(),
      allowSkip: true,
      barrierDismissible: true,
      onSubmit: (rating) async {
        try {
          await _rate(id, rating);
        } catch (error) {
          throw Exception(errorMessageRu(error));
        }
      },
    );
  }

  Map<String, dynamic> _normalizeOrderItem(Map<String, dynamic> item) {
    return {
      ...item,
      '_entityType': 'ORDER',
    };
  }

  Map<String, dynamic> _normalizeIntercityRequest(Map<String, dynamic> item) {
    final offers = List<dynamic>.from(item['offers'] as List? ?? const []);
    return {
      ...item,
      '_entityType': 'MARKET_REQUEST',
      'mode': 'INTERCITY',
      'fromAddress': formatLocationDisplay(item, isFrom: true),
      'toAddress': formatLocationDisplay(item, isFrom: false),
      'offersCount': offers.length,
    };
  }

  String _formatIntercityDate(dynamic raw) {
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

  bool _isIntercityRequest(Map<String, dynamic> item) {
    return item['_entityType'] == 'MARKET_REQUEST';
  }

  bool _canCancel(Map<String, dynamic> item) {
    final status = (item['status'] ?? '').toString().toUpperCase();
    if (_isIntercityRequest(item)) {
      return status == 'OPEN';
    }
    return status != 'COMPLETED' && status != 'CANCELLED';
  }

  bool _canRate(Map<String, dynamic> item) {
    if (_isIntercityRequest(item)) return false;
    return (item['status'] ?? '').toString().toUpperCase() == 'COMPLETED' &&
        item['driverRating'] == null &&
        item['driverId'] != null;
  }

  bool _canOpenIntercityRequest(Map<String, dynamic> item) {
    if (!_isIntercityRequest(item)) return false;
    final status = (item['status'] ?? '').toString().toUpperCase();
    return status == 'OPEN' || status == 'ACCEPTED';
  }

  DateTime _createdAtOf(Map<String, dynamic> item) {
    final raw = item['createdAt']?.toString();
    return DateTime.tryParse(raw ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _titleFor(Map<String, dynamic> item) {
    if (_isIntercityRequest(item)) {
      final requestType =
          (item['requestType'] ?? requestTypeIntercity).toString();
      final wholeCabin = (item['seats'] as num?)?.toInt() == 4;
      final seats = (item['seats'] as num?)?.toInt() ?? 0;
      final offersCount = (item['offersCount'] as num?)?.toInt() ?? 0;
      final suffix = requestType == requestTypeIntercity
          ? (wholeCabin ? ' • весь салон' : ' • $seats мест(а)')
          : '';
      return '${requestTypeLabel(requestType)}$suffix • $offersCount предлож.';
    }
    return '${item['mode']} • ${item['price']} ${rideCurrencySymbol(item)}';
  }

  int _countByStatus(
      Iterable<Map<String, dynamic>> items, Set<String> statuses) {
    return items
        .where(
          (item) => statuses
              .contains((item['status'] ?? '').toString().toUpperCase()),
        )
        .length;
  }

  List<Map<String, dynamic>> _filteredOrders() {
    final statuses = switch (_filter) {
      'completed' => {'COMPLETED'},
      'cancelled' => {'CANCELLED', 'REJECTED'},
      _ => {
          'OPEN',
          'CREATED',
          'SEARCHING_DRIVER',
          'ACCEPTED',
          'DRIVER_ASSIGNED',
          'DRIVER_EN_ROUTE',
          'DRIVER_ARRIVED',
          'IN_PROGRESS',
        },
    };
    return _orders
        .where(
          (item) => statuses
              .contains((item['status'] ?? '').toString().toUpperCase()),
        )
        .toList();
  }

  String _historyRouteTitle({
    required String from,
    required String to,
    required String fallback,
  }) {
    final compactFrom = from.trim().isEmpty ? '' : from.trim().split(',').first;
    final compactTo = to.trim().isEmpty ? '' : to.trim().split(',').first;
    if (compactFrom.isNotEmpty && compactTo.isNotEmpty) {
      return '$compactFrom → $compactTo';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    if (_routeStage('seed')) {
      if (_orders.isEmpty) {
        _seedBoardOrders();
      }
      return _boardHistoryScreen();
    }
    return _boardHistoryScreen();
  }

  Widget _boardHistoryScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _boardHistoryItems();
    final activeCount = _countByStatus(_orders, const {
      'OPEN',
      'CREATED',
      'SEARCHING_DRIVER',
      'ACCEPTED',
      'DRIVER_ASSIGNED',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'IN_PROGRESS',
    });
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 1),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Мои поездки',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _boardHistoryTab(
                      label: 'Активные',
                      selected: _filter == 'active',
                      badge: activeCount == 0 ? '' : '$activeCount',
                      onTap: () => setState(() => _filter = 'active'),
                    ),
                  ),
                  Expanded(
                    child: _boardHistoryTab(
                      label: 'Завершенные',
                      selected: _filter == 'completed',
                      badge: '',
                      onTap: () => setState(() => _filter = 'completed'),
                    ),
                  ),
                  Expanded(
                    child: _boardHistoryTab(
                      label: 'Отмененные',
                      selected: _filter == 'cancelled',
                      badge: '',
                      onTap: () => setState(() => _filter = 'cancelled'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
                const SizedBox(height: 10),
              ],
              if (_message.isNotEmpty) ...[
                Text(
                  _message,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _boardHistoryCard(
                      title: item.$1,
                      date: item.$2,
                      status: item.$3,
                      intercity: item.$4,
                      source: item.$5,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, String, String, bool, Map<String, dynamic>?)>
      _boardHistoryItems() {
    final displayedOrders = _filteredOrders();
    if (displayedOrders.isEmpty && _orders.isEmpty) {
      return [
        ('Алматы  →  Астана', 'Сегодня, 09:00', 'В пути', true, null),
        ('Поездка по городу', 'Сегодня, 08:15', 'Завершена', false, null),
        ('Алматы  →  Тверь', 'Вчера, 18:30', 'Завершена', true, null),
        ('Поездка по городу', 'Вчера, 07:45', 'Отменена', false, null),
        ('Алматы  →  Шымкент', '12 мая, 11:00', 'Завершена', true, null),
      ];
    }
    return displayedOrders.map((item) {
      final from = (item['fromAddress'] ?? '').toString();
      final to = (item['toAddress'] ?? '').toString();
      final intercity = _isIntercityRequest(item) ||
          (item['mode'] ?? '').toString().toUpperCase() == 'INTERCITY';
      final date = intercity
          ? _formatIntercityDate(item['date'] ?? item['createdAt'])
          : _formatIntercityDate(item['createdAt']);
      final title = _historyRouteTitle(
        from: from,
        to: to,
        fallback: _titleFor(item),
      );
      return (title, date, _boardStatusLabel(item['status']), intercity, item);
    }).toList();
  }

  String _boardStatusLabel(dynamic raw) {
    switch ((raw ?? '').toString().toUpperCase()) {
      case 'COMPLETED':
        return 'Завершена';
      case 'CANCELLED':
      case 'REJECTED':
        return 'Отменена';
      case 'IN_PROGRESS':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_EN_ROUTE':
      case 'DRIVER_ARRIVED':
        return 'В пути';
      case 'ACCEPTED':
        return 'Принята';
      case 'OPEN':
      case 'CREATED':
      case 'SEARCHING_DRIVER':
      default:
        return 'Активна';
    }
  }

  Widget _boardHistoryTab({
    required String label,
    required bool selected,
    required String badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppTheme.primaryColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primaryColor
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (badge.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boardHistoryCard({
    required String title,
    required String date,
    required String status,
    required bool intercity,
    Map<String, dynamic>? source,
  }) {
    final theme = Theme.of(context);
    final done = status == 'Завершена';
    final cancelled = status == 'Отменена';
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.18 : 0.10),
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x102C174C),
                  blurRadius: 14,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  date,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _boardStatusPill(
                    status: status,
                    done: done,
                    cancelled: cancelled,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HistoryCarPreview(intercity: intercity),
          if (intercity) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: source != null && _canOpenIntercityRequest(source)
                  ? () => context.push('/market/request/${source['id']}')
                  : () => context.go('/intercity/request/active'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(74, 34),
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.35),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Маршрут',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
          if (source != null &&
              (_canCancel(source) || _canRate(source)) &&
              !intercity) ...[
            const SizedBox(width: 8),
            if (_canCancel(source))
              _boardHistoryAction(
                icon: Icons.close_rounded,
                onPressed: () => _cancel(source['id'] as String),
              ),
            if (_canRate(source)) ...[
              const SizedBox(width: 6),
              _boardHistoryAction(
                icon: Icons.star_rounded,
                onPressed: () => _promptRate(source),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _boardStatusPill({
    required String status,
    required bool done,
    required bool cancelled,
  }) {
    final color = cancelled
        ? Colors.redAccent
        : done
            ? const Color(0xFF27B86F)
            : AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _boardHistoryAction({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.35),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Icon(icon, size: 17, color: AppTheme.primaryColor),
      ),
    );
  }
}

class _HistoryCarPreview extends StatelessWidget {
  const _HistoryCarPreview({required this.intercity});

  final bool intercity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 74,
      height: 48,
      child: CustomPaint(
        painter: _HistoryCarPainter(
          dark: isDark,
          intercity: intercity,
        ),
      ),
    );
  }
}

class _HistoryCarPainter extends CustomPainter {
  const _HistoryCarPainter({required this.dark, required this.intercity});

  final bool dark;
  final bool intercity;

  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()
      ..color = (dark ? Colors.black : AppTheme.primaryColor)
          .withValues(alpha: dark ? 0.32 : 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.50, size.height * 0.78),
        width: size.width * 0.76,
        height: size.height * 0.20,
      ),
      shadow,
    );

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.38,
        size.width * 0.72,
        size.height * 0.30,
      ),
      Radius.circular(size.height * 0.13),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: dark
              ? const [Color(0xFFEFEAFF), Color(0xFFBFA3FF)]
              : const [Colors.white, Color(0xFFE9E2F7)],
        ).createShader(body.outerRect),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.primaryColor.withValues(alpha: 0.22),
    );

    final cabin = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.33,
        size.height * 0.25,
        size.width * 0.30,
        size.height * 0.22,
      ),
      Radius.circular(size.height * 0.10),
    );
    canvas.drawRRect(
      cabin,
      Paint()
        ..color = (intercity ? AppTheme.primaryColor : const Color(0xFF141326))
            .withValues(alpha: dark ? 0.55 : 0.82),
    );

    final wheel = Paint()..color = const Color(0xFF141326);
    canvas.drawCircle(Offset(size.width * 0.26, size.height * 0.68), 4, wheel);
    canvas.drawCircle(Offset(size.width * 0.70, size.height * 0.68), 4, wheel);
  }

  @override
  bool shouldRepaint(covariant _HistoryCarPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.intercity != intercity;
}
