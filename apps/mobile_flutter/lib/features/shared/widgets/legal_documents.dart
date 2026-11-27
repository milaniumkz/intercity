import 'package:flutter/material.dart';

class LegalDocuments extends StatelessWidget {
  const LegalDocuments({super.key, required this.offer, required this.agreement});
  final String offer;
  final String agreement;

  void _read(BuildContext context, String title, String document) {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: SelectableText(document)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      TextButton(
        onPressed: () => _read(context, 'Публичная оферта', offer),
        child: const Text('Публичная оферта'),
      ),
      TextButton(
        onPressed: () => _read(context, 'Пользовательское соглашение', agreement),
        child: const Text('Пользовательское соглашение'),
      ),
    ],
  );
}
