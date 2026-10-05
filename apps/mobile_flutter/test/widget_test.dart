import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intercity_mobile/main.dart';

void main() {
  testWidgets('INTERCITY app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: IntercityApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
