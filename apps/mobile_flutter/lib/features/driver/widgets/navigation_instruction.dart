String navigationAction(Map<String, dynamic> step, bool kazakh) {
  final maneuver = step['maneuver'] is Map ? step['maneuver'] as Map : const {};
  final type = '${maneuver['type']}', modifier = '${maneuver['modifier']}';
  if (type == 'arrive') return kazakh ? 'Сіз келдіңіз' : 'Вы прибыли';
  if (type == 'roundabout' || type == 'rotary') {
    return kazakh ? 'Айналма жолмен жүріңіз' : 'Следуйте по круговому движению';
  }
  if (modifier.contains('uturn')) {
    return kazakh ? 'Кері бұрылыңыз' : 'Выполните разворот';
  }
  if (modifier.contains('left')) {
    return kazakh ? 'Солға бұрылыңыз' : 'Поверните налево';
  }
  if (modifier.contains('right')) {
    return kazakh ? 'Оңға бұрылыңыз' : 'Поверните направо';
  }
  return kazakh ? 'Тура жүріңіз' : 'Продолжайте движение прямо';
}

String navigationSpeech(Map<String, dynamic> step, int threshold, bool kazakh) {
  final action = navigationAction(step, kazakh);
  if (threshold <= 50) return action;
  return kazakh
      ? '$threshold метрден кейін ${action[0].toLowerCase()}${action.substring(1)}'
      : 'Через $threshold метров ${action[0].toLowerCase()}${action.substring(1)}';
}
