import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

const duplicateMessage =
    'На этот маршрут и дату уже есть заявка. Выберите другую дату или откройте существующую заявку.';

class _DuplicateApi extends ApiClient {
  Map<String, dynamic>? submitted;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/app/runtime-settings'
              ? {'passengerMapHomeEnabled': false}
              : []);
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data,
      Map<String, dynamic>? queryParameters,
      Options? options}) async {
    if (path == '/intercity/requests') {
      submitted = Map<String, dynamic>.from(data);
      final request = RequestOptions(path: path);
      throw DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: request, statusCode: 409, data: {
            'code': 'DUPLICATE_INTERCITY_DEPARTURE',
            'message': duplicateMessage
          }));
    }
    return Response(requestOptions: RequestOptions(path: path), data: {
      'price': 1000,
      'distance': 180,
      'duration': 10000,
      'currency': 'KZT'
    });
  }
}

void main() {
  testWidgets(
      'duplicate date rejection keeps the intercity form and explains how to proceed',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final departure = DateTime.now().add(const Duration(days: 3));
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 1,
      'comment': 'Село Черногорка, встреча у магазина',
      'intercityDate': departure.toUtc().toIso8601String(),
      'fromText': 'Шакарима 143',
      'fromAddress': 'Шакарима 143',
      'fromLat': 49.97,
      'fromLng': 82.61,
      'toText': 'Абая 10',
      'toAddress': 'Абая 10',
      'toLat': 50.41,
      'toLng': 80.25,
      'intercityFromCityName': 'Усть-Каменогорск',
      'intercityFromCityLat': 49.97,
      'intercityFromCityLng': 82.61,
      'intercityToCityName': 'Семей',
      'intercityToCityLat': 50.41,
      'intercityToCityLng': 80.25,
      'boardPrice': 1000
    }));
    final api = _DuplicateApi();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: OrderScreen(
            routeStage: 'intercity_options',
            apiClient: api,
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pumpAndSettle();
    final submit = find.text('Далее');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.submitted, isNotNull);
    expect(api.submitted!['comment'],
        contains('Село Черногорка, встреча у магазина'));
    expect(api.submitted!['departureOffsetMinutes'],
        departure.timeZoneOffset.inMinutes);
    expect(find.text(duplicateMessage), findsOneWidget);
    expect(find.byType(OrderScreen), findsOneWidget);
    final saved = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(saved['comment'], 'Село Черногорка, встреча у магазина');
    expect(saved['fromText'], 'Шакарима 143');
    expect(saved['toText'], 'Абая 10');
    expect(DateTime.parse(saved['intercityDate']).isAtSameMomentAs(departure),
        true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
