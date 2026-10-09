import 'package:flutter/material.dart';

class DriverActiveTripView extends StatelessWidget {
  const DriverActiveTripView(
      {super.key,
      required this.map,
      required this.passenger,
      required this.from,
      required this.to,
      required this.price,
      required this.status,
      required this.payment,
      required this.onRefresh,
      required this.onCall,
      required this.onChat,
      required this.onNavigate,
      this.instruction,
      this.message,
      this.onBack,
      this.actionLabel,
      this.actionIcon,
      this.onAction,
      this.busy = false});

  final Widget map;
  final String passenger, from, to, price, status, payment;
  final String? instruction, actionLabel, message;
  final VoidCallback? onBack;
  final IconData? actionIcon;
  final VoidCallback onRefresh, onCall, onChat, onNavigate;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Активный заказ'),
            automaticallyImplyLeading: false,
            leading: onBack == null
                ? null
                : IconButton(
                    onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            actions: [
              IconButton(
                  tooltip: 'Обновить',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh))
            ]),
        body: SafeArea(
            top: false,
            bottom: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(passenger,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(price,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      Theme.of(context).textTheme.titleLarge))
                        ]),
                        Text('$status · $payment',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        _address('Откуда', from, Icons.trip_origin),
                        const SizedBox(height: 6),
                        _address('Куда', to, Icons.location_on_outlined),
                      ])),
              Expanded(
                  child: Stack(children: [
                Positioned.fill(child: map),
                if (instruction != null)
                  Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(instruction!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis)))),
              ])),
            ])),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (message != null)
                    Text(message!,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                            tooltip: 'Позвонить',
                            onPressed: onCall,
                            icon: const Icon(Icons.phone_outlined)),
                        IconButton(
                            tooltip: 'Чат',
                            onPressed: onChat,
                            icon: const Icon(Icons.chat_bubble_outline)),
                        IconButton(
                            tooltip: 'Навигатор',
                            onPressed: onNavigate,
                            icon: const Icon(Icons.navigation_outlined)),
                      ]),
                  if (actionLabel != null)
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                            key: const ValueKey('driver-primary-ride-action'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56)),
                            onPressed: busy ? null : onAction,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (busy)
                                    const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                  else
                                    Icon(actionIcon),
                                  const SizedBox(width: 8),
                                  Flexible(
                                      child: Text(actionLabel!,
                                          maxLines: 2,
                                          textAlign: TextAlign.center)),
                                ]))),
                ]))),
      );

  Widget _address(String label, String address, IconData icon) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
            child: Text('$label: $address',
                maxLines: 2, overflow: TextOverflow.ellipsis))
      ]);
}
