String homeRouteForRole(String role) {
  switch (role.toUpperCase()) {
    case 'ADMIN':
      return '/admin/dashboard';
    case 'DRIVER':
      return '/driver/home';
    default:
      return '/order';
  }
}
