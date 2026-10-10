import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import '../../../core/utils/request_flow_utils.dart';

class TaxiPriceOfferDialog extends StatelessWidget {
  const TaxiPriceOfferDialog(
      {super.key,
      required this.order,
      required this.secondsLeft,
      required this.onSubmit,
      required this.onReject});
  final Map<String, dynamic> order;
  final int secondsLeft;
  final ValueChanged<double> onSubmit;
  final VoidCallback onReject;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = (order['price'] as num?)?.toDouble();
    bool valid(double? value) =>
        value != null &&
        value.isFinite &&
        value >= 1 &&
        value <= 10000000 &&
        secondsLeft > 0;
    final currency = rideCurrencySymbol(order);
    return PopScope(
        canPop: false,
        child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.local_taxi_rounded),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Заказ такси',
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800))),
                        Text('$secondsLeft с',
                            style: TextStyle(
                                color: secondsLeft <= 10
                                    ? Colors.redAccent
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                          value: secondsLeft.clamp(0, 30) / 30),
                      const SizedBox(height: 16),
                      for (final field in ['fromAddress', 'toAddress'])
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Icon(
                                  field == 'fromAddress'
                                      ? Icons.trip_origin
                                      : Icons.location_on,
                                  size: 20,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text('${order[field] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)),
                            ])),
                      Text(
                          '${vehicleClassLabel(order['vehicleClass']?.toString() ?? 'ECONOMY')} · ${paymentMethodLabel(order['paymentMethod']?.toString())}',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      Text(
                          'Цена пассажира: ${order['price']} ${rideCurrencySymbol(order)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: valid(amount)
                                  ? () => onSubmit(amount!)
                                  : null,
                              child: const Text('Принять цену пассажира'))),
                      const SizedBox(height: 10),
                      Row(children: [
                        for (final extra in [200, 500, 700])
                          Expanded(
                              child: Padding(
                                  padding: EdgeInsets.only(
                                      right: extra == 700 ? 0 : 6),
                                  child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 12)),
                                      onPressed: valid(amount == null
                                              ? null
                                              : amount + extra)
                                          ? () => onSubmit(amount! + extra)
                                          : null,
                                      child: Text(
                                          '${((amount ?? 0) + extra).toStringAsFixed(0)} $currency')))),
                      ]),
                      const SizedBox(height: 12),
                      const Text(
                          'После отправки пассажир подтверждает водителя. Предложение действует 30 секунд.',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 16),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                              onPressed: onReject,
                              child: const Text('Отклонить'))),
                    ],
                  ))),
        ));
  }
}
