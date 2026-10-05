import 'package:dio/dio.dart';
import 'package:intercity_shared/intercity_shared.dart';

import '../api/api_client.dart';

class VehicleCatalogService {
  VehicleCatalogService({
    Dio? dio,
    ApiClient? apiClient,
    bool useBackendCatalog = true,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://vpic.nhtsa.dot.gov/api',
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 20),
              ),
            ),
        _apiClient = apiClient,
        _useBackendCatalog = useBackendCatalog;

  static final VehicleCatalogService instance = VehicleCatalogService();

  final Dio _dio;
  final ApiClient? _apiClient;
  final bool _useBackendCatalog;

  List<Map<String, dynamic>>? _makesCache;
  final Map<String, List<String>> _modelsCache = <String, List<String>>{};

  Future<List<Map<String, dynamic>>> getMakes() async {
    if (_makesCache != null) return _makesCache!;
    if (_useBackendCatalog) {
      try {
        final res = await (_apiClient ?? ApiClient()).get(
          '/vehicle-catalog/makes',
        );
        final backendResults = (res.data as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .map((e) => {
                  'id': e['id'],
                  'name': (e['name'] ?? '').toString().trim(),
                })
            .where((e) => (e['name'] as String).isNotEmpty)
            .toList()
          ..sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String),
          );
        if (backendResults.isNotEmpty) {
          _makesCache = backendResults;
          return backendResults;
        }
      } catch (_) {}
    }

    final res = await _dio
        .get('/vehicles/GetMakesForVehicleType/car', queryParameters: {
      'format': 'json',
    });
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    final results = (data['Results'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map((e) => {
              'id': e['MakeId'],
              'name': (e['MakeName'] ?? '').toString().trim(),
            })
        .where((e) => (e['name'] as String).isNotEmpty)
        .toList();
    results
        .sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    _makesCache = results;
    return results;
  }

  Future<List<String>> getModelsForMake(String makeName) async {
    final key = makeName.trim().toUpperCase();
    if (key.isEmpty) return const [];
    final cached = _modelsCache[key];
    if (cached != null) return cached;

    if (_useBackendCatalog) {
      try {
        final res = await (_apiClient ?? ApiClient()).get(
          '/vehicle-catalog/models',
          queryParameters: {'make': makeName.trim()},
        );
        final backendResults = (res.data as List? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (backendResults.isNotEmpty) {
          _modelsCache[key] = backendResults;
          return backendResults;
        }
      } catch (_) {}
    }

    final encodedMake = Uri.encodeComponent(makeName.trim());

    final res = await _dio
        .get('/vehicles/GetModelsForMake/$encodedMake', queryParameters: {
      'format': 'json',
    });
    final data = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    final results = (data['Results'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map((e) => (e['Model_Name'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _modelsCache[key] = results;
    return results;
  }

  static const List<String> colorsRu = <String>[
    'Белый',
    'Черный',
    'Серый',
    'Серебристый',
    'Синий',
    'Голубой',
    'Красный',
    'Бордовый',
    'Зеленый',
    'Желтый',
    'Оранжевый',
    'Коричневый',
    'Бежевый',
    'Золотистый',
    'Фиолетовый',
    'Розовый',
  ];

  static String composeCarModelWithColor({
    required String make,
    required String model,
    required String color,
  }) =>
      VehicleDescriptor(make: make, model: model, color: color).displayValue;

  static ({String make, String model, String color}) parseComposedCarModel(
    String raw, {
    Iterable<String>? knownMakes,
  }) {
    final parsed = VehicleDescriptor.parse(raw, knownMakes: knownMakes);
    return (
      make: parsed.make,
      model: parsed.model,
      color: parsed.color,
    );
  }
}
