import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_profile_page.dart';

class _ProfileApi extends ApiClient {
  final cities = Completer<Response<dynamic>>();
  bool delivery = false;
  final saved = <Map<String, dynamic>>[];
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path != '/driver/profile/service-modes') {
      throw StateError('Unexpected write: $path');
    }
    saved.add(Map<String, dynamic>.from(data as Map));
    delivery = data['acceptDelivery'] == true;
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

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
                'acceptDelivery': delivery,
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
      'current profile exposes delivery, saves modes and preserves edits during optional loading',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ProfileApi();
    await tester
        .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(find.text('Какие заказы получать'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).at(3)).value, false);
    await tester.ensureVisible(find.byType(Switch).at(3));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(3));
    await tester.pumpAndSettle();
    api.cities.complete(Response(
        requestOptions: RequestOptions(path: '/geo/cities'),
        data: <dynamic>[]));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(3)).value, true);
    await tester.ensureVisible(find.text('Сохранить настройки заказов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить настройки заказов'));
    await tester.pumpAndSettle();
    expect(api.saved.single['acceptDelivery'], true);
    expect(
        api.saved.single.keys,
        unorderedEquals([
          'acceptCityFixed',
          'acceptCityAuction',
          'acceptIntercity',
          'acceptDelivery',
          'acceptCargo'
        ]));
    await tester.pumpWidget(const SizedBox());
    await tester
        .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(3)).value, true);
    await tester.pumpWidget(const SizedBox());
  });
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
    expect(find.text('Заработок'), findsOneWidget);
    expect(find.textContaining('private-rating-record'), findsNothing);
    api.cities.complete(Response(
        requestOptions: RequestOptions(path: '/geo/cities'),
        data: <dynamic>[]));
    await tester.pumpAndSettle();
    expect(find.text('Олег'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
