import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../api/api_client.dart';

class SseConnection {
  SseConnection({required this.stream, required this.close});

  final Stream<Map<String, dynamic>> stream;
  final Future<void> Function() close;
}

class SseService {
  static Future<SseConnection?> connect(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final token = await ApiClient().getAccessToken();
    if (token == null || token.isEmpty) return null;

    final uri = Uri.parse('${ApiClient.currentBaseUrl}$path').replace(
      queryParameters: <String, String>{
        ...?queryParameters?.map((key, value) => MapEntry(key, '$value')),
        'access_token': token,
      },
    );

    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final source = web.EventSource(uri.toString());
    final listeners = <({String type, web.EventListener listener})>[];

    void addListener(String type) {
      final listener = ((web.Event event) {
        final data = event.getProperty<JSAny?>('data'.toJS)?.dartify();
        Object? parsed = data;
        if (data is String) {
          try {
            parsed = jsonDecode(data);
          } catch (_) {
            parsed = data;
          }
        }
        final payload = <String, dynamic>{'event': type};
        if (parsed is Map) {
          payload['data'] = Map<String, dynamic>.from(parsed);
        } else {
          payload['data'] = parsed;
        }
        if (!controller.isClosed) controller.add(payload);
      }).toJS;
      source.addEventListener(type, listener);
      listeners.add((type: type, listener: listener));
    }

    addListener('message');
    addListener('heartbeat');
    addListener('event');
    addListener('order-event');
    addListener('driver-event');

    source.onerror = ((web.Event _) {
      if (source.readyState == web.EventSource.CLOSED && !controller.isClosed) {
        controller.close();
      }
    }).toJS;

    return SseConnection(
      stream: controller.stream,
      close: () async {
        for (final entry in listeners) {
          source.removeEventListener(entry.type, entry.listener);
        }
        source.close();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
  }
}
