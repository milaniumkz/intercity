import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';

class VtbSandboxCheckout {
  static Future<Map<String, dynamic>> instructions(ApiClient api) async {
    final response = await api.get('/wallet/vtb/sandbox');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> check(ApiClient api, String id) async {
    final response = await api.post('/wallet/vtb/sandbox/payments/$id/check');
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<bool> openBank(BuildContext context, String value) async {
    final url = Uri.tryParse(value);
    if (!context.mounted || url == null || url.scheme != 'https' ||
        url.host != 'vtbkz.rbsuat.com' || !url.path.startsWith('/payment/')) {
      return false;
    }
    // Hosted bank checkout must not be embedded in an iframe (3DS/frame policies).
    return launchUrl(url, mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self');
  }

  static Future<Map<String, dynamic>> pay(BuildContext context, ApiClient api,
      {required double amount, required String purpose,
      Future<bool> Function(BuildContext, String)? opener}) async {
    final info = await instructions(api);
    if (info['eligible'] != true || info['available'] != true) {
      throw Exception((info['message'] ?? 'Оплата ВТБ в рублях пока недоступна').toString());
    }
    final response = await api.post('/wallet/vtb/sandbox/payments', data: {
      'amount': amount, 'currency': 'RUB', 'purpose': purpose,
      'requestKey': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    final id = data['id']?.toString() ?? '';
    if (id.isEmpty || data['currency'] != 'RUB' ||
        data['paymentMode'] != 'TEST' || data['creditsWallet'] != false) {
      throw const FormatException('Некорректный ответ тестовой оплаты ВТБ');
    }
    if (data['bankCurrency'] != 'KZT' || data['conversionRate'] != 7 ||
        data['bankAmount'] is! num) {
      throw const FormatException('Не подтверждён курс оплаты ВТБ');
    }
    final url = (data['paymentUrl'] ?? '').toString();
    if (url.isEmpty || !context.mounted) return data;
    final appAmount = (data['amount'] as num).toStringAsFixed(2);
    final bankAmount = (data['bankAmount'] as num).toStringAsFixed(2);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Тестовая оплата ВТБ'),
        content: Text('Сумма в приложении: $appAmount ₽\nВ банке: $bankAmount ₸\n'
            'Курс приложения: 1 ₽ = 7 ₸.\nСумма списания с рублёвой карты зависит от курса её банка.\n'
            'Тестовая операция не пополняет настоящий баланс и не оплачивает реальную поездку.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Перейти в ВТБ')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return {...data, 'message': 'Переход к тестовой оплате отменён. Баланс не изменён.'};
    }
    final opened = await (opener ?? openBank)(context, url);
    if (!opened) return {...data, 'message': 'Не удалось открыть ВТБ. Повторно оплачивать не нужно: проверьте созданную операцию.'};
    return check(api, id);
  }

  static String message(Map<String, dynamic> data) {
    switch (data['status']) {
      case 'SUCCEEDED':
        return 'Тестовая оплата ВТБ подтверждена. Настоящий баланс не изменён; реальная поездка не оплачена.';
      case 'FAILED':
      case 'CANCELLED':
        return 'Тестовая оплата ВТБ отклонена или отменена. Баланс не изменён.';
      default:
        return (data['message'] ?? 'Ожидаем подтверждение тестовой оплаты ВТБ. Реальные деньги не зачисляются.').toString();
    }
  }
}
