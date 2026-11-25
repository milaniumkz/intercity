import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

import 'speech_playback_speed.dart';

class IdentityVoice {
  AudioPlayer? _player;
  bool muted = false;
  bool failed = false;
  void play(String cue) {
    if (muted) return;
    unawaited(_play(cue));
  }

  Future<void> _play(String cue) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setPlaybackRate(speechPlaybackSpeedMultiplier);
      await player.play(AssetSource('sounds/identity/$cue.wav'));
      failed = false;
    } catch (_) {
      failed = true;
    }
  }

  void stop() {
    unawaited(_player?.stop().catchError((_) {}));
  }

  void dispose() {
    unawaited(_player?.dispose().catchError((_) {}));
  }
}
