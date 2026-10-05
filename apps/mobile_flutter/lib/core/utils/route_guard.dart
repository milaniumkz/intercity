bool isPublicRoute(String path) {
  if (path == '/startup' ||
      path == '/login' ||
      path == '/admin/login' ||
      path == '/register' ||
      path == '/forgot-password') {
    return true;
  }
  return path.startsWith('/register/') || path.startsWith('/ref/');
}

String? resolveAuthRedirect({
  required String path,
  required bool hasToken,
  bool bypassAuth = false,
}) {
  if (bypassAuth) {
    return null;
  }

  final publicRoute = isPublicRoute(path);
  final adminRoute = path.startsWith('/admin/') && path != '/admin/login';

  if (!hasToken && !publicRoute) {
    return adminRoute ? '/admin/login' : '/login';
  }

  if (hasToken && publicRoute && path != '/startup') {
    return '/startup';
  }

  return null;
}
