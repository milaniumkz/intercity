import 'dart:js_interop';
import 'package:web/web.dart' as web;

class DriverOfferSound {
  static web.AudioContext? _context;

  // Called directly by the driver's online button to unlock browser audio.
  static Future<void> prepare() async {
    try {
      _context ??= web.AudioContext();
      await _context!.resume().toDart;
    } catch (_) {}
  }

  static Future<void> play() async {
    try {
      final context = _context;
      if (context == null || context.state != 'running') return;
      for (var i = 0; i < 3; i++) {
        final start = context.currentTime + i * 0.22;
        final tone = context.createOscillator();
        final gain = context.createGain();
        tone.frequency.value = i == 1 ? 1050 : 780;
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(0.25, start + 0.015);
        gain.gain.linearRampToValueAtTime(0, start + 0.18);
        tone.connect(gain);
        gain.connect(context.destination);
        tone.start(start);
        tone.stop(start + 0.2);
      }
    } catch (_) {}
  }
}
