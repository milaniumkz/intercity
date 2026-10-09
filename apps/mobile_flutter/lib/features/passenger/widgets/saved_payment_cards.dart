import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';

class SavedPaymentCards extends StatefulWidget {
  const SavedPaymentCards({super.key, this.apiClient, this.onReadyChanged});
  final ApiClient? apiClient;
  final void Function(bool ready, String? last4)? onReadyChanged;
  @override
  State<SavedPaymentCards> createState() => _SavedPaymentCardsState();
}

class _SavedPaymentCardsState extends State<SavedPaymentCards> {
  late final _api = widget.apiClient ?? ApiClient();
  List<Map<String, dynamic>> _cards = [];
  bool _configured = false;
  bool _busy = true;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool sync = false}) async {
    if (mounted) {
      setState(() => _busy = true);
    }
    try {
      final response = sync
          ? await _api.post('/payments/cards/sync')
          : await _api.get('/payments/cards');
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) {
        return;
      }
      final cards = (data['cards'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _cards = cards;
        _configured = data['configured'] == true;
        _message = data['message']?.toString() ?? '';
      });
      final selected = cards.where((c) => c['isDefault'] == true);
      widget.onReadyChanged?.call(_configured && selected.isNotEmpty,
          selected.isEmpty ? null : '${selected.first['last4']}');
    } catch (e) {
      if (mounted) {
        setState(() => _message = errorMessageRu(e));
        widget.onReadyChanged?.call(false, null);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _bind() async {
    setState(() => _busy = true);
    try {
      final response = await _api.post('/payments/cards/bind');
      final uri = Uri.parse('${response.data['url']}');
      if (uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Не удалось открыть Kassa24');
      }
      if (mounted) {
        setState(() => _message =
            'Завершите привязку в Kassa24, затем нажмите «Обновить карты».');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = errorMessageRu(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _choose(Map<String, dynamic> card) async {
    setState(() => _busy = true);
    try {
      await _api.patch('/payments/cards/${card['id']}/default');
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _message = errorMessageRu(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove(Map<String, dynamic> card) async {
    setState(() => _busy = true);
    try {
      await _api.delete('/payments/cards/${card['id']}');
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _message = errorMessageRu(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.credit_card_rounded),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Банковские карты',
                      style: TextStyle(fontWeight: FontWeight.w800))),
              IconButton(
                  tooltip: 'Обновить карты',
                  onPressed: _busy ? null : () => _load(sync: true),
                  icon: const Icon(Icons.refresh))
            ]),
            const Text(
                'Для поездок в тенге. Стоимость списывается при начале поездки.'),
            if (_busy) const LinearProgressIndicator(),
            for (final card in _cards)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(card['isDefault'] == true
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text('•••• ${card['last4']}'),
                  subtitle: card['isDefault'] == true
                      ? const Text('Для следующего заказа')
                      : null,
                  onTap: _busy ? null : () => _choose(card),
                  trailing: IconButton(
                      tooltip: 'Отвязать карту',
                      onPressed: _busy ? null : () => _remove(card),
                      icon: const Icon(Icons.delete_outline))),
            if (_configured)
              OutlinedButton.icon(
                  onPressed: _busy ? null : _bind,
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить карту')),
            if (_configured)
              const Text(
                  'Добавляя карту, вы разрешаете списание согласованной стоимости заказанных поездок. Данные карты вводятся в защищённой форме Kassa24.'),
            if (_message.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message)),
          ])));
}
