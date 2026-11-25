import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../utils/error_message_ru.dart';
import '../utils/payment_modal.dart';

class VtbTripCheckout {
  static Future<Map<String, dynamic>> check(ApiClient api, String kind, String tripId) async {
    final response = await api.post('/payments/vtb/trips/$kind/$tripId/checkout');
    return Map<String, dynamic>.from(response.data as Map);
  }
  static Future<Map<String, dynamic>> open(BuildContext context, ApiClient api, {
    required String kind, required String tripId,
    Future<bool> Function(BuildContext, String)? opener,
  }) async {
    var payment = await check(api, kind, tripId);
    const finished = ['PAID', 'SETTLED', 'FAILED', 'REFUNDED', 'CANCELLED', 'CASH'];
    for (var form = 0; form < 3; form++) {
      for (var i = 0; i < 5 && payment['paymentUrl'] == null &&
          !finished.contains(payment['status']); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        payment = await check(api, kind, tripId);
      }
      if (!context.mounted || finished.contains(payment['status'])) { return payment; }
      final url = Uri.tryParse(payment['paymentUrl']?.toString() ?? '');
      if (url == null || url.scheme != 'https' || url.host != 'vtbkz.rbsuat.com' ||
          !url.path.startsWith('/payment/') || url.userInfo.isNotEmpty) {
        throw StateError('ВТБ ещё готовит форму оплаты. Нажмите «Оплатить через ВТБ» в заказе через несколько секунд.');
      }
      final attempt = payment['attempts'] ?? 1;
      var nextAttempt = false;
      if (opener != null) {
        await opener(context, url.toString());
      } else {
        await showPaymentModal(context, url.toString(),
          title: 'ВТБ · ${payment['amount']} ₽ = ${payment['bankAmount']} ₸ · попытка $attempt/3 · тест',
          isCompleted: () async {
            payment = await check(api, kind, tripId);
            nextAttempt = (payment['attempts'] ?? 1) != attempt;
            return nextAttempt || finished.contains(payment['status']);
          });
      }
      payment = await check(api, kind, tripId);
      if (!nextAttempt) { return payment; }
    }
    return payment;
  }
}

class VtbTripPaymentPanel extends StatefulWidget {
  const VtbTripPaymentPanel({super.key, required this.api, required this.kind,
    required this.tripId, required this.trip});
  final ApiClient api;
  final String kind;
  final String tripId;
  final Map<String, dynamic>? trip;
  @override
  State<VtbTripPaymentPanel> createState() => _VtbTripPaymentPanelState();
}
class _VtbTripPaymentPanelState extends State<VtbTripPaymentPanel> {
  bool _busy = false;
  bool _autoOpened = false;
  @override
  void initState() { super.initState(); _maybeOpenAfterAcceptance(); }
  @override
  void didUpdateWidget(covariant VtbTripPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget); _maybeOpenAfterAcceptance();
  }
  void _maybeOpenAfterAcceptance() {
    final trip = widget.trip;
    final p = trip?['cardPayment'];
    if (_autoOpened || p is! Map || p['provider'] != 'VTB_SANDBOX' ||
        !['PENDING','PROCESSING','CHECKING','ACTION_REQUIRED'].contains(p['status']) ||
        !['DRIVER_ASSIGNED','DRIVER_EN_ROUTE','DRIVER_ARRIVED','ACCEPTED'].contains(trip?['status'])) { return; }
    _autoOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { _pay(); } });
  }
  String? _error;
  Future<void> _pay() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await VtbTripCheckout.open(context, widget.api, kind: widget.kind, tripId: widget.tripId);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessageRu(e));
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    if (trip == null || trip['currency'] != 'RUB' || trip['paymentMethod'] != 'CARD') return const SizedBox.shrink();
    final raw = trip['cardPayment'];
    final payment = raw is Map ? raw : const <String, dynamic>{};
    final status = payment['status']?.toString();
    final settled = status == 'PAID' || status == 'SETTLED';
    final terminal = ['FAILED', 'CANCELLED', 'REFUNDED', 'REFUND_PENDING', 'CASH'].contains(status);
    final amount = payment['amount'];
    final bankMinor = payment['bankAmountMinor'];
    final bankAmount = bankMinor is num ? bankMinor / 100 : null;
    final message = settled ? 'Оплачено через ВТБ'
        : status == 'CASH' ? 'Три попытки оплаты не прошли. Заказ переведён на наличные.'
        : status == 'REFUND_PENDING' && trip['status'] == 'CANCELLED' && payment['paidAt'] == null
            ? 'Заказ отменён. Оплачивать его не нужно.'
        : status == 'REFUND_PENDING' ? 'ВТБ: возврат оплаты подтверждается банком'
        : status == 'REFUNDED' ? 'ВТБ: оплата возвращена'
        : status == 'FAILED' ? 'ВТБ отклонил оплату. Отмените заказ и повторите его.'
        : status == 'CANCELLED' ? 'Оплата ВТБ отменена'
        : raw == null && widget.kind == 'CITY' && trip['requestType'] != 'CITY_AUCTION'
            ? 'ВТБ: списание после принятия заказа водителем'
        : raw == null ? 'ВТБ: оплата после выбора предложения водителя'
        : 'ВТБ: подтвердите оплату до начала поездки';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (amount != null && bankAmount != null)
            Text('$amount ₽ = ${bankAmount.toStringAsFixed(2)} ₸ · тестовый контур'),
          if (raw != null && !settled && !terminal)
            FilledButton.icon(onPressed: _busy ? null : _pay,
              icon: const Icon(Icons.credit_card),
              label: Text(_busy ? 'Проверяем ВТБ…' : 'Оплатить через ВТБ')),
          if (_error != null) Text(_error!),
        ])));
  }
}
