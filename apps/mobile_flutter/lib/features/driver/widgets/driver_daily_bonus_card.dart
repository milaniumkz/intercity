import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';

class DriverDailyBonusCard extends StatelessWidget {
  const DriverDailyBonusCard({super.key, required this.bonus});
  final Map<String, dynamic>? bonus;
  @override
  Widget build(BuildContext context) {
    final data = bonus;
    if (data == null || data['enabled'] != true || data['credited'] == true) {
      return const SizedBox.shrink();
    }
    final target = (data['targetOrders'] as num?)?.toInt() ?? 1;
    final completed = (data['completed'] as num?)?.toInt() ?? 0;
    final credited = data['credited'] == true;
    final amount = (data['rewardAmount'] as num?)?.toStringAsFixed(0) ?? '0';
    final currency = data['currency'] == 'RUB' ? '₽' : '₸';
    final color = credited ? const Color(0xFF22C55E) : AppTheme.primaryColor;
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          key: const ValueKey('driver-daily-bonus'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.25))),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(
                          credited ? 'Бонус начислен' : 'Акция за сегодня',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: color))),
                  Text('+$amount $currency',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, color: color)),
                ]),
                const SizedBox(height: 4),
                Text('Выполнено $completed из $target заказов · сутки UTC+5',
                    style: Theme.of(context).textTheme.labelSmall),
                if ((data['heldOrders'] as num? ?? 0) > 0)
                  Text(
                      'На проверке: ${data['heldOrders']} · бонусы ожидают решения',
                      style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                    value: target > 0 ? (completed / target).clamp(0, 1) : 0,
                    color: color,
                    borderRadius: BorderRadius.circular(4)),
              ]),
        ));
  }
}
