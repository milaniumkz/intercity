import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:intercity_mobile/core/api/api_client.dart';
import 'package:intercity_mobile/core/widgets/road_route_layer.dart';

class _RouteApi extends ApiClient {
  int calls = 0;
  bool fail = false;
  final pending = <Completer<Response<dynamic>>>[];
  bool delay = false;
  @override
  Future<Response<dynamic>> get(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) async {
    calls++;
    expect(path, '/route');
    if (delay) {
      final completer = Completer<Response<dynamic>>();
      pending.add(completer);
      return completer.future;
    }
    if (fail) throw Exception('router unavailable');
    return _response();
  }
}

Response<dynamic> _response({double lng = 82.62}) =>
    Response(requestOptions: RequestOptions(path: '/route'), data: {
      'duration': 7,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [82.61, 49.95],
          [lng, 49.94],
          [82.609, 49.90]
        ]
      }
    });
Widget _map(RoadRouteRepository repository,
        {LatLng from = const LatLng(49.95, 82.61)}) =>
    MaterialApp(
      home: Scaffold(
          body: FlutterMap(
        options: const MapOptions(
            initialCenter: LatLng(49.95, 82.61), initialZoom: 12),
        children: [
          RoadRouteLayer(
              from: from,
              to: const LatLng(49.90, 82.609),
              color: Colors.purple,
              repository: repository)
        ],
      )),
    );
void main() {
  testWidgets('renders all road vertices and reuses geometry across screens',
      (tester) async {
    final api = _RouteApi();
    final repository = RoadRouteRepository(api);
    await tester.pumpWidget(_map(repository));
    await tester.pumpAndSettle();
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(layer.polylines.single.points.length, 3);
    expect(layer.polylines.single.points[1], const LatLng(49.94, 82.62));
    await repository.route(
        const LatLng(49.95, 82.61), const LatLng(49.90, 82.609));
    expect(api.calls, 1);
    final details = await repository.details(
        const LatLng(49.95, 82.61), const LatLng(49.90, 82.609));
    expect(details.durationMinutes, 7);
    expect(api.calls, 1);
  });
  testWidgets('failure draws no straight line and supports retry',
      (tester) async {
    final api = _RouteApi()..fail = true;
    await tester.pumpWidget(_map(RoadRouteRepository(api)));
    await tester.pumpAndSettle();
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.text('Маршрут недоступен. Повторить'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(api.calls, 2);
  });
  testWidgets('late geometry for old coordinates cannot overwrite new route',
      (tester) async {
    final api = _RouteApi()..delay = true;
    final repository = RoadRouteRepository(api);
    await tester.pumpWidget(_map(repository));
    await tester.pump();
    await tester.pumpWidget(_map(repository, from: const LatLng(49.96, 82.61)));
    await tester.pump();
    api.pending[1].complete(_response(lng: 82.63));
    await tester.pumpAndSettle();
    api.pending[0].complete(_response());
    await tester.pumpAndSettle();
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(layer.polylines.single.points[1], const LatLng(49.94, 82.63));
  });
}
