import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/features/passenger/screens/intercity_request_page.dart';

void main() {
  testWidgets('completed intercity prompts rating and stores it once',
      (tester) async {
    tester.view.physicalSize = const Size(392, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = TripApi(status: 'COMPLETED');
    await tester.pumpWidget(MaterialApp(
        home: IntercityRequestPage(
            requestId: 'trip', apiClient: api, enableLiveMap: false)));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(api.ratings, [5]);
    expect(find.text('Ваша оценка: 5 ★'), findsOneWidget);
    expect(find.text('Оценить водителя'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final available in [false, true]) {
    testWidgets(
        'pickup ETA ${available ? 'uses real route duration' : 'explicitly awaits GPS'}',
        (tester) async {
      tester.view.physicalSize = const Size(392, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: IntercityRequestPage(
              requestId: 'trip',
              apiClient: TripApi(
                  status: 'DRIVER_EN_ROUTE',
                  location: available ? {'lat': 49.9, 'lng': 82.6} : null),
              enableLiveMap: false)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
          find.textContaining(available
              ? 'До приезда около 11 мин'
              : 'Время прибытия пока не определено'),
          findsOneWidget);
      expect(find.text('Поездка в пути'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'accepted trip shows numeric rating, real status and launches dialer',
      (tester) async {
    tester.view.physicalSize = const Size(392, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final api = TripApi();
    await tester.pumpWidget(MaterialApp(
        home: IntercityRequestPage(
            requestId: 'trip', apiClient: api, enableLiveMap: false)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('5.0'), findsOneWidget);
    expect(find.textContaining('ratingAvg'), findsNothing);
    expect(find.text('Водитель собирает пассажиров'), findsWidgets);
    expect(find.text('Поездка в пути'), findsNothing);
    expect(find.text('210 км'), findsNothing);
    expect(find.text('2 ч 15 мин'), findsNothing);
    await tester.tap(find.text('Позвонить'));
    await tester.pump();
    expect(
        calls.any((c) =>
            c.method == 'launch' &&
            (c.arguments as Map)['url'] == 'tel:+77058652235'),
        isTrue);
    await tester.tap(find.text('Чат'));
    await tester.pumpAndSettle();
    expect(api.chatReads, greaterThan(0));
    expect(find.text('Данные не найдены.'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Жду у входа');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(api.sent, ['Жду у входа']);
    expect(find.byKey(const ValueKey('chat-message-message')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class TripApi extends ApiClient {
  TripApi({this.status = 'DRIVER_ASSIGNED', this.location});
  final String status;
  final Map<String, dynamic>? location;

  int chatReads = 0;
  final sent = <String>[];
  final ratings = <int>[];
  @override
  Future<Response<dynamic>> post(String path,
      {dynamic data, Options? options}) async {
    if (path == '/intercity/requests/trip/rate') {
      ratings.add(data['rating'] as int);
      return Response(
          requestOptions: RequestOptions(path: path),
          data: {'success': true, 'pendingReview': false});
    }
    if (path != '/intercity/requests/trip/chat') {
      throw StateError('Wrong chat endpoint $path');
    }
    sent.add(data['text'] as String);
    return Response(requestOptions: RequestOptions(path: path), data: {});
  }

  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    if (path == '/route') {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [82.6, 49.9],
            [82.61, 49.91]
          ]
        },
        'duration': 10.4
      });
    }
    if (path.endsWith('/chat')) {
      if (path != '/intercity/requests/trip/chat') {
        throw StateError('Wrong chat endpoint $path');
      }
      chatReads++;
      return Response(
          requestOptions: RequestOptions(path: path),
          data: sent
              .map((text) => {
                    'id': 'message',
                    'text': text,
                    'isMine': true,
                    'participantRole': 'PASSENGER'
                  })
              .toList());
    }
    return Response(requestOptions: RequestOptions(path: path), data: {
      'id': 'trip',
      'requestType': 'INTERCITY',
      'status': status,
      'selectedDriverId': 'driver',
      'fromLat': 49.91,
      'fromLng': 82.61,
      'pickupProgress': {'driverLocation': location},
      'fromCity': 'Риддер',
      'toCity': 'Усть-Каменогорск',
      'price': 3000,
      'currency': 'KZT',
      'seats': 1,
      'offers': [
        {
          'id': 'offer',
          'status': 'ACCEPTED',
          'price': 3500,
          'driver': {
            'name': 'Олег',
            'phone': '+77058652235',
            'driverProfile': {
              'carModel': 'BMW X5',
              'carNumber': '077',
              'rating': {'ratingAvg': 5, 'ratingCount': 6}
            }
          }
        }
      ]
    });
  }
}
