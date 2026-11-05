import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../constants/app_constants.dart';

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
  Timer? _timeout;
  bool _failed = false, _loaded = false, _queued = false, _retrying = false;
  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted && !_loaded) setState(() => _failed = true);
    });
  }

  void _health() {
    if (_queued) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted) return;
      final loaded =
          _observed.keys.any((t) => t.imageInfo != null && !t.loadError);
      final failed = !loaded && _observed.keys.any((t) => t.loadError);
      if (loaded) _timeout?.cancel();
      if (loaded != _loaded || failed != _failed) {
        setState(() {
          _loaded = loaded;
          _failed = failed;
        });
      }
    });
  }

  void _observe(TileImage tile) {
    if (_observed.containsKey(tile)) return;
    void listener() => _health();
    _observed[tile] = listener;
    tile.addListener(listener);
    if (_observed.length > 256) {
      final old = _observed.keys.first;
      old.removeListener(_observed.remove(old)!);
    }
    _health();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    _retrying = true;
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
    for (final entry in _observed.entries) {
      entry.key.removeListener(entry.value);
    }
    _observed.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        TileLayer(
            key: ValueKey(_attempt),
            tileProvider: _provider,
            urlTemplate: AppConstants.osmTileUrl,
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
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить загрузку карты'))
                      ])))),
      ]);
}
