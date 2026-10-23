import 'package:flutter/material.dart';
import '../../../core/utils/location_display.dart';
import '../../../core/utils/request_flow_utils.dart';
import 'package:intercity_shared/intercity_shared.dart';

String intercityCurrencyLabel(Map<String, dynamic> request) =>
    rideCurrencyCode(request) == 'RUB' ? 'руб.' : 'тг';

String intercityDepartureLabel(dynamic raw) {
  final date = DateTime.tryParse('$raw')?.toLocal();
  if (date == null) return 'Время выезда уточняется';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} · ${two(date.hour)}:${two(date.minute)}';
}

class IntercityRequestCard extends StatelessWidget {
  const IntercityRequestCard(
      {super.key,
      required this.request,
      this.onTap,
      required this.onOffer,
      this.onAccept,
      this.accepting = false});
  final Map<String, dynamic> request;
  final VoidCallback? onTap;
  final VoidCallback onOffer;
  final VoidCallback? onAccept;
  final bool accepting;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = request['price'];
    final distance = request['tripDistanceKm'] ??
        request['distanceKm'] ??
        request['distance'];
    final myOffer = request['myOffer'] as Map?;
    String address(bool from) {
      final city = '${request[from ? 'fromCity' : 'toCity'] ?? ''}'.trim();
      final label = formatLocationDisplay(request, isFrom: from);
      return city.isEmpty || label.toLowerCase().contains(city.toLowerCase())
          ? label
          : '$city, $label';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        requestTypeLabel(
                            '${request['requestType'] ?? 'INTERCITY'}'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final from in [true, false])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                    from
                                        ? Icons.trip_origin
                                        : Icons.location_on_outlined,
                                    size: 19,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(from ? 'Откуда' : 'Куда',
                                          style: theme.textTheme.labelSmall),
                                      Text(address(from),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ])),
                              ])),
                    Wrap(spacing: 12, runSpacing: 5, children: [
                      Text(intercityDepartureLabel(
                          request['date'] ?? request['departureTime'])),
                      if ('${request['requestType']}'.startsWith('DELIVERY'))
                        Text(
                            '${request['itemDescription'] ?? 'Груз'}${request['itemWeightKg'] == null ? '' : ' · ${request['itemWeightKg']} кг'}')
                      else
                        Text('${request['seats'] ?? 1} мест(а)'),
                      if (distance is num && distance > 0)
                        Text('${distance.toStringAsFixed(1)} км'),
                    ]),
                    const SizedBox(height: 8),
                    Text(price is num && price > 0
                        ? 'Цена пассажира: ${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} ${intercityCurrencyLabel(request)}'
                        : 'Пассажир ждёт предложения цены'),
                    if (myOffer != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                              'Моё предложение: ${myOffer['price']} ${intercityCurrencyLabel(request)} · ждём ответа')),
                    const SizedBox(height: 10),
                    if (onAccept != null && price is num && price > 0) ...[
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: accepting ? null : onAccept,
                              child: Text(accepting
                                  ? 'Проверяем заказ…'
                                  : 'Принять ${price.toStringAsFixed(price == price.roundToDouble() ? 0 : 2)} ${intercityCurrencyLabel(request)}'))),
                      const SizedBox(height: 6),
                    ],
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                            onPressed: accepting ? null : onOffer,
                            child: Text(myOffer == null
                                ? 'Предложить цену'
                                : 'Изменить предложение'))),
                  ]))),
    );
  }
}
