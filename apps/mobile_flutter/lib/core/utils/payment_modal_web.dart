import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../theme/theme_controller.dart';

Future<bool> showPaymentModal(BuildContext context, String url) async {
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

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog.fullscreen(
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
                  const Expanded(
                    child: Text(
                      'Пополнение баланса',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(child: HtmlElementView(viewType: viewType)),
          ],
        ),
      ),
    ),
  );
  return true;
}
