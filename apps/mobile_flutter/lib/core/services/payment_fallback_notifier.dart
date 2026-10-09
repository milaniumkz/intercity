import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/localization_service.dart';
import 'app_preferences.dart';
import 'text_to_speech_service.dart';

class PaymentFallbackNotifier {
  PaymentFallbackNotifier({TextToSpeechService? speech})
      : _speech = speech ?? _sharedSpeech;
  static final _sharedSpeech = createTextToSpeechService();
  final TextToSpeechService _speech;
  final Set<String> _seen = {};
  static Future<void> prime() async {
    await _sharedSpeech.setVolume(1);
    await _sharedSpeech.speak('');
  }

  Future<void> notify(
      BuildContext context, Map<String, dynamic> trip, String role) async {
    final id = trip['id']?.toString();
    if (id == null ||
        trip['cardPayment'] is! Map ||
        trip['cardPayment']['status'] != 'CASH') {
      return;
    }
    final key = '$role:$id';
    if (!_seen.add(key)) {
      return;
    }
    try {
      if (!await AppPreferences.claimPaymentFallbackNotice(key)) {
        return;
      }
    } catch (_) {/* In-memory dedup still prevents repeated alerts. */}
    if (!context.mounted) {
      return;
    }
    final text = LocalizationService.translate(
        'Не удалось списать оплату с карты. Способ оплаты переведён на наличные.',
        'Картадан төлем алынбады. Төлем әдісі қолма-қол ақшаға ауыстырылды.');
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 8)));
    try {
      await _speech.setLanguage(
          LocalizationService.currentLanguage == AppLanguage.kazakh
              ? 'kk-KZ'
              : 'ru-RU');
      await _speech.setVolume(1);
      await _speech.setSpeechRate(1);
      await _speech.speak(text);
    } catch (_) {
      /* The visible notice remains when the browser blocks audio. */
    }
  }
}

String cardPaymentStatusLabel(Map<String, dynamic> trip) {
  final status = trip['cardPayment'] is Map
      ? trip['cardPayment']['status']?.toString()
      : null;
  if (status == 'PAID' || status == 'SETTLED') {
    return 'Картой · оплачено';
  }
  if (status == 'CASH') {
    return 'Наличными';
  }
  if (status == 'REFUND_PENDING') {
    return 'Возврат оплаты проверяется';
  }
  if (status == 'REFUNDED') {
    return 'Оплата возвращена';
  }
  if (trip['paymentMethod'] == 'CARD' &&
      ['PENDING', 'PROCESSING', 'CHECKING'].contains(status)) {
    return 'Проверяем оплату картой';
  }
  return '';
}
