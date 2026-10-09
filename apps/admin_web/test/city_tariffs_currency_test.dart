import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/screens/admin_dashboard_page.dart';

void main() {
  testWidgets('city country is stored when creating and editing a city',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _TariffApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminCitiesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Россия — рубли (₽)').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Название города'), 'Новый город');
    await tester.tap(find.widgetWithText(FilledButton, 'Создать город'));
    await tester.pumpAndSettle();
    expect(api.createdCities.single, containsPair('countryCode', 'RU'));
    await tester.tap(find.widgetWithText(ListTile, 'Москва • ₽'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Обновить город'));
    await tester.pumpAndSettle();
    expect(api.updatedCities.single, containsPair('countryCode', 'RU'));
  });

  testWidgets('city rates can be created and edited in RUB and KZT',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _TariffApi();
    AdminApiClient.debugOverride(api);
    addTearDown(() => AdminApiClient.debugOverride(null));
    await tester.pumpWidget(const MaterialApp(home: AdminTariffsPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(
            TextField, 'Город тарифа — начните вводить название'),
        'Москва');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Москва,').last);
    await tester.pumpAndSettle();
    expect(find.text('₽'), findsNWidgets(4));
    await tester.enterText(
        find.widgetWithText(TextField, 'Базовая стоимость'), '150');
    await tester.enterText(
        find.widgetWithText(TextField, 'Цена за км'), '20,5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Цена за минуту'), '5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Минимальная стоимость'), '200');
    final create = find.widgetWithText(FilledButton, 'Создать городской тариф');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(api.created.single, containsPair('cityId', 'ru'));
    expect(api.created.single, containsPair('basePrice', 150.0));
    expect(api.created.single, containsPair('pricePerKm', 20.5));

    final tariff = find.widgetWithText(ListTile, 'Стандарт');
    await tester.ensureVisible(tariff);
    await tester.tap(tariff);
    await tester.pumpAndSettle();
    final km = find.widgetWithText(TextField, 'Цена за км');
    await tester.ensureVisible(km);
    await tester.enterText(km, '30');
    final save =
        find.widgetWithText(FilledButton, 'Сохранить изменения тарифа');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.updated.single, containsPair('pricePerKm', 30.0));

    final city = find.widgetWithText(
        TextField, 'Город тарифа — начните вводить название');
    await tester.ensureVisible(city);
    await tester.enterText(city, 'Алматы');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Алматы,').last);
    await tester.pumpAndSettle();
    expect(find.text('₸'), findsNWidgets(4));
  });
}

class _TariffApi implements AdminApi {
  final created = <Map<String, dynamic>>[];
  final updated = <Map<String, dynamic>>[];
  final createdCities = <Map<String, dynamic>>[];
  final updatedCities = <Map<String, dynamic>>[];
  final cities = [
    {
      'id': 'ru',
      'name': 'Москва',
      'countryCode': 'RU',
      'lat': 55.75,
      'lng': 37.6,
      'isActive': true
    },
    {
      'id': 'kz',
      'name': 'Алматы',
      'countryCode': 'KZ',
      'lat': 43.23,
      'lng': 76.89,
      'isActive': true
    },
  ];
  final tariffs = <Map<String, dynamic>>[];

  Response<dynamic> response(String path, dynamic data) => Response(
      requestOptions: RequestOptions(path: path), data: data, statusCode: 200);

  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? query}) async =>
      response(
          path,
          path == '/admin/cities'
              ? cities
              : path == '/admin/tariffs/city'
                  ? tariffs
                  : []);

  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    final payload = Map<String, dynamic>.from(data as Map);
    if (path == '/admin/cities') {
      createdCities.add(payload);
      return response(path, payload);
    }
    created.add(payload);
    tariffs.add(
        {...payload, 'id': 'tariff', 'isActive': true, 'city': cities.first});
    return response(path, tariffs.last);
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) async {
    if (path.startsWith('/admin/cities/')) {
      updatedCities.add(Map<String, dynamic>.from(data as Map));
      return response(path, data);
    }
    updated.add(Map<String, dynamic>.from(data as Map));
    tariffs.first.addAll(updated.last);
    return response(path, tariffs.first);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
