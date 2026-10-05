import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

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

    final dio = Dio(BaseOptions(
      baseUrl: ApiClient.currentBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(hours: 12),
      responseType: ResponseType.stream,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
      },
    ));

    final cancelToken = CancelToken();
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    StreamSubscription<String>? linesSub;

    try {
      final res = await dio.get<ResponseBody>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body == null) {
        await controller.close();
        return null;
      }

      String? eventName;
      final dataLines = <String>[];

      void flush() {
        if (dataLines.isEmpty) return;
        final rawData = dataLines.join('\n');
        Object? parsed;
        try {
          parsed = jsonDecode(rawData);
        } catch (_) {
          parsed = rawData;
        }
        final payload = <String, dynamic>{
          'event': eventName ?? 'message',
        };
        if (parsed is Map) {
          payload['data'] = Map<String, dynamic>.from(parsed);
        } else {
          payload['data'] = parsed;
        }
        if (!controller.isClosed) {
          controller.add(payload);
        }
        eventName = null;
        dataLines.clear();
      }

      linesSub = body.stream
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('event:')) {
            eventName = line.substring(6).trim();
            return;
          }
          if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
            return;
          }
          if (line.trim().isEmpty) {
            flush();
          }
        },
        onDone: () async {
          flush();
          await controller.close();
        },
        onError: (error, stackTrace) async {
          if (!controller.isClosed) controller.addError(error, stackTrace);
          await controller.close();
        },
        cancelOnError: true,
      );
    } catch (_) {
      await controller.close();
      return null;
    }

    return SseConnection(
      stream: controller.stream,
      close: () async {
        cancelToken.cancel('SSE closed by client');
        await linesSub?.cancel();
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
  }
}
