import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

void main() {
  testWidgets('two seats survive moving between intercity booking screens',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget page(String stage) => MaterialApp(
        home: OrderScreen(
            routeStage: stage,
            apiClient: DateApi(),
            enableLiveMap: false,
            autoLocateOnStart: false));
    await tester.pumpWidget(page('intercity_start'));
    await tester.pumpAndSettle();
    final increase = find.byKey(const ValueKey('intercity-seats-increase'));
    await tester.ensureVisible(increase);
    await tester.pumpAndSettle();
    await tester.tap(increase);
    await tester.pumpAndSettle();
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    expect(draft['intercitySeats'], 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('intercity_start'));
    await tester.pumpAndSettle();
    expect(find.text('2 пассажир(а)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('intercity_options'));
    await tester.pumpAndSettle();
    expect(
        jsonDecode((await AppPreferences.getOrderDraft())!)['intercitySeats'],
        2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('intercity_start'));
    await tester.pumpAndSettle();
    expect(find.text('2 пассажир(а)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class DateApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: []);
}
