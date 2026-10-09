import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/theme/theme_controller.dart';
import 'package:intercity_mobile/features/shared/widgets/order_chat_sheet.dart';

class _ChatApi extends ApiClient {
  @override
  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) async =>
      Response(requestOptions: RequestOptions(path: path), data: [
        {
          'id': 'mine',
          'isMine': true,
          'participantRole': 'PASSENGER',
          'sender': {'role': 'DRIVER', 'name': 'Олег'},
          'text': 'Я у подъезда',
          'createdAt': '2026-10-09T12:15:00'
        },
        {
          'id': 'other',
          'isMine': false,
          'participantRole': 'DRIVER',
          'sender': {'role': 'DRIVER', 'name': 'Данил'},
          'text': 'Подъезжаю',
          'createdAt': '2026-10-09T12:16:00'
        },
      ]);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'chat separates participants and shows authors and time in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
              body: OrderChatSheet(
                  orderId: 'ride',
                  orderStatus: 'DRIVER_EN_ROUTE',
                  title: 'Чат с водителем',
                  currentRole: 'PASSENGER',
                  apiClient: _ChatApi()))));
      await tester.pumpAndSettle();
      expect(find.text('Вы'), findsOneWidget);
      expect(find.text('Водитель · Данил'), findsOneWidget);
      expect(find.text('12:15'), findsOneWidget);
      expect(find.text('12:16'), findsOneWidget);
      final mine =
          tester.getRect(find.byKey(const ValueKey('chat-message-mine')));
      final other =
          tester.getRect(find.byKey(const ValueKey('chat-message-other')));
      expect(mine.right, closeTo(304, 1));
      expect(other.left, closeTo(16, 1));
      expect(mine.left, greaterThan(other.left));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
