import 'package:flutter/material.dart';
import '../../../core/utils/error_message_ru.dart';
import 'intercity_request_card.dart';

class IntercityPriceProposalDialog extends StatefulWidget {
  const IntercityPriceProposalDialog(
      {super.key, required this.request, required this.onSubmit});
  final Map<String, dynamic> request;
  final Future<void> Function(double price) onSubmit;
  @override
  State<IntercityPriceProposalDialog> createState() =>
      _IntercityPriceProposalDialogState();
}

class _IntercityPriceProposalDialogState
    extends State<IntercityPriceProposalDialog> {
  late final _price = TextEditingController(
      text:
          '${(widget.request['myOffer'] as Map?)?['price'] ?? widget.request['price'] ?? ''}');
  bool _saving = false;
  String _error = '';
  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price == null || !price.isFinite || price <= 0) {
      setState(() => _error = 'Укажите цену больше нуля');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.onSubmit(price);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorMessageRu(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Предложить цену'),
        content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  '${widget.request['fromCity']} → ${widget.request['toCity']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(intercityDepartureLabel(widget.request['date'])),
              Text('${widget.request['requestType']}'.startsWith('DELIVERY') ? '${widget.request['itemDescription'] ?? 'Груз'}${widget.request['itemWeightKg'] == null ? '' : ' · ${widget.request['itemWeightKg']} кг'} · ${intercityCurrencyLabel(widget.request)}' : '${widget.request['seats'] ?? 1} мест(а) · ${intercityCurrencyLabel(widget.request)}'),
              const SizedBox(height: 16),
              TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText:
                          'Цена, ${intercityCurrencyLabel(widget.request)}')),
              if (_error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ])),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: _saving ? null : _submit,
              child: Text(_saving ? 'Отправляем…' : 'Отправить предложение'))
        ],
      );
}
