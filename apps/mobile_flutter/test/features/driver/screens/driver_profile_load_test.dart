import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_profile_page.dart';

class _ProfileApi extends ApiClient {
  final cities = Completer<Response<dynamic>>();
  bool delivery = false;
  bool failWrite = false;
  Completer<void>? pendingWrite;
  bool cityFixed = true, cityAuction = true;
  final saved = <Map<String, dynamic>>[];
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path != '/driver/profile/service-modes') {
      throw StateError('Unexpected write: $path');
    }
    saved.add(Map<String, dynamic>.from(data as Map));
    await pendingWrite?.future;
    if (failWrite) {
      throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError);
    }
    delivery = data['acceptDelivery'] == true;
    cityFixed = data['acceptCityFixed'] == true;
    cityAuction = data['acceptCityAuction'] == true;
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
                'acceptCityFixed': cityFixed,
                'acceptCityAuction': cityAuction,
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
  for (final fails in [false, true]) {
    testWidgets(
        'autosave disables switches while pending and handles failure=$fails',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pending = Completer<void>();
      final api = _ProfileApi()
        ..pendingWrite = pending
        ..failWrite = fails;
      api.cities.complete(Response(
          requestOptions: RequestOptions(path: '/geo/cities'),
          data: <dynamic>[]));
      await tester
          .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(2));
      await tester.pump();
      expect(api.saved.length, 1);
      expect(find.text('Сохраняем...'), findsOneWidget);
      expect(
          tester
              .widgetList<Switch>(find.byType(Switch))
              .every((s) => s.onChanged == null),
          true);
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, !fails);
      expect(api.delivery, !fails);
      expect(find.text('Сохранить настройки заказов'), findsNothing);
      if (fails) {
        expect(
            find.textContaining('Не удалось сохранить. Настройка возвращена'),
            findsOneWidget);
        api.failWrite = false;
        await tester.ensureVisible(find.byType(Switch).at(2));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch).at(2));
        await tester.pumpAndSettle();
        expect(api.saved.length, 2);
        expect(api.delivery, true);
      }
      expect(find.text('Сохранено'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final initial in [
    (false, false),
    (true, false),
    (false, true),
    (true, true)
  ]) {
    testWidgets('city trips control saves both modes together from $initial',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _ProfileApi()
        ..cityFixed = initial.$1
        ..cityAuction = initial.$2;
      api.cities.complete(Response(
          requestOptions: RequestOptions(path: '/geo/cities'),
          data: <dynamic>[]));
      await tester
          .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
      await tester.pumpAndSettle();
      expect(find.text('Городские поездки'), findsOneWidget);
      expect(find.text('Город'), findsNothing);
      expect(find.text('Аукцион'), findsNothing);
      expect(find.byType(Switch), findsNWidgets(4));
      expect(find.text('Сохранить настройки заказов'), findsNothing);
      var value = initial.$1 || initial.$2;
      expect(tester.widget<Switch>(find.byType(Switch).first).value, value);
      for (var n = 0; n < 2; n++) {
        await tester.ensureVisible(find.byType(Switch).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        value = !value;
        expect(api.saved.last['acceptCityFixed'], value);
        expect(api.saved.last['acceptCityAuction'], value);
        await tester.pumpWidget(const SizedBox());
        await tester
            .pumpWidget(MaterialApp(home: DriverProfilePage(apiClient: api)));
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(find.byType(Switch).first).value, value);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
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
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, false);
    await tester.ensureVisible(find.byType(Switch).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(2));
    await tester.pumpAndSettle();
    api.cities.complete(Response(
        requestOptions: RequestOptions(path: '/geo/cities'),
        data: <dynamic>[]));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, true);
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
    expect(tester.widget<Switch>(find.byType(Switch).at(2)).value, true);
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
