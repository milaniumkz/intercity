import 'features/admin/screens/admin_identity_history_page.dart';
import 'features/admin/screens/admin_people_page.dart';
import 'features/admin/screens/admin_identity_reviews_page.dart';
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
      initialRoute:
          Uri.base.fragment.startsWith('/') ? Uri.base.fragment : '/login',
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri == null) return null;
        Widget? page;
        if (uri.pathSegments.length == 2 &&
            uri.pathSegments.first == 'person') {
          page = AdminPersonPage(userId: uri.pathSegments.last);
        }
        if (uri.query.isNotEmpty) {
          page = switch (uri.path) {
            '/users' => const AdminPeoplePage(),
            '/drivers' => const AdminPeoplePage(drivers: true),
            '/trip-register' => const AdminTripRegisterPage(),
            '/identity-history' => const AdminIdentityHistoryPage(),
            _ => page
          };
        }
        if (page == null) return null;
        return MaterialPageRoute(
            settings: RouteSettings(name: settings.name, arguments: {
              ...uri.queryParameters,
              ...(settings.arguments is Map ? (settings.arguments as Map) : {})
            }),
            builder: (_) => page!);
      },
      routes: {
        '/login': (context) => const AdminLoginPage(),
        '/dashboard': (context) => const AdminDashboardPage(),
        '/users': (context) => const AdminPeoplePage(),
        '/person': (context) => ModalRoute.of(context)?.settings.arguments
                is String
            ? AdminPersonPage(
                userId: ModalRoute.of(context)!.settings.arguments as String)
            : const AdminPeoplePage(),
        '/trip-register': (context) => const AdminTripRegisterPage(),
        '/drivers': (context) => const AdminPeoplePage(drivers: true),
        '/cities': (context) => const AdminCitiesPage(),
        '/tariffs': (context) => const AdminTariffsPage(),
        '/settings': (context) => const AdminSettingsPage(),
        '/topups': (context) => const AdminTopupsPage(),
        '/payouts': (context) => const AdminPayoutsPage(),
        '/identity-history': (context) => const AdminIdentityHistoryPage(),
        '/identity-reviews': (context) => const _IdentityReviewAccess(),
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

class _IdentityReviewAccess extends StatefulWidget {
  const _IdentityReviewAccess();
  @override
  State<_IdentityReviewAccess> createState() => _IdentityReviewAccessState();
}

class _IdentityReviewAccessState extends State<_IdentityReviewAccess> {
  late final Future<bool> _authorized = _check();
  Future<bool> _check() async {
    final api = AdminApiClient.instance;
    if (api is AdminApiClient && !await api.hasSavedSession()) return false;
    try {
      final response = await api.get('/auth/me');
      return response.data is Map && response.data['role'] == 'ADMIN';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _authorized,
        builder: (context, snapshot) => snapshot.connectionState !=
                ConnectionState.done
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : snapshot.data == true
                ? const AdminIdentityReviewsPage()
                : const AdminLoginPage(reviewAfterLogin: true),
      );
}
