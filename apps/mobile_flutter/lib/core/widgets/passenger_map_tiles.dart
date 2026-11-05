import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../constants/app_constants.dart';
import '../services/technical_telemetry.dart';

/// GPS permission and raster-map loading are independent. Never leave a blank
/// surface when the tile network fails, and evict failed images before retry.
class PassengerMapTiles extends StatefulWidget {
  const PassengerMapTiles({super.key, this.tileProvider});
  final TileProvider? tileProvider;
  @override
  State<PassengerMapTiles> createState() => _PassengerMapTilesState();
}

class _PassengerMapTilesState extends State<PassengerMapTiles> {
  late TileProvider _provider = widget.tileProvider ?? NetworkTileProvider();
  int _attempt = 0;
  final Map<TileImage, VoidCallback> _observed = {};
  Timer? _timeout, _monitor, _automaticRetry;
  MapCamera? _camera;
  String _viewport = '';
  bool _viewExpired = false;
  bool _serverTiles = false;
  int _autoAttempts = 0;
  String get _url => _serverTiles
      ? '${AppConstants.baseUrl}/geo/tiles/{z}/{x}/{y}.png'
      : AppConstants.osmTileUrl;
  Iterable<TileImage> get _visibleTiles {
    final camera = _camera;
    if (camera == null) return const [];
    final zoom = camera.zoom.round().clamp(0, 19);
    return _observed.keys.where((tile) {
      if (tile.coordinates.z != zoom) return false;
      final bounds = camera.pixelBoundsAtZoom(zoom.toDouble());
      final x = tile.coordinates.x * 256, y = tile.coordinates.y * 256;
      return x + 256 > bounds.min.x &&
          x < bounds.max.x &&
          y + 256 > bounds.min.y &&
          y < bounds.max.y;
    });
  }

  bool _failed = false, _loaded = false, _queued = false, _retrying = false;
  @override
  void initState() {
    super.initState();
    _startTimeout();
    _monitor = Timer.periodic(const Duration(seconds: 2), (_) => _health());
  }

  void _startTimeout() {
    _timeout?.cancel();
    _viewExpired = false;
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        _viewExpired = true;
        _health();
      }
    });
  }

  void _health() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final disposed = _observed.keys
          .where((tile) => tile.cancelLoading.isCompleted)
          .toList();
      for (final tile in disposed) {
        tile.removeListener(_observed.remove(tile)!);
      }
      final visible = _visibleTiles.toList();
      final loaded = visible.any((t) => t.imageInfo != null && !t.loadError);
      final timedOut = _viewExpired;
      final failed = !loaded && (timedOut || visible.any((t) => t.loadError));
      if (loaded) {
        _timeout?.cancel();
        _automaticRetry?.cancel();
        _automaticRetry = null;
        _autoAttempts = 0;
      }
      if (failed &&
          _automaticRetry == null &&
          _autoAttempts < 3 &&
          !_retrying) {
        unawaited(TechnicalTelemetry.mapEvent(
            'map.load_failed', _serverTiles ? 'server' : 'direct'));
        _automaticRetry =
            Timer(Duration(seconds: [1, 3, 8][_autoAttempts]), () {
          _automaticRetry = null;
          _autoAttempts++;
          _retry(automatic: true);
        });
      }
      if (loaded != _loaded || failed != _failed) {
        setState(() {
          _loaded = loaded;
          _failed = failed;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _observe(TileImage tile) {
    if (tile.cancelLoading.isCompleted || _observed.containsKey(tile)) return;
    void listener() => _health();
    _observed[tile] = listener;
    tile.addListener(listener);
    if (_observed.length > 256) {
      final old = _observed.keys.first;
      old.removeListener(_observed.remove(old)!);
    }
    _health();
  }

  Future<void> _retry({bool automatic = false}) async {
    if (_retrying) return;
    _retrying = true;
    _automaticRetry?.cancel();
    _automaticRetry = null;
    if (!automatic) _autoAttempts = 0;
    _serverTiles = true;
    _startTimeout();
    // The image provider caches by URL, including failed completers on web.
    // Evict before mounting the replacement layer, not during its disposal.
    await Future.wait(_observed.keys.map((tile) async {
      try {
        await tile.imageProvider.evict();
      } catch (_) {}
    }));
    if (!mounted) return;
    _retrying = false;
    for (final entry in _observed.entries) {
      entry.key.removeListener(entry.value);
    }
    _observed.clear();
    setState(() {
      _failed = false;
      _loaded = false;
      _attempt++;
      _provider = widget.tileProvider ?? NetworkTileProvider();
    });
    _startTimeout();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _monitor?.cancel();
    _automaticRetry?.cancel();
    for (final entry in _observed.entries) {
      entry.key.removeListener(entry.value);
    }
    _observed.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _camera = MapCamera.of(context);
    final c = _camera!;
    final viewport =
        '${c.zoom.round()}:${(c.pixelBounds.min.x / 128).floor()}:${(c.pixelBounds.min.y / 128).floor()}:${c.size}';
    if (_viewport != viewport) {
      _viewport = viewport;
      _startTimeout();
      _health();
    }
    return Stack(fit: StackFit.expand, children: [
      TileLayer(
          key: ValueKey(_attempt),
          tileProvider: _provider,
          urlTemplate: _url,
          maxNativeZoom: 19,
          userAgentPackageName: 'com.milanium.intercity',
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
          tileBuilder: (context, child, tile) {
            _observe(tile);
            return child;
          },
          errorTileCallback: (_, __, ___) => _health()),
      if (_failed)
        Positioned(
            top: 70,
            left: 12,
            right: 12,
            child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Не удалось загрузить карту. Проверьте соединение. Адреса можно ввести вручную.',
                          textAlign: TextAlign.center),
                      TextButton.icon(
                          onPressed: () => _retry(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить загрузку карты'))
                    ])))),
    ]);
  }
}
