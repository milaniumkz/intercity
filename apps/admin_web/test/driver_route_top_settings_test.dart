import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/widgets/driver_route_top_settings_card.dart';

void main() {
  testWidgets(
      'route top tariff previews RUB and saves KZT base, rate and duration',
      (tester) async {
    final api = _Api();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: DriverRouteTopSettingsCard()))));
    await tester.pumpAndSettle();
    expect(find.text('Стоимость в России: 142.86 руб.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Базовая цена, тг'), '1400');
    await tester.pump();
    expect(find.text('Стоимость в России: 200.00 руб.'), findsOneWidget);
    await tester.tap(find.text('Сохранить тариф топа'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(api.saved!['value']) as Map;
    expect(saved['priceKzt'], 1400);
    expect(saved['kztPerRub'], 7);
    expect(saved['durationHours'], 12);
    expect(saved['firstAccessSeconds'], 30);
  });
}

class _Api implements AdminApi {
  Map? saved;
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      Response(requestOptions: RequestOptions(path: path), data: []);
  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    saved = Map.from(data);
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

  @override
  Future<Map<String, dynamic>> login(String a, String b) async => {};
  @override
  Future<void> logout() async {}
  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) =>
      post(path, data: data);
  @override
  Future<Response<dynamic>> delete(String path) => post(path);
}
