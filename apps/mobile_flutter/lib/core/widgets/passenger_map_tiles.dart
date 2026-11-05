import 'dart:async';
import 'package:flutter/material.dart';
import 'map_tile_transport.dart';
import 'package:flutter_map/flutter_map.dart';
import '../constants/app_constants.dart';
import '../utils/network_recovery.dart';
import '../services/technical_telemetry.dart';

/// GPS permission and raster-map loading are independent. Never leave a blank
/// surface when the tile network fails, and evict failed images before retry.
class PassengerMapTiles extends StatefulWidget {
  const PassengerMapTiles({super.key, this.tileProvider, this.networkEvents});
  final Stream<void>? networkEvents;
  final TileProvider? tileProvider;
  @override
  State<PassengerMapTiles> createState() => _PassengerMapTilesState();
}

class _PassengerMapTilesState extends State<PassengerMapTiles> {
  late final TileProvider _provider = widget.tileProvider ??
      NetworkTileProvider(httpClient: MapTileHttpClient());
  int _attempt = 0;
  final Object _retryOwner = Object();
  final Map<TileImage, VoidCallback> _observed = {};
  Timer? _timeout, _monitor, _automaticRetry;
  StreamSubscription<void>? _network;
  AppLifecycleListener? _lifecycle;
  MapCamera? _camera;
  String _viewport = '';
  bool _viewExpired = false;
  int _autoAttempts = 0;
  String get _url => AppConstants.serverMapTileUrl;
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
  bool _partialFailure = false;
  @override
  void initState() {
    super.initState();
    void restored() {
      if (mounted &&
          (_failed ||
              _visibleTiles.any((t) => t.loadError || t.imageInfo == null))) {
        unawaited(_retry());
      }
    }

    _network = (widget.networkEvents ?? networkRecoveryEvents())
        .listen((_) => restored());
    _lifecycle = AppLifecycleListener(onResume: restored);
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
      bool displayed(TileImage t) =>
          t.imageInfo != null &&
          !t.loadError &&
          t.readyToDisplay &&
          t.opacity > 0;
      final loaded = visible.any(displayed);
      final complete = visible.isNotEmpty && visible.every(displayed);
      final needsRetry =
          visible.any((t) => t.loadError) || (!complete && _viewExpired);
      // A late tile is not a failure of the entire map.
      final failed = !loaded && _viewExpired;
      if (complete) {
        _timeout?.cancel();
        _automaticRetry?.cancel();
        _automaticRetry = null;
        _autoAttempts = 0;
      }
      if (needsRetry &&
          _automaticRetry == null &&
          _autoAttempts < 3 &&
          !_retrying) {
        unawaited(TechnicalTelemetry.mapEvent('map.load_failed', 'server'));
        _automaticRetry =
            Timer(Duration(seconds: [1, 3, 8][_autoAttempts]), () {
          _automaticRetry = null;
          _autoAttempts++;
          _retry(automatic: true);
        });
      }
      final partialFailure =
          loaded && !complete && _viewExpired && _autoAttempts >= 3;
      if (loaded != _loaded ||
          failed != _failed ||
          partialFailure != _partialFailure) {
        setState(() {
          _loaded = loaded;
          _failed = failed;
          _partialFailure = partialFailure;
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
    // flutter_map 6 may create a tile during layout without starting it until
    // a camera event. A restored camera can remain unchanged on re-entry.
    // Start only unstarted visible tiles after layout, retaining cached pixels.
    if (tile.loadStarted == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !tile.cancelLoading.isCompleted &&
            tile.loadStarted == null) {
          tile.load();
        }
      });
    }
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
    final tiles = _visibleTiles
        .where((tile) =>
            tile.loadError || (_viewExpired && tile.imageInfo == null))
        .toList();
    if (!automatic) _startTimeout();
    _attempt++;
    await Future.wait(tiles.map((tile) async {
      final original = tile.imageProvider is _RetryTileImage
          ? (tile.imageProvider as _RetryTileImage).original
          : tile.imageProvider;
      try {
        await tile.imageProvider.evict();
        await original.evict();
      } catch (_) {}
      if (!mounted || tile.cancelLoading.isCompleted) return;
      tile.imageProvider = _RetryTileImage(original, _attempt, _retryOwner);
      tile.loadError = false;
      tile.load();
    }));
    if (!mounted) return;
    _retrying = false;
    if (!automatic) setState(() => _failed = false);
    _health();
  }

  @override
  void dispose() {
    _network?.cancel();
    _lifecycle?.dispose();
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
          panBuffer: 0,
          tileProvider: _provider,
          urlTemplate: _url,
          maxNativeZoom: 19,
          tileDisplay: const TileDisplay.instantaneous(),
          userAgentPackageName: 'com.milanium.intercity',
          evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
          tileBuilder: (context, child, tile) {
            _observe(tile);
            return child;
          },
          errorTileCallback: (_, __, ___) => _health()),
      if (!_loaded && !_failed)
        const Positioned(
            top: 70,
            left: 12,
            right: 12,
            child: IgnorePointer(
                child: Center(
                    child: Material(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Загрузка карты…')))))),
      if (_partialFailure)
        Positioned(
            top: 70,
            right: 12,
            child: Material(
                borderRadius: BorderRadius.circular(12),
                child: TextButton.icon(
                    onPressed: () => _retry(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Догрузить карту')))),
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

/// Renew a failed image's Flutter key without changing its cacheable HTTP URL.
class _RetryTileImage extends ImageProvider<_RetryTileKey> {
  const _RetryTileImage(this.original, this.generation, this.owner);
  final ImageProvider original;
  final int generation;
  final Object owner;
  @override
  Future<_RetryTileKey> obtainKey(ImageConfiguration configuration) async =>
      _RetryTileKey(
          original, await original.obtainKey(configuration), generation, owner);
  @override
  ImageStreamCompleter loadImage(
      _RetryTileKey key, ImageDecoderCallback decode) {
    // Delegate decoding using the original provider's correctly typed key.
    // ignore: invalid_use_of_protected_member
    return key.original.loadImage(key.originalKey, decode);
  }
}

class _RetryTileKey {
  const _RetryTileKey(
      this.original, this.originalKey, this.generation, this.owner);
  final ImageProvider original;
  final dynamic originalKey;
  final int generation;
  final Object owner;
  @override
  bool operator ==(Object other) =>
      other is _RetryTileKey &&
      other.originalKey == originalKey &&
      other.generation == generation &&
      identical(other.owner, owner);
  @override
  int get hashCode => Object.hash(originalKey, generation, owner);
}
