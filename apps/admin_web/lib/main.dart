import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/admin/screens/admin_login_page.dart';
import 'features/admin/screens/admin_dashboard_page.dart';

void main() {
  runApp(const ProviderScope(child: IntercityAdminApp()));
}

class IntercityAdminApp extends StatelessWidget {
  const IntercityAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F5B7A),
      brightness: Brightness.light,
    );
    return MaterialApp(
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
      },
    );
  }
}
