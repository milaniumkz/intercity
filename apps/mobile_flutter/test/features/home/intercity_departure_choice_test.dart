import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intercity_mobile/core/services/app_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/home/screens/order_screen.dart';

void main() {
  testWidgets(
      'passenger departure is explicitly chosen and cancelling time keeps it unselected',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        home: OrderScreen(
            routeStage: 'intercity_start',
            apiClient: DateApi(),
            enableLiveMap: false,
            autoLocateOnStart: false));
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();
    final choose = find.text('Выберите дату');
    await tester.ensureVisible(choose);
    await tester.pumpAndSettle();
    expect(find.text('Выберите время'), findsOneWidget);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(choose, findsOneWidget);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Переключиться на ручной ввод'));
    await tester.pumpAndSettle();
    final date = DateTime.now().add(const Duration(days: 2));
    String two(int n) => n.toString().padLeft(2, '0');
    final text = '${two(date.day)}.${two(date.month)}.${date.year}';
    await tester.enterText(
        find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextField)),
        text);
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Перейти в режим ввода текста'));
    await tester.pumpAndSettle();
    final times = find.descendant(
        of: find.byType(TimePickerDialog), matching: find.byType(TextField));
    await tester.enterText(times.first, '23');
    await tester.enterText(times.last, '59');
    await tester.tap(find.text('Выбрать'));
    await tester.pumpAndSettle();
    expect(find.textContaining('$text 23:59'), findsWidgets);
    expect(choose, findsNothing);
    final draft = jsonDecode((await AppPreferences.getOrderDraft())!);
    final saved = DateTime.parse(draft['intercityDate']).toLocal();
    expect(saved.day, date.day);
    expect(saved.hour, 23);
    expect(saved.minute, 59);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();
    expect(find.textContaining('$text 23:59'), findsWidgets);
    expect(find.text('Выберите дату'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

class DateApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: []);
}
