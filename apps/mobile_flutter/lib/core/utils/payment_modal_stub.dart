import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> showPaymentModal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.inAppBrowserView);
}
