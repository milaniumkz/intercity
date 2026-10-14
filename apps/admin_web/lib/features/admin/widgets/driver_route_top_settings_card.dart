import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';

class DriverRouteTopSettingsCard extends StatefulWidget {
  const DriverRouteTopSettingsCard({super.key});
  @override
  State<DriverRouteTopSettingsCard> createState() =>
      _DriverRouteTopSettingsCardState();
}

class _DriverRouteTopSettingsCardState
    extends State<DriverRouteTopSettingsCard> {
  final _price = TextEditingController(text: '1000');
  final _rate = TextEditingController(text: '7');
  final _hours = TextEditingController(text: '12');
  final _seconds = TextEditingController(text: '30');
  bool _loading = true, _saving = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_price, _rate, _hours, _seconds]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await AdminApiClient.instance.get('/admin/settings');
      final rows = (response.data as List)
          .whereType<Map>()
          .where((row) => row['key'] == 'driverRouteTopPolicy');
      if (rows.isNotEmpty && mounted) {
        final data = jsonDecode('${rows.first['value']}') as Map;
        _price.text = '${data['priceKzt']}';
        _rate.text = '${data['kztPerRub']}';
        _hours.text = '${data['durationHours']}';
        _seconds.text = '${data['firstAccessSeconds']}';
      }
    } catch (error) {
      if (mounted) _message = 'Не удалось загрузить настройки топа';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final values = [_price, _rate, _hours, _seconds]
        .map((c) => double.tryParse(c.text.trim().replaceAll(',', '.')))
        .toList();
    if (values.any((v) => v == null || !v.isFinite || v <= 0)) {
      setState(() => _message = 'Укажите положительные числовые значения');
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminApiClient.instance.post('/admin/settings', data: {
        'key': 'driverRouteTopPolicy',
        'value': jsonEncode({
          'priceKzt': values[0],
          'kztPerRub': values[1],
          'durationHours': values[2],
          'firstAccessSeconds': values[3]
        })
      });
      if (mounted) setState(() => _message = 'Настройки топа сохранены');
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            error is DioException && error.response?.data is Map
                ? '${(error.response!.data as Map)['message']}'
                : 'Не удалось сохранить настройки топа');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_price.text.replaceAll(',', '.')) ?? 0,
        rate = double.tryParse(_rate.text.replaceAll(',', '.')) ?? 0;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Топ межгородских маршрутов',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                  'Сначала заявки одновременно получают все водители в топе одного направления. Если никто не принял заказ, его получают обычные водители. Назначение только одному водителю защищено от одновременных нажатий.'),
              const SizedBox(height: 16),
              if (_loading) const LinearProgressIndicator(),
              Wrap(spacing: 16, runSpacing: 12, children: [
                for (final entry in {
                  'Базовая цена, тг': _price,
                  'Курс: тг за 1 рубль': _rate,
                  'Срок в топе, часов': _hours,
                  'Первый доступ, секунд': _seconds
                }.entries)
                  SizedBox(
                      width: 220,
                      child: TextField(
                          controller: entry.value,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(labelText: entry.key))),
              ]),
              const SizedBox(height: 12),
              Text(
                  'Стоимость в России: ${rate > 0 ? (price / rate).toStringAsFixed(2) : '—'} руб.'),
              const SizedBox(height: 8),
              const Text(
                  'Действующие покупки сохраняют оплаченный срок. Изменение настроек применяется к новым покупкам; повторный запрос оплаты не списывает деньги снова.'),
              if (_message.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message)),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: _loading || _saving ? null : _save,
                  child: Text(_saving ? 'Сохраняем…' : 'Сохранить тариф топа')),
            ])));
  }
}
