import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';

/// Edits the actual fixed-price freight catalogue. Market delivery uses offers.
class FreightTariffDialog extends StatefulWidget {
  final String kind;
  final Map<String, dynamic>? tariff;
  const FreightTariffDialog({super.key, required this.kind, this.tariff});
  @override
  State<FreightTariffDialog> createState() => _FreightTariffDialogState();
}

class _FreightTariffDialogState extends State<FreightTariffDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  late String _country;
  late bool _active;
  bool _saving = false;
  String? _error;
  bool get _delivery => widget.kind == 'delivery';
  @override
  void initState() {
    super.initState();
    _country = widget.tariff?['countryCode']?.toString() ?? 'KZ';
    _active = widget.tariff?['isActive'] != false;
    _fields = {
      for (final key in [
        'name',
        'basePrice',
        'pricePerKm',
        'pricePerKg',
        'minPrice',
        if (_delivery) 'doorToDoorFee'
      ])
        key: TextEditingController(text: widget.tariff?[key]?.toString() ?? '')
    };
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{
      'countryCode': _country,
      'isActive': _active,
      for (final entry in _fields.entries)
        entry.key: entry.key == 'name'
            ? entry.value.text.trim()
            : double.parse(entry.value.text.replaceAll(',', '.'))
    };
    try {
      final path = '/admin/tariffs/${widget.kind}';
      if (widget.tariff == null) {
        await AdminApiClient.instance.post(path, data: data);
      } else {
        await AdminApiClient.instance
            .patch('$path/${widget.tariff!['id']}', data: data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Не удалось сохранить тариф: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_delivery ? 'Тариф доставки' : 'Грузовой тариф'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_delivery)
                        const Text(
                            'Этот тариф применяется к фиксированному расчёту. В доставке по предложениям цену согласовывают пассажир и водитель.'),
                      DropdownButtonFormField<String>(
                          initialValue: _country,
                          decoration: const InputDecoration(
                              labelText: 'Страна и валюта'),
                          items: const [
                            DropdownMenuItem(
                                value: 'KZ', child: Text('Казахстан — ₸')),
                            DropdownMenuItem(
                                value: 'RU', child: Text('Россия — ₽'))
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _country = value!)),
                      for (final entry in _fields.entries)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextFormField(
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                controller: entry.value,
                                enabled: !_saving,
                                keyboardType: entry.key == 'name'
                                    ? TextInputType.text
                                    : const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: const {
                                      'name': 'Название',
                                      'basePrice': 'Базовая стоимость',
                                      'pricePerKm': 'Цена за км',
                                      'pricePerKg': 'Цена за кг',
                                      'minPrice': 'Минимальная стоимость',
                                      'doorToDoorFee':
                                          'Доплата от двери до двери'
                                    }[entry.key],
                                    suffixText: entry.key == 'name'
                                        ? null
                                        : (_country == 'RU' ? '₽' : '₸')),
                                validator: (value) {
                                  if (entry.key == 'name') {
                                    return value!.trim().isEmpty
                                        ? 'Введите название'
                                        : null;
                                  }
                                  final n = double.tryParse(
                                      value!.replaceAll(',', '.'));
                                  return n == null ||
                                          !n.isFinite ||
                                          n < 0 ||
                                          n > 10000000
                                      ? 'Введите сумму от 0 до 10 000 000'
                                      : null;
                                })),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Тариф активен'),
                          value: _active,
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _active = value)),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ])))),
        actions: [
          TextButton(
              onPressed:
                  _saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохранение…' : 'Сохранить'))
        ],
      );
}
