List<String> freightDetails(Map<String, dynamic> order) {
  final pickup = DateTime.tryParse('${order['scheduledFor'] ?? ''}')?.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final fields = <String, dynamic>{
    if (pickup != null)
      'Дата и время подачи':
          '${two(pickup.day)}.${two(pickup.month)}.${pickup.year} ${two(pickup.hour)}:${two(pickup.minute)}',
    'Груз': order['itemDescription'] ?? order['deliveryItemDescription'],
    'Вес, кг': order['itemWeightKg'] ?? order['deliveryWeightKg'],
    'Размеры': order['itemDimensions'] ?? order['deliveryDimensions'],
    'Получатель':
        order['recipientContact'] ?? order['deliveryRecipientContact'],
  };
  return fields.entries
      .where((entry) =>
          entry.value != null && entry.value.toString().trim().isNotEmpty)
      .map((entry) => '${entry.key}: ${entry.value}')
      .toList();
}
