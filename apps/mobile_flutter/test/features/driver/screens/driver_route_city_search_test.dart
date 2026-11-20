import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/driver/screens/driver_trip_create_page.dart';
import 'package:intercity_mobile/features/driver/widgets/intercity_request_card.dart';

class _SearchApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: []);
  @override
  Future<Response<dynamic>> post(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: [
        {
          'name': 'Усть-Каменогорск',
          'displayName': 'Усть-Каменогорск, Казахстан',
          'lat': 49.97,
          'lng': 82.61
        }
      ]);
}

class _RefreshingRouteApi extends _SearchApi {
  bool hasSavedRoute = false;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/driver/intercity/routes') {
      return Response(
          requestOptions: RequestOptions(path: path),
          data: [
            if (hasSavedRoute)
              {
                'id': 'saved-route',
                'fromCity': 'Алматы',
                'toCity': 'Астана',
                'seatsAvailable': 2,
                'currency': 'KZT',
                'departureAt': DateTime.now()
                    .add(const Duration(days: 1))
                    .toUtc()
                    .toIso8601String(),
              }
          ]);
    }
    return super.get(path, queryParameters: queryParameters, options: options);
  }
}

class _FilterApi extends _SearchApi {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/driver/intercity/matching'
              ? [
                  for (final type in [
                    'INTERCITY',
                    'DELIVERY_INTERCITY',
                    'DELIVERY_RF',
                    'DELIVERY_CITY'
                  ])
                    {
                      'id': type,
                      'requestType': type,
                      'fromCity': 'Алматы',
                      'toCity': 'Астана',
                      'paymentMethod': 'CASH'
                    }
                ]
              : []);
}

void main() {
  testWidgets(
      'intercity filter includes distant deliveries and excludes local delivery',
      (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: DriverTripCreatePage(apiClient: _FilterApi())));
    await tester.pumpAndSettle();
    List<String> visibleTypes() => tester
        .widgetList<IntercityRequestCard>(find.byType(IntercityRequestCard))
        .map((card) => card.request['requestType'] as String)
        .toList();
    expect(visibleTypes(), ['INTERCITY', 'DELIVERY_INTERCITY', 'DELIVERY_RF']);
    await tester.tap(find.text('По городу'));
    await tester.pumpAndSettle();
    expect(visibleTypes(), ['DELIVERY_CITY']);
    await tester.tap(find.text('Все').first);
    await tester.pumpAndSettle();
    expect(visibleTypes(),
        ['INTERCITY', 'DELIVERY_INTERCITY', 'DELIVERY_RF', 'DELIVERY_CITY']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      '20 repeated departure and destination selections preserve the driver form even on double taps',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _RefreshingRouteApi();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) =>
                                DriverTripCreatePage(apiClient: api))),
                    child: const Text('Открыть межгород'))))));
    await tester.tap(find.text('Открыть межгород'));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 20; attempt++) {
      for (final label in ['Откуда', 'Куда']) {
        final field = find.text(label);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        final search = find.descendant(
            of: find.byType(BottomSheet), matching: find.byType(TextField));
        await tester.enterText(search, 'Усть');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final city = find.widgetWithText(ListTile, 'Усть-Каменогорск');
        final select = tester.widget<ListTile>(city).onTap!;
        select();
        select();
        await tester.pumpAndSettle();
        expect(find.byType(DriverTripCreatePage), findsOneWidget,
            reason: '$label: повтор ${attempt + 1}');
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('Усть-Каменогорск'), findsWidgets);
        expect(tester.takeException(), isNull);
        api.hasSavedRoute = !api.hasSavedRoute;
        await tester.pump(const Duration(seconds: 11));
        await tester.pumpAndSettle();
        expect(find.text(label).hitTestable(), findsOneWidget,
            reason: 'Фоновое обновление не должно сворачивать заявку');
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
