import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intercity_mobile/core/theme/theme_controller.dart';
import 'package:intercity_mobile/features/driver/widgets/driver_dashboard_metrics.dart';

Map<String, dynamic> _performance(String level) => {
      'activity': {
        'score': level == 'blocked'
            ? 0
            : level == 'red'
                ? 20
                : level == 'yellow'
                    ? 50
                    : 100,
        'level': level,
        'blocked': level == 'blocked',
        'rules': {
          'initialScore': 100,
          'rejectPenalty': 3,
          'blockHours': 12,
          'restoredScore': 30,
          'greenFrom': 70,
          'yellowFrom': 30
        }
      },
      'rating': {'average': 4.85, 'count': 12},
      'priority': {
        'total': 15,
        'items': [
          {
            'label': 'Шашка',
            'points': 5,
            'rule': 'Подтверждённая шашка: +5 баллов.'
          },
          {
            'label': 'Обклейка',
            'points': 10,
            'rule': 'Подтверждённая обклейка: +10 баллов.'
          },
        ]
      },
    };

void main() {
  for (final level in ['green', 'yellow', 'red', 'blocked']) {
    testWidgets('activity highlights the server $level state', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DriverDashboardMetrics(
                  balance: '500 ₽',
                  today: 3,
                  performance: _performance(level)))));
      final tile = find.byKey(const ValueKey('driver-metric-Активность'));
      final score = _performance(level)['activity']['score'].toString();
      final text = tester
          .widget<Text>(find.descendant(of: tile, matching: find.text(score)));
      expect(text.style?.color, DriverDashboardMetrics.activityColors[level]);
      if (level == 'blocked') {
        expect(
            find.descendant(
                of: tile, matching: find.byIcon(Icons.lock_outline)),
            findsOneWidget);
      }
      expect(find.text('4.85'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
        'compact cards and all explanations work in ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
              body: MediaQuery(
                  data: const MediaQueryData(
                      size: Size(320, 568), textScaler: TextScaler.linear(1.5)),
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DriverDashboardMetrics(
                          balance: '500 ₽',
                          today: 3,
                          performance: _performance('green')))))));
      final tops = ['Баланс', 'Сегодня', 'Активность', 'Рейтинг', 'Приоритет']
          .map((label) => tester
              .getTopLeft(find.byKey(ValueKey('driver-metric-$label')))
              .dy)
          .toSet();
      expect(tops, hasLength(2));
      for (final label in [
        'Баланс',
        'Сегодня',
        'Активность',
        'Рейтинг',
        'Приоритет'
      ]) {
        final rect =
            tester.getRect(find.byKey(ValueKey('driver-metric-$label')));
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(304));
        expect(rect.height, lessThan(75));
      }
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(DriverDashboardMetrics)).height,
          lessThan(150));
      for (final section in ['Активность', 'Рейтинг', 'Приоритет']) {
        final tile = find.byKey(ValueKey('driver-metric-$section'));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text(section)),
            findsOneWidget);
        if (section == 'Приоритет') {
          expect(find.text('Подтверждённая шашка: +5 баллов.'), findsOneWidget);
          expect(find.text('+10'), findsOneWidget);
        }
        final scroll = find.byKey(const ValueKey('driver-metric-help-scroll'));
        final scrollWidget = tester.widget<SingleChildScrollView>(scroll);
        expect(
            scrollWidget.controller!.position.maxScrollExtent, greaterThan(0));
        final closeTop = tester.getTopLeft(find.byTooltip('Закрыть'));
        await tester.drag(scroll, const Offset(0, -180));
        await tester.pumpAndSettle();
        expect(scrollWidget.controller!.offset, greaterThan(0));
        expect(tester.getTopLeft(find.byTooltip('Закрыть')), closeTop);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Закрыть'));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
