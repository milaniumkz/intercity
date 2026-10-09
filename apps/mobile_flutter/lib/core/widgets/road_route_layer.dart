import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../api/api_client.dart';

/// Shared road geometry: successful requests are cached, failed ones are retried.
class RoadRouteRepository {
  RoadRouteRepository(this.api);
  final ApiClient api;
  static final shared = RoadRouteRepository(ApiClient());
  final _cache = <String, ({DateTime expires, List<LatLng> points})>{};
  final _pending = <String, Future<List<LatLng>>>{};

  Future<List<LatLng>> route(LatLng from, LatLng to) async {
    final key =
        '${from.latitude},${from.longitude}:${to.latitude},${to.longitude}';
    final cached = _cache[key];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.points;
    }
    if (_pending[key] case final request?) return request;
    final request = _load(from, to).then((points) {
      if (_cache.length >= 100) _cache.remove(_cache.keys.first);
      _cache[key] = (
        expires: DateTime.now().add(const Duration(minutes: 5)),
        points: points
      );
      return points;
    });
    _pending[key] = request;
    try {
      return await request;
    } finally {
      _pending.remove(key);
    }
  }

  Future<List<LatLng>> _load(LatLng from, LatLng to) async {
    final response = await api.get('/route', queryParameters: {
      'fromLat': from.latitude,
      'fromLng': from.longitude,
      'toLat': to.latitude,
      'toLng': to.longitude,
    });
    final data = response.data;
    final geometry = data is Map ? data['geometry'] : null;
    final coordinates = geometry is Map && geometry['type'] == 'LineString'
        ? geometry['coordinates']
        : null;
    if (coordinates is! List || coordinates.length < 2) {
      throw const FormatException('Road geometry unavailable');
    }
    final points = <LatLng>[];
    for (final c in coordinates) {
      if (c is! List || c.length < 2 || c[0] is! num || c[1] is! num) {
        throw const FormatException('Invalid road coordinates');
      }
      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
        throw const FormatException('Invalid road coordinates');
      }
      points.add(LatLng(lat, lng));
    }
    return points;
  }
}

class RoadRouteLayer extends StatefulWidget {
  const RoadRouteLayer(
      {super.key,
      required this.from,
      required this.to,
      required this.color,
      this.strokeWidth = 5,
      this.repository});
  final LatLng from;
  final LatLng to;
  final Color color;
  final double strokeWidth;
  final RoadRouteRepository? repository;
  @override
  State<RoadRouteLayer> createState() => _RoadRouteLayerState();
}

class _RoadRouteLayerState extends State<RoadRouteLayer> {
  List<LatLng> _points = const [];
  bool _failed = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RoadRouteLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from ||
        oldWidget.to != widget.to ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _points = const [];
      _failed = false;
    });
    try {
      final points = await (widget.repository ?? RoadRouteRepository.shared)
          .route(widget.from, widget.to);
      if (mounted && request == _request) setState(() => _points = points);
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isNotEmpty) {
      return PolylineLayer(polylines: [
        Polyline(
            points: _points,
            color: widget.color,
            strokeWidth: widget.strokeWidth)
      ]);
    }
    return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Card(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: _failed
                ? TextButton(
                    onPressed: _load,
                    child: const Text('Маршрут недоступен. Повторить'))
                : const Text('Строим маршрут по дорогам…'),
          )),
        ));
  }
}
