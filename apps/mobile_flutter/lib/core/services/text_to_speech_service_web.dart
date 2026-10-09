import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'text_to_speech_service_base.dart';
import 'navigation_voice_catalog.dart';

TextToSpeechService createTextToSpeechService() {
  return _BrowserTextToSpeechService();
}

class _BrowserTextToSpeechService implements TextToSpeechService {
  final _navigationAudio = web.HTMLAudioElement()..preload = 'auto';
  int _generation = 0;
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
    if (normalized.isEmpty) {
      // Prime this same audio element from the driver's explicit Online tap.
      _navigationAudio.src =
          'data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YSADAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA==';
      try {
        await _navigationAudio.play().toDart;
      } catch (_) {}
      return;
    }

    await stop();
    final recording = navigationVoiceRecordings[normalized];
    if (recording != null) {
      final completer = Completer<void>();
      _activeSpeakCompleter = completer;
      _navigationAudio
        ..src = Uri.base.resolve(recording).toString()
        ..volume = _volume.clamp(0, 1)
        ..playbackRate = _speechRate.clamp(0.75, 1.25)
        ..onended = ((web.Event _) => _completeSpeak(completer)).toJS
        ..onerror = ((web.Event _) => _completeSpeak(completer)).toJS;
      try {
        await _navigationAudio.play().toDart;
      } catch (_) {
        _completeSpeak(completer);
        rethrow;
      }
      if (_awaitSpeakCompletion) {
        await completer.future.timeout(_speakTimeout(normalized),
            onTimeout: () {
          unawaited(stop());
        });
      }
      return;
    }
    final generation = _generation;
    var voice = _resolveVoice(_language);
    for (var i = 0; voice == null && i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (generation != _generation) return;
      voice = _resolveVoice(_language);
    }
    if (generation != _generation) return;
    if (voice == null) {
      throw StateError(
          'Для озвучки установите голос языка $_language в настройках устройства.');
    }
    final utterance = web.SpeechSynthesisUtterance(normalized)
      ..lang = _language
      ..rate = _speechRate
      ..volume = _volume
      ..pitch = _pitch
      ..voice = voice;

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
    _generation++;
    try {
      _navigationAudio.pause();
      _navigationAudio.currentTime = 0;
    } catch (_) {}
    final completer = _activeSpeakCompleter;
    _activeSpeakCompleter = null;
    _cancelActiveUtterance(completer);
  }

  web.SpeechSynthesisVoice? _resolveVoice(String language) {
    try {
      final normalized = language.toLowerCase();
      final voices = _speechSynthesis.getVoices().toDart;
      final prefix = normalized.split('-').first;
      final candidates = voices
          .where((voice) =>
              voice.lang.toLowerCase().replaceAll('_', '-').split('-').first ==
              prefix)
          .toList();
      int score(web.SpeechSynthesisVoice voice) {
        final name = voice.name.toLowerCase();
        final female = [
          'svetlana',
          'irina',
          'dariya',
          'female',
          'amira',
          'aigul',
          'жанар',
          'алтынай',
          'ассель',
          'google русский'
        ].any(name.contains);
        return (female ? 100 : 0) +
            (voice.lang.toLowerCase().replaceAll('_', '-') == normalized
                ? 10
                : 0) +
            (name.contains('google') ? 5 : 0);
      }

      candidates.sort((a, b) => score(b).compareTo(score(a)));
      if (candidates.isNotEmpty) return candidates.first;
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
