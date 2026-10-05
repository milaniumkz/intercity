import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/api/api_client.dart';
import 'core/constants/app_constants.dart';
import 'core/services/push_notifications_service.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/localization_service.dart';
import 'core/utils/route_guard.dart';
import 'features/passenger/screens/login_page.dart';
import 'core/utils/web_splash.dart';
import 'features/passenger/screens/register_page.dart';
import 'features/passenger/screens/order_page.dart';
import 'features/passenger/screens/order_searching_page.dart';
import 'features/passenger/screens/intercity_request_page.dart';
import 'features/passenger/screens/profile_page.dart';
import 'features/passenger/screens/wallet_page.dart';
import 'features/passenger/screens/orders_history_page.dart';
import 'features/driver/screens/driver_home_page.dart';
import 'features/driver/screens/driver_verification_page.dart';
import 'features/driver/screens/driver_trip_create_page.dart';
import 'features/driver/screens/driver_wallet_page.dart';
import 'features/driver/screens/driver_profile_page.dart';
import 'features/admin/screens/admin_login_page.dart';
import 'features/admin/screens/admin_dashboard_page.dart';
import 'features/auth/screens/startup_screen.dart';
import 'features/auth/screens/register_role_choice_screen.dart';
import 'features/auth/screens/onboarding_screen.dart';
import 'features/auth/screens/forgot_password_screen.dart';
import 'features/referral/screens/referral_landing_page.dart';

GoRouter createRouter({
  String initialLocation = '/startup',
  bool disableAuthRedirect = false,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      redirect: (context, state) async {
        if (disableAuthRedirect) return null;
        final tokenStore = SecureApiTokenStore();
        final token = await tokenStore.read(AppConstants.accessTokenKey);
        final hasToken = (token ?? '').isNotEmpty;
        return resolveAuthRedirect(
          path: state.uri.path,
          hasToken: hasToken,
        );
      },
      routes: [
        GoRoute(
            path: '/startup',
            builder: (context, state) => const StartupScreen()),
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/admin/login',
          builder: (context, state) => const AdminLoginPage(),
        ),
        GoRoute(
          path: '/admin/dashboard',
          builder: (context, state) => const AdminDashboardPage(),
        ),
        GoRoute(
            path: '/register',
            builder: (context, state) => const RegisterRoleChoiceScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/onboarding/:stage',
          builder: (context, state) => OnboardingScreen(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/register/:role',
          builder: (context, state) => RegisterPage(
            role: state.pathParameters['role'] ?? 'passenger',
            referralCode: state.uri.queryParameters['ref'],
          ),
        ),
        GoRoute(
          path: '/ref/:code',
          builder: (context, state) => ReferralLandingPage(
            referralCode: state.pathParameters['code'] ?? '',
          ),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/order',
          builder: (context, state) => OrderPage(
            key: ValueKey(state.uri.toString()),
            resetToken: state.uri.queryParameters['reset'],
            initialStep: int.tryParse(state.uri.queryParameters['step'] ?? ''),
          ),
        ),
        GoRoute(
          path: '/order/:stage',
          builder: (context, state) => OrderPage(
            key: ValueKey(state.uri.toString()),
            resetToken: state.uri.queryParameters['reset'],
            routeStage: state.pathParameters['stage'],
            initialStep: int.tryParse(state.uri.queryParameters['step'] ?? ''),
          ),
        ),
        GoRoute(
          path: '/order/searching/:id',
          builder: (context, state) => OrderSearchingPage(
            orderId: state.pathParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: '/intercity/request/:id',
          builder: (context, state) => IntercityRequestPage(
            requestId: state.pathParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: '/market/request/:id',
          builder: (context, state) => IntercityRequestPage(
            requestId: state.pathParameters['id'] ?? '',
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfilePage(),
        ),
        GoRoute(
          path: '/profile/payments',
          builder: (context, state) => const WalletPage(paymentsOnly: true),
        ),
        GoRoute(
          path: '/profile/:stage',
          builder: (context, state) => ProfilePage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/wallet',
          builder: (context, state) => const WalletPage(),
        ),
        GoRoute(
          path: '/orders-history',
          builder: (context, state) => const OrdersHistoryPage(),
        ),
        GoRoute(
          path: '/orders-history/:stage',
          builder: (context, state) => OrdersHistoryPage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/driver/home',
          builder: (context, state) => const DriverHomePage(),
        ),
        GoRoute(
          path: '/driver/home/:stage',
          builder: (context, state) => DriverHomePage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/driver/verification',
          builder: (context, state) => const DriverVerificationPage(),
        ),
        GoRoute(
          path: '/driver/verification/:stage',
          builder: (context, state) => DriverVerificationPage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/driver/trip-create',
          builder: (context, state) => const DriverTripCreatePage(),
        ),
        GoRoute(
          path: '/driver/trip-create/:stage',
          builder: (context, state) => DriverTripCreatePage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/driver/wallet',
          builder: (context, state) => const DriverWalletPage(),
        ),
        GoRoute(
          path: '/driver/wallet/:stage',
          builder: (context, state) => DriverWalletPage(
            routeStage: state.pathParameters['stage'],
          ),
        ),
        GoRoute(
          path: '/driver/profile',
          builder: (context, state) => const DriverProfilePage(),
        ),
      ],
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalizationService.init();
  await ApiClient.init();
  unawaited(_initializeBackgroundServices());
  runApp(const ProviderScope(child: IntercityApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) => removeWebSplash());
}

Future<void> _initializeBackgroundServices() async {
  try {
    await PushNotificationsService.instance.init();
  } catch (_) {
    // Notifications should never block first paint or routing.
  }
}

class IntercityApp extends ConsumerStatefulWidget {
  const IntercityApp({super.key});

  @override
  ConsumerState<IntercityApp> createState() => _IntercityAppState();
}

class _IntercityAppState extends ConsumerState<IntercityApp> {
  late final GoRouter _router = createRouter(
    initialLocation: _initialLocationFromUri(),
    disableAuthRedirect:
        const bool.fromEnvironment('INTERCITY_DISABLE_AUTH_REDIRECT'),
  );

  String _initialLocationFromUri() {
    final uri = Uri.base;
    if (uri.path.isEmpty || uri.path == '/') return '/startup';
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeControllerProvider);
    final urlDarkOverride = Uri.base.toString().contains('dark=1');
    final urlLightOverride = Uri.base.toString().contains('light=1');
    return MaterialApp.router(
      title: 'INTERCITY',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: urlLightOverride
          ? ThemeMode.light
          : urlDarkOverride
              ? ThemeMode.dark
              : switch (mode) {
                  AppThemeMode.light => ThemeMode.light,
                  AppThemeMode.dark => ThemeMode.dark,
                  AppThemeMode.system => ThemeMode.system,
                },
      locale: const Locale('ru'),
      supportedLocales: const [
        Locale('ru'),
        Locale('kk'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
          child: _ModeSwitcherOverlay(
            router: _router,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      routerConfig: _router,
    );
  }
}

class _ModeSwitcherOverlay extends StatefulWidget {
  const _ModeSwitcherOverlay({
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  State<_ModeSwitcherOverlay> createState() => _ModeSwitcherOverlayState();
}

class _ModeSwitcherOverlayState extends State<_ModeSwitcherOverlay> {
  String _path = '';

  @override
  void initState() {
    super.initState();
    _syncPath();
    widget.router.routerDelegate.addListener(_syncPath);
  }

  @override
  void didUpdateWidget(covariant _ModeSwitcherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router == widget.router) return;
    oldWidget.router.routerDelegate.removeListener(_syncPath);
    widget.router.routerDelegate.addListener(_syncPath);
    _syncPath();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_syncPath);
    super.dispose();
  }

  void _syncPath() {
    final next = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (next == _path) return;
    if (mounted) {
      setState(() => _path = next);
    } else {
      _path = next;
    }
  }

  bool get _showSwitcher {
    if (_path.startsWith('/admin') ||
        _path.startsWith('/login') ||
        _path.startsWith('/startup') ||
        _path.startsWith('/onboarding') ||
        _path.startsWith('/register') ||
        _path.startsWith('/forgot-password') ||
        _path.startsWith('/ref/')) {
      return false;
    }
    return _path.startsWith('/driver') ||
        _path.startsWith('/order') ||
        _path.startsWith('/intercity') ||
        _path.startsWith('/market') ||
        _path.startsWith('/profile') ||
        _path.startsWith('/wallet') ||
        _path.startsWith('/orders-history');
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = _path.startsWith('/driver');
    final child = _showSwitcher
        ? Padding(
            padding: const EdgeInsets.only(top: 34),
            child: widget.child,
          )
        : widget.child;
    return Stack(
      children: [
        child,
        if (_showSwitcher)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(child: _ModeBadge(isDriver: isDriver)),
            ),
          ),
      ],
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final label = isDriver ? 'Режим водителя' : 'Режим пассажира';
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xEE11101D) : const Color(0xEEFFFFFF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: dark ? const Color(0xFF2B2340) : const Color(0xFFE6DDF8),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF8A3FFC),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white : const Color(0xFF211B32),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
