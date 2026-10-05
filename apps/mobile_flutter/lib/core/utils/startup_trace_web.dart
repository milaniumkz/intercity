import 'dart:convert';
import 'package:web/web.dart' as web;

void startupTraceMark(
  String stage, {
  Map<String, Object?> data = const <String, Object?>{},
}) {
  try {
    final trace = <Object?>[
      ..._readTrace(),
      <String, Object?>{
        'ts': DateTime.now().toIso8601String(),
        'stage': stage,
        'data': data,
      },
    ];
    final encoded = jsonEncode(trace);
    web.window.localStorage.setItem('intercity.startup.trace', encoded);
  } catch (_) {
    // Tracing must never break app startup.
  }
}

List<Object?> _readTrace() {
  final raw = web.window.localStorage.getItem('intercity.startup.trace');
  if (raw == null || raw.isEmpty) {
    return const <Object?>[];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List<Object?>) {
      return decoded;
    }
  } catch (_) {
    return const <Object?>[];
  }
  return const <Object?>[];
}
