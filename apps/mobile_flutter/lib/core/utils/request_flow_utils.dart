import 'localization_service.dart';

const String requestTypeCityFixed = 'CITY_FIXED';
const String requestTypeCityAuction = 'CITY_AUCTION';
const String requestTypeIntercity = 'INTERCITY';
const String requestTypeDeliveryCity = 'DELIVERY_CITY';
const String requestTypeDeliveryIntercity = 'DELIVERY_INTERCITY';
const String requestTypeDeliveryRf = 'DELIVERY_RF';

const String paymentMethodCard = 'CARD';
const String paymentMethodCash = 'CASH';
const String paymentMethodCardTransfer = 'CARD_TRANSFER';
const String paymentMethodBonus = 'BONUS';

const String vehicleClassEconomy = 'ECONOMY';
const String vehicleClassOptimal = 'OPTIMAL';
const String vehicleClassComfort = 'COMFORT';
const String vehicleClassBusiness = 'BUSINESS';

List<String> paymentMethodsForRequestType(String requestType) {
  switch (requestType) {
    case requestTypeCityFixed:
    case requestTypeCityAuction:
    case requestTypeIntercity:
      return const [
        paymentMethodCash,
        paymentMethodCard,
        paymentMethodCardTransfer,
        paymentMethodBonus,
      ];
    case requestTypeDeliveryCity:
    case requestTypeDeliveryIntercity:
    case requestTypeDeliveryRf:
      return const [
        paymentMethodCash,
        paymentMethodCard,
        paymentMethodCardTransfer,
      ];
    default:
      return const [
        paymentMethodCash,
        paymentMethodCard,
        paymentMethodCardTransfer,
      ];
  }
}

bool supportsManualAddressForRequestType(String requestType) {
  return requestType != requestTypeCityFixed;
}

bool requiresConfirmedCoordinates(String requestType) {
  return requestType == requestTypeCityFixed;
}

bool supportsVehicleClassForRequestType(String requestType) {
  return requestType == requestTypeCityFixed;
}

bool supportsSystemPriceForRequestType(String requestType) {
  return requestType == requestTypeCityFixed;
}

bool isMarketRequestType(String requestType) {
  return requestType != requestTypeCityFixed;
}

String requestTypeLabel(String requestType) {
  switch (requestType) {
    case requestTypeCityFixed:
      return LocalizationService.translate(
        'Легковой по городу',
        'Қала бойынша жеңіл көлік',
      );
    case requestTypeCityAuction:
      return LocalizationService.translate('Аукцион', 'Аукцион');
    case requestTypeIntercity:
      return LocalizationService.translate('Межгород', 'Қалааралық');
    case requestTypeDeliveryCity:
      return LocalizationService.translate(
        'Доставка по городу',
        'Қала ішіндегі жеткізу',
      );
    case requestTypeDeliveryIntercity:
      return LocalizationService.translate(
        'Межгородская доставка',
        'Қалааралық жеткізу',
      );
    case requestTypeDeliveryRf:
      return LocalizationService.translate(
        'Доставка по РФ',
        'РФ бойынша жеткізу',
      );
    default:
      return requestType;
  }
}

String paymentMethodLabel(String? paymentMethod) {
  switch ((paymentMethod ?? '').toUpperCase()) {
    case paymentMethodCard:
      return LocalizationService.translate(
          'банковской картой', 'банк картасымен');
    case paymentMethodCardTransfer:
      return LocalizationService.translate('переводом', 'аударыммен');
    case paymentMethodBonus:
      return LocalizationService.translate('бонусами', 'бонустармен');
    case paymentMethodCash:
    default:
      return LocalizationService.translate('наличными', 'қолма-қол');
  }
}

String vehicleClassLabel(String? vehicleClass) {
  switch ((vehicleClass ?? '').toUpperCase()) {
    case vehicleClassOptimal:
      return LocalizationService.translate('Оптимал', 'Оптимал');
    case vehicleClassComfort:
      return LocalizationService.translate('Комфорт', 'Комфорт');
    case vehicleClassBusiness:
      return LocalizationService.translate('Бизнес', 'Бизнес');
    case vehicleClassEconomy:
    default:
      return LocalizationService.translate('Эконом', 'Эконом');
  }
}
