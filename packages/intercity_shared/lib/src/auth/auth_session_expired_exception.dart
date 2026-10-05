class AuthSessionExpiredException implements Exception {
  const AuthSessionExpiredException([
    this.message = 'Authentication session expired.',
  ]);

  final String message;

  @override
  String toString() => message;
}
