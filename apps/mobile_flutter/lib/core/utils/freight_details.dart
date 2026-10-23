List<String> freightDetails(Map<String, dynamic> order) {
  final fields = <String, dynamic>{
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
