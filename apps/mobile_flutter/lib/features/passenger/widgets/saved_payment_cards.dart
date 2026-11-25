import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/payment_modal.dart';

class SavedPaymentCards extends StatefulWidget {
  const SavedPaymentCards({super.key, this.apiClient, this.onReadyChanged});
  final ApiClient? apiClient;
  final void Function(bool ready, String? last4)? onReadyChanged;
  @override
  State<SavedPaymentCards> createState() => _SavedPaymentCardsState();
}

class _SavedPaymentCardsState extends State<SavedPaymentCards> with WidgetsBindingObserver {
  late final _api = widget.apiClient ?? ApiClient();
  List<Map<String, dynamic>> _cards = [];
  bool _configured = false;
  bool _vtb = false;
  bool _canBind = true;
  bool _busy = true;
  Timer? _bindingPoll;
  String _message = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bindingPoll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) { _load(); }
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
        _vtb = data['provider'] == 'VTB_SANDBOX';
        _canBind = data['cardBindingAvailable'] != false;
        _message = data['message']?.toString() ?? '';
      });
      final binding = data['binding'];
      final pending = binding is Map && ['CREATED', 'PENDING', 'CHECKING', 'REFUND_PENDING'].contains(binding['status']);
      if (pending) {
        _bindingPoll ??= Timer.periodic(const Duration(seconds: 3), (_) {
          if (mounted && !_busy) { _load(); }
        });
      } else {
        _bindingPoll?.cancel();
        _bindingPoll = null;
      }
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
      final uri = Uri.tryParse(response.data['url']?.toString() ?? '');
      if (uri == null || uri.scheme != 'https') {
        throw Exception('Банк ещё готовит форму. Обновите карты через несколько секунд.');
      }
      if (_vtb) {
        if (uri.host != 'vtbkz.rbsuat.com' || !uri.path.startsWith('/payment/')) {
          throw Exception('Некорректная ссылка ВТБ');
        }
        if (!mounted) { return; }
        await showPaymentModal(context, uri.toString(),
          title: 'Привязка карты ВТБ · 1 ₸ с возвратом · тест',
          isCompleted: () async {
            final result = await _api.get('/payments/cards');
            final binding = result.data['binding'];
            return binding is Map && ['SYNCED', 'NOT_SAVED', 'CANCELLED'].contains(binding['status']);
          });
        if (mounted) { await _load(); }
      } else {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw Exception('Не удалось открыть Kassa24');
        }
        if (mounted) {
          setState(() => _message =
            'Завершите привязку в Kassa24, затем нажмите «Обновить карты».');
        }
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
            Text(_vtb
                ? 'Для поездок в рублях. Банк списывает тенге по курсу 1 ₽ = 7 ₸. Сохранённая карта выбирается для следующего заказа.'
                : 'Для поездок в тенге. Стоимость списывается при начале поездки.'),
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
            if (_configured && _canBind)
              OutlinedButton.icon(
                  onPressed: _busy ? null : _bind,
                  icon: const Icon(Icons.add),
                  label: Text(_vtb ? 'Добавить карту · 1 ₸ с возвратом' : 'Добавить карту')),
            if (_configured && _canBind)
              Text(_vtb
                  ? 'Данные карты и CVC вводятся только в форме ВТБ. Проверочный 1 ₸ возвращается автоматически. Для сохранения отметьте «Сохранить карту» в форме банка. При следующем заказе ВТБ может запросить CVC или 3-D Secure.'
                  : 'Добавляя карту, вы разрешаете списание согласованной стоимости заказанных поездок. Данные карты вводятся в защищённой форме Kassa24.'),
            if (_message.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message)),
          ])));
}
