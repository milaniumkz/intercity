import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/road_route_layer.dart';

/// Keep the same map/camera while GPS changes; gestures temporarily pause follow.
class DriverNavigationMap extends StatefulWidget {
  const DriverNavigationMap(
      {super.key,
      required this.driver,
      required this.target,
      required this.heading,
      required this.route,
      required this.routeStart});
  final LatLng? driver;
  final LatLng target;
  final LatLng routeStart;
  final double heading;
  final List<LatLng> route;

  @override
  State<DriverNavigationMap> createState() => _DriverNavigationMapState();
}

class _DriverNavigationMapState extends State<DriverNavigationMap>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _animation;
  bool _ready = false;
  bool _follow = true;
  LatLng? _from, _to;
  double _rotationStart = 0, _rotationDelta = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650))
      ..addListener(() {
        if (!_ready || !_follow || _from == null || _to == null) return;
        final t = Curves.easeOut.transform(_animation.value);
        _map.moveAndRotate(
            LatLng(
              _from!.latitude + (_to!.latitude - _from!.latitude) * t,
              _from!.longitude + (_to!.longitude - _from!.longitude) * t,
            ),
            _map.camera.zoom,
            _rotationStart + _rotationDelta * t);
      });
  }

  @override
  void didUpdateWidget(covariant DriverNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driver != widget.driver ||
        oldWidget.heading != widget.heading) {
      _followDriver();
    }
  }

  void _followDriver() {
    if (!_ready || !_follow || widget.driver == null) return;
    _from = _map.camera.center;
    _to = widget.driver;
    _rotationStart = _map.camera.rotation;
    _rotationDelta = ((-widget.heading - _rotationStart + 180) % 360) - 180;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _animation.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.driver ?? widget.routeStart;
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: start,
          initialZoom: 16.5,
          minZoom: 3,
          maxZoom: 19,
          initialRotation: -widget.heading,
          onMapReady: () {
            _ready = true;
            _followDriver();
          },
          onPositionChanged: (_, hasGesture) {
            if (hasGesture && _follow) {
              _animation.stop();
              setState(() => _follow = false);
            }
          },
        ),
        children: [
          TileLayer(
              urlTemplate: AppConstants.osmTileUrl,
              subdomains: AppConstants.mapTileSubdomains,
              userAgentPackageName: 'com.milanium.intercity'),
          const MapDataAttribution(),
          if (widget.route.length >= 2)
            PolylineLayer(polylines: [
              Polyline(
                  points: widget.route,
                  strokeWidth: 6,
                  color: AppTheme.primaryColor)
            ])
          else
            RoadRouteLayer(
                from: widget.routeStart,
                to: widget.target,
                fitCamera: false,
                color: AppTheme.primaryColor),
          MarkerLayer(markers: [
            Marker(
                point: widget.target,
                width: 36,
                height: 36,
                child: const Icon(Icons.location_on,
                    size: 32, color: AppTheme.secondaryColor)),
            if (widget.driver != null)
              Marker(
                  point: widget.driver!,
                  width: 44,
                  height: 44,
                  child: Transform.rotate(
                      angle: widget.heading * math.pi / 180,
                      child: Container(
                          decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppTheme.primaryColor, width: 2)),
                          child: const Icon(Icons.navigation,
                              color: AppTheme.primaryColor, size: 30)))),
          ]),
        ],
      ),
      Positioned(
          right: 12,
          bottom: 24,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Следовать за машиной',
            backgroundColor: _follow ? AppTheme.primaryColor : Colors.white,
            foregroundColor: _follow ? Colors.white : AppTheme.primaryColor,
            onPressed: () {
              setState(() => _follow = true);
              _map.move(_map.camera.center, 16.5);
              _followDriver();
            },
            child: Icon(_follow ? Icons.navigation : Icons.my_location),
          )),
    ]);
  }
}
