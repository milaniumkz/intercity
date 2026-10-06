import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../home/screens/order_screen.dart';

class OrderPage extends StatefulWidget {
  const OrderPage(
      {super.key,
      this.resetToken,
      this.routeStage,
      this.initialStep,
      this.apiClient});
  final String? resetToken;
  final String? routeStage;
  final int? initialStep;
  final ApiClient? apiClient;
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  bool _checking = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _checkActiveOrder();
  }

  Future<void> _checkActiveOrder() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final response = await _api.get('/orders/active');
      if (!mounted) return;
      final data = response.data;
      if (data is Map && (data['id'] ?? '').toString().isNotEmpty) {
        final id = Uri.encodeComponent(data['id'].toString());
        if (data['type'] == 'CITY') {
          context.go('/order/searching/$id');
          return;
        }
        if (data['type'] == 'INTERCITY') {
          context.go('/market/request/$id');
          return;
        }
        throw StateError('Unexpected active order type');
      }
      setState(() => _checking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _error != null) {
      return Scaffold(
          body: SafeArea(
              child: Center(
                  child: _checking
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                  onPressed: _checkActiveOrder,
                                  child: const Text('Повторить проверку'))
                            ],
                          )))));
    }
    return OrderScreen(
        resetToken: widget.resetToken,
        routeStage: widget.routeStage,
        initialStep: widget.initialStep,
        apiClient: _api);
  }
}
