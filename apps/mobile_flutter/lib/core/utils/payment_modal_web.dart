import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../theme/theme_controller.dart';

Future<bool> showPaymentModal(BuildContext context, String url, {String title = 'Пополнение баланса', Future<bool> Function()? isCompleted}) async {
  if (Uri.tryParse(url) == null || !context.mounted) return false;
  final viewType =
      'intercity-inline-payment-${DateTime.now().microsecondsSinceEpoch}';
  final iframe = web.HTMLIFrameElement()
    ..src = url
    ..allow = 'payment *; fullscreen; clipboard-read; clipboard-write'
    ..referrerPolicy = 'no-referrer-when-downgrade';
  iframe.style
    ..setProperty('border', '0')
    ..setProperty('width', '100%')
    ..setProperty('height', '100%')
    ..setProperty('background', '#ffffff')
    ..setProperty('pointer-events', 'auto');

  ui_web.platformViewRegistry.registerViewFactory(viewType, (_) => iframe);

  BuildContext? activeDialog;
  Timer? poll;
  var checking = false;
  var closing = false;
  if (isCompleted != null) {
    poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (checking || closing) return;
      checking = true;
      try {
        if (await isCompleted() && activeDialog != null && activeDialog!.mounted && !closing) {
          closing = true;
          Navigator.pop(activeDialog!);
        }
      } catch (_) { /* The same bank order remains available for another check. */ }
      finally { checking = false; }
    });
  }
  try {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      activeDialog = dialogContext;
      return Dialog.fullscreen(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Theme.of(dialogContext).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppTheme.primaryColor,
                    tooltip: 'Назад',
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Открыть банк отдельно',
                    onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new)),
                ],
              ),
            ),
            Expanded(child: HtmlElementView(viewType: viewType)),
          ],
        ),
      ),
    );
    },
  );
  } finally {
    closing = true;
    poll?.cancel();
    iframe.removeAttribute('src');
    iframe.remove();
  }
  return true;
}
