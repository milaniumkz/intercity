import 'package:audioplayers/audioplayers.dart';

class DriverOfferSound {
  static int _generation = 0;
  static final AudioPlayer _player = AudioPlayer();
  static Future<void> prepare() async {
    try {
      await _player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.duckOthers}),
      ));
    } catch (_) {}
  }

  static Future<void> play() async {
    final generation = ++_generation;
    try {
      await prepare();
      if (generation != _generation) return;
      await _player.play(AssetSource('sounds/intercity_order.wav'), volume: 1);
    } catch (_) {}
  }

  static Future<void> stop() async {
    _generation++;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
