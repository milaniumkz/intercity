abstract class TextToSpeechService {
  Future<void> awaitSpeakCompletion(bool enabled);
  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> setPitch(double pitch);
  Future<void> speak(String text);
  Future<void> stop();
}
