import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String currentRouteText(BuildContext context) {
  try {
    return GoRouterState.of(context).uri.toString();
  } catch (_) {
    return Uri.base.toString();
  }
}

bool routeHas(BuildContext context, String marker) {
  return currentRouteText(context).contains(marker) ||
      Uri.base.toString().contains(marker);
}
