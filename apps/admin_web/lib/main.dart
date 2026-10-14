import 'features/admin/screens/admin_tax_registry_page.dart';
import 'features/admin/screens/admin_trip_reviews_page.dart';
import 'features/admin/screens/admin_rating_reviews_page.dart';
import 'package:flutter/material.dart';
import 'core/api/admin_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/admin/screens/admin_login_page.dart';
import 'features/admin/screens/admin_dashboard_page.dart';

void main() {
  runApp(const ProviderScope(child: IntercityAdminApp()));
}

class IntercityAdminApp extends StatefulWidget {
  const IntercityAdminApp({super.key});

  @override
  State<IntercityAdminApp> createState() => _IntercityAdminAppState();
}

class _IntercityAdminAppState extends State<IntercityAdminApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
    AdminApiClient.sessionExpired.addListener(_onSessionExpired);
  }

  void _onSessionExpired() {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectScheduled = false;
      if (!mounted) return;
      _navigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (_) => false);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    AdminApiClient.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F5B7A),
      brightness: Brightness.light,
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'INTERCITY Админка',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const AdminLoginPage(),
        '/dashboard': (context) => const AdminDashboardPage(),
        '/users': (context) => const AdminUsersPage(),
        '/drivers': (context) => const AdminDriversPage(),
        '/cities': (context) => const AdminCitiesPage(),
        '/tariffs': (context) => const AdminTariffsPage(),
        '/settings': (context) => const AdminSettingsPage(),
        '/topups': (context) => const AdminTopupsPage(),
        '/payouts': (context) => const AdminPayoutsPage(),
        '/notifications': (context) => const AdminNotificationsPage(),
        '/finance-audit': (context) => const AdminFinanceAuditPage(),
        '/orders': (context) => const AdminOrdersPage(),
        '/trip-reviews': (context) => const AdminTripReviewsPage(),
        '/tax-self-employed': (context) => const AdminTaxRegistryPage(),
        '/tax-ie': (context) => const AdminTaxRegistryPage(kind: 'IE'),
        '/rating-reviews': (context) => const AdminRatingReviewsPage(),
      },
    );
  }
}
