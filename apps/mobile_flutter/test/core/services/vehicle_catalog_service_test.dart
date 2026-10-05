import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/services/vehicle_catalog_service.dart';

void main() {
  group('VehicleCatalogService', () {
    test('parses multi-word make and preserves model and color', () {
      final parsed = VehicleCatalogService.parseComposedCarModel(
        'Land Rover Range Rover • Черный',
        knownMakes: const <String>['Land Rover', 'Toyota'],
      );

      expect(parsed.make, 'Land Rover');
      expect(parsed.model, 'Range Rover');
      expect(parsed.color, 'Черный');
    });

    test('falls back to first token when make catalog is unavailable', () {
      final parsed = VehicleCatalogService.parseComposedCarModel(
        'Toyota Camry • Белый',
      );

      expect(parsed.make, 'Toyota');
      expect(parsed.model, 'Camry');
      expect(parsed.color, 'Белый');
    });

    test('encodes make name safely when loading models', () async {
      final requestedPaths = <String>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://vpic.nhtsa.dot.gov/api'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedPaths.add(options.path);
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  data: <String, dynamic>{'Results': const <dynamic>[]},
                  statusCode: 200,
                ),
              );
            },
          ),
        );
      final service = VehicleCatalogService(dio: dio);

      await service.getModelsForMake('Land Rover');

      expect(
        requestedPaths.single,
        '/vehicles/GetModelsForMake/Land%20Rover',
      );
    });
  });
}
