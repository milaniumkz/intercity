import 'text_to_speech_service_base.dart';
import 'text_to_speech_service_stub.dart'
    if (dart.library.io) 'text_to_speech_service_native.dart'
    if (dart.library.js_interop) 'text_to_speech_service_web.dart' as impl;

export 'text_to_speech_service_base.dart';

TextToSpeechService createTextToSpeechService() {
  return impl.createTextToSpeechService();
}
