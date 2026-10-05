import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/sse_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';

class _FieldDraft {
  _FieldDraft({required this.key, required this.value});

  final TextEditingController key;
  final TextEditingController value;
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _api = ApiClient();
  bool _loading = true;
  String? _error;
  String _section = 'overview';

  List<dynamic> _pendingDrivers = const [];
  List<dynamic> _topups = const [];
  List<dynamic> _payouts = const [];
  List<dynamic> _walletTransactions = const [];
  List<dynamic> _orders = const [];
  List<dynamic> _cities = const [];
  List<dynamic> _cityTariffs = const [];
  List<dynamic> _cargoTariffs = const [];
  List<dynamic> _deliveryTariffs = const [];
  List<dynamic> _settings = const [];
  List<dynamic> _vehicles = const [];
  List<dynamic> _promos = const [];
  List<dynamic> _complaints = const [];
  List<dynamic> _notifications = const [];
  List<dynamic> _problemOrders = const [];
  Map<String, dynamic>? _financeReport;
  Map<String, dynamic>? _dashboardKpis;
  List<dynamic> _users = const [];
  List<dynamic> _collections = const [];
  List<dynamic> _collectionItems = const [];
  Map<String, dynamic>? _collectionSchema;
  String? _selectedCollection;
  bool _collectionLoading = false;
  bool _collectionSchemaLoading = false;
  bool _usersLoading = false;
  bool _collectionsSupported = true;
  String _usersRoleFilter = 'ALL';
  bool _usersLoadedAll = false;
  int _usersLoadedCount = 0;
  static const int _usersHardLimit = 5000;
  final Map<String, String> _loadIssues = {};
  bool _authErrorDuringLoad = false;
  bool _systemLoading = false;
  bool _systemAutoRefresh = true;
  SseConnection? _adminSse;
  StreamSubscription<Map<String, dynamic>>? _adminSseSub;
  DateTime? _lastRealtimeAdminRefreshAt;
  Timer? _notificationJobPollTimer;
  final Map<String, Map<String, dynamic>> _notificationJobsByCampaignId = {};
  Map<String, dynamic>? _systemOverview;
  Map<String, dynamic>? _systemHealth;
  List<dynamic> _systemRequestLogs = const [];
  List<dynamic> _systemErrorLogs = const [];
  List<dynamic> _adminAuditLogs = const [];
  bool _rbacLoading = false;
  List<dynamic> _rbacRoles = const [];
  List<dynamic> _rbacPermissions = const [];
  List<dynamic> _rbacAdmins = const [];
  final _systemLogsLimitCtrl = TextEditingController(text: '200');
  final _auditAdminIdCtrl = TextEditingController();
  final _auditActionCtrl = TextEditingController();
  final _auditFromCtrl = TextEditingController();
  final _auditToCtrl = TextEditingController();
  Timer? _systemRefreshTimer;

  final _cityNameCtrl = TextEditingController();
  final _cityRegionCtrl = TextEditingController();
  final _cityLatCtrl = TextEditingController();
  final _cityLngCtrl = TextEditingController();

  final _cityTariffCityIdCtrl = TextEditingController();
  final _cityTariffNameCtrl = TextEditingController(text: 'Стандарт');
  final _cityTariffBaseCtrl = TextEditingController(text: '300');
  final _cityTariffPerKmCtrl = TextEditingController(text: '120');
  final _cityTariffPerMinCtrl = TextEditingController(text: '20');
  final _cityTariffMinPriceCtrl = TextEditingController(text: '500');

  final _cargoTariffNameCtrl = TextEditingController(text: 'Грузовой стандарт');
  final _cargoTariffBaseCtrl = TextEditingController(text: '800');
  final _cargoTariffPerKmCtrl = TextEditingController(text: '220');
  final _cargoTariffPerKgCtrl = TextEditingController(text: '15');
  final _cargoTariffMinPriceCtrl = TextEditingController(text: '1200');

  final _deliveryTariffNameCtrl =
      TextEditingController(text: 'Доставка стандарт');
  final _deliveryTariffBaseCtrl = TextEditingController(text: '400');
  final _deliveryTariffPerKmCtrl = TextEditingController(text: '90');
  final _deliveryTariffPerKgCtrl = TextEditingController(text: '10');
  final _deliveryTariffMinPriceCtrl = TextEditingController(text: '500');
  final _deliveryDoorFeeCtrl = TextEditingController(text: '300');

  final _settingKeyCtrl = TextEditingController();
  final _settingValueCtrl = TextEditingController();
  final _vehicleDriverIdCtrl = TextEditingController();
  final _vehicleBrandCtrl = TextEditingController();
  final _vehicleModelCtrl = TextEditingController();
  final _vehiclePlateCtrl = TextEditingController();
  final _promoCodeCtrl = TextEditingController();
  final _promoTitleCtrl = TextEditingController();
  final _promoDiscountCtrl = TextEditingController(text: '10');
  final _complaintTypeCtrl = TextEditingController(text: 'GENERAL');
  final _complaintTextCtrl = TextEditingController();
  final _notificationTitleCtrl = TextEditingController();
  final _notificationBodyCtrl = TextEditingController();
  final _financeFromCtrl = TextEditingController();
  final _financeToCtrl = TextEditingController();
  final _walletTxUserIdCtrl = TextEditingController();
  final _walletTxTypeCtrl = TextEditingController();
  final _walletTxSourceCtrl = TextEditingController();
  final _walletTxTakeCtrl = TextEditingController(text: '100');
  final _orderAdminPriceCtrl = TextEditingController();
  final _orderAdminCommissionCtrl = TextEditingController();
  final _usersSearchCtrl = TextEditingController();
  final _collectionIdCtrl = TextEditingController();
  final _collectionTakeCtrl = TextEditingController(text: '100');
  final _collectionSkipCtrl = TextEditingController(text: '0');
  final _collectionSearchCtrl = TextEditingController();
  final _collectionPayloadCtrl = TextEditingController(text: '{\n  \n}');

  @override
  void initState() {
    super.initState();
    _loadAll();
    _refreshNotificationJobs();
    _connectAdminRealtime();
    _systemRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_systemAutoRefresh) return;
      _loadSystemData(silent: true);
    });
  }

  @override
  void dispose() {
    _cityNameCtrl.dispose();
    _cityRegionCtrl.dispose();
    _cityLatCtrl.dispose();
    _cityLngCtrl.dispose();
    _cityTariffCityIdCtrl.dispose();
    _cityTariffNameCtrl.dispose();
    _cityTariffBaseCtrl.dispose();
    _cityTariffPerKmCtrl.dispose();
    _cityTariffPerMinCtrl.dispose();
    _cityTariffMinPriceCtrl.dispose();
    _cargoTariffNameCtrl.dispose();
    _cargoTariffBaseCtrl.dispose();
    _cargoTariffPerKmCtrl.dispose();
    _cargoTariffPerKgCtrl.dispose();
    _cargoTariffMinPriceCtrl.dispose();
    _deliveryTariffNameCtrl.dispose();
    _deliveryTariffBaseCtrl.dispose();
    _deliveryTariffPerKmCtrl.dispose();
    _deliveryTariffPerKgCtrl.dispose();
    _deliveryTariffMinPriceCtrl.dispose();
    _deliveryDoorFeeCtrl.dispose();
    _settingKeyCtrl.dispose();
    _settingValueCtrl.dispose();
    _vehicleDriverIdCtrl.dispose();
    _vehicleBrandCtrl.dispose();
    _vehicleModelCtrl.dispose();
    _vehiclePlateCtrl.dispose();
    _promoCodeCtrl.dispose();
    _promoTitleCtrl.dispose();
    _promoDiscountCtrl.dispose();
    _complaintTypeCtrl.dispose();
    _complaintTextCtrl.dispose();
    _notificationTitleCtrl.dispose();
    _notificationBodyCtrl.dispose();
    _financeFromCtrl.dispose();
    _financeToCtrl.dispose();
    _walletTxUserIdCtrl.dispose();
    _walletTxTypeCtrl.dispose();
    _walletTxSourceCtrl.dispose();
    _walletTxTakeCtrl.dispose();
    _orderAdminPriceCtrl.dispose();
    _orderAdminCommissionCtrl.dispose();
    _usersSearchCtrl.dispose();
    _collectionIdCtrl.dispose();
    _collectionTakeCtrl.dispose();
    _collectionSkipCtrl.dispose();
    _collectionSearchCtrl.dispose();
    _collectionPayloadCtrl.dispose();
    _systemLogsLimitCtrl.dispose();
    _auditAdminIdCtrl.dispose();
    _auditActionCtrl.dispose();
    _auditFromCtrl.dispose();
    _auditToCtrl.dispose();
    _notificationJobPollTimer?.cancel();
    _adminSseSub?.cancel();
    _adminSse?.close();
    _systemRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectAdminRealtime() async {
    _adminSseSub?.cancel();
    await _adminSse?.close();
    final conn = await SseService.connect('/realtime/events');
    if (!mounted || conn == null) return;
    _adminSse = conn;
    _adminSseSub = conn.stream.listen((event) async {
      final eventType = (event['event'] ?? '').toString();
      if (eventType != 'event') return;
      final raw = event['data'];
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      final type = (data['type'] ?? '').toString().toLowerCase();
      if (!(type.startsWith('finance.') ||
          type.startsWith('order.') ||
          type.startsWith('notification.') ||
          type == 'dispatch.retry.spike')) {
        return;
      }
      if (type == 'dispatch.retry.spike' && mounted) {
        _toast('Alert: spike retry/fail в dispatch за последние 30 минут');
      }
      final now = DateTime.now();
      final last = _lastRealtimeAdminRefreshAt;
      if (last != null && now.difference(last).inMilliseconds < 1200) return;
      _lastRealtimeAdminRefreshAt = now;
      if (!_loading) {
        await _loadAll();
      }
    });
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadIssues.clear();
      _authErrorDuringLoad = false;
    });
    try {
      final results = await Future.wait([
        _safeGetList('/admin/drivers/pending', sectionName: 'Водители'),
        _safeGetList('/admin/topups', sectionName: 'Пополнения'),
        _safeGetList('/admin/payouts', sectionName: 'Выводы'),
        _safeGetList('/admin/orders', sectionName: 'Заказы'),
        _safeGetList('/admin/cities', sectionName: 'Города'),
        _safeGetList('/admin/tariffs/city', sectionName: 'Тарифы города'),
        _safeGetList('/admin/tariffs/cargo', sectionName: 'Тарифы груз'),
        _safeGetList('/admin/tariffs/delivery', sectionName: 'Тарифы доставка'),
        _safeGetList('/admin/settings', sectionName: 'Настройки'),
        _safeGetList('/admin/vehicles', sectionName: 'Авто'),
        _safeGetList('/admin/promos', sectionName: 'Промокоды'),
        _safeGetList('/admin/complaints', sectionName: 'Support'),
        _safeGetList('/admin/notifications', sectionName: 'Уведомления'),
        _safeGetList('/admin/orders/problems',
            sectionName: 'Проблемные заказы'),
        _safeGetList('/admin/wallet-transactions?take=100',
            sectionName: 'Финтранзакции'),
      ]);

      if (!mounted) return;
      setState(() {
        _pendingDrivers = results[0];
        _topups = results[1];
        _payouts = results[2];
        _orders = results[3];
        _cities = results[4];
        _cityTariffs = results[5];
        _cargoTariffs = results[6];
        _deliveryTariffs = results[7];
        _settings = results[8];
        _vehicles = results[9];
        _promos = results[10];
        _complaints = results[11];
        _notifications = results[12];
        _problemOrders = results[13];
        _walletTransactions = results[14];
      });

      if (_authErrorDuringLoad) {
        setState(() {
          _error =
              'Сессия администратора истекла или недостаточно прав. Войдите в админку заново.';
        });
        return;
      }

      try {
        final collectionsRes = await _api.get('/admin/collections');
        final collections = _normalizeList(collectionsRes.data);
        if (!mounted) return;
        setState(() {
          _collections = collections;
          _selectedCollection ??=
              _collections.isNotEmpty ? _collections.first.toString() : null;
          _collectionsSupported = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _collectionsSupported = false;
          _collections = const [];
          _collectionItems = const [];
          _collectionSchema = null;
          _selectedCollection = null;
        });
        // Continue: old backend may not support universal collections endpoint.
      }
      if (_selectedCollection != null && _collectionsSupported) {
        await _loadCollectionSchema(silent: true);
        await _loadCollectionItems(silent: true);
      }
      await _loadUsers(silent: true, loadAll: false);
      await _loadDashboardKpis(silent: true);
      await _loadSystemData(silent: true);
      await _loadRbacData(silent: true);
      await _loadFinanceReport(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isAuthError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode ?? 0;
      return code == 401 || code == 403;
    }
    return false;
  }

  List<dynamic> _normalizeList(dynamic data) {
    if (data is List) return List<dynamic>.from(data);
    if (data is Map) {
      for (final key in const ['items', 'data', 'results', 'rows']) {
        final value = data[key];
        if (value is List) return List<dynamic>.from(value);
      }
    }
    return const [];
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<dynamic>> _safeGetList(
    String path, {
    required String sectionName,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final res = await _api.get(path, queryParameters: queryParameters);
      return _normalizeList(res.data);
    } catch (e) {
      if (_isAuthError(e)) {
        _authErrorDuringLoad = true;
      }
      _loadIssues[sectionName] = errorMessageRu(e);
      return const [];
    }
  }

  Future<void> _postAction(
    String path,
    String successMessage, {
    Map<String, dynamic>? data,
    bool reload = true,
    bool requireReason = false,
    FutureOr<void> Function()? onSuccess,
  }) async {
    try {
      Map<String, dynamic>? payload = data;
      if (requireReason) {
        final reason = await _askReasonDialog('Укажите причину действия');
        if (reason == null) return;
        payload = {...?payload, 'reason': reason};
      }
      await _api.post(path, data: payload);
      if (!mounted) return;
      _toast(successMessage);
      if (onSuccess != null) {
        await onSuccess();
      } else if (reload) {
        await _loadAll();
      }
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _patchAction(
      String path, Map<String, dynamic> data, String successMessage,
      {bool requireReason = false,
      FutureOr<void> Function()? onSuccess}) async {
    try {
      var payload = Map<String, dynamic>.from(data);
      if (requireReason) {
        final reason = await _askReasonDialog('Укажите причину изменения');
        if (reason == null) return;
        payload['reason'] = reason;
      }
      await _api.patch(path, data: payload);
      if (!mounted) return;
      _toast(successMessage);
      if (onSuccess != null) {
        await onSuccess();
      } else {
        await _loadAll();
      }
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _deleteAction(
    String path,
    String successMessage, {
    FutureOr<void> Function()? onSuccess,
  }) async {
    try {
      await _api.delete(path);
      if (!mounted) return;
      _toast(successMessage);
      if (onSuccess != null) {
        await onSuccess();
      } else {
        await _loadAll();
      }
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  void _removePendingDriver(String id) {
    setState(() {
      _pendingDrivers = _pendingDrivers
          .where((driver) => _idOf(driver) != id)
          .toList(growable: false);
    });
  }

  void _markModerationItem(
    String id,
    String status, {
    required bool topup,
  }) {
    final source = topup ? _topups : _payouts;
    final updated = source.map((item) {
      if (item is! Map || _idOf(item) != id) {
        return item;
      }
      final next = Map<String, dynamic>.from(item);
      next['status'] = status;
      return next;
    }).toList(growable: false);
    setState(() {
      if (topup) {
        _topups = updated;
      } else {
        _payouts = updated;
      }
    });
  }

  Future<String?> _askReasonDialog(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Причина',
            hintText:
                'Например: дубликат, ошибка оператора, проверка безопасности',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (!mounted) return;
    context.go('/login');
  }

  String _idOf(dynamic item) => (item is Map ? item['id'] : null).toString();

  String _phoneFrom(dynamic item) {
    final user = item is Map ? item['user'] : null;
    final wallet = item is Map ? item['wallet'] : null;
    final walletUser = wallet is Map ? wallet['user'] : null;
    if (walletUser is Map) return (walletUser['phone'] ?? '-').toString();
    if (user is Map) return (user['phone'] ?? '-').toString();
    return '-';
  }

  String _nameFrom(dynamic item) {
    final user = item is Map ? item['user'] : null;
    final wallet = item is Map ? item['wallet'] : null;
    final walletUser = wallet is Map ? wallet['user'] : null;
    if (walletUser is Map) {
      return (walletUser['name'] ?? 'Без имени').toString();
    }
    if (user is Map) return (user['name'] ?? 'Без имени').toString();
    return 'Без имени';
  }

  double? _numOrNull(String value) =>
      double.tryParse(value.replaceAll(',', '.'));

  Widget _summaryCard(String title, int count, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppTheme.deepViolet, AppTheme.primaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _opsHero() {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            AppTheme.darkBackground,
            AppTheme.deepViolet,
            AppTheme.primaryColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/branding/adaptive-icon.png',
                  width: 42,
                  height: 42,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'InterCity',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Единый контур управления платформой • $date',
            style: const TextStyle(color: Color(0xFFE8DEFF)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(Icons.directions_car, 'Заказы: ${_orders.length}'),
              _heroPill(
                  Icons.people_alt_outlined, 'Пользователи: ${_users.length}'),
              _heroPill(Icons.support_agent, 'Жалобы: ${_complaints.length}'),
              _heroPill(Icons.local_offer_outlined, 'Промо: ${_promos.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x2BFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : AppTheme.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.16 : 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
              ),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 18,
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toUpperCase()) {
      case 'ADMIN':
        return const Color(0xFF7A4B00);
      case 'DRIVER':
        return const Color(0xFF064E3B);
      case 'PASSENGER':
        return const Color(0xFF1E3A8A);
      default:
        return const Color(0xFF334155);
    }
  }

  Widget _roleBadge(String role) {
    final color = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _adminInputDecoration(label),
    );
  }

  InputDecoration _adminInputDecoration(String label, {IconData? icon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      prefixIcon:
          icon == null ? null : Icon(icon, color: AppTheme.primaryColor),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.04)
          : AppTheme.primaryColor.withValues(alpha: 0.04),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.16 : 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _adminCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = accent ?? AppTheme.primaryColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor.withValues(alpha: isDark ? 0.18 : 0.13),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: borderColor.withValues(alpha: 0.07),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: child,
    );
  }

  Widget _adminActionButton({
    required String label,
    required VoidCallback? onPressed,
    IconData? icon,
    bool filled = false,
    bool danger = false,
  }) {
    final enabled = onPressed != null;
    final accent = danger ? Colors.redAccent : AppTheme.primaryColor;
    final radius = BorderRadius.circular(16);
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: filled && !danger
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: filled && danger ? Colors.redAccent : null,
              border: filled
                  ? null
                  : Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: filled ? Colors.white : accent),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : accent,
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

  Future<void> _createCity() async {
    final lat = _numOrNull(_cityLatCtrl.text);
    final lng = _numOrNull(_cityLngCtrl.text);
    if (_cityNameCtrl.text.trim().isEmpty || lat == null || lng == null) {
      _toast('Заполните город, широту и долготу');
      return;
    }
    await _postAction('/admin/cities', 'Город создан', data: {
      'name': _cityNameCtrl.text.trim(),
      'region': _cityRegionCtrl.text.trim().isEmpty
          ? null
          : _cityRegionCtrl.text.trim(),
      'lat': lat,
      'lng': lng,
    });
  }

  Future<void> _editCity(Map<String, dynamic> city) async {
    final name = TextEditingController(text: (city['name'] ?? '').toString());
    final region =
        TextEditingController(text: (city['region'] ?? '').toString());
    final lat = TextEditingController(text: (city['lat'] ?? '').toString());
    final lng = TextEditingController(text: (city['lng'] ?? '').toString());
    bool active = (city['isActive'] ?? true) == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Редактировать город'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Название')),
                TextField(
                    controller: region,
                    decoration: const InputDecoration(labelText: 'Регион')),
                _numberField(lat, 'Широта'),
                _numberField(lng, 'Долгота'),
                SwitchListTile(
                  title: const Text('Активен'),
                  value: active,
                  onChanged: (v) => setStateDialog(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final latNum = _numOrNull(lat.text);
    final lngNum = _numOrNull(lng.text);
    if (latNum == null || lngNum == null || name.text.trim().isEmpty) {
      _toast('Некорректные данные города');
      return;
    }
    await _patchAction(
        '/admin/cities/${city['id']}',
        {
          'name': name.text.trim(),
          'region': region.text.trim(),
          'lat': latNum,
          'lng': lngNum,
          'isActive': active,
        },
        'Город обновлен');
  }

  Future<void> _createCityTariff() async {
    final base = _numOrNull(_cityTariffBaseCtrl.text);
    final perKm = _numOrNull(_cityTariffPerKmCtrl.text);
    final perMin = _numOrNull(_cityTariffPerMinCtrl.text);
    final minPrice = _numOrNull(_cityTariffMinPriceCtrl.text);
    if (_cityTariffCityIdCtrl.text.trim().isEmpty ||
        _cityTariffNameCtrl.text.trim().isEmpty ||
        base == null ||
        perKm == null ||
        perMin == null ||
        minPrice == null) {
      _toast('Заполните все поля тарифа города');
      return;
    }
    await _postAction('/admin/tariffs/city', 'Городской тариф создан', data: {
      'cityId': _cityTariffCityIdCtrl.text.trim(),
      'name': _cityTariffNameCtrl.text.trim(),
      'basePrice': base,
      'pricePerKm': perKm,
      'pricePerMin': perMin,
      'minPrice': minPrice,
    });
  }

  Future<void> _createCargoTariff() async {
    final base = _numOrNull(_cargoTariffBaseCtrl.text);
    final perKm = _numOrNull(_cargoTariffPerKmCtrl.text);
    final perKg = _numOrNull(_cargoTariffPerKgCtrl.text);
    final minPrice = _numOrNull(_cargoTariffMinPriceCtrl.text);
    if (_cargoTariffNameCtrl.text.trim().isEmpty ||
        base == null ||
        perKm == null ||
        perKg == null ||
        minPrice == null) {
      _toast('Заполните все поля грузового тарифа');
      return;
    }
    await _postAction('/admin/tariffs/cargo', 'Грузовой тариф создан', data: {
      'name': _cargoTariffNameCtrl.text.trim(),
      'basePrice': base,
      'pricePerKm': perKm,
      'pricePerKg': perKg,
      'minPrice': minPrice,
    });
  }

  Future<void> _createDeliveryTariff() async {
    final base = _numOrNull(_deliveryTariffBaseCtrl.text);
    final perKm = _numOrNull(_deliveryTariffPerKmCtrl.text);
    final perKg = _numOrNull(_deliveryTariffPerKgCtrl.text);
    final minPrice = _numOrNull(_deliveryTariffMinPriceCtrl.text);
    final doorFee = _numOrNull(_deliveryDoorFeeCtrl.text);
    if (_deliveryTariffNameCtrl.text.trim().isEmpty ||
        base == null ||
        perKm == null ||
        perKg == null ||
        minPrice == null ||
        doorFee == null) {
      _toast('Заполните все поля тарифа доставки');
      return;
    }
    await _postAction('/admin/tariffs/delivery', 'Тариф доставки создан',
        data: {
          'name': _deliveryTariffNameCtrl.text.trim(),
          'basePrice': base,
          'pricePerKm': perKm,
          'pricePerKg': perKg,
          'minPrice': minPrice,
          'doorToDoorFee': doorFee,
        });
  }

  Future<void> _editTariff({
    required String title,
    required String patchPath,
    required Map<String, dynamic> tariff,
    required List<String> numericFields,
  }) async {
    final nameCtrl =
        TextEditingController(text: (tariff['name'] ?? '').toString());
    final ctrls = <String, TextEditingController>{
      for (final k in numericFields)
        k: TextEditingController(text: (tariff[k] ?? '').toString()),
    };
    bool isActive = (tariff['isActive'] ?? true) == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Название')),
                ...numericFields.map(
                    (k) => _numberField(ctrls[k]!, _ruLabelForTariffField(k))),
                SwitchListTile(
                  title: const Text('Активен'),
                  value: isActive,
                  onChanged: (v) => setStateDialog(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final patch = <String, dynamic>{
      'name': nameCtrl.text.trim(),
      'isActive': isActive,
    };
    for (final k in numericFields) {
      final v = _numOrNull(ctrls[k]!.text);
      if (v == null) {
        _toast('Некорректное числовое поле: ${_ruLabelForTariffField(k)}');
        return;
      }
      patch[k] = v;
    }
    await _patchAction(patchPath, patch, 'Тариф обновлен');
  }

  String _ruLabelForTariffField(String field) {
    switch (field) {
      case 'basePrice':
        return 'Базовая цена';
      case 'pricePerKm':
        return 'Цена за км';
      case 'pricePerMin':
        return 'Цена за минуту';
      case 'pricePerKg':
        return 'Цена за кг';
      case 'minPrice':
        return 'Минимальная цена';
      case 'doorToDoorFee':
        return 'Доплата до двери';
      default:
        return field;
    }
  }

  Future<void> _saveSetting() async {
    final key = _settingKeyCtrl.text.trim();
    if (key.isEmpty) {
      _toast('Введите ключ настройки');
      return;
    }
    await _postAction('/admin/settings', 'Настройка сохранена', data: {
      'key': key,
      'value': _settingValueCtrl.text,
    });
  }

  Future<void> _createVehicle() async {
    if (_vehicleDriverIdCtrl.text.trim().isEmpty ||
        _vehicleBrandCtrl.text.trim().isEmpty ||
        _vehicleModelCtrl.text.trim().isEmpty ||
        _vehiclePlateCtrl.text.trim().isEmpty) {
      _toast('Заполните driverId, brand, model, plate');
      return;
    }
    await _postAction('/admin/vehicles', 'Авто добавлено', data: {
      'driverId': _vehicleDriverIdCtrl.text.trim(),
      'brand': _vehicleBrandCtrl.text.trim(),
      'model': _vehicleModelCtrl.text.trim(),
      'plateNumber': _vehiclePlateCtrl.text.trim(),
    });
  }

  Future<void> _updateVehicleStatus(
      String id, String verificationStatus, bool isActive) async {
    await _patchAction(
        '/admin/vehicles/$id',
        {
          'verificationStatus': verificationStatus,
          'isActive': isActive,
        },
        'Статус авто обновлен');
  }

  Future<void> _createPromo() async {
    if (_promoCodeCtrl.text.trim().isEmpty ||
        _promoTitleCtrl.text.trim().isEmpty) {
      _toast('Введите код и название промокода');
      return;
    }
    await _postAction('/admin/promos', 'Промокод создан', data: {
      'code': _promoCodeCtrl.text.trim().toUpperCase(),
      'title': _promoTitleCtrl.text.trim(),
      'discountType': 'PERCENT',
      'discountValue': double.tryParse(_promoDiscountCtrl.text.trim()) ?? 10,
      'isActive': true,
    });
  }

  Future<void> _togglePromo(String id, bool active) async {
    await _patchAction(
        '/admin/promos/$id', {'isActive': active}, 'Промокод обновлен');
  }

  Future<void> _createComplaint() async {
    if (_complaintTextCtrl.text.trim().isEmpty) {
      _toast('Введите текст жалобы');
      return;
    }
    await _postAction('/admin/complaints', 'Жалоба создана', data: {
      'type': _complaintTypeCtrl.text.trim().isEmpty
          ? 'GENERAL'
          : _complaintTypeCtrl.text.trim(),
      'text': _complaintTextCtrl.text.trim(),
    });
  }

  Future<void> _setComplaintStatus(
      String id, String status, String? resolutionNote) async {
    await _patchAction(
        '/admin/complaints/$id',
        {
          'status': status,
          if (resolutionNote != null) 'resolutionNote': resolutionNote,
        },
        'Жалоба обновлена');
  }

  Future<void> _createNotification() async {
    if (_notificationTitleCtrl.text.trim().isEmpty ||
        _notificationBodyCtrl.text.trim().isEmpty) {
      _toast('Введите заголовок и текст уведомления');
      return;
    }
    await _postAction('/admin/notifications', 'Рассылка создана', data: {
      'title': _notificationTitleCtrl.text.trim(),
      'body': _notificationBodyCtrl.text.trim(),
      'audience': 'ALL',
      'isSent': false,
    });
  }

  Future<void> _markNotificationSent(String id) async {
    final reason = await _askReasonDialog('Укажите причину отправки рассылки');
    if (reason == null) return;
    try {
      final res = await _api
          .post('/admin/notifications/$id/send', data: {'reason': reason});
      final job = Map<String, dynamic>.from((res.data as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _notificationJobsByCampaignId[id] = job;
      });
      _toast('Рассылка поставлена в очередь');
      _startNotificationJobPolling();
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _requeueNotificationJob(String jobId, String campaignId) async {
    final reason = await _askReasonDialog('Укажите причину повторной отправки');
    if (reason == null) return;
    try {
      final res = await _api.post('/admin/notifications/jobs/$jobId/requeue',
          data: {'reason': reason});
      final job = Map<String, dynamic>.from((res.data as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _notificationJobsByCampaignId[campaignId] = job;
      });
      _toast('Job поставлен в повторную очередь');
      _startNotificationJobPolling();
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _refreshNotificationJobs() async {
    try {
      final res = await _api
          .get('/admin/notifications/jobs', queryParameters: {'limit': 200});
      final list = List<dynamic>.from((res.data as List?) ?? const []);
      final byCampaign = <String, Map<String, dynamic>>{};
      for (final raw in list) {
        if (raw is! Map) continue;
        final job = Map<String, dynamic>.from(raw);
        final campaignId = (job['campaignId'] ?? '').toString();
        if (campaignId.isEmpty) continue;
        final prev = byCampaign[campaignId];
        if (prev == null) {
          byCampaign[campaignId] = job;
          continue;
        }
        final prevAt = (prev['queuedAt'] ?? '').toString();
        final curAt = (job['queuedAt'] ?? '').toString();
        if (curAt.compareTo(prevAt) > 0) {
          byCampaign[campaignId] = job;
        }
      }
      if (!mounted) return;
      final hasRunning = byCampaign.values.any((job) {
        final status = (job['status'] ?? '').toString().toUpperCase();
        return status == 'QUEUED' || status == 'RUNNING';
      });
      setState(() {
        _notificationJobsByCampaignId
          ..clear()
          ..addAll(byCampaign);
      });
      if (hasRunning) {
        _startNotificationJobPolling();
      }
    } catch (_) {
      // Non-blocking for notifications list rendering.
    }
  }

  void _startNotificationJobPolling() {
    _notificationJobPollTimer?.cancel();
    _notificationJobPollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      await _refreshNotificationJobs();
      if (!mounted) return;
      final hasRunning = _notificationJobsByCampaignId.values.any((job) {
        final status = (job['status'] ?? '').toString().toUpperCase();
        return status == 'QUEUED' || status == 'RUNNING';
      });
      if (!hasRunning) {
        _notificationJobPollTimer?.cancel();
      }
    });
  }

  Future<void> _loadFinanceReport({bool silent = false}) async {
    try {
      final query = <String, dynamic>{};
      if (_financeFromCtrl.text.trim().isNotEmpty) {
        query['from'] = _financeFromCtrl.text.trim();
      }
      if (_financeToCtrl.text.trim().isNotEmpty) {
        query['to'] = _financeToCtrl.text.trim();
      }
      final res =
          await _api.get('/admin/reports/finance', queryParameters: query);
      if (!mounted) return;
      setState(() {
        _financeReport =
            res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      });
    } catch (e) {
      if (!silent && mounted) _toast(errorMessageRu(e));
    }
  }

  Future<void> _loadWalletTransactions({bool silent = false}) async {
    try {
      final query = <String, dynamic>{};
      final take = int.tryParse(_walletTxTakeCtrl.text.trim());
      if (take != null && take > 0) query['take'] = take;
      if (_walletTxUserIdCtrl.text.trim().isNotEmpty) {
        query['userId'] = _walletTxUserIdCtrl.text.trim();
      }
      if (_walletTxTypeCtrl.text.trim().isNotEmpty) {
        query['type'] = _walletTxTypeCtrl.text.trim();
      }
      if (_walletTxSourceCtrl.text.trim().isNotEmpty) {
        query['source'] = _walletTxSourceCtrl.text.trim().toUpperCase();
      }
      if (_financeFromCtrl.text.trim().isNotEmpty) {
        query['from'] = _financeFromCtrl.text.trim();
      }
      if (_financeToCtrl.text.trim().isNotEmpty) {
        query['to'] = _financeToCtrl.text.trim();
      }
      final res =
          await _api.get('/admin/wallet-transactions', queryParameters: query);
      if (!mounted) return;
      setState(() {
        _walletTransactions =
            List<dynamic>.from((res.data as List?) ?? const []);
      });
    } catch (e) {
      if (!silent && mounted) _toast(errorMessageRu(e));
    }
  }

  Future<void> _exportWalletTransactionsCsv() async {
    try {
      final query = <String, dynamic>{};
      if (_walletTxUserIdCtrl.text.trim().isNotEmpty) {
        query['userId'] = _walletTxUserIdCtrl.text.trim();
      }
      if (_walletTxTypeCtrl.text.trim().isNotEmpty) {
        query['type'] = _walletTxTypeCtrl.text.trim();
      }
      if (_walletTxSourceCtrl.text.trim().isNotEmpty) {
        query['source'] = _walletTxSourceCtrl.text.trim().toUpperCase();
      }
      if (_financeFromCtrl.text.trim().isNotEmpty) {
        query['from'] = _financeFromCtrl.text.trim();
      }
      if (_financeToCtrl.text.trim().isNotEmpty) {
        query['to'] = _financeToCtrl.text.trim();
      }
      final res = await _api.get('/admin/reports/wallet-transactions/csv',
          queryParameters: query);
      if (!mounted) return;
      final map = Map<String, dynamic>.from((res.data as Map?) ?? const {});
      final csv = (map['csv'] ?? '').toString();
      final lineCount = csv.isEmpty ? 0 : '\n'.allMatches(csv).length + 1;
      _toast('CSV wallet-транзакций готов (строк: $lineCount)');
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _adminUpdateOrderDialog(Map<String, dynamic> order) async {
    final id = (order['id'] ?? '').toString();
    if (id.isEmpty) return;
    String status = (order['status'] ?? 'CREATED').toString();
    _orderAdminPriceCtrl.text = (order['price'] ?? '').toString();
    _orderAdminCommissionCtrl.text =
        (order['commissionAmount'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Управление заказом $id'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Статус'),
                  items: const [
                    DropdownMenuItem(value: 'CREATED', child: Text('CREATED')),
                    DropdownMenuItem(
                        value: 'SEARCHING_DRIVER',
                        child: Text('SEARCHING_DRIVER')),
                    DropdownMenuItem(
                        value: 'DRIVER_ASSIGNED',
                        child: Text('DRIVER_ASSIGNED')),
                    DropdownMenuItem(
                        value: 'DRIVER_EN_ROUTE',
                        child: Text('DRIVER_EN_ROUTE')),
                    DropdownMenuItem(
                        value: 'DRIVER_ARRIVED', child: Text('DRIVER_ARRIVED')),
                    DropdownMenuItem(
                        value: 'IN_PROGRESS', child: Text('IN_PROGRESS')),
                    DropdownMenuItem(
                        value: 'COMPLETED', child: Text('COMPLETED')),
                    DropdownMenuItem(
                        value: 'CANCELLED', child: Text('CANCELLED')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => status = v);
                  },
                ),
                TextField(
                  controller: _orderAdminPriceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Цена'),
                ),
                TextField(
                  controller: _orderAdminCommissionCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Комиссия'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final reason =
        await _askReasonDialog('Укажите причину ручного изменения заказа');
    if (reason == null) return;
    try {
      await _api.patch('/admin/orders/$id', data: {
        'status': status,
        'price': double.tryParse(_orderAdminPriceCtrl.text.trim()),
        'commissionAmount':
            double.tryParse(_orderAdminCommissionCtrl.text.trim()),
        'reason': reason,
      });
      if (!mounted) return;
      _toast('Заказ обновлен');
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _showOrderEventsDialog(String orderId) async {
    if (orderId.trim().isEmpty) return;
    try {
      final res = await _api
          .get('/admin/orders/$orderId/events', queryParameters: {'take': 100});
      final events = List<Map<String, dynamic>>.from(
        (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('События заказа $orderId'),
          content: SizedBox(
            width: 720,
            child: events.isEmpty
                ? const Text('События не найдены')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = events[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${item['fromStatus'] ?? '-'} -> ${item['toStatus'] ?? '-'}',
                        ),
                        subtitle: Text(
                          '${item['createdAt'] ?? '-'} • source: ${item['source'] ?? '-'} • actor: ${item['actorRole'] ?? '-'} ${item['actorUserId'] ?? ''}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _loadCollectionItems({bool silent = false}) async {
    final collection = _selectedCollection;
    if (collection == null || collection.isEmpty) return;
    if (_collectionLoading) return;
    setState(() => _collectionLoading = true);
    final take = int.tryParse(_collectionTakeCtrl.text) ?? 100;
    final skip = int.tryParse(_collectionSkipCtrl.text) ?? 0;
    try {
      final res = await _api.get(
        '/admin/collections/$collection',
        queryParameters: {'take': take, 'skip': skip},
      );
      if (!mounted) return;
      setState(() {
        _collectionItems = List<dynamic>.from(res.data as List);
      });
    } catch (e) {
      if (!mounted || silent) return;
      _toast(errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _collectionLoading = false);
    }
  }

  Future<void> _loadUsers({bool silent = false, bool loadAll = true}) async {
    if (_usersLoading) return;
    setState(() => _usersLoading = true);
    try {
      const batch = 200;
      var skip = 0;
      final all = <dynamic>[];
      var reachedEnd = false;
      while (!reachedEnd) {
        List<dynamic> chunk = const [];
        try {
          final res = await _api.get(
            '/admin/users',
            queryParameters: {'take': batch, 'skip': skip},
          );
          final data = res.data;
          if (data is Map && data['items'] is List) {
            chunk = List<dynamic>.from(data['items'] as List);
          } else if (data is List) {
            chunk = List<dynamic>.from(data);
          }
        } catch (_) {
          final res = await _api.get(
            '/admin/collections/User',
            queryParameters: {'take': batch, 'skip': skip},
          );
          chunk = List<dynamic>.from(res.data as List);
        }
        all.addAll(chunk);
        if (!loadAll || chunk.length < batch || all.length >= _usersHardLimit) {
          reachedEnd = true;
        } else {
          skip += chunk.length;
        }
      }
      if (!mounted) return;
      setState(() {
        _users = all.take(_usersHardLimit).toList(growable: false);
        _usersLoadedCount = _users.length;
        _usersLoadedAll = loadAll && _users.length < _usersHardLimit;
      });
    } catch (e) {
      if (!silent && mounted) {
        _toast(errorMessageRu(e));
      }
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  List<Map<String, dynamic>> _filteredUsers() {
    final query = _usersSearchCtrl.text.trim().toLowerCase();
    final list = _users
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final roleFiltered = _usersRoleFilter == 'ALL'
        ? list
        : list
            .where((u) =>
                (u['role'] ?? '').toString().toUpperCase() == _usersRoleFilter)
            .toList(growable: false);
    if (query.isEmpty) return roleFiltered;
    return roleFiltered.where((u) {
      final id = (u['id'] ?? '').toString().toLowerCase();
      final phone = (u['phone'] ?? '').toString().toLowerCase();
      final name = (u['name'] ?? '').toString().toLowerCase();
      final role = (u['role'] ?? '').toString().toLowerCase();
      return id.contains(query) ||
          phone.contains(query) ||
          name.contains(query) ||
          role.contains(query);
    }).toList(growable: false);
  }

  int _usersCountByRole(String role) {
    return _users
        .whereType<Map>()
        .where((u) => (u['role'] ?? '').toString().toUpperCase() == role)
        .length;
  }

  Future<void> _editUserDialog(Map<String, dynamic> user) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty) return;
    final name = TextEditingController(text: (user['name'] ?? '').toString());
    final phone = TextEditingController(text: (user['phone'] ?? '').toString());
    final cityId =
        TextEditingController(text: (user['cityId'] ?? '').toString());
    String role = (user['role'] ?? 'PASSENGER').toString().toUpperCase();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Редактировать пользователя'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Имя'),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Телефон'),
                ),
                TextField(
                  controller: cityId,
                  decoration: const InputDecoration(labelText: 'City ID'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Роль'),
                  items: const [
                    DropdownMenuItem(
                        value: 'PASSENGER', child: Text('PASSENGER')),
                    DropdownMenuItem(value: 'DRIVER', child: Text('DRIVER')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                  ],
                  onChanged: (value) {
                    if (value != null) setStateDialog(() => role = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.patch('/admin/collections/User/$id', data: {
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'cityId': cityId.text.trim().isEmpty ? null : cityId.text.trim(),
        'role': role,
      });
      if (!mounted) return;
      _toast('Пользователь обновлен');
      await _loadUsers(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    } finally {
      name.dispose();
      phone.dispose();
      cityId.dispose();
    }
  }

  Future<void> _deleteUser(String id) async {
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить пользователя?'),
        content: Text('ID: $id'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final reason =
        await _askReasonDialog('Укажите причину удаления пользователя');
    if (reason == null) return;
    try {
      final encodedReason = Uri.encodeQueryComponent(reason);
      await _api.delete('/admin/users/$id?reason=$encodedReason');
      if (!mounted) return;
      _toast('Пользователь удален');
      await _loadUsers(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _setUserRole(String id, String role) async {
    if (id.isEmpty) return;
    try {
      await _api.patch('/admin/collections/User/$id', data: {'role': role});
      if (!mounted) return;
      _toast('Роль обновлена: $role');
      await _loadUsers(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _loadCollectionSchema({bool silent = false}) async {
    final collection = _selectedCollection;
    if (collection == null || collection.isEmpty) return;
    if (_collectionSchemaLoading) return;
    setState(() => _collectionSchemaLoading = true);
    try {
      final res = await _api.get('/admin/collections/$collection/schema');
      final schema = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() => _collectionSchema = schema);
    } catch (e) {
      if (!mounted) return;
      setState(() => _collectionSchema = null);
      if (!silent) {
        _toast(errorMessageRu(e));
      }
    } finally {
      if (mounted) setState(() => _collectionSchemaLoading = false);
    }
  }

  int _systemLogsLimit() {
    final value = int.tryParse(_systemLogsLimitCtrl.text.trim());
    if (value == null) return 200;
    return value.clamp(20, 2000);
  }

  Future<void> _loadSystemData({bool silent = false}) async {
    if (_systemLoading) return;
    if (mounted) setState(() => _systemLoading = true);
    try {
      final limit = _systemLogsLimit();
      final auditQuery = <String, dynamic>{'limit': limit};
      if (_auditAdminIdCtrl.text.trim().isNotEmpty) {
        auditQuery['adminId'] = _auditAdminIdCtrl.text.trim();
      }
      if (_auditActionCtrl.text.trim().isNotEmpty) {
        auditQuery['action'] = _auditActionCtrl.text.trim();
      }
      if (_auditFromCtrl.text.trim().isNotEmpty) {
        auditQuery['from'] = _auditFromCtrl.text.trim();
      }
      if (_auditToCtrl.text.trim().isNotEmpty) {
        auditQuery['to'] = _auditToCtrl.text.trim();
      }
      final responses = await Future.wait([
        _api.get('/admin/system/overview'),
        _api.get('/admin/system/health'),
        _api.get('/admin/system/logs',
            queryParameters: {'type': 'request', 'limit': limit}),
        _api.get('/admin/system/logs',
            queryParameters: {'type': 'error', 'limit': limit}),
        _api.get('/admin/audit-logs', queryParameters: auditQuery),
      ]);
      if (!mounted) return;
      setState(() {
        _systemOverview = responses[0].data is Map
            ? Map<String, dynamic>.from(responses[0].data as Map)
            : null;
        _systemHealth = responses[1].data is Map
            ? Map<String, dynamic>.from(responses[1].data as Map)
            : null;
        _systemRequestLogs = _normalizeList(responses[2].data);
        _systemErrorLogs = _normalizeList(responses[3].data);
        _adminAuditLogs = _normalizeList(responses[4].data);
      });
    } catch (e) {
      if (!silent && mounted) {
        _toast(errorMessageRu(e));
      }
    } finally {
      if (mounted) setState(() => _systemLoading = false);
    }
  }

  Future<void> _exportFinanceCsv() async {
    try {
      final query = <String, dynamic>{};
      if (_financeFromCtrl.text.trim().isNotEmpty) {
        query['from'] = _financeFromCtrl.text.trim();
      }
      if (_financeToCtrl.text.trim().isNotEmpty) {
        query['to'] = _financeToCtrl.text.trim();
      }
      final res =
          await _api.get('/admin/reports/finance/csv', queryParameters: query);
      final payload = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final csv = (payload['csv'] ?? '').toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text((payload['filename'] ?? 'finance-report.csv').toString()),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _exportAuditCsv() async {
    try {
      final query = <String, dynamic>{'limit': _systemLogsLimit()};
      if (_auditAdminIdCtrl.text.trim().isNotEmpty) {
        query['adminId'] = _auditAdminIdCtrl.text.trim();
      }
      if (_auditActionCtrl.text.trim().isNotEmpty) {
        query['action'] = _auditActionCtrl.text.trim();
      }
      if (_auditFromCtrl.text.trim().isNotEmpty) {
        query['from'] = _auditFromCtrl.text.trim();
      }
      if (_auditToCtrl.text.trim().isNotEmpty) {
        query['to'] = _auditToCtrl.text.trim();
      }
      final res =
          await _api.get('/admin/audit-logs/csv', queryParameters: query);
      final payload = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final csv = (payload['csv'] ?? '').toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text((payload['filename'] ?? 'audit-logs.csv').toString()),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: SelectableText(
                csv,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _clearSystemLogs() async {
    try {
      await _api.post('/admin/system/logs/clear');
      if (!mounted) return;
      _toast('Логи очищены');
      await _loadSystemData(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _loadRbacData({bool silent = false}) async {
    if (_rbacLoading) return;
    if (mounted) setState(() => _rbacLoading = true);
    try {
      final responses = await Future.wait([
        _api.get('/admin/rbac/roles'),
        _api.get('/admin/rbac/permissions'),
        _api.get('/admin/rbac/admins'),
      ]);
      if (!mounted) return;
      setState(() {
        _rbacRoles = _normalizeList(responses[0].data);
        _rbacPermissions = _normalizeList(responses[1].data);
        _rbacAdmins = _normalizeList(responses[2].data);
      });
    } catch (e) {
      if (!silent && mounted) {
        _toast(errorMessageRu(e));
      }
    } finally {
      if (mounted) setState(() => _rbacLoading = false);
    }
  }

  Future<void> _bootstrapRbac() async {
    try {
      await _api.post('/admin/rbac/bootstrap');
      if (!mounted) return;
      _toast('RBAC инициализирован');
      await _loadRbacData(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _setRolePermissionsDialog(Map<String, dynamic> role) async {
    final roleId = (role['id'] ?? '').toString();
    if (roleId.isEmpty) return;
    final selected = <String>{};
    final existing = role['permissions'];
    if (existing is List) {
      for (final item in existing) {
        if (item is Map) {
          final permission = item['permission'];
          if (permission is Map) {
            final id = (permission['id'] ?? '').toString();
            if (id.isNotEmpty) selected.add(id);
          }
        }
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Права роли ${(role['code'] ?? role['name'] ?? '')}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _rbacPermissions
                    .whereType<Map>()
                    .map((raw) => Map<String, dynamic>.from(raw))
                    .map((p) {
                  final id = (p['id'] ?? '').toString();
                  final key = (p['key'] ?? '').toString();
                  final checked = selected.contains(id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    title: Text(key),
                    subtitle: Text((p['description'] ?? '').toString()),
                    onChanged: (v) {
                      setDialog(() {
                        if (v == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.post('/admin/rbac/roles/$roleId/permissions', data: {
        'permissionIds': selected.toList(),
      });
      if (!mounted) return;
      _toast('Права роли обновлены');
      await _loadRbacData(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _setAdminRolesDialog(Map<String, dynamic> admin) async {
    final userId = (admin['id'] ?? '').toString();
    if (userId.isEmpty) return;
    final selected = <String>{};
    final roles = admin['adminRoles'];
    if (roles is List) {
      for (final item in roles) {
        if (item is Map) {
          final role = item['role'];
          if (role is Map) {
            final id = (role['id'] ?? '').toString();
            if (id.isNotEmpty) selected.add(id);
          }
        }
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Роли админа ${(admin['name'] ?? admin['phone'] ?? '')}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _rbacRoles
                    .whereType<Map>()
                    .map((raw) => Map<String, dynamic>.from(raw))
                    .map((r) {
                  final id = (r['id'] ?? '').toString();
                  final code = (r['code'] ?? '').toString();
                  final checked = selected.contains(id);
                  return CheckboxListTile(
                    dense: true,
                    value: checked,
                    title: Text(code),
                    subtitle: Text((r['name'] ?? '').toString()),
                    onChanged: (v) {
                      setDialog(() {
                        if (v == true) {
                          selected.add(id);
                        } else {
                          selected.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.post('/admin/rbac/admins/$userId/roles', data: {
        'roleIds': selected.toList(),
      });
      if (!mounted) return;
      _toast('Роли админа обновлены');
      await _loadRbacData(silent: true);
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _loadDashboardKpis({bool silent = false}) async {
    try {
      final res = await _api.get('/admin/dashboard/kpis');
      if (!mounted) return;
      setState(() {
        _dashboardKpis =
            res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      });
    } catch (e) {
      if (!silent && mounted) {
        _toast(errorMessageRu(e));
      }
    }
  }

  Widget _loadIssuesBanner() {
    if (_loadIssues.isEmpty) return const SizedBox.shrink();
    return _adminCard(
      accent: Colors.orangeAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                'Часть разделов не загрузилась',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._loadIssues.entries.take(4).map(
                (e) => Text('• ${e.key}: ${e.value}'),
              ),
          if (_loadIssues.length > 4)
            Text('• Еще ошибок: ${_loadIssues.length - 4}'),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _schemaFields() {
    final raw = _collectionSchema?['fields'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  bool _isWritableSchemaField(Map<String, dynamic> field) {
    final name = (field['name'] ?? '').toString();
    if (name.isEmpty) return false;
    if (name == 'id' || name == 'createdAt' || name == 'updatedAt') {
      return false;
    }
    if (field['kind']?.toString() != 'scalar') return false;
    return true;
  }

  dynamic _sampleByType(String type, {required bool required}) {
    switch (type) {
      case 'String':
        return required ? 'value' : null;
      case 'Int':
        return required ? 0 : null;
      case 'BigInt':
        return required ? 0 : null;
      case 'Float':
      case 'Decimal':
        return required ? 0.0 : null;
      case 'Boolean':
        return required ? false : null;
      case 'DateTime':
        return required ? DateTime.now().toIso8601String() : null;
      default:
        return required ? 'value' : null;
    }
  }

  void _fillCollectionPayloadTemplate({required bool forUpdate}) {
    final fields = _schemaFields().where(_isWritableSchemaField);
    final payload = <String, dynamic>{};
    for (final field in fields) {
      final name = (field['name'] ?? '').toString();
      final hasDefault = field['hasDefaultValue'] == true;
      final isRequired = field['isRequired'] == true;
      if (!isRequired && !forUpdate) continue;
      if (hasDefault && !forUpdate) continue;
      payload[name] = _sampleByType(
        (field['type'] ?? '').toString(),
        required: isRequired,
      );
    }
    setState(() {
      _collectionPayloadCtrl.text =
          const JsonEncoder.withIndent('  ').convert(payload);
    });
  }

  Map<String, dynamic>? _payloadFromEditor() {
    try {
      final text = _collectionPayloadCtrl.text.trim();
      if (text.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        _toast('JSON должен быть объектом вида {"field":"value"}');
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      _toast('Некорректный JSON: $e');
      return null;
    }
  }

  dynamic _parseEditorValue(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.toLowerCase() == 'null') return null;
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(value.replaceAll(',', '.'));
    if (asDouble != null) return asDouble;
    if ((value.startsWith('{') && value.endsWith('}')) ||
        (value.startsWith('[') && value.endsWith(']'))) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  Map<String, dynamic> _normalizeMap(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{'value': item};
  }

  List<Map<String, dynamic>> _filteredCollectionItems() {
    final query = _collectionSearchCtrl.text.trim().toLowerCase();
    final items = _collectionItems.map(_normalizeMap).toList(growable: false);
    if (query.isEmpty) return items;
    return items.where((item) {
      if (item['id']?.toString().toLowerCase().contains(query) == true) {
        return true;
      }
      return jsonEncode(item).toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<Map<String, dynamic>?> _showCollectionEditorDialog({
    required String title,
    Map<String, dynamic>? initial,
  }) async {
    final entries = (initial ?? <String, dynamic>{})
        .entries
        .where((entry) => entry.key != 'id')
        .map((entry) => _FieldDraft(
              key: TextEditingController(text: entry.key),
              value: TextEditingController(
                text: entry.value == null
                    ? 'null'
                    : entry.value is String
                        ? entry.value.toString()
                        : jsonEncode(entry.value),
              ),
            ))
        .toList();
    if (entries.isEmpty) {
      entries.add(
        _FieldDraft(
          key: TextEditingController(),
          value: TextEditingController(),
        ),
      );
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Поддержка типов: true/false, null, числа, JSON объект/массив.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...entries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final draft = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: draft.key,
                                decoration:
                                    const InputDecoration(labelText: 'Поле'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: draft.value,
                                decoration: const InputDecoration(
                                    labelText: 'Значение'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: entries.length == 1
                                  ? null
                                  : () => setDialogState(() {
                                        entries.removeAt(index);
                                      }),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() {
                          entries.add(
                            _FieldDraft(
                              key: TextEditingController(),
                              value: TextEditingController(),
                            ),
                          );
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('Добавить поле'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () {
                  final payload = <String, dynamic>{};
                  for (final item in entries) {
                    final key = item.key.text.trim();
                    if (key.isEmpty) continue;
                    payload[key] = _parseEditorValue(item.value.text);
                  }
                  Navigator.pop(context, payload);
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        );
      },
    );

    for (final entry in entries) {
      entry.key.dispose();
      entry.value.dispose();
    }
    return result;
  }

  Future<void> _createCollectionItemDialog() async {
    final collection = _selectedCollection;
    if (collection == null || collection.isEmpty) return;
    final payload = await _showCollectionEditorDialog(
      title: 'Создать запись в $collection',
    );
    if (payload == null) return;
    try {
      await _api.post('/admin/collections/$collection', data: payload);
      if (!mounted) return;
      _toast('Запись создана');
      await _loadCollectionItems();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _editCollectionItemDialog(Map<String, dynamic> item) async {
    final collection = _selectedCollection;
    final id = item['id']?.toString();
    if (collection == null || collection.isEmpty || id == null || id.isEmpty) {
      return;
    }
    final payload = await _showCollectionEditorDialog(
      title: 'Редактировать запись $id',
      initial: item,
    );
    if (payload == null) return;
    try {
      await _api.patch('/admin/collections/$collection/$id', data: payload);
      if (!mounted) return;
      _toast('Запись обновлена');
      await _loadCollectionItems();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _confirmDeleteCollectionItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text('ID: $id'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteCollectionItem(id);
    }
  }

  Future<void> _createCollectionItem() async {
    final collection = _selectedCollection;
    if (collection == null || collection.isEmpty) return;
    final payload = _payloadFromEditor();
    if (payload == null) return;
    try {
      await _api.post('/admin/collections/$collection', data: payload);
      if (!mounted) return;
      _toast('Запись создана');
      await _loadCollectionItems();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _updateCollectionItem() async {
    final collection = _selectedCollection;
    final id = _collectionIdCtrl.text.trim();
    if (collection == null || collection.isEmpty || id.isEmpty) {
      _toast('Укажите collection и id');
      return;
    }
    final payload = _payloadFromEditor();
    if (payload == null) return;
    try {
      await _api.patch('/admin/collections/$collection/$id', data: payload);
      if (!mounted) return;
      _toast('Запись обновлена');
      await _loadCollectionItems();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Future<void> _deleteCollectionItem(String id) async {
    final collection = _selectedCollection;
    if (collection == null || collection.isEmpty) return;
    try {
      await _api.delete('/admin/collections/$collection/$id');
      if (!mounted) return;
      _toast('Запись удалена');
      await _loadCollectionItems();
    } catch (e) {
      if (!mounted) return;
      _toast(errorMessageRu(e));
    }
  }

  Widget _pendingDriversSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Водители на проверке',
          subtitle: 'Одобрение документов и вход в линию',
        ),
        if (_pendingDrivers.isEmpty)
          const Text('Нет заявок')
        else
          ..._pendingDrivers.map((driver) {
            final id = _idOf(driver);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nameFrom(driver),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_phoneFrom(driver)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _postAction(
                                '/admin/drivers/$id/approve',
                                'Водитель одобрен',
                                requireReason: true,
                                onSuccess: () => _removePendingDriver(id)),
                            child: const Text('Одобрить'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _postAction(
                                '/admin/drivers/$id/reject',
                                'Водитель отклонен',
                                requireReason: true,
                                onSuccess: () => _removePendingDriver(id)),
                            child: const Text('Отклонить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _moneyRequestsSection({
    required String title,
    required List<dynamic> items,
    required String pathPrefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title == 'Пополнения')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Финансовый отчет',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _financeFromCtrl,
                          decoration: const InputDecoration(
                            labelText: 'from (ISO, напр. 2026-03-01)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _financeToCtrl,
                          decoration: const InputDecoration(
                            labelText: 'to (ISO, напр. 2026-03-12)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loadFinanceReport,
                        icon: const Icon(Icons.query_stats),
                        label: const Text('Обновить отчет'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportFinanceCsv,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('CSV'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadWalletTransactions,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Журнал транзакций'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportWalletTransactionsCsv,
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('CSV wallet tx'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextField(
                          controller: _walletTxUserIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'userId (опционально)',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _walletTxTypeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'type (например TOPUP_APPROVED)',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _walletTxSourceCtrl,
                          decoration: const InputDecoration(
                            labelText: 'source MONEY',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _walletTxTakeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'take',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_financeReport != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                            label: Text(
                                'Revenue: ${_financeReport!['revenue'] ?? 0}')),
                        Chip(
                            label: Text(
                                'Commission: ${_financeReport!['commission'] ?? 0}')),
                        Chip(
                            label: Text(
                                'Topups: ${_financeReport!['topupsApproved'] ?? 0}')),
                        Chip(
                            label: Text(
                                'Payouts: ${_financeReport!['payoutsApproved'] ?? 0}')),
                        Chip(
                            label: Text(
                                'NetFlow: ${_financeReport!['netFlow'] ?? 0}')),
                        Chip(
                            label: Text(
                                'Completed rides: ${_financeReport!['ordersCompletedCount'] ?? 0}')),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    'Wallet Transactions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (_walletTransactions.isEmpty)
                    const Text('Транзакции не найдены')
                  else
                    ..._walletTransactions.take(20).map((tx) {
                      final m = tx is Map
                          ? Map<String, dynamic>.from(tx)
                          : <String, dynamic>{};
                      final user = (m['wallet'] is Map &&
                              (m['wallet'] as Map)['user'] is Map)
                          ? Map<String, dynamic>.from(
                              (m['wallet'] as Map)['user'] as Map)
                          : <String, dynamic>{};
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${m['type'] ?? '-'} • ${m['direction'] ?? '-'} ${m['amount'] ?? '-'}'),
                        subtitle: Text(
                            '${m['balanceSource'] ?? '-'} • ${user['phone'] ?? '-'} • ${m['createdAt'] ?? '-'}'),
                      );
                    }),
                ],
              ),
            ),
          ),
        _sectionHeader(title),
        if (items.isEmpty)
          const Text('Нет заявок')
        else
          ...items.take(30).map((item) {
            final id = _idOf(item);
            final amount = item is Map ? item['amount'] : null;
            final status = item is Map ? item['status'] : null;
            final canModerate = status?.toString() == 'PENDING';
            return Card(
              child: ListTile(
                title: Text('${_nameFrom(item)} • ${_phoneFrom(item)}'),
                subtitle: Text('Сумма: $amount • Статус: $status'),
                trailing: canModerate
                    ? Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _postAction(
                                '$pathPrefix/$id/approve', 'Заявка одобрена',
                                requireReason: true,
                                onSuccess: () => _markModerationItem(
                                      id,
                                      'APPROVED',
                                      topup: pathPrefix.contains('/topups'),
                                    )),
                            child: const Text('Одобрить'),
                          ),
                          TextButton(
                            onPressed: () => _postAction(
                                '$pathPrefix/$id/reject', 'Заявка отклонена',
                                requireReason: true,
                                onSuccess: () => _markModerationItem(
                                      id,
                                      'REJECTED',
                                      topup: pathPrefix.contains('/topups'),
                                    )),
                            child: const Text('Отклонить'),
                          ),
                        ],
                      )
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Widget _ordersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Последние заказы',
          subtitle: 'Контроль статусов и проблемных поездок',
        ),
        if (_orders.isEmpty)
          const Text('Нет заказов')
        else
          ..._orders.take(40).map((order) {
            final m = Map<String, dynamic>.from(order as Map);
            final passenger = m['passenger'] as Map?;
            final city = m['city'] as Map?;
            return _adminCard(
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Заказ ${m['id']}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${passenger?['name'] ?? passenger?['phone'] ?? '-'} • '
                          '${city?['name'] ?? '-'} • ${m['mode']} • ${m['status']} • ${m['price']}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _adminActionButton(
                        label: 'Timeline',
                        icon: Icons.timeline_rounded,
                        onPressed: () =>
                            _showOrderEventsDialog((m['id'] ?? '').toString()),
                      ),
                      _adminActionButton(
                        label: 'Управлять',
                        icon: Icons.tune_rounded,
                        onPressed: () => _adminUpdateOrderDialog(m),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 12),
        _sectionHeader(
          'Проблемные заказы',
          subtitle: 'Отмены и зависшие статусы, требующие вмешательства',
        ),
        if (_problemOrders.isEmpty)
          const Text('Проблемные заказы не найдены')
        else
          ..._problemOrders.take(40).map((order) {
            final m = Map<String, dynamic>.from(order as Map);
            final passenger = m['passenger'] as Map?;
            final driver = (m['driver'] as Map?)?['user'] as Map?;
            return _adminCard(
              accent: Colors.redAccent,
              child: Row(
                children: [
                  const Icon(Icons.report_problem_outlined,
                      color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Заказ ${m['id']} • ${m['status']}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Пассажир: ${passenger?['phone'] ?? '-'} • Водитель: ${driver?['phone'] ?? '-'} • updatedAt: ${m['updatedAt'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _adminActionButton(
                        label: 'Timeline',
                        icon: Icons.timeline_rounded,
                        onPressed: () =>
                            _showOrderEventsDialog((m['id'] ?? '').toString()),
                      ),
                      _adminActionButton(
                        label: 'Разобрать',
                        icon: Icons.build_circle_outlined,
                        danger: true,
                        onPressed: () => _adminUpdateOrderDialog(m),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _citiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Города',
          subtitle: 'Зоны работы сервиса и география тарификации',
        ),
        _adminCard(
          child: Column(
            children: [
              TextField(
                controller: _cityNameCtrl,
                decoration: _adminInputDecoration(
                  'Название города',
                  icon: Icons.location_city_rounded,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cityRegionCtrl,
                decoration: _adminInputDecoration(
                  'Регион (необязательно)',
                  icon: Icons.map_rounded,
                ),
              ),
              const SizedBox(height: 8),
              _numberField(_cityLatCtrl, 'Широта'),
              const SizedBox(height: 8),
              _numberField(_cityLngCtrl, 'Долгота'),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _adminActionButton(
                  label: 'Создать город',
                  icon: Icons.add_location_alt_rounded,
                  filled: true,
                  onPressed: _createCity,
                ),
              ),
            ],
          ),
        ),
        ..._cities.map((c) {
          final city = Map<String, dynamic>.from(c as Map);
          return _adminCard(
            child: Row(
              children: [
                const Icon(Icons.location_city_rounded,
                    color: AppTheme.primaryColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${city['name']} (${city['id']})',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Регион: ${city['region'] ?? '-'} • '
                        'lat=${city['lat']} lng=${city['lng']} • '
                        '${(city['isActive'] ?? true) == true ? 'активен' : 'неактивен'}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _adminActionButton(
                      label: 'Изм.',
                      icon: Icons.edit_rounded,
                      onPressed: () => _editCity(city),
                    ),
                    _adminActionButton(
                      label: 'Удалить',
                      icon: Icons.delete_outline_rounded,
                      danger: true,
                      onPressed: () => _deleteAction(
                          '/admin/cities/${city['id']}', 'Город удален'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _tariffsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Тарифы',
          subtitle: 'Настройка стоимости CITY / CARGO / DELIVERY',
        ),
        _adminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Городской тариф',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                controller: _cityTariffCityIdCtrl,
                decoration: _adminInputDecoration('ID города',
                    icon: Icons.location_city_rounded),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cityTariffNameCtrl,
                decoration: _adminInputDecoration('Название',
                    icon: Icons.badge_rounded),
              ),
              const SizedBox(height: 8),
              _numberField(_cityTariffBaseCtrl, 'Базовая цена'),
              const SizedBox(height: 8),
              _numberField(_cityTariffPerKmCtrl, 'Цена за км'),
              const SizedBox(height: 8),
              _numberField(_cityTariffPerMinCtrl, 'Цена за минуту'),
              const SizedBox(height: 8),
              _numberField(_cityTariffMinPriceCtrl, 'Минимальная цена'),
              const SizedBox(height: 10),
              _adminActionButton(
                label: 'Создать городской тариф',
                icon: Icons.add_road_rounded,
                filled: true,
                onPressed: _createCityTariff,
              ),
            ],
          ),
        ),
        _adminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Грузовой тариф',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                controller: _cargoTariffNameCtrl,
                decoration: _adminInputDecoration('Название',
                    icon: Icons.badge_rounded),
              ),
              const SizedBox(height: 8),
              _numberField(_cargoTariffBaseCtrl, 'Базовая цена'),
              const SizedBox(height: 8),
              _numberField(_cargoTariffPerKmCtrl, 'Цена за км'),
              const SizedBox(height: 8),
              _numberField(_cargoTariffPerKgCtrl, 'Цена за кг'),
              const SizedBox(height: 8),
              _numberField(_cargoTariffMinPriceCtrl, 'Минимальная цена'),
              const SizedBox(height: 10),
              _adminActionButton(
                label: 'Создать грузовой тариф',
                icon: Icons.local_shipping_rounded,
                filled: true,
                onPressed: _createCargoTariff,
              ),
            ],
          ),
        ),
        _adminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Тариф доставки',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                controller: _deliveryTariffNameCtrl,
                decoration: _adminInputDecoration('Название',
                    icon: Icons.badge_rounded),
              ),
              const SizedBox(height: 8),
              _numberField(_deliveryTariffBaseCtrl, 'Базовая цена'),
              const SizedBox(height: 8),
              _numberField(_deliveryTariffPerKmCtrl, 'Цена за км'),
              const SizedBox(height: 8),
              _numberField(_deliveryTariffPerKgCtrl, 'Цена за кг'),
              const SizedBox(height: 8),
              _numberField(_deliveryTariffMinPriceCtrl, 'Минимальная цена'),
              const SizedBox(height: 8),
              _numberField(_deliveryDoorFeeCtrl, 'Доплата до двери'),
              const SizedBox(height: 10),
              _adminActionButton(
                label: 'Создать тариф доставки',
                icon: Icons.delivery_dining_rounded,
                filled: true,
                onPressed: _createDeliveryTariff,
              ),
            ],
          ),
        ),
        _tariffList(
          title: 'Городские тарифы',
          items: _cityTariffs,
          onDelete: (id) => _deleteAction(
              '/admin/tariffs/city/$id', 'Городской тариф удален'),
          onDeactivate: (id) => _patchAction(
              '/admin/tariffs/city/$id', {'isActive': false}, 'Тариф отключен'),
          onEdit: (m) => _editTariff(
            title: 'Редактировать городской тариф',
            patchPath: '/admin/tariffs/city/${m['id']}',
            tariff: m,
            numericFields: const [
              'basePrice',
              'pricePerKm',
              'pricePerMin',
              'minPrice'
            ],
          ),
          subtitleBuilder: (m) =>
              'Город: ${((m['city'] as Map?)?['name'] ?? m['cityId'])} • '
              'base=${m['basePrice']} км=${m['pricePerKm']} мин=${m['pricePerMin']} min=${m['minPrice']}',
        ),
        _tariffList(
          title: 'Грузовые тарифы',
          items: _cargoTariffs,
          onDelete: (id) => _deleteAction(
              '/admin/tariffs/cargo/$id', 'Грузовой тариф удален'),
          onDeactivate: (id) => _patchAction('/admin/tariffs/cargo/$id',
              {'isActive': false}, 'Тариф отключен'),
          onEdit: (m) => _editTariff(
            title: 'Редактировать грузовой тариф',
            patchPath: '/admin/tariffs/cargo/${m['id']}',
            tariff: m,
            numericFields: const [
              'basePrice',
              'pricePerKm',
              'pricePerKg',
              'minPrice'
            ],
          ),
          subtitleBuilder: (m) =>
              'base=${m['basePrice']} км=${m['pricePerKm']} кг=${m['pricePerKg']} min=${m['minPrice']}',
        ),
        _tariffList(
          title: 'Тарифы доставки',
          items: _deliveryTariffs,
          onDelete: (id) => _deleteAction(
              '/admin/tariffs/delivery/$id', 'Тариф доставки удален'),
          onDeactivate: (id) => _patchAction('/admin/tariffs/delivery/$id',
              {'isActive': false}, 'Тариф отключен'),
          onEdit: (m) => _editTariff(
            title: 'Редактировать тариф доставки',
            patchPath: '/admin/tariffs/delivery/${m['id']}',
            tariff: m,
            numericFields: const [
              'basePrice',
              'pricePerKm',
              'pricePerKg',
              'minPrice',
              'doorToDoorFee'
            ],
          ),
          subtitleBuilder: (m) =>
              'base=${m['basePrice']} км=${m['pricePerKm']} кг=${m['pricePerKg']} min=${m['minPrice']} дверь=${m['doorToDoorFee']}',
        ),
      ],
    );
  }

  Widget _tariffList({
    required String title,
    required List<dynamic> items,
    required void Function(String id) onDelete,
    required void Function(String id) onDeactivate,
    required void Function(Map<String, dynamic> item) onEdit,
    required String Function(Map<String, dynamic> item) subtitleBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Нет тарифов'),
          ),
        ...items.map((t) {
          final m = Map<String, dynamic>.from(t as Map);
          final active = (m['isActive'] ?? true) == true;
          return Card(
            child: ListTile(
              title: Text('${m['name']} (${m['id']})'),
              subtitle: Text(
                  '${subtitleBuilder(m)} • ${active ? 'активен' : 'неактивен'}'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                      onPressed: () => onEdit(m), child: const Text('Изм.')),
                  if (active)
                    TextButton(
                        onPressed: () => onDeactivate(m['id'] as String),
                        child: const Text('Отключить')),
                  TextButton(
                      onPressed: () => onDelete(m['id'] as String),
                      child: const Text('Удалить')),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _settingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Настройки приложения',
          subtitle: 'Ключевые runtime-параметры без релиза',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Автопринятие: вкл'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'driverAutoAcceptEnabled';
                    _settingValueCtrl.text = 'true';
                  },
                ),
                ActionChip(
                  label: const Text('Автопринятие радиус (км)'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'driverAutoAcceptRadiusKm';
                    _settingValueCtrl.text = '3';
                  },
                ),
                ActionChip(
                  label: const Text('Окно принятия (сек)'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'driverOfferAcceptSec';
                    _settingValueCtrl.text = '30';
                  },
                ),
                ActionChip(
                  label: const Text('Радиус поиска (км)'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'searchRadiusKm';
                    _settingValueCtrl.text = '5';
                  },
                ),
                ActionChip(
                  label: const Text('Пассажир: карта вкл'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'passengerMapHomeEnabled';
                    _settingValueCtrl.text = 'true';
                  },
                ),
                ActionChip(
                  label: const Text('Пассажир: карта выкл'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'passengerMapHomeEnabled';
                    _settingValueCtrl.text = 'false';
                  },
                ),
                ActionChip(
                  label: const Text('Комиссия межгород по км'),
                  onPressed: () {
                    _settingKeyCtrl.text = 'intercityCommissionByDistanceKm';
                    _settingValueCtrl.text =
                        '[{"fromKm":0,"toKm":200,"fee":500},{"fromKm":200,"toKm":500,"fee":1000},{"fromKm":500,"toKm":1000,"fee":1500},{"fromKm":1000,"toKm":null,"fee":2000}]';
                  },
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                    controller: _settingKeyCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Ключ настройки')),
                TextField(
                    controller: _settingValueCtrl,
                    decoration: const InputDecoration(labelText: 'Значение')),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: _saveSetting,
                    child: const Text('Сохранить настройку')),
              ],
            ),
          ),
        ),
        ..._settings.map((s) {
          final m = Map<String, dynamic>.from(s as Map);
          return Card(
            child: ListTile(
              title: Text(m['key'].toString()),
              subtitle: Text(m['value']?.toString() ?? ''),
              onTap: () {
                _settingKeyCtrl.text = m['key'].toString();
                _settingValueCtrl.text = m['value']?.toString() ?? '';
              },
              trailing: TextButton(
                onPressed: () async {
                  _settingKeyCtrl.text = m['key'].toString();
                  _settingValueCtrl.text = m['value']?.toString() ?? '';
                  await _saveSetting();
                },
                child: const Text('Обновить'),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _vehiclesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Автопарк', subtitle: 'Машины водителей и их статусы'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                    controller: _vehicleDriverIdCtrl,
                    decoration: const InputDecoration(labelText: 'Driver ID')),
                TextField(
                    controller: _vehicleBrandCtrl,
                    decoration: const InputDecoration(labelText: 'Марка')),
                TextField(
                    controller: _vehicleModelCtrl,
                    decoration: const InputDecoration(labelText: 'Модель')),
                TextField(
                    controller: _vehiclePlateCtrl,
                    decoration: const InputDecoration(labelText: 'Гос. номер')),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: _createVehicle,
                    child: const Text('Добавить авто')),
              ],
            ),
          ),
        ),
        if (_vehicles.isEmpty)
          const Text('Нет авто')
        else
          ..._vehicles.map((v) {
            final m = Map<String, dynamic>.from(v as Map);
            final id = (m['id'] ?? '').toString();
            final status = (m['verificationStatus'] ?? 'PENDING').toString();
            final isActive = m['isActive'] == true;
            return Card(
              child: ListTile(
                title:
                    Text('${m['brand']} ${m['model']} • ${m['plateNumber']}'),
                subtitle: Text(
                    'driver=${((m['driver'] as Map?)?['id'] ?? m['driverId'])} • status=$status • ${isActive ? 'active' : 'inactive'}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _updateVehicleStatus(id, 'VERIFIED', true),
                      child: const Text('Одобрить'),
                    ),
                    TextButton(
                      onPressed: () =>
                          _updateVehicleStatus(id, 'REJECTED', false),
                      child: const Text('Отклонить'),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _promosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Промокоды', subtitle: 'Управление акциями и скидками'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                    controller: _promoCodeCtrl,
                    decoration: const InputDecoration(labelText: 'Промокод')),
                TextField(
                    controller: _promoTitleCtrl,
                    decoration: const InputDecoration(labelText: 'Название')),
                TextField(
                    controller: _promoDiscountCtrl,
                    decoration: const InputDecoration(labelText: 'Скидка (%)')),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: _createPromo,
                    child: const Text('Создать промокод')),
              ],
            ),
          ),
        ),
        if (_promos.isEmpty)
          const Text('Промокоды не найдены')
        else
          ..._promos.map((p) {
            final m = Map<String, dynamic>.from(p as Map);
            final id = (m['id'] ?? '').toString();
            final active = m['isActive'] == true;
            return Card(
              child: ListTile(
                title: Text('${m['code']} • ${m['title']}'),
                subtitle: Text(
                    '${m['discountType']} ${m['discountValue']} • usageLimit=${m['usageLimit'] ?? '-'} • ${active ? 'active' : 'inactive'}'),
                trailing: TextButton(
                  onPressed: () => _togglePromo(id, !active),
                  child: Text(active ? 'Отключить' : 'Включить'),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _supportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Жалобы и поддержка',
            subtitle: 'Обработка обращений и решений'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                    controller: _complaintTypeCtrl,
                    decoration: const InputDecoration(labelText: 'Тип жалобы')),
                TextField(
                  controller: _complaintTextCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Текст жалобы', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                    onPressed: _createComplaint,
                    child: const Text('Создать жалобу')),
              ],
            ),
          ),
        ),
        if (_complaints.isEmpty)
          const Text('Жалобы не найдены')
        else
          ..._complaints.map((c) {
            final m = Map<String, dynamic>.from(c as Map);
            final id = (m['id'] ?? '').toString();
            final status = (m['status'] ?? 'NEW').toString();
            return Card(
              child: ExpansionTile(
                title: Text('${m['type']} • $status'),
                subtitle: Text((m['text'] ?? '').toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'order=${m['orderId'] ?? '-'} • user=${m['userId'] ?? '-'} • driver=${m['driverId'] ?? '-'}'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            _setComplaintStatus(id, 'IN_REVIEW', null),
                        child: const Text('В работу'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setComplaintStatus(
                            id, 'RESOLVED', 'Resolved by admin'),
                        child: const Text('Решено'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setComplaintStatus(
                            id, 'REJECTED', 'Rejected by admin'),
                        child: const Text('Отклонить'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _notificationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Контент и уведомления',
            subtitle: 'Массовые рассылки и системные сообщения'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                    controller: _notificationTitleCtrl,
                    decoration: const InputDecoration(labelText: 'Заголовок')),
                TextField(
                  controller: _notificationBodyCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                      labelText: 'Текст', alignLabelWithHint: true),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                        onPressed: _createNotification,
                        child: const Text('Создать рассылку')),
                    OutlinedButton(
                      onPressed: _refreshNotificationJobs,
                      child: const Text('Обновить статусы jobs'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_notifications.isEmpty)
          const Text('Рассылки не найдены')
        else
          ..._notifications.map((n) {
            final m = Map<String, dynamic>.from(n as Map);
            final id = (m['id'] ?? '').toString();
            final sent = m['isSent'] == true;
            final job = _notificationJobsByCampaignId[id];
            final jobStatus = (job?['status'] ?? '').toString().toUpperCase();
            final jobId = (job?['id'] ?? '').toString();
            return Card(
              child: ListTile(
                title: Text((m['title'] ?? '').toString()),
                subtitle: Text(
                    '${m['body'] ?? ''} • audience=${m['audience'] ?? 'ALL'} • ${sent ? 'sent' : 'draft'}${jobStatus.isNotEmpty ? ' • job=$jobStatus' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: sent
                    ? const Text('Отправлено')
                    : Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _markNotificationSent(id),
                            child: const Text('Отправить'),
                          ),
                          if (jobStatus == 'FAILED' && jobId.isNotEmpty)
                            OutlinedButton(
                              onPressed: () =>
                                  _requeueNotificationJob(jobId, id),
                              child: const Text('Requeue'),
                            ),
                        ],
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _usersSection() {
    final users = _filteredUsers();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Пользователи',
          subtitle:
              'Полный список аккаунтов, фильтрация по ролям и быстрые действия',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Подсказка: начните с фильтра роли, затем откройте нужного пользователя.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usersSearchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск по имени / телефону / роли / ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _usersLoading
                          ? null
                          : () => _loadUsers(loadAll: true),
                      icon: const Icon(Icons.refresh),
                      label:
                          Text(_usersLoading ? 'Загрузка...' : 'Обновить все'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _usersLoading
                          ? null
                          : () => _loadUsers(loadAll: false),
                      icon: const Icon(Icons.download_for_offline_outlined),
                      label: const Text('Быстро (200)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        _section = 'collections';
                        _selectedCollection = 'User';
                        _loadCollectionSchema();
                        _loadCollectionItems();
                        setState(() {});
                      },
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('Открыть в Коллекциях'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text('ALL (${_users.length})'),
                      selected: _usersRoleFilter == 'ALL',
                      onSelected: (_) =>
                          setState(() => _usersRoleFilter = 'ALL'),
                    ),
                    ChoiceChip(
                      label:
                          Text('PASSENGER (${_usersCountByRole('PASSENGER')})'),
                      selected: _usersRoleFilter == 'PASSENGER',
                      onSelected: (_) =>
                          setState(() => _usersRoleFilter = 'PASSENGER'),
                    ),
                    ChoiceChip(
                      label: Text('DRIVER (${_usersCountByRole('DRIVER')})'),
                      selected: _usersRoleFilter == 'DRIVER',
                      onSelected: (_) =>
                          setState(() => _usersRoleFilter = 'DRIVER'),
                    ),
                    ChoiceChip(
                      label: Text('ADMIN (${_usersCountByRole('ADMIN')})'),
                      selected: _usersRoleFilter == 'ADMIN',
                      onSelected: (_) =>
                          setState(() => _usersRoleFilter = 'ADMIN'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _usersLoadedAll
                      ? 'Загружены все пользователи: $_usersLoadedCount'
                      : 'Загружено: $_usersLoadedCount${_usersLoadedCount >= _usersHardLimit ? ' (достигнут лимит $_usersHardLimit)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (users.isEmpty)
          const Text('Пользователи не найдены')
        else
          ...users.take(300).map((u) {
            final id = (u['id'] ?? '').toString();
            final role = (u['role'] ?? '').toString();
            final createdAt = (u['createdAt'] ?? '').toString();
            return Card(
              child: ExpansionTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(u['name'] ?? 'Без имени')} • ${(u['phone'] ?? '-')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _roleBadge(role),
                  ],
                ),
                subtitle: Text(
                  'ID: $id${createdAt.isNotEmpty ? ' • Создан: ${createdAt.substring(0, createdAt.length > 10 ? 10 : createdAt.length)}' : ''}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(u),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _editUserDialog(u),
                        icon: const Icon(Icons.edit),
                        label: const Text('Редактировать'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setUserRole(id, 'PASSENGER'),
                        child: const Text('PASSENGER'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setUserRole(id, 'DRIVER'),
                        child: const Text('DRIVER'),
                      ),
                      OutlinedButton(
                        onPressed: () => _setUserRole(id, 'ADMIN'),
                        child: const Text('ADMIN'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _deleteUser(id),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Удалить'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _collectionsSection() {
    final filteredItems = _filteredCollectionItems();
    final take = int.tryParse(_collectionTakeCtrl.text) ?? 100;
    final skip = int.tryParse(_collectionSkipCtrl.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Управление всей БД',
          subtitle: 'Табличный CRUD по всем коллекциям с просмотром схемы',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedCollection,
                  decoration: const InputDecoration(labelText: 'Коллекция'),
                  items: _collections
                      .map((item) => item.toString())
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    setState(() {
                      _selectedCollection = value;
                      _collectionSchema = null;
                    });
                    await _loadCollectionSchema();
                    await _loadCollectionItems();
                  },
                ),
                const SizedBox(height: 8),
                if (_collectionSchemaLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_collectionSchema != null)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Структура: ${_collectionSchema!['collection']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'PK: ${((_collectionSchema!['primaryKey'] as List?) ?? const [
                                  'id'
                                ]).join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _schemaFields().map((field) {
                              final name = (field['name'] ?? '').toString();
                              final type = (field['type'] ?? '').toString();
                              final required = field['isRequired'] == true;
                              final relation =
                                  field['kind']?.toString() == 'object';
                              final suffix = relation
                                  ? 'rel'
                                  : required
                                      ? 'req'
                                      : 'opt';
                              return Chip(
                                label: Text('$name: $type ($suffix)'),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: _numberField(_collectionTakeCtrl, 'Лимит (take)'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child:
                          _numberField(_collectionSkipCtrl, 'Смещение (skip)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _collectionSearchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Поиск по ID и JSON',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          _collectionLoading ? null : _loadCollectionItems,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                          _collectionLoading ? 'Загрузка...' : 'Загрузить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _collectionSchemaLoading
                          ? null
                          : _loadCollectionSchema,
                      icon: const Icon(Icons.schema_outlined),
                      label: const Text('Схема'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _createCollectionItemDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Создать запись'),
                    ),
                    OutlinedButton.icon(
                      onPressed: skip > 0
                          ? () {
                              final next = (skip - take).clamp(0, 1000000);
                              _collectionSkipCtrl.text = '$next';
                              _loadCollectionItems();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Назад'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _collectionItems.isEmpty
                          ? null
                          : () {
                              _collectionSkipCtrl.text = '${skip + take}';
                              _loadCollectionItems();
                            },
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Вперед'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Показано: ${filteredItems.length} из ${_collectionItems.length} (take=$take, skip=$skip)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Расширенный JSON режим'),
                  subtitle: const Text('Для массовых или сложных изменений'),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    TextField(
                      controller: _collectionIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ID записи (для update/delete)',
                      ),
                    ),
                    TextField(
                      controller: _collectionPayloadCtrl,
                      minLines: 5,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        labelText: 'JSON payload для create/update',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _fillCollectionPayloadTemplate(forUpdate: false),
                          child: const Text('Шаблон create'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              _fillCollectionPayloadTemplate(forUpdate: true),
                          child: const Text('Шаблон update'),
                        ),
                        ElevatedButton(
                          onPressed: _createCollectionItem,
                          child: const Text('Создать (JSON)'),
                        ),
                        OutlinedButton(
                          onPressed: _updateCollectionItem,
                          child: const Text('Обновить по ID (JSON)'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            final id = _collectionIdCtrl.text.trim();
                            if (id.isNotEmpty) _confirmDeleteCollectionItem(id);
                          },
                          child: const Text('Удалить по ID'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (filteredItems.isEmpty)
          const Text('Нет данных или коллекция не выбрана')
        else
          ...filteredItems.map((map) {
            final id = (map['id'] ?? '').toString();
            final title = id.isEmpty
                ? (map['key']?.toString() ??
                    map['name']?.toString() ??
                    'Запись')
                : id;
            final fieldSummary = map.entries
                .where((entry) => entry.key != 'id')
                .take(4)
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(' • ');
            return Card(
              child: ExpansionTile(
                title: Text(title),
                subtitle: Text(
                  fieldSummary.isEmpty ? 'Нет полей' : fieldSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(map),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (id.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: () => _editCollectionItemDialog(map),
                          icon: const Icon(Icons.edit),
                          label: const Text('Редактировать'),
                        ),
                      if (id.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => _confirmDeleteCollectionItem(id),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Удалить'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          _collectionIdCtrl.text = id;
                          _collectionPayloadCtrl.text =
                              const JsonEncoder.withIndent('  ').convert(map);
                        },
                        icon: const Icon(Icons.data_object),
                        label: const Text('В JSON режим'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _rbacSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Роли и права доступа',
          subtitle: 'RBAC для админов: роли, permissions и назначения',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _rbacLoading ? null : () => _loadRbacData(),
                  icon: const Icon(Icons.refresh),
                  label: Text(_rbacLoading ? 'Загрузка...' : 'Обновить RBAC'),
                ),
                OutlinedButton.icon(
                  onPressed: _rbacLoading ? null : _bootstrapRbac,
                  icon: const Icon(Icons.security_outlined),
                  label: const Text('Bootstrap RBAC'),
                ),
              ],
            ),
          ),
        ),
        _sectionHeader('Роли'),
        if (_rbacRoles.isEmpty)
          const Text('Роли не найдены')
        else
          ..._rbacRoles.map((raw) {
            final role = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'code': raw.toString()};
            final permissions = (role['permissions'] is List)
                ? (role['permissions'] as List).length
                : 0;
            final users =
                (role['users'] is List) ? (role['users'] as List).length : 0;
            return Card(
              child: ListTile(
                title: Text('${role['code']} • ${role['name'] ?? ''}'),
                subtitle: Text(
                  'permissions: $permissions • admins: $users${role['isSystem'] == true ? ' • system' : ''}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _setRolePermissionsDialog(role),
                      child: const Text('Права'),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        _sectionHeader('Администраторы'),
        if (_rbacAdmins.isEmpty)
          const Text('Администраторы не найдены')
        else
          ..._rbacAdmins.map((raw) {
            final admin = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'name': raw.toString()};
            final roles = (admin['adminRoles'] is List)
                ? (admin['adminRoles'] as List)
                    .whereType<Map>()
                    .map((e) => e['role'])
                    .whereType<Map>()
                    .map((e) => (e['code'] ?? '').toString())
                    .where((e) => e.isNotEmpty)
                    .join(', ')
                : '';
            return Card(
              child: ListTile(
                title: Text(
                    '${admin['name'] ?? 'Admin'} • ${admin['phone'] ?? '-'}'),
                subtitle: Text(roles.isEmpty ? 'Роли не назначены' : roles),
                trailing: TextButton(
                  onPressed: () => _setAdminRolesDialog(admin),
                  child: const Text('Назначить роли'),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _systemSection() {
    final counters = _systemOverview?['counters'] is Map
        ? Map<String, dynamic>.from(_systemOverview!['counters'] as Map)
        : <String, dynamic>{};
    final memory = _systemOverview?['memory'] is Map
        ? Map<String, dynamic>.from(_systemOverview!['memory'] as Map)
        : <String, dynamic>{};
    final logs = _systemOverview?['logs'] is Map
        ? Map<String, dynamic>.from(_systemOverview!['logs'] as Map)
        : <String, dynamic>{};
    final env = _systemOverview?['env'] is Map
        ? Map<String, dynamic>.from(_systemOverview!['env'] as Map)
        : <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Управление сервером',
          subtitle:
              'Мониторинг backend, runtime-настройки, очередь jobs и системные логи',
        ),
        _adminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _adminActionButton(
                    label: _systemLoading ? 'Обновление...' : 'Обновить',
                    icon: Icons.sync,
                    filled: true,
                    onPressed: _systemLoading ? null : () => _loadSystemData(),
                  ),
                  _adminActionButton(
                    label: 'Обновить jobs',
                    icon: Icons.notifications_active_outlined,
                    onPressed: _systemLoading ? null : _refreshNotificationJobs,
                  ),
                  _adminActionButton(
                    label: 'Очистить логи',
                    icon: Icons.cleaning_services_outlined,
                    danger: true,
                    onPressed: _systemLoading ? null : _clearSystemLogs,
                  ),
                  _adminActionButton(
                    label: 'Audit CSV',
                    icon: Icons.file_download_outlined,
                    onPressed: _systemLoading ? null : _exportAuditCsv,
                  ),
                  FilterChip(
                    selected: _systemAutoRefresh,
                    label: const Text('Автообновление 10с'),
                    onSelected: (v) => setState(() => _systemAutoRefresh = v),
                  ),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _systemLogsLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _adminInputDecoration(
                        'Лимит логов',
                        icon: Icons.format_list_numbered_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _auditAdminIdCtrl,
                      decoration: _adminInputDecoration(
                        'Audit adminId',
                        icon: Icons.admin_panel_settings_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _auditActionCtrl,
                      decoration: _adminInputDecoration(
                        'Audit action contains',
                        icon: Icons.manage_search_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _auditFromCtrl,
                      decoration: _adminInputDecoration(
                        'Audit from (ISO date/time)',
                        icon: Icons.date_range_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _auditToCtrl,
                      decoration: _adminInputDecoration(
                        'Audit to (ISO date/time)',
                        icon: Icons.event_available_rounded,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_systemOverview == null)
                const Text('Данные системы еще не загружены')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'Dispatch: queued ${_dashboardKpis?['notificationDispatchQueued'] ?? 0}, running ${_dashboardKpis?['notificationDispatchRunning'] ?? 0}, failed ${_dashboardKpis?['notificationDispatchFailed'] ?? 0}',
                      ),
                    ),
                    Chip(
                        label: Text(
                            'Uptime: ${_systemOverview!['uptimeSec'] ?? 0} c')),
                    Chip(
                        label: Text(
                            'Users: ${counters['users'] ?? 0} • Drivers: ${counters['drivers'] ?? 0}')),
                    Chip(
                        label: Text(
                            'Orders: ${counters['orders'] ?? 0} • Cities: ${counters['cities'] ?? 0}')),
                    Chip(
                        label: Text(
                            'Pending: topups ${counters['topupsPending'] ?? 0}, payouts ${counters['payoutsPending'] ?? 0}')),
                    Chip(
                        label: Text(
                            'Memory: heap ${memory['heapUsedMb'] ?? 0}/${memory['heapTotalMb'] ?? 0} MB')),
                    Chip(
                        label: Text(
                            'Logs: req ${logs['requests'] ?? 0}, err ${logs['errors'] ?? 0}')),
                    Chip(
                        label: Text(
                            'Node: ${env['version'] ?? '-'} (${env['nodeEnv'] ?? '-'})')),
                    Chip(
                      label: Text(
                        'Health: ${_systemHealth?['status'] ?? '-'} • DB ${_systemHealth?['db'] ?? '-'}',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _sectionHeader(
          'Runtime-настройки',
          subtitle: 'Оперативные параметры backend без отдельного релиза',
        ),
        _serverSettingsOverview(),
        const SizedBox(height: 8),
        _sectionHeader(
          'Очередь фоновых jobs',
          subtitle: 'Статусы отправки рассылок, ретраи и операционные ошибки',
        ),
        _serverNotificationJobsOverview(),
        const SizedBox(height: 8),
        _sectionHeader('Ошибки сервера'),
        if (_systemErrorLogs.isEmpty)
          const Text('Ошибки не зафиксированы')
        else
          ..._systemErrorLogs.take(200).map((raw) {
            final item = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'message': raw.toString()};
            return _adminCard(
              accent: Colors.redAccent,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item['message'] ?? '-').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item['at'] ?? ''} ${item['method'] ?? ''} ${item['path'] ?? ''}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    (item['source'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 8),
        _sectionHeader('Аудит действий админов'),
        if (_adminAuditLogs.isEmpty)
          const Text('Действия администраторов пока не зафиксированы')
        else
          ..._adminAuditLogs.take(200).map((raw) {
            final item = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'action': raw.toString()};
            return _adminCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (item['action'] ?? '-').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item['at'] ?? ''} • admin=${item['adminId'] ?? '-'} • ${item['target'] ?? ''}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    (item['role'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 8),
        _sectionHeader('Последние запросы'),
        if (_systemRequestLogs.isEmpty)
          const Text('Запросы не зафиксированы')
        else
          ..._systemRequestLogs.take(300).map((raw) {
            final item = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'path': raw.toString()};
            final status =
                int.tryParse((item['statusCode'] ?? '0').toString()) ?? 0;
            final color = status >= 500
                ? Colors.red
                : status >= 400
                    ? Colors.orange
                    : Colors.green;
            return _adminCard(
              accent: color,
              child: Row(
                children: [
                  Icon(Icons.http, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['method'] ?? '-'} ${item['path'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item['at'] ?? ''} • ${item['durationMs'] ?? 0} ms • ${item['ip'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$status',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _serverSettingsOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _adminCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _adminActionButton(
                label: 'Автопринятие: вкл',
                icon: Icons.auto_awesome_rounded,
                onPressed: () {
                  _settingKeyCtrl.text = 'driverAutoAcceptEnabled';
                  _settingValueCtrl.text = 'true';
                },
              ),
              _adminActionButton(
                label: 'Автопринятие радиус',
                icon: Icons.radar_rounded,
                onPressed: () {
                  _settingKeyCtrl.text = 'driverAutoAcceptRadiusKm';
                  _settingValueCtrl.text = '3';
                },
              ),
              _adminActionButton(
                label: 'Окно принятия',
                icon: Icons.timer_rounded,
                onPressed: () {
                  _settingKeyCtrl.text = 'driverOfferAcceptSec';
                  _settingValueCtrl.text = '30';
                },
              ),
              _adminActionButton(
                label: 'Радиус поиска',
                icon: Icons.travel_explore_rounded,
                onPressed: () {
                  _settingKeyCtrl.text = 'searchRadiusKm';
                  _settingValueCtrl.text = '5';
                },
              ),
            ],
          ),
        ),
        _adminCard(
          child: Column(
            children: [
              TextField(
                controller: _settingKeyCtrl,
                decoration: _adminInputDecoration(
                  'Ключ настройки',
                  icon: Icons.key_rounded,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _settingValueCtrl,
                decoration: _adminInputDecoration(
                  'Значение',
                  icon: Icons.tune_rounded,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _adminActionButton(
                  label: 'Сохранить настройку',
                  icon: Icons.save_rounded,
                  filled: true,
                  onPressed: _saveSetting,
                ),
              ),
            ],
          ),
        ),
        if (_settings.isEmpty)
          const Text('Runtime-настройки пока не загружены')
        else
          ..._settings.take(15).map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            return _adminCard(
              child: Row(
                children: [
                  const Icon(Icons.settings_applications_rounded,
                      color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m['key'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(m['value']?.toString() ?? ''),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _adminActionButton(
                    label: 'В редактор',
                    icon: Icons.edit_rounded,
                    onPressed: () {
                      _settingKeyCtrl.text = m['key'].toString();
                      _settingValueCtrl.text = m['value']?.toString() ?? '';
                    },
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _serverNotificationJobsOverview() {
    final items = _notifications
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map((campaign) {
      final id = (campaign['id'] ?? '').toString();
      final job = _notificationJobsByCampaignId[id];
      return <String, dynamic>{
        'campaign': campaign,
        'job': job,
      };
    }).toList()
      ..sort((a, b) {
        final aAt = ((a['job'] as Map?)?['queuedAt'] ?? '').toString();
        final bAt = ((b['job'] as Map?)?['queuedAt'] ?? '').toString();
        return bAt.compareTo(aAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _adminCard(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _adminActionButton(
                label: 'Обновить статусы jobs',
                icon: Icons.refresh_rounded,
                onPressed: _refreshNotificationJobs,
              ),
              FilterChip(
                selected: _systemAutoRefresh,
                label: const Text('Автообновление 10с'),
                onSelected: (v) => setState(() => _systemAutoRefresh = v),
              ),
            ],
          ),
        ),
        if (items.isEmpty)
          const Text('Очередь jobs пока пуста')
        else
          ...items.take(20).map((item) {
            final campaign = Map<String, dynamic>.from(
              item['campaign'] as Map<String, dynamic>,
            );
            final job = item['job'] is Map
                ? Map<String, dynamic>.from(item['job'] as Map)
                : <String, dynamic>{};
            final campaignId = (campaign['id'] ?? '').toString();
            final jobId = (job['id'] ?? '').toString();
            final status = (job['status'] ?? 'NO_JOB').toString().toUpperCase();
            final statusColor = switch (status) {
              'DONE' => Colors.green,
              'FAILED' => Colors.red,
              'RUNNING' => AppTheme.primaryColor,
              'QUEUED' => Colors.orange,
              _ => Colors.grey,
            };
            final subtitle = [
              'audience=${campaign['audience'] ?? 'ALL'}',
              'sent=${campaign['isSent'] == true ? 'yes' : 'no'}',
              if (job.isNotEmpty) 'job=$status',
              if ((job['retryCount'] ?? 0) != 0) 'retry=${job['retryCount']}',
              if ((job['successCount'] ?? 0) != 0) 'ok=${job['successCount']}',
              if ((job['failCount'] ?? 0) != 0) 'fail=${job['failCount']}',
            ].join(' • ');
            final timing = [
              if ((job['queuedAt'] ?? '').toString().isNotEmpty)
                'queued ${job['queuedAt']}',
              if ((job['finishedAt'] ?? '').toString().isNotEmpty)
                'finished ${job['finishedAt']}',
            ].join('\n');
            return _adminCard(
              accent: statusColor,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.work_outline, color: statusColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (campaign['title'] ?? '').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          timing.isEmpty ? subtitle : '$subtitle\n$timing',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  status == 'FAILED' &&
                          jobId.isNotEmpty &&
                          campaignId.isNotEmpty
                      ? _adminActionButton(
                          label: 'Requeue',
                          icon: Icons.restart_alt_rounded,
                          onPressed: () =>
                              _requeueNotificationJob(jobId, campaignId),
                        )
                      : Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _sectionsNav() {
    const items = <Map<String, String>>[
      {'key': 'overview', 'label': 'Обзор'},
      {'key': 'users', 'label': 'Пользователи'},
      {'key': 'drivers', 'label': 'Водители'},
      {'key': 'finance', 'label': 'Финансы'},
      {'key': 'orders', 'label': 'Заказы'},
      {'key': 'cities', 'label': 'Города'},
      {'key': 'tariffs', 'label': 'Тарифы'},
      {'key': 'vehicles', 'label': 'Авто'},
      {'key': 'promos', 'label': 'Промокоды'},
      {'key': 'support', 'label': 'Support'},
      {'key': 'notifications', 'label': 'Уведомления'},
      {'key': 'settings', 'label': 'Настройки'},
      {'key': 'rbac', 'label': 'Роли и права'},
      {'key': 'system', 'label': 'Управление сервером'},
      {'key': 'collections', 'label': 'Коллекции'},
      {'key': 'all', 'label': 'Все'},
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppTheme.secondaryColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Разделы центра управления',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .where((item) =>
                    _collectionsSupported || item['key'] != 'collections')
                .map((item) {
              final key = item['key']!;
              final label = item['label']!;
              final selected = _section == key;
              return _adminSectionChip(
                label: label,
                icon: _sectionIcon(key),
                selected: selected,
                onTap: () => setState(() => _section = key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _adminSectionChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final radius = BorderRadius.circular(999);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: selected
                ? const LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  )
                : null,
            color: selected ? null : const Color(0xFFF7F4FF),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryColor
                  : AppTheme.secondaryColor.withValues(alpha: 0.12),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.20),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : const Color(0xFF5F5577),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF342A4E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _sectionIcon(String key) {
    switch (key) {
      case 'overview':
        return Icons.dashboard_outlined;
      case 'users':
        return Icons.people_alt_outlined;
      case 'drivers':
        return Icons.directions_car_outlined;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'orders':
        return Icons.receipt_long_outlined;
      case 'cities':
        return Icons.location_city_outlined;
      case 'tariffs':
        return Icons.local_offer_outlined;
      case 'vehicles':
        return Icons.car_rental_outlined;
      case 'promos':
        return Icons.discount_outlined;
      case 'support':
        return Icons.support_agent_outlined;
      case 'notifications':
        return Icons.notifications_active_outlined;
      case 'settings':
        return Icons.settings_outlined;
      case 'rbac':
        return Icons.admin_panel_settings_outlined;
      case 'system':
        return Icons.dns_outlined;
      case 'collections':
        return Icons.table_rows_outlined;
      case 'all':
        return Icons.widgets_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.deepViolet, AppTheme.primaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/adaptive-icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Админ-панель',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Ошибка загрузки админки',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadAll,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  )
                : DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.lightBackground,
                          Color(0xFFF1ECFF),
                          AppTheme.lightSurface
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: RefreshIndicator(
                      onRefresh: _loadAll,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1280),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _opsHero(),
                                  _sectionsNav(),
                                  if (_loadIssues.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _loadIssuesBanner(),
                                  ],
                                  const SizedBox(height: 12),
                                  if (_section == 'overview' ||
                                      _section == 'all') ...[
                                    const Card(
                                      color: Color(0xFFF7FAFF),
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Быстрый старт для новичка',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                                '1. Откройте "Пользователи" и проверьте роли.'),
                                            Text(
                                                '2. В "Водители" одобрите заявки на проверке.'),
                                            Text(
                                                '3. В "Тарифы" проверьте базовые цены.'),
                                            Text(
                                                '4. В "Настройки" установите ключевые параметры.'),
                                            Text(
                                                '5. Для любой таблицы используйте "Коллекции".'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (_dashboardKpis != null) ...[
                                      Card(
                                        color: (_dashboardKpis![
                                                    'notificationDispatchDegraded24h'] ==
                                                true)
                                            ? const Color(0xFFFFF1F0)
                                            : const Color(0xFFF0FFF5),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              Text(
                                                (_dashboardKpis![
                                                            'notificationDispatchDegraded24h'] ==
                                                        true)
                                                    ? 'Dispatch Alert: degraded (24h)'
                                                    : 'Dispatch Alert: healthy (24h)',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: (_dashboardKpis![
                                                              'notificationDispatchDegraded24h'] ==
                                                          true)
                                                      ? const Color(0xFFB42318)
                                                      : const Color(0xFF027A48),
                                                ),
                                              ),
                                              Chip(
                                                  label: Text(
                                                      'Done24h: ${_asInt(_dashboardKpis!['notificationDispatchDone24h'])}')),
                                              Chip(
                                                  label: Text(
                                                      'Failed24h: ${_asInt(_dashboardKpis!['notificationDispatchFailed24h'])}')),
                                              Chip(
                                                label: Text(
                                                  'SuccessRate24h: ${((_dashboardKpis!['notificationDispatchSuccessRate24h'] as num?) ?? 1).toStringAsFixed(2)}',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      _summaryCard(
                                        'Активные заказы',
                                        _asInt(_dashboardKpis!['activeOrders']),
                                        Icons.local_taxi_outlined,
                                      ),
                                      _summaryCard(
                                        'Завершенные заказы',
                                        _asInt(
                                            _dashboardKpis!['completedOrders']),
                                        Icons.check_circle_outline,
                                      ),
                                      _summaryCard(
                                        'Отмененные заказы',
                                        _asInt(
                                            _dashboardKpis!['cancelledOrders']),
                                        Icons.cancel_outlined,
                                      ),
                                      _summaryCard(
                                        'Онлайн водители',
                                        _asInt(
                                            _dashboardKpis!['onlineDrivers']),
                                        Icons.wifi_tethering_outlined,
                                      ),
                                      _summaryCard(
                                        'Активные клиенты (24ч)',
                                        _asInt(_dashboardKpis![
                                            'activeClients24h']),
                                        Icons.person_pin_circle_outlined,
                                      ),
                                      _summaryCard(
                                        'Проблемные заказы',
                                        _asInt(
                                            _dashboardKpis!['problemOrders']),
                                        Icons.report_problem_outlined,
                                      ),
                                      _summaryCard(
                                        'Dispatch queued',
                                        _asInt(_dashboardKpis![
                                            'notificationDispatchQueued']),
                                        Icons.schedule_send_outlined,
                                      ),
                                      _summaryCard(
                                        'Dispatch running',
                                        _asInt(_dashboardKpis![
                                            'notificationDispatchRunning']),
                                        Icons.sync_outlined,
                                      ),
                                      _summaryCard(
                                        'Dispatch failed',
                                        _asInt(_dashboardKpis![
                                            'notificationDispatchFailed']),
                                        Icons.error_outline,
                                      ),
                                      _summaryCard(
                                        'Retries 24h',
                                        _asInt(_dashboardKpis![
                                            'notificationDispatchRetries24h']),
                                        Icons.refresh_outlined,
                                      ),
                                      _summaryCard(
                                        'Retry done 24h',
                                        _asInt(_dashboardKpis![
                                            'notificationDispatchRetryDone24h']),
                                        Icons.task_alt_outlined,
                                      ),
                                    ],
                                    _summaryCard(
                                        'Водители на проверке',
                                        _pendingDrivers.length,
                                        Icons.verified_user_outlined),
                                    _summaryCard('Пользователи', _users.length,
                                        Icons.people_alt_outlined),
                                    _summaryCard('Пополнения', _topups.length,
                                        Icons.account_balance_wallet_outlined),
                                    _summaryCard('Выводы', _payouts.length,
                                        Icons.payments_outlined),
                                    _summaryCard('Заказы', _orders.length,
                                        Icons.receipt_long_outlined),
                                    _summaryCard('Города', _cities.length,
                                        Icons.location_city_outlined),
                                    _summaryCard('Настройки', _settings.length,
                                        Icons.settings_outlined),
                                  ],
                                  const SizedBox(height: 12),
                                  if (_section == 'users' ||
                                      _section == 'all') ...[
                                    _usersSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'drivers' ||
                                      _section == 'all') ...[
                                    _pendingDriversSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'finance' ||
                                      _section == 'all') ...[
                                    _moneyRequestsSection(
                                      title: 'Пополнения',
                                      items: _topups,
                                      pathPrefix: '/admin/topups',
                                    ),
                                    const SizedBox(height: 16),
                                    _moneyRequestsSection(
                                      title: 'Выводы',
                                      items: _payouts,
                                      pathPrefix: '/admin/payouts',
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'orders' ||
                                      _section == 'all') ...[
                                    _ordersSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'cities' ||
                                      _section == 'all') ...[
                                    _citiesSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'tariffs' ||
                                      _section == 'all') ...[
                                    _tariffsSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'vehicles' ||
                                      _section == 'all') ...[
                                    _vehiclesSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'promos' ||
                                      _section == 'all') ...[
                                    _promosSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'support' ||
                                      _section == 'all') ...[
                                    _supportSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'notifications' ||
                                      _section == 'all') ...[
                                    _notificationsSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'settings' ||
                                      _section == 'all') ...[
                                    _settingsSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'rbac' ||
                                      _section == 'all') ...[
                                    _rbacSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'system' ||
                                      _section == 'all') ...[
                                    _systemSection(),
                                    const SizedBox(height: 16),
                                  ],
                                  if (_section == 'collections' ||
                                      _section == 'all') ...[
                                    _collectionsSection(),
                                  ],
                                  const SizedBox(height: 32),
                                ],
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
}
