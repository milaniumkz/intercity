import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/route_guard.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('redirects guest from passenger protected route to login', () {
      expect(
        resolveAuthRedirect(path: '/order', hasToken: false),
        '/login',
      );
    });

    test('redirects guest from admin route to admin login', () {
      expect(
        resolveAuthRedirect(path: '/admin/dashboard', hasToken: false),
        '/admin/login',
      );
    });

    test('allows guest on public routes', () {
      expect(resolveAuthRedirect(path: '/login', hasToken: false), isNull);
      expect(resolveAuthRedirect(path: '/register/passenger', hasToken: false),
          isNull);
      expect(resolveAuthRedirect(path: '/startup', hasToken: false), isNull);
    });

    test('redirects authenticated user away from login-like routes', () {
      expect(resolveAuthRedirect(path: '/login', hasToken: true), '/startup');
      expect(
        resolveAuthRedirect(path: '/register/driver', hasToken: true),
        '/startup',
      );
      expect(
        resolveAuthRedirect(path: '/forgot-password', hasToken: true),
        '/startup',
      );
    });

    test('allows authenticated user on protected routes and startup', () {
      expect(resolveAuthRedirect(path: '/order', hasToken: true), isNull);
      expect(
        resolveAuthRedirect(path: '/admin/dashboard', hasToken: true),
        isNull,
      );
      expect(resolveAuthRedirect(path: '/startup', hasToken: true), isNull);
    });
  });
}
