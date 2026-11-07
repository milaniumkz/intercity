import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/core/utils/browser_location_model.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

class _ResumeApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/app/runtime-settings'
              ? {'passengerMapHomeEnabled': false}
              : []);
}

void main() {
  testWidgets(
      'returning to an intercity draft never resets addresses or departure via GPS',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await AppPreferences.setOrderCity({
      'id': 'ust',
      'name': 'Усть-Каменогорск',
      'lat': 49.97,
      'lng': 82.61,
      'countryCode': 'KZ'
    });
    final departure = DateTime.now().add(const Duration(days: 3));
    await AppPreferences.setOrderDraft(jsonEncode({
      'modeIndex': 1,
      'comment': 'Уварово — село Черногорка, встреча у магазина',
      'intercityDate': departure.toUtc().toIso8601String(),
      'fromText': 'Шакарима 143',
      'fromAddress': 'Шакарима 143',
      'toText': 'Семей, Абая 10',
      'toAddress': 'Семей, Абая 10',
      'intercityFromCityName': 'Усть-Каменогорск',
      'intercityFromCityLat': 49.97,
      'intercityFromCityLng': 82.61,
      'intercityToCityName': 'Семей',
      'intercityToCityLat': 50.41,
      'intercityToCityLng': 80.25,
    }));
    var gpsCalls = 0;
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: OrderScreen(
            routeStage: 'intercity_start',
            apiClient: _ResumeApi(),
            enableLiveMap: false,
            locationProvider: () async {
              gpsCalls++;
              return const BrowserLocation(
                  latitude: 49.97, longitude: 82.61, accuracy: 10);
            })));
    await tester.pumpAndSettle();
    expect(gpsCalls, 0);
    final commentField = find.byWidgetPredicate((widget) =>
        widget is TextField &&
        widget.controller?.text ==
            'Уварово — село Черногорка, встреча у магазина');
    expect(commentField, findsOneWidget);
    await tester.ensureVisible(commentField);
    await tester.enterText(commentField, 'Село Черногорка, позвоните');
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gpsCalls, 0,
        reason:
            'resuming an intercity form must not start destructive automatic GPS');
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['comment'], 'Село Черногорка, позвоните');
    expect(draft['fromText'], 'Шакарима 143');
    expect(draft['toText'], 'Семей, Абая 10');
    expect(DateTime.parse(draft['intercityDate']).isAtSameMomentAs(departure),
        true);
    expect(find.text('Межгород'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
