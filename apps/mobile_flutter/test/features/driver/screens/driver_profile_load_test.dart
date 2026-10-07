import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_profile_page.dart';

class _ProfileApi extends ApiClient {
  final cities = Completer<Response<dynamic>>();
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/geo/cities') return cities.future;
    if (path == '/driver/intercity/routes') {
      throw Exception('optional routes unavailable');
    }
    return Response(
        requestOptions: RequestOptions(path: path),
        data: path == '/me'
            ? {'name': 'Олег', 'phone': '+77058652235'}
            : {
                'carModel': 'Mercedes-Benz E-Class',
                'carNumber': '099',
                'status': 'APPROVED',
                'rating': {
                  'id': 'private-rating-record',
                  'ratingAvg': 4.8,
                  'ratingCount': 7
                },
                'completedTrips': 12
              });
  }
}

void main() {
  testWidgets(
      'primary driver profile loads before optional cities and shows numeric rating',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ProfileApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Олег'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('12 поездок'), findsOneWidget);
    expect(find.textContaining('private-rating-record'), findsNothing);
    api.cities.complete(Response(
        requestOptions: RequestOptions(path: '/geo/cities'),
        data: <dynamic>[]));
    await tester.pumpAndSettle();
    expect(find.text('Олег'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
