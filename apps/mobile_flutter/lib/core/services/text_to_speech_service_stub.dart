import 'text_to_speech_service_base.dart';

TextToSpeechService createTextToSpeechService() {
  return const _NoopTextToSpeechService();
}

class _NoopTextToSpeechService implements TextToSpeechService {
  const _NoopTextToSpeechService();

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {}

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}
