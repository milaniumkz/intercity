import '../../referral/widgets/referral_profile_card.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/driver_access.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/widgets/car_selector_fields.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/theme_settings_card.dart';
import '../widgets/driver_bottom_nav.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({super.key});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final _carModelCtrl = TextEditingController();
  final _carNumberCtrl = TextEditingController();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _cities = const [];
  List<Map<String, dynamic>> _intercityRoutes = const [];
  String? _selectedCityId;
  String? _routeFromCityId;
  String? _routeToCityId;
  bool _loading = false;
  bool _hasResolvedProfileLoad = false;
  bool _saving = false;
  bool _routeSaving = false;
  bool _acceptCityFixed = true;
  bool _acceptCityAuction = true;
  bool _acceptIntercity = true;
  bool _acceptDelivery = true;
  bool _acceptCargo = true;
  String _message = '';

  bool get _useIntercityBoardUi => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _carModelCtrl.dispose();
    _carNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final me = await ApiClient().get('/me');
      final profileRes = await ApiClient().get('/driver/profile');
      final citiesRes = await ApiClient().get('/geo/cities');
      final routesRes = await ApiClient().get('/driver/intercity/routes');
      final profile = profileRes.data is Map
          ? Map<String, dynamic>.from(profileRes.data as Map)
          : <String, dynamic>{};
      final online = profile['online'] is Map
          ? Map<String, dynamic>.from(profile['online'] as Map)
          : <String, dynamic>{};
      final cities = citiesRes.data is List
          ? (citiesRes.data as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      final routes = routesRes.data is List
          ? (routesRes.data as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
          : <Map<String, dynamic>>[];
      cities.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            ),
      );
      if (!mounted) return;
      setState(() {
        _hasResolvedProfileLoad = true;
        _user =
            me.data is Map ? Map<String, dynamic>.from(me.data as Map) : null;
        _profile = profile;
        _cities = cities;
        _intercityRoutes = routes;
        _carModelCtrl.text = (profile['carModel'] ?? '').toString();
        _carNumberCtrl.text = (profile['carNumber'] ?? '').toString();
        _acceptCityFixed = (profile['acceptCityFixed'] ?? true) == true;
        _acceptCityAuction = (profile['acceptCityAuction'] ?? true) == true;
        _acceptIntercity = (profile['acceptIntercity'] ?? true) == true;
        _acceptDelivery = (profile['acceptDelivery'] ?? true) == true;
        _acceptCargo = (profile['acceptCargo'] ?? true) == true;
        final cityId = (online['cityId'] ?? '').toString().trim();
        _selectedCityId = cityId.isEmpty ? null : cityId;
        _message = 'Профиль водителя загружен';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasResolvedProfileLoad = true;
        _message = errorMessageRu(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ApiClient().post('/driver/profile', data: {
        'carModel': _carModelCtrl.text.trim(),
        'carNumber': _carNumberCtrl.text.trim(),
        'acceptCityFixed': _acceptCityFixed,
        'acceptCityAuction': _acceptCityAuction,
        'acceptIntercity': _acceptIntercity,
        'acceptDelivery': _acceptDelivery,
        'acceptCargo': _acceptCargo,
      });
      await ApiClient().post('/driver/online', data: {
        'isOnline': (_profile?['online'] is Map)
            ? (Map<String, dynamic>.from(
                    _profile!['online'] as Map)['isOnline'] ==
                true)
            : false,
        'cityId': _selectedCityId,
      });
      if (!mounted) return;
      setState(() => _message = 'Профиль водителя сохранен');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _cityNameById(String? id) {
    if (id == null || id.isEmpty) return '';
    final match = _cities.cast<Map<String, dynamic>?>().firstWhere(
          (city) => city?['id']?.toString() == id,
          orElse: () => null,
        );
    return (match?['name'] ?? '').toString().trim();
  }

  Future<void> _addIntercityRoute() async {
    if (_routeSaving) return;
    final fromCity = _cityNameById(_routeFromCityId);
    final toCity = _cityNameById(_routeToCityId);
    if (fromCity.isEmpty || toCity.isEmpty) {
      setState(() => _message = 'Выберите город отправления и назначения');
      return;
    }
    setState(() => _routeSaving = true);
    try {
      await ApiClient().post('/driver/intercity/routes', data: {
        'fromCity': fromCity,
        'toCity': toCity,
      });
      if (!mounted) return;
      setState(() {
        _message = 'Заявка на маршрут добавлена';
        _routeFromCityId = null;
        _routeToCityId = null;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _routeSaving = false);
    }
  }

  Future<void> _deleteIntercityRoute(String id) async {
    try {
      await ApiClient().post('/driver/intercity/routes/$id/delete');
      if (!mounted) return;
      setState(() => _message = 'Маршрут отключен');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    }
  }

  Future<void> _logout() async {
    await ApiClient().clearTokens();
    await AppPreferences.clearLastAppMode();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (!mounted) return;
    await _load();
  }

  void _closeProfile() {
    goBackOr(context, fallback: '/driver/home');
  }

  Future<void> _showProfileDialog({
    required String title,
    required String message,
    required IconData icon,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, color: AppTheme.primaryColor),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  void _openSupportInfo() {
    _showProfileDialog(
      icon: Icons.support_agent_rounded,
      title: 'Поддержка водителя',
      message:
          'Если не приходят заказы, проверьте онлайн-статус, баланс, город работы и включённые типы заказов. По спорным ситуациям укажите телефон, ID заказа и описание проблемы.',
    );
  }

  void _openAboutInfo() {
    _showProfileDialog(
      icon: Icons.info_outline_rounded,
      title: 'InterCity Driver',
      message:
          'Профиль водителя управляет автомобилем, городом работы, типами заказов, верификацией, балансом и межгородними заявками.',
    );
  }

  Color _statusColor(String? status) {
    final s = (status ?? '').toUpperCase();
    if (isApprovedDriverStatus(s)) return Colors.greenAccent;
    if (s == 'REJECTED') return Colors.redAccent;
    return Colors.orangeAccent;
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return ICCard(padding: padding ?? const EdgeInsets.all(18), child: child);
  }

  InputDecoration _inputDecoration({
    required String label,
    IconData? icon,
    String? helperText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      prefixIcon:
          icon == null ? null : Icon(icon, color: AppTheme.primaryColor),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFF8F6FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.4),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: _closeProfile,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Expanded(
          child: ICBrandHeader(
            compact: true,
            subtitle: 'Профиль водителя',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useBoardProfile = _useIntercityBoardUi;
    final status = _profile?['status']?.toString();
    final statusLabel = _hasResolvedProfileLoad
        ? driverAccessMessageRu(status)
        : 'Загружаем профиль водителя';

    if (useBoardProfile) {
      return _boardDriverProfileScreen(statusLabel);
    }

    if (!_hasResolvedProfileLoad) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        bottomNavigationBar: const DriverBottomNav(currentIndex: 4),
        body: ICPremiumBackground(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _header(context),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Загружаем профиль водителя',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const LinearProgressIndicator(color: AppTheme.primaryColor),
                    const SizedBox(height: 10),
                    Text(
                      'Получаем данные профиля, автомобиля и статуса.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 4),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ICPremiumBackground(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _header(context),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    color: AppTheme.primaryColor,
                    backgroundColor:
                        theme.colorScheme.outline.withValues(alpha: 0.16),
                  ),
                ),
              _driverProfileHero(statusLabel),
              const SizedBox(height: 12),
              const _DriverProfileProgressStrip(),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_user?['name'] ?? 'Водитель').toString(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (_user?['phone'] ?? '-').toString(),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(22)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.directions_car_filled_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Автомобиль',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Данные авто используются в заказах',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _carModelCtrl,
                            readOnly: true,
                            decoration: _inputDecoration(
                              label: 'Автомобиль',
                              icon: Icons.directions_car_outlined,
                              helperText:
                                  'Марка, модель и цвет выбираются ниже',
                            ),
                          ),
                          const SizedBox(height: 10),
                          CarSelectorFields(
                            initialComposedValue: _carModelCtrl.text,
                            requiredFields: true,
                            onChanged: (value) {
                              _carModelCtrl.text = value.displayValue;
                            },
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _carNumberCtrl,
                            decoration: _inputDecoration(
                              label: 'Госномер',
                              icon: Icons.confirmation_number_outlined,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _driverCityWorkCard(),
                          const SizedBox(height: 10),
                          _driverIntercityRoutesCard(),
                          const SizedBox(height: 10),
                          _serviceModesCard(),
                          const SizedBox(height: 14),
                          ICGradientButton(
                            label:
                                _saving ? 'Сохраняем...' : 'Сохранить профиль',
                            loading: _saving,
                            onPressed: _saving ? null : _saveProfile,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const ThemeSettingsCard(),
              const SizedBox(height: 12),
              _quickActionsCard(),
              const SizedBox(height: 10),
              if (_message.isNotEmpty) ICPremiumInfoBanner(text: _message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardDriverProfileScreen(String statusLabel) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = (_user?['name'] ?? 'Водитель').toString();
    final phone = (_user?['phone'] ?? 'Телефон не указан').toString();
    final car = (_profile?['carModel'] ?? _carModelCtrl.text).toString().trim();
    final number =
        (_profile?['carNumber'] ?? _carNumberCtrl.text).toString().trim();
    final rating = (_profile?['rating'] ?? '—').toString();
    final trips = (_profile?['completedTrips'] ?? '0').toString();
    final online = _profile?['online'] is Map &&
        (Map<String, dynamic>.from(_profile!['online'] as Map)['isOnline'] ==
            true);
    final bg = isDark ? AppTheme.darkBackground : AppTheme.lightBackground;
    final surface = isDark ? const Color(0xFF11101D) : Colors.white;
    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 4),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              ReferralProfileCard(user: _user),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: _closeProfile,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Профиль',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(color: AppTheme.primaryColor),
                ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                  boxShadow: [
                    if (!isDark)
                      const BoxShadow(
                        color: Color(0x182C174C),
                        blurRadius: 18,
                        offset: Offset(0, 10),
                      ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
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
                            size: 38,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                phone,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _boardChip(Icons.star_rounded, rating),
                                  _boardChip(
                                      Icons.route_rounded, '$trips поездок'),
                                  _boardChip(
                                    online
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    online ? 'Онлайн' : 'Оффлайн',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_car_filled_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              [
                                if (car.isNotEmpty) car,
                                if (number.isNotEmpty) number,
                                if (car.isEmpty && number.isEmpty)
                                  'Автомобиль не указан',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _boardDriverSection(
                children: [
                  _boardProfileRow(
                    Icons.verified_user_outlined,
                    'Документы и проверка',
                    statusLabel,
                    () => _openAndRefresh('/driver/verification'),
                  ),
                  _boardProfileRow(
                    Icons.account_balance_wallet_outlined,
                    'Кошелёк',
                    'Баланс, пополнение и вывод',
                    () => _openAndRefresh('/driver/wallet'),
                  ),
                  _boardProfileRow(
                    Icons.alt_route_rounded,
                    'Межгородние заявки',
                    'Доступные поездки и комиссии',
                    () => _openAndRefresh('/driver/trip-create'),
                  ),
                  _boardProfileRow(
                    Icons.support_agent_rounded,
                    'Поддержка',
                    'Помощь по заказам и балансу',
                    _openSupportInfo,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _boardDriverSection(
                children: [
                  _boardProfileRow(
                    Icons.switch_account_rounded,
                    'Режим пассажира',
                    'Перейти к заказу поездки',
                    () async {
                      await AppModeManager.rememberPassengerMode();
                      if (!mounted) return;
                      context.go('/order');
                    },
                  ),
                  _boardProfileRow(
                    Icons.info_outline_rounded,
                    'О приложении',
                    'Версия и настройки профиля',
                    _openAboutInfo,
                  ),
                  _boardProfileRow(
                    Icons.logout_rounded,
                    'Выйти из аккаунта',
                    'Завершить текущую сессию',
                    _logout,
                    danger: true,
                  ),
                ],
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 12),
                ICPremiumInfoBanner(text: _message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardDriverSection({required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.10)),
      ),
      child: Column(children: children),
    );
  }

  Widget _boardProfileRow(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger ? Colors.redAccent : AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: danger ? color : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _driverProfileHero(String statusLabel) {
    final status = _profile?['status']?.toString();
    final accent = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF271044), Color(0xFF100B1F)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x552C174C),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
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
              Icons.drive_eta_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (_user?['name'] ?? 'Водитель').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (_user?['phone'] ?? '-').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ).copyWith(color: accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: () => _openAndRefresh('/driver/verification'),
            icon: const Icon(Icons.verified_user_rounded),
            tooltip: 'Проверка',
          ),
        ],
      ),
    );
  }

  Widget _driverCityWorkCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
      ),
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
                      color: AppTheme.primaryColor.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Город работы',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Заказы будут подбираться по этому городу',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _cities.any((city) => city['id'] == _selectedCityId)
                ? _selectedCityId
                : null,
            isExpanded: true,
            decoration: _inputDecoration(
              label: 'Город',
              icon: Icons.radar_rounded,
              helperText: 'Выберите город, где хотите получать заказы',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Определять автоматически'),
              ),
              ..._cities.map(
                (city) => DropdownMenuItem<String?>(
                  value: city['id']?.toString(),
                  child: Text(
                    [
                      city['name']?.toString() ?? '',
                      city['region']?.toString() ?? '',
                    ].where((part) => part.trim().isNotEmpty).join(', '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _selectedCityId = value),
          ),
        ],
      ),
    );
  }

  Widget _driverIntercityRoutesCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cityItems = _cities
        .map(
          (city) => DropdownMenuItem<String>(
            value: city['id']?.toString(),
            child: Text(
              (city['name'] ?? '').toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Межгород-маршруты',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Межгород-заказы приходят только по выбранным маршрутам',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cities.any((city) => city['id'] == _routeFromCityId)
                ? _routeFromCityId
                : null,
            isExpanded: true,
            decoration: _inputDecoration(
              label: 'Откуда',
              icon: Icons.trip_origin_rounded,
            ),
            items: cityItems,
            onChanged: (value) => setState(() => _routeFromCityId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _cities.any((city) => city['id'] == _routeToCityId)
                ? _routeToCityId
                : null,
            isExpanded: true,
            decoration: _inputDecoration(
              label: 'Куда',
              icon: Icons.location_on_rounded,
            ),
            items: cityItems,
            onChanged: (value) => setState(() => _routeToCityId = value),
          ),
          const SizedBox(height: 10),
          ICGradientButton(
            label: _routeSaving ? 'Отправляем...' : 'Подать заявку на маршрут',
            loading: _routeSaving,
            onPressed: _routeSaving ? null : _addIntercityRoute,
          ),
          if (_intercityRoutes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._intercityRoutes.map((route) {
              final id = (route['id'] ?? '').toString();
              final from = (route['fromCity'] ?? '').toString();
              final to = (route['toCity'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.035)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.route_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$from → $to',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: id.isEmpty
                          ? null
                          : () => unawaited(_deleteIntercityRoute(id)),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Отключить маршрут',
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _serviceModesCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
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
                child: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Какие заказы получать',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Включенные типы будут приходить на главный экран',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _serviceSwitch(
            icon: Icons.local_taxi_rounded,
            title: 'Город',
            subtitle: 'Фиксированные заказы по городу',
            value: _acceptCityFixed,
            onChanged: (value) => setState(() => _acceptCityFixed = value),
          ),
          _serviceSwitch(
            icon: Icons.gavel_rounded,
            title: 'Аукцион',
            subtitle: 'Городские заказы с предложением цены',
            value: _acceptCityAuction,
            onChanged: (value) => setState(() => _acceptCityAuction = value),
          ),
          _serviceSwitch(
            icon: Icons.alt_route_rounded,
            title: 'Межгород',
            subtitle: 'Заявки пассажиров на межгород',
            value: _acceptIntercity,
            onChanged: (value) => setState(() => _acceptIntercity = value),
          ),
          _serviceSwitch(
            icon: Icons.inventory_2_rounded,
            title: 'Доставка',
            subtitle: 'Доставка по городу и между городами',
            value: _acceptDelivery,
            onChanged: (value) => setState(() => _acceptDelivery = value),
          ),
          _serviceSwitch(
            icon: Icons.local_shipping_rounded,
            title: 'Грузовые',
            subtitle: 'Грузовые и крупные заказы',
            value: _acceptCargo,
            onChanged: (value) => setState(() => _acceptCargo = value),
          ),
        ],
      ),
    );
  }

  Widget _serviceSwitch({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withValues(alpha: 0.10),
            ),
            child: Icon(icon, color: AppTheme.primaryColor, size: 20),
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
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _quickActionsCard() {
    return _card(
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
                child: const Icon(Icons.dashboard_customize_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Быстрые действия',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _quickAction(
            icon: Icons.verified_user_outlined,
            title: 'Верификация',
            subtitle: 'Документы и проверка',
            onTap: () => _openAndRefresh('/driver/verification'),
          ),
          _quickAction(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Кошелёк',
            subtitle: 'Баланс, пополнение и вывод',
            onTap: () => _openAndRefresh('/driver/wallet'),
          ),
          _quickAction(
            icon: Icons.alt_route_rounded,
            title: 'Межгород',
            subtitle: 'Поездки, заявки и поднятие в топ',
            onTap: () => _openAndRefresh('/driver/trip-create'),
          ),
          _quickAction(
            icon: Icons.switch_account_rounded,
            title: 'Режим пассажира',
            subtitle: 'Перейти к оформлению заказа',
            onTap: () async {
              await AppModeManager.rememberPassengerMode();
              if (!mounted) return;
              context.go('/order');
            },
          ),
          _quickAction(
            icon: Icons.support_agent_rounded,
            title: 'Поддержка',
            subtitle: 'Помощь по заказам, балансу и профилю',
            onTap: _openSupportInfo,
          ),
          _quickAction(
            icon: Icons.info_outline_rounded,
            title: 'О приложении',
            subtitle: 'Что настраивается в профиле водителя',
            onTap: _openAboutInfo,
          ),
          _quickAction(
            icon: Icons.logout_rounded,
            title: 'Выйти',
            subtitle: 'Завершить текущую сессию',
            danger: true,
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = danger ? Colors.redAccent : AppTheme.primaryColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.16)),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: danger ? color : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverProfileProgressStrip extends StatelessWidget {
  const _DriverProfileProgressStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const steps = [
      (Icons.person_rounded, 'Профиль'),
      (Icons.directions_car_filled_rounded, 'Авто'),
      (Icons.verified_user_rounded, 'Проверка'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          if (!isDark)
            const BoxShadow(
              color: Color(0x142C174C),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
        ],
      ),
      child: Row(
        children: steps.map((step) {
          final index = steps.indexOf(step);
          final selected = index < 2;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
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
                              : AppTheme.primaryColor.withValues(alpha: 0.08),
                        ),
                        child: Icon(
                          step.$1,
                          size: 20,
                          color: selected
                              ? Colors.white
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.$2,
                        style: TextStyle(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != steps.length - 1)
                  Container(
                    width: 22,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: AppTheme.primaryColor.withValues(alpha: 0.22),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
