import 'package:flutter/material.dart';
import '../../home/screens/order_screen.dart';

class OrderPage extends StatelessWidget {
  const OrderPage(
      {super.key, this.resetToken, this.routeStage, this.initialStep});

  final String? resetToken;
  final String? routeStage;
  final int? initialStep;

  @override
  Widget build(BuildContext context) => OrderScreen(
        resetToken: resetToken,
        routeStage: routeStage,
        initialStep: initialStep,
      );
}
