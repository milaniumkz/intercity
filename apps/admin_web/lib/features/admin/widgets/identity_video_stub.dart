import 'dart:typed_data';
import 'package:flutter/material.dart';

class IdentityVideo extends StatelessWidget {
  const IdentityVideo({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) =>
      const Text('Видео доступно в веб-версии админки');
}
