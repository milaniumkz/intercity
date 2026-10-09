import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';

Future<void> showOrderChatSheet({
  required BuildContext context,
  required String orderId,
  required String orderStatus,
  required String title,
  required String currentRole,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OrderChatSheet(
      orderId: orderId,
      orderStatus: orderStatus,
      title: title,
      currentRole: currentRole,
    ),
  );
}

class OrderChatSheet extends StatefulWidget {
  const OrderChatSheet({
    super.key,
    required this.orderId,
    required this.orderStatus,
    required this.title,
    required this.currentRole,
    this.apiClient,
  });

  final String orderId;
  final String orderStatus;
  final String title;
  final String currentRole;
  final ApiClient? apiClient;

  @override
  State<OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends State<OrderChatSheet> {
  late final _api = widget.apiClient ?? ApiClient();
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<dynamic> _messages = const [];
  String _error = '';
  bool _loading = true;
  bool _sending = false;
  bool _loadingMessages = false;
  bool _reloadAfterSend = false;
  Timer? _pollTimer;

  bool get _canWrite => const {
        'DRIVER_ASSIGNED',
        'DRIVER_EN_ROUTE',
        'DRIVER_ARRIVED',
        'IN_PROGRESS',
      }.contains(widget.orderStatus.toUpperCase());

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceScroll = false}) async {
    if (_loadingMessages) {
      if (forceScroll) _reloadAfterSend = true;
      return;
    }
    _loadingMessages = true;
    final follow = forceScroll ||
        _loading ||
        !_scrollCtrl.hasClients ||
        _scrollCtrl.position.extentAfter < 80;
    final previousLast =
        _messages.isEmpty ? null : (_messages.last as Map)['id'];
    try {
      final res = await _api.get('/orders/${widget.orderId}/chat');
      if (!mounted) return;
      setState(() {
        _messages =
            res.data is List ? List<dynamic>.from(res.data as List) : const [];
        _loading = false;
        _error = '';
      });
      final last = _messages.isEmpty ? null : (_messages.last as Map)['id'];
      if (follow && (forceScroll || previousLast != last)) _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessageRu(e);
      });
    } finally {
      _loadingMessages = false;
      if (mounted && _reloadAfterSend) {
        _reloadAfterSend = false;
        unawaited(_load(forceScroll: true));
      }
    }
  }

  Future<void> _send() async {
    final text = _messageCtrl.text.trim();
    if (!_canWrite || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.post('/orders/${widget.orderId}/chat', data: {'text': text});
      _messageCtrl.clear();
      await _load(forceScroll: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.82,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (!_canWrite)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Чат закрыт. Писать можно только во время активной поездки.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(_error,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(child: Text('Сообщений пока нет'))
                      : ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final item = _messages[index] is Map
                                ? Map<String, dynamic>.from(
                                    _messages[index] as Map)
                                : <String, dynamic>{};
                            final sender = item['sender'] is Map
                                ? Map<String, dynamic>.from(
                                    item['sender'] as Map)
                                : <String, dynamic>{};
                            final role = (item['participantRole'] ??
                                    sender['role'] ??
                                    '')
                                .toString()
                                .toUpperCase();
                            final isMine = item['isMine'] is bool
                                ? item['isMine'] == true
                                : role == widget.currentRole.toUpperCase();
                            final senderName =
                                (sender['name'] ?? '').toString().trim();
                            final author = isMine
                                ? 'Вы'
                                : role == 'DRIVER'
                                    ? 'Водитель'
                                    : role == 'PASSENGER'
                                        ? 'Пассажир'
                                        : 'Поддержка';
                            final created =
                                DateTime.tryParse('${item['createdAt']}')
                                    ?.toLocal();
                            final time = created == null
                                ? ''
                                : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                            final foreground = isMine
                                ? Colors.white
                                : theme.colorScheme.onSurface;
                            return Align(
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                key: ValueKey('chat-message-${item['id']}'),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * 0.76,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMine
                                      ? AppTheme.primaryColor
                                      : Color.alphaBlend(
                                          AppTheme.primaryColor
                                              .withValues(alpha: 0.08),
                                          theme.colorScheme.surface),
                                  border: isMine
                                      ? null
                                      : Border.all(
                                          color: AppTheme.primaryColor
                                              .withValues(alpha: 0.16)),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        isMine || senderName.isEmpty
                                            ? author
                                            : '$author · $senderName',
                                        style: TextStyle(
                                            color: foreground.withValues(
                                                alpha: 0.8),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text((item['text'] ?? '').toString(),
                                        style: TextStyle(
                                            color: foreground,
                                            fontWeight: FontWeight.w500)),
                                    if (time.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(time,
                                              style: TextStyle(
                                                  color: foreground.withValues(
                                                      alpha: 0.7),
                                                  fontSize: 10))),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      enabled: _canWrite && !_sending,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText:
                            _canWrite ? 'Напишите сообщение' : 'Чат закрыт',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _canWrite && !_sending ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
