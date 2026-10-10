import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/passenger/screens/shared_trip_page.dart';
import '../../../support/memory_tile_provider.dart';

class _ShareApi extends ApiClient {
  String status = 'IN_PROGRESS';
  int calls = 0;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/route') {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'geometry': {
          'coordinates': [
            [82.60, 49.95],
            [82.61, 49.96],
            [82.62, 49.97]
          ]
        }
      });
    }
    calls++;
    return Response(requestOptions: RequestOptions(path: path), data: {
      'status': status,
      'fromLat': 49.95,
      'fromLng': 82.60,
      'toLat': 49.97,
      'toLng': 82.62,
      'fromAddress': 'Шакарима 10',
      'toAddress': 'Серикбаева 8/1А',
      'driver': {
        'carModel': 'Toyota Camry',
        'carNumber': '123 ABC',
        'online':
            status == 'COMPLETED' ? null : {'lastLat': 49.96, 'lastLng': 82.61}
      }
    });
  }
}

void main() {
  testWidgets('shared trip is read only and updates without login',
      (tester) async {
    final api = _ShareApi();
    await tester.pumpWidget(MaterialApp(
        home: SharedTripPage(
            token: 'test',
            apiClient: api,
            mapTileProvider: MemoryTileProvider())));
    await tester.pump();
    await tester.pump();
    expect(find.text('Поездка идёт'), findsOneWidget);
    expect(find.text('Откуда: Шакарима 10'), findsOneWidget);
    expect(find.text('Отменить заказ'), findsNothing);
    expect(find.text('Чат'), findsNothing);
    api.status = 'COMPLETED';
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Поездка завершена'), findsOneWidget);
    expect(api.calls, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
