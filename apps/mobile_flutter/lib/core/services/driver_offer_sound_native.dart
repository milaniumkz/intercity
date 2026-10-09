import 'package:flutter/services.dart';

class DriverOfferSound {
  static Future<void> prepare() async {}
  static Future<void> play() => SystemSound.play(SystemSoundType.alert);
}
