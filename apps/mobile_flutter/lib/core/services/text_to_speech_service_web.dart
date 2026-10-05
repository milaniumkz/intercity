import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'text_to_speech_service_base.dart';

TextToSpeechService createTextToSpeechService() {
  return _BrowserTextToSpeechService();
}

class _BrowserTextToSpeechService implements TextToSpeechService {
  String _language = 'en-US';
  double _speechRate = 1.0;
  double _volume = 1.0;
  double _pitch = 1.0;
  bool _awaitSpeakCompletion = false;
  Completer<void>? _activeSpeakCompleter;

  web.SpeechSynthesis get _speechSynthesis => web.window.speechSynthesis;

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {
    _awaitSpeakCompletion = enabled;
  }

  @override
  Future<void> setLanguage(String language) async {
    _language = language;
  }

  @override
  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> speak(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    await stop();

    final utterance = web.SpeechSynthesisUtterance(normalized)
      ..lang = _language
      ..rate = _speechRate
      ..volume = _volume
      ..pitch = _pitch
      ..voice = _resolveVoice(_language);

    final completer = Completer<void>();
    _activeSpeakCompleter = completer;
    utterance.onend = ((web.Event _) {
      _completeSpeak(completer);
    }).toJS;
    utterance.onerror = ((web.Event _) {
      _completeSpeak(completer);
    }).toJS;

    try {
      _speechSynthesis.resume();
      _speechSynthesis.speak(utterance);
    } catch (_) {
      _completeSpeak(completer);
      return;
    }

    if (_awaitSpeakCompletion) {
      await completer.future.timeout(
        _speakTimeout(normalized),
        onTimeout: () {
          _cancelActiveUtterance(completer);
        },
      );
    }
  }

  @override
  Future<void> stop() async {
    final completer = _activeSpeakCompleter;
    _activeSpeakCompleter = null;
    _cancelActiveUtterance(completer);
  }

  web.SpeechSynthesisVoice? _resolveVoice(String language) {
    try {
      final normalized = language.toLowerCase();
      final voices = _speechSynthesis.getVoices().toDart;
      for (final voice in voices) {
        if (voice.lang.toLowerCase() == normalized) {
          return voice;
        }
      }
      for (final voice in voices) {
        if (voice.lang.toLowerCase().startsWith(normalized)) {
          return voice;
        }
      }
    } catch (_) {
      // Keep browser default voice when voice enumeration is unavailable.
    }
    return null;
  }

  void _completeSpeak(Completer<void> completer) {
    if (!completer.isCompleted) {
      completer.complete();
    }
    if (identical(_activeSpeakCompleter, completer)) {
      _activeSpeakCompleter = null;
    }
  }

  Duration _speakTimeout(String text) {
    final millis = (text.length * 120).clamp(3000, 18000);
    return Duration(milliseconds: millis);
  }

  void _cancelActiveUtterance(Completer<void>? completer) {
    try {
      _speechSynthesis.cancel();
    } catch (_) {
      // Browser speech synthesis is optional on unsupported targets.
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
