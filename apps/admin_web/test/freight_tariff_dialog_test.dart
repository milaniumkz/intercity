import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_admin/core/api/admin_api_client.dart';
import 'package:intercity_admin/features/admin/widgets/freight_tariff_dialog.dart';

class _Api implements AdminApiClient {
  final saved = <String, dynamic>{};
  String path = '';
  @override
  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    this.path = path;
    saved.addAll(data as Map<String, dynamic>);
    return Response(
        requestOptions: RequestOptions(path: path), statusCode: 200);
  }

  @override
  Future<Response<dynamic>> patch(String path, {dynamic data}) =>
      post(path, data: data);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final kind in ['cargo', 'delivery']) {
    testWidgets(
        '$kind saves entered rates, validates negatives and edits existing tariff',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api();
      AdminApiClient.debugOverride(api);
      addTearDown(() => AdminApiClient.debugOverride(null));
      Future<void> open([Map<String, dynamic>? tariff]) async {
        await tester.pumpWidget(MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => FreightTariffDialog(
                                kind: kind, tariff: tariff)),
                        child: const Text('Открыть'))))));
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      for (final entry in {
        'Название': 'Проверка',
        'Базовая стоимость': '1200',
        'Цена за км': '150,5',
        'Цена за кг': '20',
        'Минимальная стоимость': '2000',
        if (kind == 'delivery') 'Доплата от двери до двери': '350'
      }.entries) {
        await tester.enterText(
            find.widgetWithText(TextFormField, entry.key), entry.value);
      }
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Цена за кг'), '-1');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.saved, isEmpty);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Цена за кг'), '20');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.path, '/admin/tariffs/$kind');
      expect(api.saved['pricePerKm'], 150.5);
      expect(api.saved['pricePerKg'], 20.0);
      expect(api.saved['countryCode'], 'KZ');
      await open({...api.saved, 'id': 'test', 'countryCode': 'RU'});
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Базовая стоимость'), '700');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(api.path, '/admin/tariffs/$kind/test');
      expect(api.saved['basePrice'], 700);
      expect(api.saved['countryCode'], 'RU');
      expect(tester.takeException(), isNull);
    });
  }
}
