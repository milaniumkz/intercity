import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/utils/request_flow_utils.dart';

void main() {
  group('request flow utils', () {
    test('city fixed requires confirmed coordinates and system price', () {
      expect(requiresConfirmedCoordinates(requestTypeCityFixed), isTrue);
      expect(supportsSystemPriceForRequestType(requestTypeCityFixed), isTrue);
      expect(supportsVehicleClassForRequestType(requestTypeCityFixed), isTrue);
      expect(
        paymentMethodsForRequestType(requestTypeCityFixed),
        contains(paymentMethodBonus),
      );
    });

    test('city auction allows manual addresses and disables system price', () {
      expect(
          supportsManualAddressForRequestType(requestTypeCityAuction), isTrue);
      expect(requiresConfirmedCoordinates(requestTypeCityAuction), isFalse);
      expect(
          supportsSystemPriceForRequestType(requestTypeCityAuction), isFalse);
      expect(
          supportsVehicleClassForRequestType(requestTypeCityAuction), isFalse);
    });

    test('delivery exposes only cash and card transfer payment methods', () {
      for (final requestType in const [
        requestTypeDeliveryCity,
        requestTypeDeliveryIntercity,
        requestTypeDeliveryRf,
      ]) {
        expect(
          paymentMethodsForRequestType(requestType),
          const [paymentMethodCash, paymentMethodCardTransfer],
        );
      }
    });

    test('labels stay user-facing and stable', () {
      expect(requestTypeLabel(requestTypeCityAuction), 'Аукцион');
      expect(paymentMethodLabel(paymentMethodCardTransfer), 'безналичными');
      expect(paymentMethodLabel(paymentMethodBonus), 'бонусами');
      expect(vehicleClassLabel(vehicleClassBusiness), 'Бизнес');
    });
  });
}
