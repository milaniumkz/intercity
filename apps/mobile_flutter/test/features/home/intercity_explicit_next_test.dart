import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

void main() {
  for (final suggestion in [true, false]) {
    testWidgets(
        'destination ${suggestion ? 'suggestion' : 'keyboard search'} leaves departure selection available until explicit next',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await AppPreferences.setOrderDraft(jsonEncode({
        'modeIndex': 1,
        'fromLat': 49.97,
        'fromLng': 82.61,
        'fromText': 'Шакарима 143',
        'fromAddress': 'Шакарима 143',
        'intercityFromCityName': 'Усть-Каменогорск',
        'intercityToCityName': 'Риддер',
        'intercityToCityLat': 50.3446,
        'intercityToCityLng': 83.5129
      }));
      final router =
          GoRouter(initialLocation: '/order/intercity_start', routes: [
        GoRoute(
            path: '/order/intercity_start',
            builder: (_, __) => OrderScreen(
                routeStage: 'intercity_start',
                apiClient: RouteApi(),
                enableLiveMap: false,
                autoLocateOnStart: false)),
        GoRoute(
            path: '/order/intercity_options',
            builder: (_, __) =>
                const Scaffold(body: Text('UNEXPECTED OPTIONS')))
      ]);
      await tester.pumpWidget(MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ru'),
          supportedLocales: const [
            Locale('ru')
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ]));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Куда');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Семеновой 7');
      if (suggestion) {
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        final item = find.text('Семеновой 7').last;
        await tester.ensureVisible(item);
        await tester.pumpAndSettle();
        await tester.tap(item);
      } else {
        await tester.testTextInput.receiveAction(TextInputAction.search);
      }
      await tester.pumpAndSettle();
      expect(find.text('UNEXPECTED OPTIONS'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path,
          '/order/intercity_start');
      final date = find.text('Выберите дату');
      await tester.ensureVisible(date);
      await tester.pumpAndSettle();
      await tester.tap(date);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    });
  }
}

class RouteApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: path == '/route'
              ? {
                  'distance': 130,
                  'duration': 139,
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      [82.61, 49.97],
                      [83.5129, 50.3446]
                    ]
                  }
                }
              : []);
  @override
  Future<Response<dynamic>> post(String path,
          {dynamic data, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: [
        {
          'displayName': 'Семеновой 7',
          'lat': 50.3446,
          'lng': 83.5129,
          'source': 'qa'
        }
      ]);
}
