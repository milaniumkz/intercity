enum BrowserLocationFailure { permissionDenied, unavailable, timeout }

class BrowserLocationException implements Exception {
  const BrowserLocationException(this.reason);
  final BrowserLocationFailure reason;

  String get userMessage => switch (reason) {
        BrowserLocationFailure.permissionDenied =>
          'Браузер не разрешил доступ к местоположению. Разрешите геолокацию для этого сайта. Адреса можно ввести вручную или выбрать на карте.',
        BrowserLocationFailure.unavailable =>
          'Устройство не передало местоположение. Включите геолокацию и нажмите повторить.',
        BrowserLocationFailure.timeout =>
          'Не удалось получить местоположение за 30 секунд. Нажмите повторить или выберите точку на карте.',
      };
}
