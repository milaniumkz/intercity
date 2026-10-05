import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

void goBackOr(BuildContext context, {required String fallback}) {
  final router = GoRouter.of(context);
  final currentPath = router.routeInformationProvider.value.uri.path;
  if (currentPath != fallback) {
    router.go(fallback);
    return;
  }
  if (router.canPop()) context.pop();
}
