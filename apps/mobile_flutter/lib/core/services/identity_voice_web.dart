import 'dart:js_interop';
import 'package:web/web.dart' as web;

class IdentityVoice {
  final web.HTMLAudioElement _audio = web.HTMLAudioElement()
    ..src =
        Uri.base.resolve('assets/assets/sounds/identity/prepare.wav').toString()
    ..preload = 'auto';
  bool muted = false;
  bool failed = false;
  void play(String cue) {
    if (muted) return;
    _audio.pause();
    _audio.src =
        Uri.base.resolve('assets/assets/sounds/identity/$cue.wav').toString();
    // Called directly from the initial button gesture to unlock iOS audio.
    _audio.play().toDart.then((_) {
      failed = false;
    }).catchError((Object _) {
      failed = true;
    });
  }

  void stop() {
    _audio.pause();
  }

  void dispose() {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
  }
}
