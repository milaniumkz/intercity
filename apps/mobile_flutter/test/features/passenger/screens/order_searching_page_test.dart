import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/sse_service.dart';
import 'package:intercity_mobile/features/passenger/screens/order_searching_page.dart';

void main() {
  testWidgets('does not keep polling while realtime stream is active',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final api = _FakeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: OrderSearchingPage(
          orderId: 'order-1',
          apiClient: api,
          pollingInterval: const Duration(seconds: 1),
          enableLiveMap: false,
          realtimeConnector: (
            String path, {
            Map<String, dynamic>? queryParameters,
          }) async {
            return SseConnection(
              stream: controller.stream,
              close: () async {},
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(api.getCalls, 1);

    await tester.pump(const Duration(seconds: 3));

    expect(api.getCalls, 1);
    await controller.close();
  });

  testWidgets('starts polling when realtime stream is unavailable',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _FakeApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: OrderSearchingPage(
          orderId: 'order-1',
          apiClient: api,
          pollingInterval: const Duration(seconds: 1),
          enableLiveMap: false,
          realtimeConnector: (
            String path, {
            Map<String, dynamic>? queryParameters,
          }) async {
            return null;
          },
        ),
      ),
    );
    await tester.pump();

    expect(api.getCalls, 1);

    await tester.pump(const Duration(seconds: 3));

    expect(api.getCalls, greaterThan(1));
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(
          dio: Dio(),
          refreshDio: Dio(),
          tokenStore: _MemoryTokenStore(),
          baseUrl: 'https://api.intercity.invalid/api',
        );

  int getCalls = 0;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    getCalls++;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: <String, dynamic>{
        'id': 'order-1',
        'status': 'SEARCHING_DRIVER',
        'fromAddress': 'Точка A',
        'toAddress': 'Точка B',
        'fromLat': 43.238949,
        'fromLng': 76.889709,
        'toLat': 43.25667,
        'toLng': 76.92861,
      },
      statusCode: 200,
    );
  }
}

class _MemoryTokenStore implements ApiTokenStore {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
