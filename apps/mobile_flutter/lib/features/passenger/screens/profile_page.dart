import '../../referral/widgets/referral_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/driver_access.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/localization_service.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/theme_settings_card.dart';
import '../widgets/passenger_bottom_nav.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, this.routeStage});

  final String? routeStage;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _driverProfile;
  String _message = '';
  bool _loading = false;
  bool _driverSwitchLoading = false;
  bool _cityLoading = false;
  bool _cityOptionsLoading = false;
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _cities = const [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadMe();
    _loadCities();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 12), (_) => _loadMe(silent: true));
  }

  bool _routeStage(String marker) {
    return widget.routeStage == marker || routeHas(context, '$marker=1');
  }

  bool get _useIntercityBoardUi => true;

  Future<void> _createSupportRequestDraft() async {
    final phone = (_user?['phone'] ?? '').toString();
    final text = 'Обращение в поддержку InterCity\n'
        '${phone.trim().isEmpty ? '' : 'Телефон: $phone\n'}'
        'Описание проблемы: ';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _message = 'Шаблон обращения скопирован');
  }

  Future<void> _callSupport() async {
    String phone = '';
    if (phone.isEmpty) {
      if (!mounted) return;
      setState(() => _message = 'Телефон поддержки не настроен');
      return;
    }
    final opened = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    setState(
      () => _message = opened
          ? 'Открываем звонок в поддержку'
          : 'Телефон поддержки скопирован',
    );
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: phone));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMe(silent: true);
    }
  }

  Future<void> _loadMe({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final api = ApiClient();
      final meRes = await api.get('/me');
      Map<String, dynamic>? driverProfile;
      try {
        final driverRes = await api.get('/driver/profile');
        if (driverRes.data is Map) {
          driverProfile = Map<String, dynamic>.from(driverRes.data as Map);
        }
      } catch (_) {
        driverProfile = null;
      }
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(meRes.data as Map);
        _driverProfile = driverProfile;
        if (!silent) {
          _message = LocalizationService.translate(
            'Профиль обновлён',
            'Профиль жаңартылды',
          );
        }
      });
      await _cacheCurrentCityFromUser();
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _message = errorMessageRu(e));
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cacheCurrentCityFromUser() async {
    final cityId = (_user?['cityId'] ?? '').toString().trim();
    final city = _user?['city'];
    final cityName = city is Map ? (city['name'] ?? '').toString().trim() : '';
    if (cityId.isEmpty) {
      await AppPreferences.clearCurrentCityId();
      await AppPreferences.clearCurrentCityName();
      return;
    }
    await AppPreferences.setCurrentCityId(cityId);
    if (cityName.isNotEmpty) {
      await AppPreferences.setCurrentCityName(cityName);
    }
  }

  Future<void> _loadCities() async {
    try {
      final res = await ApiClient().get('/geo/cities');
      if (!mounted) return;
      setState(() {
        _cities = List<Map<String, dynamic>>.from(
          List<dynamic>.from(res.data as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      });
    } catch (_) {
      // Non-blocking for the profile page.
    }
  }

  Future<void> _saveCurrentCity(String? cityId) async {
    if (!mounted) return;
    setState(() => _cityLoading = true);
    try {
      final res = await ApiClient().patch(
        '/auth/me/city',
        data: <String, dynamic>{'cityId': cityId},
      );
      if (!mounted) return;
      setState(() {
        _user = Map<String, dynamic>.from(res.data as Map);
        _message = LocalizationService.translate(
          'Город сохранён',
          'Қала сақталды',
        );
      });
      await _cacheCurrentCityFromUser();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _cityLoading = false);
    }
  }

  Future<void> _autoDetectCity() async {
    if (!mounted) return;
    setState(() => _cityLoading = true);
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          LocalizationService.translate(
            'Доступ к геолокации не выдан',
            'Геолокацияға рұқсат берілмеген',
          ),
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final reverse = await ApiClient().get(
        '/geo/reverse',
        queryParameters: {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      );
      final cityId = (reverse.data['cityId'] ?? '').toString().trim();
      if (cityId.isEmpty) {
        throw Exception(
          LocalizationService.translate(
            'Не удалось определить город автоматически',
            'Қаланы автоматты түрде анықтау мүмкін болмады',
          ),
        );
      }
      await _saveCurrentCity(cityId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cityLoading = false;
        _message = errorMessageRu(e);
      });
    }
  }

  Future<void> _openCityPicker() async {
    if (_cityOptionsLoading || _cities.isNotEmpty) {
      // noop
    } else {
      setState(() => _cityOptionsLoading = true);
      await _loadCities();
      if (mounted) {
        setState(() => _cityOptionsLoading = false);
      }
    }
    if (!mounted) return;
    final selectedCityId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final currentCityId = (_user?['cityId'] ?? '').toString();
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B0817) : Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.14),
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
                              LocalizationService.translate(
                                'Город поиска',
                                'Іздеу қаласы',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LocalizationService.translate(
                                'Адреса будут искаться в выбранном городе и рядом с ним',
                                'Мекенжайлар таңдалған қалада және маңында ізделеді',
                              ),
                              style: const TextStyle(
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.radar_rounded,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          LocalizationService.translate(
                            'Поиск адресов ограничен радиусом 50 км от города.',
                            'Мекенжай іздеу қаладан 50 км радиуспен шектелген.',
                          ),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _cities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final city = _cities[index];
                      final cityId = (city['id'] ?? '').toString();
                      final selected = currentCityId == cityId;
                      final region = (city['region'] ?? '').toString().trim();
                      return Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(cityId),
                          borderRadius: BorderRadius.circular(18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? const LinearGradient(
                                      colors: [
                                        AppTheme.secondaryColor,
                                        AppTheme.primaryColor,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: selected
                                  ? null
                                  : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: isDark ? 0.18 : 0.55),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : AppTheme.primaryColor
                                        .withValues(alpha: 0.10),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : AppTheme.primaryColor
                                            .withValues(alpha: 0.12),
                                  ),
                                  child: Icon(
                                    Icons.place_outlined,
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.primaryColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (city['name'] ?? '').toString(),
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      if (region.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          region,
                                          style: TextStyle(
                                            color: selected
                                                ? Colors.white70
                                                : theme.colorScheme
                                                    .onSurfaceVariant,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.white,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedCityId == null || selectedCityId.isEmpty) return;
    await _saveCurrentCity(selectedCityId);
  }

  Future<void> _logout() async {
    await AppModeManager.rememberPassengerMode();
    await ApiClient().clearTokens();
    if (!mounted) return;
    context.go('/login');
  }

  String _referralLinkFromUser(Map<String, dynamic>? user) {
    final code = (user?['refCode'] ?? '').toString();
    final existingLink = (user?['refLink'] ?? '').toString();
    if (existingLink.contains('/ref/') || existingLink.contains('ref=')) {
      return existingLink;
    }
    if (code.isEmpty) return '';
    return '${AppConstants.publicWebUrl}/#/ref/$code';
  }

  // ignore: unused_element
  Future<void> _copyReferralLink() async {
    final link = _referralLinkFromUser(_user);
    if (link.isEmpty) {
      if (!mounted) return;
      setState(() {
        _message = LocalizationService.translate(
          'Реферальная ссылка пока не создана. Обновите профиль позже.',
          'Реферал сілтемесі әлі жасалмаған. Профильді кейін жаңартыңыз.',
        );
      });
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    setState(() {
      _message = LocalizationService.translate(
        'Реферальная ссылка скопирована',
        'Реферал сілтемесі көшірілді',
      );
    });
  }

  Future<void> _openAndRefresh(String route) async {
    await context.push(route);
    if (!mounted) return;
    await _loadMe(silent: true);
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
            child: Text(LocalizationService.translate('Понятно', 'Түсінікті')),
          ),
        ],
      ),
    );
  }

  void _openFavoritesInfo() {
    _showProfileDialog(
      icon: Icons.location_on_outlined,
      title: LocalizationService.translate(
        'Избранные адреса',
        'Таңдаулы мекенжайлар',
      ),
      message: LocalizationService.translate(
        'Дом, работа и последние адреса сохраняются автоматически после поездок. В следующем заказе их можно выбрать в поиске адреса.',
        'Үй, жұмыс және соңғы мекенжайлар сапарлардан кейін автоматты сақталады. Келесі тапсырыста оларды мекенжай іздеуінен таңдауға болады.',
      ),
    );
  }

  void _openPaymentInfo() {
    _showProfileDialog(
      icon: Icons.credit_card_rounded,
      title: LocalizationService.translate(
        'Способы оплаты',
        'Төлем тәсілдері',
      ),
      message: LocalizationService.translate(
        'В заказе доступны наличные и безналичная оплата. Карта подключается при выборе безналичной оплаты в оформлении заказа.',
        'Тапсырыста қолма-қол және қолма-қолсыз төлем қолжетімді. Карта тапсырыс рәсімдеу кезінде қолма-қолсыз төлем таңдалғанда қосылады.',
      ),
    );
  }

  void _openSupportInfo() {
    _showProfileDialog(
      icon: Icons.support_agent_rounded,
      title: LocalizationService.translate('Поддержка', 'Қолдау'),
      message: LocalizationService.translate(
        'Если возникла проблема, напишите администратору или диспетчеру. В обращении укажите телефон аккаунта, ID заказа и краткое описание ситуации.',
        'Мәселе болса, әкімшіге немесе диспетчерге жазыңыз. Өтініште аккаунт телефонын, тапсырыс ID және жағдайдың қысқаша сипаттамасын көрсетіңіз.',
      ),
    );
  }

  void _openAboutInfo() {
    _showProfileDialog(
      icon: Icons.info_outline_rounded,
      title: 'InterCity',
      message: LocalizationService.translate(
        'InterCity — сервис городских, межгородних поездок и доставки.',
        'InterCity — қала, қалааралық сапарлар және жеткізу сервисі.',
      ),
    );
  }

  Future<void> _switchToDriverMode() async {
    setState(() => _driverSwitchLoading = true);
    try {
      final res = await ApiClient().get('/driver/profile');
      final profile =
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      final status = profile?['status']?.toString();
      final rejectionReason = profile?['rejectionReason']?.toString();
      if (isApprovedDriverStatus(status)) {
        await AppModeManager.rememberDriverMode();
        if (!mounted) return;
        context.go('/driver/home');
        return;
      }
      if (!mounted) return;
      await AppModeManager.rememberPassengerMode();
      if (!mounted) return;
      final message = driverAccessMessageRu(
        status,
        rejectionReason: rejectionReason,
      );
      setState(() {
        _driverProfile = profile;
        _message = message;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ));
      if ((status ?? '').toUpperCase() == 'REJECTED') {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        await _openAndRefresh('/driver/verification');
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        context.go('/order');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _driverSwitchLoading = false);
    }
  }

  Future<void> _openDriverModeEntry() async {
    final status = _driverProfile?['status']?.toString();
    if (isApprovedDriverStatus(status)) {
      await _switchToDriverMode();
      return;
    }
    if ((status ?? '').toUpperCase() == 'PENDING') {
      await AppModeManager.rememberPassengerMode();
      if (!mounted) return;
      final message = driverAccessMessageRu(status);
      setState(() => _message = message);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      context.go('/order');
      return;
    }
    await _openAndRefresh(
        _driverProfile == null ? '/driver/profile' : '/driver/verification');
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
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

  Color _driverStatusColor(String? status) {
    final s = (status ?? '').toUpperCase();
    if (isApprovedDriverStatus(s)) return Colors.greenAccent;
    if (s == 'REJECTED') return Colors.redAccent;
    if (s == 'PENDING') return Colors.orangeAccent;
    return Colors.white70;
  }

  String _driverStatusTitle(String? status) {
    final s = (status ?? '').toUpperCase();
    if (isApprovedDriverStatus(s)) {
      return LocalizationService.translate(
        'Режим водителя доступен',
        'Жүргізуші режимі қолжетімді',
      );
    }
    if (s == 'PENDING') {
      return LocalizationService.translate(
        'Заявка водителя на проверке',
        'Жүргізуші өтінімі тексерілуде',
      );
    }
    if (s == 'REJECTED') {
      return LocalizationService.translate(
        'Профиль водителя отклонён',
        'Жүргізуші профилі қабылданбады',
      );
    }
    return LocalizationService.translate(
      'Водительский профиль не создан',
      'Жүргізуші профилі құрылмаған',
    );
  }

  String _driverStatusBody(String? status) {
    final s = (status ?? '').toUpperCase();
    if (isApprovedDriverStatus(s)) {
      return LocalizationService.translate(
        'Профиль водителя одобрен. Можно сразу перейти в кабинет водителя.',
        'Жүргізуші профилі мақұлданды. Бірден жүргізуші кабинетіне өте аласыз.',
      );
    }
    if (s == 'PENDING') {
      return LocalizationService.translate(
        'Анкета создана. Дождитесь одобрения или откройте профиль водителя, чтобы проверить данные и документы.',
        'Өтінім жасалды. Мақұлдауды күтіңіз немесе деректер мен құжаттарды тексеру үшін жүргізуші профилін ашыңыз.',
      );
    }
    if (s == 'REJECTED') {
      return LocalizationService.translate(
        'Откройте профиль водителя, исправьте данные и повторно пройдите верификацию.',
        'Жүргізуші профилін ашып, деректерді түзетіп, қайта тексеруден өтіңіз.',
      );
    }
    return LocalizationService.translate(
      'Чтобы стать водителем, не нужно выходить из пассажира. Просто заполните профиль водителя в этом аккаунте.',
      'Жүргізуші болу үшін жолаушы режимінен шығудың қажеті жоқ. Осы аккаунтта жүргізуші профилін толтырыңыз.',
    );
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'DRIVER':
        return LocalizationService.translate('Водитель', 'Жүргізуші');
      case 'ADMIN':
        return LocalizationService.translate('Администратор', 'Әкімші');
      default:
        return LocalizationService.translate('Пассажир', 'Жолаушы');
    }
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(18);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: primary
                ? LinearGradient(
                    colors: [colorScheme.primary, colorScheme.secondary],
                  )
                : null,
            color: primary
                ? null
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
            border: primary
                ? null
                : Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.42),
                  ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.22),
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
                color: primary ? colorScheme.onPrimary : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        primary ? colorScheme.onPrimary : colorScheme.onSurface,
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

  Widget _boardSupportScreen() {
    final theme = _boardTheme();
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 3),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => goBackOr(context, fallback: '/profile'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Поддержка',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                height: 170,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7E20D8), Color(0xFF3B0B77)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Мы здесь,\nчтобы помочь',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              height: 1.08,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Ответим на ваши вопросы\nи решим любые проблемы.',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              height: 1.22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 86,
                      height: 74,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Популярные вопросы',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _boardSupportQuestion('Как отменить поездку?'),
              _boardSupportQuestion('Как изменить способ оплаты?'),
              _boardSupportQuestion('Как получить чек?'),
              _boardSupportQuestion('Проблема с водителем'),
              _boardSupportQuestion('Тарифы и цены'),
              const SizedBox(height: 14),
              ICGradientButton(
                label: 'Создать обращение',
                onPressed: _createSupportRequestDraft,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _callSupport,
                icon: const Icon(Icons.phone_rounded),
                label: const Text('Позвонить в поддержку'),
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

  Widget _boardSupportQuestion(String text) {
    final theme = _boardTheme();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF11101D)
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openSupportAnswer(text),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
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
      ),
    );
  }

  void _openSupportAnswer(String question) {
    final answer = switch (question) {
      'Как отменить поездку?' =>
        'Откройте активную поездку и нажмите отмену. Условия зависят от статуса заказа.',
      'Как изменить способ оплаты?' =>
        'До подтверждения заказа способ оплаты меняется на экране оплаты.',
      'Как получить чек?' =>
        'Чек доступен в истории поездок после завершения заказа.',
      'Проблема с водителем' =>
        'Создайте обращение с номером поездки или позвоните в поддержку.',
      'Тарифы и цены' => 'Цена зависит от маршрута, класса авто и типа заказа.',
      _ => 'Создайте обращение, и поддержка ответит по этому вопросу.',
    };
    setState(() => _message = answer);
  }

  ThemeData _boardTheme() {
    if (routeHas(context, 'dark=1')) {
      return AppTheme.darkTheme;
    }
    return Theme.of(context);
  }

  Widget _boardSettingsScreen() {
    final theme = _boardTheme();
    final isDark = theme.brightness == Brightness.dark;
    final themeMode = ref.watch(themeControllerProvider);
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 3),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => goBackOr(context, fallback: '/profile'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Настройки',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 12),
                ICPremiumInfoBanner(text: _message),
              ],
              const SizedBox(height: 24),
              _boardSettingsSection(
                title: 'Аккаунт',
                children: [
                  _boardSettingsRow(
                    icon: Icons.add_rounded,
                    title: (_user?['phone'] ?? 'Телефон не указан').toString(),
                    value: '',
                    onTap: () => setState(
                      () =>
                          _message = 'Телефон меняется через профиль аккаунта.',
                    ),
                  ),
                  _boardSettingsRow(
                    icon: Icons.credit_card_rounded,
                    title: 'Способы оплаты',
                    value: '',
                    onTap: () => context.go('/profile/payments'),
                  ),
                  _boardSettingsRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Уведомления',
                    value: '',
                    onTap: () => setState(
                      () => _message =
                          'Уведомления управляются настройками устройства.',
                    ),
                  ),
                  _boardSettingsRow(
                    icon: Icons.verified_user_outlined,
                    title: 'Безопасность',
                    value: '',
                    onTap: () => setState(
                      () => _message = 'Вход защищён паролем и токеном сессии.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _boardSettingsSection(
                title: 'Предпочтения',
                children: [
                  _boardSettingsRow(
                    icon: Icons.language_rounded,
                    title: 'Язык',
                    value: 'Русский',
                    onTap: () => setState(
                      () => _message = 'Сейчас выбран русский язык.',
                    ),
                  ),
                  _boardSettingsRow(
                    icon: Icons.shield_outlined,
                    title: 'Единицы расстояния',
                    value: 'Километры',
                    onTap: () => setState(
                      () => _message = 'Расстояние отображается в километрах.',
                    ),
                  ),
                  _boardSettingsRow(
                    icon: Icons.dark_mode_outlined,
                    title: 'Тема приложения',
                    value: '',
                    onTap: () => setState(
                      () => _message = 'Выберите тему ниже.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF11101D) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _boardThemeOption(
                            icon: Icons.light_mode_rounded,
                            label: 'Светлая',
                            selected: themeMode == AppThemeMode.light,
                            onTap: () => _setBoardTheme(AppThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _boardThemeOption(
                            icon: Icons.dark_mode_rounded,
                            label: 'Тёмная',
                            selected: themeMode == AppThemeMode.dark,
                            onTap: () => _setBoardTheme(AppThemeMode.dark),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _boardThemeOption(
                            icon: Icons.phone_iphone_rounded,
                            label: 'Системная',
                            selected: themeMode == AppThemeMode.system,
                            onTap: () => _setBoardTheme(AppThemeMode.system),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Тема будет меняться в зависимости от настроек системы.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color:
                            isDark ? Colors.white70 : const Color(0xFF7C7590),
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardSettingsSection({
    required String title,
    required List<Widget> children,
  }) {
    final isDark = _boardTheme().brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF4E4962),
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  Widget _boardSettingsRow({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    final theme = _boardTheme();
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 58,
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF11101D) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark
                          ? theme.colorScheme.onSurface
                          : const Color(0xFF141326),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (value.isNotEmpty)
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? theme.colorScheme.onSurfaceVariant
                            : const Color(0xFF7C7590),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark
                  ? theme.colorScheme.onSurfaceVariant
                  : const Color(0xFF7C7590),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBoardTheme(AppThemeMode mode) async {
    setState(() => _message = 'Тема изменена: ${_themeModeLabel(mode)}');
    await ref.read(themeControllerProvider.notifier).setThemeMode(mode);
  }

  String _themeModeLabel(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'светлая';
      case AppThemeMode.dark:
        return 'тёмная';
      case AppThemeMode.system:
        return 'системная';
    }
  }

  Widget _boardThemeOption({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = _boardTheme().brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 82,
        decoration: BoxDecoration(
          color: isDark
              ? (selected
                  ? AppTheme.primaryColor.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.04))
              : (selected ? const Color(0xFFF7F1FF) : const Color(0xFFFBFAFF)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.10),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryColor
                    : (isDark
                        ? const Color(0xFF2B2640)
                        : const Color(0xFF141326)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppTheme.primaryColor
                    : (isDark ? Colors.white70 : const Color(0xFF4E4962)),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_routeStage('settings')) {
      if (routeHas(context, 'dark=1')) {
        return Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (_) => _boardSettingsScreen()),
        );
      }
      return _boardSettingsScreen();
    }
    if (_routeStage('support')) {
      if (routeHas(context, 'dark=1')) {
        return Theme(
          data: AppTheme.darkTheme,
          child: Builder(builder: (_) => _boardSupportScreen()),
        );
      }
      return _boardSupportScreen();
    }
    if (_useIntercityBoardUi) {
      return _boardPassengerProfileScreen();
    }

    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LocalizationService.notifier,
      builder: (context, _, __) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final user = _user;
        final role = (user?['role'] ?? 'PASSENGER').toString();
        final driverStatus = _driverProfile?['status']?.toString();
        final driverAccent = _driverStatusColor(driverStatus);
        final hasDriverProfile = _driverProfile != null;
        final canOpenDriverMode = isApprovedDriverStatus(driverStatus);

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          bottomNavigationBar: const PassengerBottomNav(currentIndex: 3),
          body: RefreshIndicator(
            onRefresh: _loadMe,
            color: colorScheme.primary,
            child: ICPremiumBackground(
              padding: EdgeInsets.zero,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                children: [
                  ReferralProfileCard(user: _user),
                  const SizedBox(height: 12),
                  if (_loading)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: const LinearProgressIndicator(minHeight: 4),
                    ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [
                          theme.brightness == Brightness.dark
                              ? const Color(0xFF211138)
                              : Colors.white,
                          theme.brightness == Brightness.dark
                              ? const Color(0xFF0F0B1C)
                              : const Color(0xFFF8F3FF),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.12),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                AppTheme.secondaryColor,
                                AppTheme.primaryColor,
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.26),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (user?['name'] ??
                                        LocalizationService.translate(
                                          'Пассажир',
                                          'Жолаушы',
                                        ))
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (user?['phone'] ?? '-').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _infoChip(
                                    _roleLabel(role),
                                    AppTheme.primaryColor,
                                  ),
                                  _infoChip(
                                    'Premium',
                                    AppTheme.secondaryColor,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _loadMe,
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.04)
                                : const Color(0xFFF8F6FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color:
                                  colorScheme.primary.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.10),
                                ),
                                child: Icon(
                                  Icons.my_location_rounded,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (((_user?['city'] as Map?)?['name']) ??
                                              LocalizationService.translate(
                                                'Город не выбран',
                                                'Қала таңдалмаған',
                                              ))
                                          .toString(),
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (((_user?['city'] as Map?)?['region']) ??
                                              '')
                                          .toString(),
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _quickAction(
                                icon: Icons.my_location_rounded,
                                label: _cityLoading
                                    ? LocalizationService.translate(
                                        'Определяем...',
                                        'Анықталуда...',
                                      )
                                    : LocalizationService.translate(
                                        'Определить автоматически',
                                        'Автоматты анықтау',
                                      ),
                                onTap: _cityLoading ? () {} : _autoDetectCity,
                                primary: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _quickAction(
                                icon: Icons.edit_location_alt_rounded,
                                label: _cityOptionsLoading
                                    ? LocalizationService.translate(
                                        'Загружаем...',
                                        'Жүктелуде...',
                                      )
                                    : LocalizationService.translate(
                                        'Выбрать город',
                                        'Қаланы таңдау',
                                      ),
                                onTap: (_cityLoading || _cityOptionsLoading)
                                    ? () {}
                                    : _openCityPicker,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          icon: Icons.dashboard_customize_rounded,
                          title: LocalizationService.translate(
                            'Быстрые действия',
                            'Жылдам әрекеттер',
                          ),
                          subtitle: LocalizationService.translate(
                            'Оплата, история, рефкод и выход',
                            'Төлем, тарих, рефкод және шығу',
                          ),
                        ),
                        const SizedBox(height: 12),
                        _profileActionTile(
                          icon: Icons.location_on_outlined,
                          title: LocalizationService.translate(
                            'Избранные адреса',
                            'Таңдаулы мекенжайлар',
                          ),
                          subtitle: LocalizationService.translate(
                            'Дом, работа и последние точки',
                            'Үй, жұмыс және соңғы нүктелер',
                          ),
                          onTap: _openFavoritesInfo,
                        ),
                        _profileActionTile(
                          icon: Icons.credit_card_rounded,
                          title: LocalizationService.translate(
                            'Способы оплаты',
                            'Төлем тәсілдері',
                          ),
                          subtitle: LocalizationService.translate(
                            'Наличные и безналичная оплата',
                            'Қолма-қол және қолма-қолсыз',
                          ),
                          onTap: _openPaymentInfo,
                        ),
                        _profileActionTile(
                          icon: Icons.history_rounded,
                          title: LocalizationService.translate(
                            'История поездок',
                            'Сапарлар тарихы',
                          ),
                          subtitle: LocalizationService.translate(
                            'Активные, завершённые и отменённые заказы',
                            'Белсенді, аяқталған және тоқтатылған тапсырыстар',
                          ),
                          onTap: () => _openAndRefresh('/orders-history'),
                        ),
                        _profileActionTile(
                          icon: Icons.support_agent_rounded,
                          title: LocalizationService.translate(
                            'Поддержка',
                            'Қолдау',
                          ),
                          subtitle: LocalizationService.translate(
                            'Как обратиться по заказу или аккаунту',
                            'Тапсырыс немесе аккаунт бойынша байланыс',
                          ),
                          onTap: _openSupportInfo,
                        ),
                        _profileActionTile(
                          icon: Icons.info_outline_rounded,
                          title: LocalizationService.translate(
                            'О приложении',
                            'Қолданба туралы',
                          ),
                          subtitle: LocalizationService.translate(
                            'Версия и описание сервиса',
                            'Нұсқа және сервис сипаттамасы',
                          ),
                          onTap: _openAboutInfo,
                        ),
                        _profileActionTile(
                          icon: Icons.logout_rounded,
                          title: LocalizationService.translate(
                            'Выйти из аккаунта',
                            'Аккаунттан шығу',
                          ),
                          subtitle: LocalizationService.translate(
                            'Завершить текущую сессию',
                            'Ағымдағы сессияны аяқтау',
                          ),
                          onTap: _logout,
                          danger: true,
                        ),
                      ],
                    ),
                  ),
                  if (_message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ICPremiumInfoBanner(text: _message),
                  ],
                  const SizedBox(height: 12),
                  const ThemeSettingsCard(),
                  const SizedBox(height: 12),
                  _driverModeCard(
                    driverStatus: driverStatus,
                    driverAccent: driverAccent,
                    hasDriverProfile: hasDriverProfile,
                    canOpenDriverMode: canOpenDriverMode,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _driverModeCard({
    required String? driverStatus,
    required Color driverAccent,
    required bool hasDriverProfile,
    required bool canOpenDriverMode,
  }) {
    final theme = Theme.of(context);
    return _card(
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
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
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
                    Icons.drive_eta_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocalizationService.translate(
                          'Режим водителя',
                          'Жүргізуші режимі',
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        LocalizationService.translate(
                          'Статус профиля и переход к заказам',
                          'Профиль күйі және тапсырыстарға өту',
                        ),
                        style: const TextStyle(
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: driverAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: driverAccent.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        canOpenDriverMode
                            ? Icons.check_circle_rounded
                            : Icons.pending_actions_rounded,
                        color: driverAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _driverStatusTitle(driverStatus),
                              style: TextStyle(
                                color: driverAccent,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _driverStatusBody(driverStatus),
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!hasDriverProfile)
                  _quickAction(
                    icon: Icons.drive_eta_rounded,
                    label: LocalizationService.translate(
                      'Стать водителем',
                      'Жүргізуші болу',
                    ),
                    onTap: () => _openAndRefresh('/driver/profile'),
                    primary: true,
                  ),
                if (hasDriverProfile && !canOpenDriverMode)
                  _quickAction(
                    icon: Icons.badge_outlined,
                    label: LocalizationService.translate(
                      'Открыть профиль водителя',
                      'Жүргізуші профилін ашу',
                    ),
                    onTap: () => _openAndRefresh('/driver/profile'),
                    primary: true,
                  ),
                if (canOpenDriverMode)
                  _quickAction(
                    icon: Icons.switch_account_rounded,
                    label: _driverSwitchLoading
                        ? LocalizationService.translate(
                            'Переходим...',
                            'Өтіп жатырмыз...',
                          )
                        : LocalizationService.translate(
                            'Перейти в режим водителя',
                            'Жүргізуші режиміне өту',
                          ),
                    onTap: _driverSwitchLoading ? () {} : _switchToDriverMode,
                    primary: true,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (hasDriverProfile && !canOpenDriverMode)
                      Expanded(
                        child: _quickAction(
                          icon: Icons.verified_user_outlined,
                          label: LocalizationService.translate(
                            'Верификация',
                            'Растау',
                          ),
                          onTap: () => _openAndRefresh('/driver/verification'),
                        ),
                      ),
                    if (hasDriverProfile && !canOpenDriverMode)
                      const SizedBox(width: 8),
                    Expanded(
                      child: _quickAction(
                        icon: Icons.info_outline_rounded,
                        label: LocalizationService.translate(
                          'Обновить статус',
                          'Күйді жаңарту',
                        ),
                        onTap: _loadMe,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
    );
  }

  Widget _profileActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = danger ? theme.colorScheme.error : AppTheme.primaryColor;
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
                          fontWeight: FontWeight.w600,
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

  Widget _boardPassengerProfileScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = _user;
    final name =
        (user?['name'] ?? user?['fullName'] ?? user?['firstName'] ?? '')
            .toString()
            .trim();
    final phone = (user?['phone'] ?? '').toString().trim();
    final driverStatus = _driverProfile?['status']?.toString();
    final driverModeValue =
        isApprovedDriverStatus(driverStatus) ? 'Доступен' : 'Настроить';
    final displayName = name.isEmpty ? 'Пассажир' : name;
    final displayPhone = phone.isEmpty ? 'Телефон не указан' : phone;
    return Scaffold(
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 3),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightSurface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: ListView(
            children: [
              if (_loading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE9DDFF), AppTheme.secondaryColor],
                      ),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          displayPhone,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Premium',
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
                ],
              ),
              const SizedBox(height: 22),
              ReferralProfileCard(user: _user),
              const SizedBox(height: 12),
              _boardProfileRow(
                icon: Icons.location_on_outlined,
                title: 'Избранные адреса',
                value: '5 адресов',
                onTap: () => context.go('/order/address'),
              ),
              _boardProfileRow(
                icon: Icons.credit_card_rounded,
                title: 'Способы оплаты',
                value: '3 карты',
                onTap: () => context.go('/profile/payments'),
              ),
              _boardProfileRow(
                icon: Icons.drive_eta_rounded,
                title: _driverSwitchLoading
                    ? 'Открываем режим водителя...'
                    : 'Режим водителя',
                value: driverModeValue,
                onTap: _driverSwitchLoading ? null : _openDriverModeEntry,
              ),
              _boardProfileRow(
                icon: Icons.settings_rounded,
                title: 'Настройки',
                value: '',
                onTap: () => context.go('/profile/settings'),
              ),
              _boardProfileRow(
                icon: Icons.support_agent_rounded,
                title: 'Поддержка',
                value: '',
                onTap: () => context.go('/profile/support'),
              ),
              _boardProfileRow(
                icon: Icons.info_outline_rounded,
                title: 'О приложении',
                value: 'Версия 2.4.1',
                onTap: _openAboutInfo,
              ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: _logout,
                child: const Text(
                  'Выйти из аккаунта',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardProfileRow({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 58,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
}
