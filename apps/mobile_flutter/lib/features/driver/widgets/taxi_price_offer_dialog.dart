import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import '../../../core/utils/request_flow_utils.dart';

class TaxiPriceOfferDialog extends StatefulWidget {
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
  State<TaxiPriceOfferDialog> createState() => _TaxiPriceOfferDialogState();
}

class _TaxiPriceOfferDialogState extends State<TaxiPriceOfferDialog> {
  late final price =
      TextEditingController(text: '${widget.order['price'] ?? ''}');
  bool counter = false;
  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = counter
        ? double.tryParse(price.text.replaceAll(',', '.'))
        : (widget.order['price'] as num?)?.toDouble();
    final valid =
        amount != null && amount.isFinite && amount >= 1 && amount <= 10000000;
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
                        Text('${widget.secondsLeft} с',
                            style: TextStyle(
                                color: widget.secondsLeft <= 10
                                    ? Colors.redAccent
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                          value: widget.secondsLeft.clamp(0, 30) / 30),
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
                                  child: Text('${widget.order[field] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)),
                            ])),
                      Text(
                          '${vehicleClassLabel(widget.order['vehicleClass']?.toString() ?? 'ECONOMY')} · ${paymentMethodLabel(widget.order['paymentMethod']?.toString())}',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      Text(
                          'Цена пассажира: ${widget.order['price']} ${rideCurrencySymbol(widget.order)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: ChoiceChip(
                                label: const Text('Согласиться'),
                                selected: !counter,
                                showCheckmark: false,
                                onSelected: (_) =>
                                    setState(() => counter = false))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: ChoiceChip(
                                label: const Text('Своя цена'),
                                selected: counter,
                                showCheckmark: false,
                                onSelected: (_) =>
                                    setState(() => counter = true))),
                      ]),
                      if (counter) ...[
                        const SizedBox(height: 10),
                        TextField(
                            key: const ValueKey('driver-taxi-counter-price'),
                            controller: price,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                                labelText: 'Ваша цена',
                                suffixText: rideCurrencySymbol(widget.order),
                                isDense: true)),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                          'После отправки пассажир подтверждает водителя. Предложение действует 30 секунд.',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: widget.onReject,
                                child: const Text('Отклонить'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: FilledButton(
                                onPressed: valid
                                    ? () => widget.onSubmit(amount)
                                    : null,
                                child: Text(
                                    counter ? 'Предложить' : 'Отправить'))),
                      ]),
                    ],
                  ))),
        ));
  }
}
