class IntercityApiConfig {
  static const String envKey = 'INTERCITY_API_BASE_URL';
  static const String safePlaceholderBaseUrl =
      'https://api.intercity.invalid/api';

  static String normalize(String? raw) {
    var value = (raw ?? '').trim();
    if (value.isEmpty) return safePlaceholderBaseUrl;

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty) {
      return safePlaceholderBaseUrl;
    }

    final pathSegments = [
      ...parsed.pathSegments.where((segment) => segment.isNotEmpty),
    ];
    if (pathSegments.isEmpty || pathSegments.last.toLowerCase() != 'api') {
      pathSegments.add('api');
    }

    return parsed
        .replace(
          pathSegments: pathSegments,
          queryParameters: parsed.queryParameters.isEmpty
              ? null
              : parsed.queryParameters,
          fragment: null,
        )
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
