import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/road_route_layer.dart';

class DriverIdleMap extends StatefulWidget {
  const DriverIdleMap(
      {super.key,
      required this.point,
      required this.marker,
      this.tileProvider});
  final LatLng point;
  final Widget marker;
  final TileProvider? tileProvider;
  @override
  State<DriverIdleMap> createState() => DriverIdleMapState();
}

class DriverIdleMapState extends State<DriverIdleMap>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _animation;
  LatLng? _from, _to, _lastFollowed;
  bool _ready = false, _follow = true;
  @override
  void initState() {
    super.initState();
    _lastFollowed = widget.point;
    _animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650))
      ..addListener(() {
        if (!_ready || !_follow || _from == null || _to == null) return;
        final t = Curves.easeOut.transform(_animation.value);
        _map.move(
            LatLng(_from!.latitude + (_to!.latitude - _from!.latitude) * t,
                _from!.longitude + (_to!.longitude - _from!.longitude) * t),
            _map.camera.zoom);
      });
  }

  @override
  void didUpdateWidget(covariant DriverIdleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point != widget.point &&
        _follow &&
        _ready &&
        const Distance().as(LengthUnit.Meter, _lastFollowed!, widget.point) >=
            10) {
      _moveToDriver();
    }
  }

  void recenter() {
    _follow = true;
    _moveToDriver();
  }

  void _moveToDriver() {
    if (!_ready) return;
    _from = _map.camera.center;
    _to = widget.point;
    _lastFollowed = widget.point;
    _animation.forward(from: 0);
  }

  @override
  void dispose() {
    _animation.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FlutterMap(
          mapController: _map,
          options: MapOptions(
              initialCenter: widget.point,
              initialZoom: 16.5,
              minZoom: 3,
              maxZoom: 19,
              onMapReady: () {
                _ready = true;
                if (_follow) _moveToDriver();
              },
              onPositionChanged: (_, gesture) {
                if (gesture) {
                  _follow = false;
                  _animation.stop();
                }
              },
              interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom)),
          children: [
            TileLayer(
                tileProvider: widget.tileProvider,
                urlTemplate: AppConstants.osmTileUrl,
                subdomains: AppConstants.mapTileSubdomains,
                userAgentPackageName: 'com.milanium.intercity',
                retinaMode: true),
            const Padding(
                padding: EdgeInsets.only(bottom: 90),
                child: MapDataAttribution()),
            MarkerLayer(markers: [
              Marker(
                  point: widget.point,
                  width: 58,
                  height: 58,
                  child: widget.marker)
            ]),
          ]);
}
