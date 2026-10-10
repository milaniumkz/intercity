import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/road_route_layer.dart';

class SharedTripPage extends StatefulWidget {
  const SharedTripPage(
      {super.key, required this.token, this.apiClient, this.mapTileProvider});
  final String token;
  final ApiClient? apiClient;
  final TileProvider? mapTileProvider;
  @override
  State<SharedTripPage> createState() => _SharedTripPageState();
}

class _SharedTripPageState extends State<SharedTripPage> {
  late final _api = widget.apiClient ?? ApiClient();
  late final _roads = RoadRouteRepository(_api);
  Timer? _timer;
  Map<String, dynamic>? _trip;
  List<LatLng> _route = [];
  String? _error;
  String? _routeKey;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final response = await _api.get('/orders/shared/${widget.token}');
      final trip = Map<String, dynamic>.from(response.data as Map);
      final from = _point(trip, 'from');
      final to = _point(trip, 'to');
      final key = '$from:$to';
      if (_routeKey != key) {
        try {
          _route = await _roads.route(from, to);
        } catch (_) {
          _route = [];
        }
        _routeKey = key;
      }
      if (mounted) {
        setState(() {
          _trip = trip;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _trip == null
            ? 'Ссылка недействительна или срок её действия истёк.'
            : 'Не удалось обновить положение. Повторяем запрос…');
      }
    } finally {
      _busy = false;
    }
  }

  LatLng _point(Map trip, String prefix) => LatLng(
      (trip['${prefix}Lat'] as num).toDouble(),
      (trip['${prefix}Lng'] as num).toDouble());
  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Поездка')),
          body: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!))));
    }
    final from = _point(trip, 'from');
    final to = _point(trip, 'to');
    final driver = trip['driver'] as Map?;
    final online = driver?['online'] as Map?;
    final car = online?['lastLat'] is num && online?['lastLng'] is num
        ? LatLng((online!['lastLat'] as num).toDouble(),
            (online['lastLng'] as num).toDouble())
        : null;
    final status = switch (trip['status']) {
      'DRIVER_EN_ROUTE' ||
      'DRIVER_ASSIGNED' ||
      'ACCEPTED' =>
        'Водитель едет к пассажиру',
      'DRIVER_ARRIVED' => 'Водитель на месте',
      'IN_PROGRESS' => 'Поездка идёт',
      'COMPLETED' => 'Поездка завершена',
      'CANCELLED' => 'Поездка отменена',
      _ => 'Поиск водителя'
    };
    return Scaffold(
        appBar: AppBar(title: const Text('Поездка')),
        body: Column(children: [
          Expanded(
              child: FlutterMap(
                  options: MapOptions(
                      initialCenter: from,
                      initialCameraFit: CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(
                              [from, to, if (car != null) car]),
                          padding: const EdgeInsets.all(48))),
                  children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    tileProvider: widget.mapTileProvider,
                    userAgentPackageName: 'kz.intercity.app'),
                if (_route.isNotEmpty)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: _route,
                        color: const Color(0xFF842BFF),
                        strokeWidth: 5)
                  ]),
                MarkerLayer(markers: [
                  Marker(
                      point: from,
                      child: const Icon(Icons.trip_origin,
                          color: Color(0xFF842BFF), size: 30)),
                  Marker(
                      point: to,
                      child: const Icon(Icons.location_on,
                          color: Colors.redAccent, size: 36)),
                  if (car != null)
                    Marker(
                        point: car,
                        child: const Icon(Icons.local_taxi,
                            color: Color(0xFF842BFF), size: 36))
                ]),
                const RichAttributionWidget(attributions: [
                  TextSourceAttribution('OpenStreetMap contributors')
                ]),
              ])),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(status,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        Text('Откуда: ${trip['fromAddress'] ?? ''}'),
                        const SizedBox(height: 6),
                        Text('Куда: ${trip['toAddress'] ?? ''}'),
                        if (driver != null) ...[
                          const SizedBox(height: 10),
                          Text(
                              '${driver['carModel'] ?? ''} · ${driver['carNumber'] ?? ''}')
                        ],
                        const SizedBox(height: 10),
                        Text(_error ?? 'Положение обновляется автоматически',
                            style: Theme.of(context).textTheme.bodySmall)
                      ]))),
        ]));
  }
}
