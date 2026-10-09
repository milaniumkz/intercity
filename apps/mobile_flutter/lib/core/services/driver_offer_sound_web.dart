import 'dart:js_interop';
import 'package:web/web.dart' as web;

class DriverOfferSound {
  static int _generation = 0;
  static web.AudioContext? _context;
  static final _tones = <web.OscillatorNode>[];

  // Called directly by the driver's online button to unlock browser audio.
  static Future<void> prepare() async {
    try {
      _context ??= web.AudioContext();
      await _context!.resume().toDart;
    } catch (_) {}
  }

  static Future<void> stop() async {
    _generation++;
    _clearTones();
  }

  static void _clearTones() {
    for (final tone in List<web.OscillatorNode>.of(_tones)) {
      try {
        tone.stop();
      } catch (_) {}
    }
    _tones.clear();
  }

  static Future<void> play() async {
    final generation = ++_generation;
    try {
      _context ??= web.AudioContext();
      final context = _context!;
      if (context.state != 'running') {
        await context.resume().toDart.timeout(const Duration(seconds: 1));
      }
      if (context.state != 'running' || generation != _generation) return;
      _clearTones();
      for (var i = 0; i < 4; i++) {
        final start = context.currentTime + i * 0.35;
        final tone = context.createOscillator();
        final gain = context.createGain();
        tone.frequency.value = i == 1 ? 1050 : 780;
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(0.65, start + 0.015);
        gain.gain.linearRampToValueAtTime(0, start + 0.37);
        _tones.add(tone);
        tone.onended = ((web.Event _) {
          _tones.remove(tone);
        }).toJS;
        tone.connect(gain);
        gain.connect(context.destination);
        tone.start(start);
        tone.stop(start + 0.3);
      }
    } catch (_) {}
  }
}
