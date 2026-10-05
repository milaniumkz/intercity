import 'package:flutter_tts/flutter_tts.dart';

import 'text_to_speech_service_base.dart';

TextToSpeechService createTextToSpeechService() {
  return _NativeTextToSpeechService();
}

class _NativeTextToSpeechService implements TextToSpeechService {
  _NativeTextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {
    await _tts.awaitSpeakCompletion(enabled);
  }

  @override
  Future<void> setLanguage(String language) async {
    await _tts.setLanguage(language);
  }

  @override
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch);
  }

  @override
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    await _tts.setVolume(volume);
  }

  @override
  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}
