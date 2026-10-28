import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

void main() {
  testWidgets(
      'intercity origin search survives keyboard resize and selecting twice cannot close the order form',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: OrderScreen(
            routeStage: 'intercity_start',
            apiClient: SearchApi(),
            enableLiveMap: false,
            autoLocateOnStart: false)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Город откуда'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Город откуда'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'Поиск города по карте');
    await tester.enterText(input, 'Усть');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'Усть');
    final result = find.byType(ListTile);
    expect(result, findsOneWidget);
    final select = tester.widget<ListTile>(result).onTap!;
    select();
    select();
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('Куда поедем?'), findsOneWidget);
    expect(find.text('Город откуда'), findsOneWidget);
    expect(find.textContaining('Усть-Каменогорск'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class SearchApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: []);
  @override
  Future<Response<dynamic>> post(String path,
          {dynamic data, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: [
        {
          'id': 'city',
          'name': 'Усть-Каменогорск',
          'displayName': 'Усть-Каменогорск, Казахстан',
          'lat': 49.97,
          'lng': 82.61
        }
      ]);
}
