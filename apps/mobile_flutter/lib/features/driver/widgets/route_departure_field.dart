import 'package:flutter/material.dart';

String formatRouteDeparture(DateTime? value, {int? offsetMinutes}) {
  if (value == null) return 'Дата и время не указаны';
  final date = offsetMinutes == null
      ? value.toLocal()
      : value.toUtc().add(Duration(minutes: offsetMinutes));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
}

class RouteDepartureField extends StatelessWidget {
  const RouteDepartureField(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true,
      this.title = 'Дата и время отправления',
      this.helperText =
          'Заказы только на выбранный день, до времени отправления. Время по настройкам устройства.'});
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool enabled;
  final String title, helperText;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toLocal() ?? now.add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Дата отправления',
      cancelText: 'Отмена',
      confirmText: 'Далее',
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Время отправления',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (time == null || !context.mounted) return;
    final departure =
        DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (!departure.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите будущее время отправления')));
      return;
    }
    onChanged(departure);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: enabled ? () => _pick(context) : null,
          icon: const Icon(Icons.event_rounded),
          label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(children: [
                Text(title, textAlign: TextAlign.center),
                Text(
                    value == null
                        ? 'Выбрать дату и время'
                        : formatRouteDeparture(value),
                    textAlign: TextAlign.center),
              ])),
        ),
        const SizedBox(height: 6),
        Text(helperText, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
