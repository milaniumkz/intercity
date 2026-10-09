import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';

class DriverDashboardMetrics extends StatelessWidget {
  const DriverDashboardMetrics(
      {super.key,
      required this.balance,
      required this.today,
      required this.performance,
      this.onBalance});
  final String balance;
  final int today;
  final Map<String, dynamic>? performance;
  final VoidCallback? onBalance;

  Map<String, dynamic> _section(String key) => performance?[key] is Map
      ? Map<String, dynamic>.from(performance![key] as Map)
      : {};
  static const activityColors = {
    'green': Color(0xFF22C55E),
    'yellow': Color(0xFFFBBF24),
    'red': Color(0xFFEF4444),
    'blocked': Color(0xFF94A3B8)
  };
  static const activityLabels = {
    'green': 'Высокая',
    'yellow': 'Снижена',
    'red': 'Низкая',
    'blocked': 'Заблокировано'
  };

  @override
  Widget build(BuildContext context) {
    final activity = _section('activity'),
        rating = _section('rating'),
        priority = _section('priority');
    final level = activity['level']?.toString() ?? '';
    final count = (rating['count'] as num?)?.toInt() ?? 0;
    final tiles = <Widget>[
      _tile(
          context,
          'Баланс',
          balance,
          'Кошелёк',
          Icons.account_balance_wallet_outlined,
          AppTheme.primaryColor,
          onBalance),
      _tile(context, 'Сегодня', '$today', 'Завершённые заказы',
          Icons.check_circle_outline, AppTheme.primaryColor, null),
      _tile(
          context,
          'Активность',
          '${activity['score'] ?? '—'}',
          activityLabels[level] ?? 'Нет данных',
          level == 'blocked' ? Icons.lock_outline : Icons.bolt,
          activityColors[level] ?? Colors.grey,
          () => _showHelp(context, 'activity')),
      _tile(
          context,
          'Рейтинг',
          rating['average'] is num
              ? (rating['average'] as num).toStringAsFixed(2)
              : '—',
          count == 0 ? 'Нет оценок' : '$count ${_reviewWord(count)}',
          Icons.star_outline,
          const Color(0xFFFBBF24),
          () => _showHelp(context, 'rating')),
      _tile(
          context,
          'Приоритет',
          '${priority['total'] ?? '—'}',
          'Баллы',
          Icons.trending_up,
          AppTheme.primaryColor,
          () => _showHelp(context, 'priority')),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width =
          ((constraints.maxWidth - 32) / 5).clamp(128.0, double.infinity);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
            child: Row(children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(width: width, child: tiles[i]),
          ],
        ])),
      );
    });
  }

  Widget _tile(BuildContext context, String label, String value,
      String subtitle, IconData icon, Color accent, VoidCallback? onTap) {
    final theme = Theme.of(context);
    return Semantics(
        button: onTap != null,
        label: '$label: $value, $subtitle',
        child: Material(
            key: ValueKey('driver-metric-$label'),
            color: Color.alphaBlend(
                accent.withValues(alpha: 0.06), theme.colorScheme.surface),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: accent.withValues(alpha: 0.28))),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Row(children: [
                            Expanded(
                                child: Text(value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: accent))),
                            Icon(icon, color: accent, size: 16),
                          ]),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ])))));
  }

  String _reviewWord(int count) => count % 100 >= 11 && count % 100 <= 14
      ? 'оценок'
      : count % 10 == 1
          ? 'оценка'
          : count % 10 >= 2 && count % 10 <= 4
              ? 'оценки'
              : 'оценок';

  Future<void> _showHelp(BuildContext context, String section) async {
    final activity = _section('activity'),
        rating = _section('rating'),
        priority = _section('priority');
    final rules = activity['rules'] is Map
        ? Map<String, dynamic>.from(activity['rules'] as Map)
        : <String, dynamic>{};
    final title = {
      'activity': 'Активность',
      'rating': 'Рейтинг',
      'priority': 'Приоритет'
    }[section]!;
    final icon = {
      'activity': Icons.bolt,
      'rating': Icons.star_outline,
      'priority': Icons.trending_up
    }[section]!;
    final accent = section == 'activity'
        ? activityColors[activity['level']] ?? Colors.grey
        : section == 'rating'
            ? const Color(0xFFFBBF24)
            : AppTheme.primaryColor;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _DriverMetricHelpSheet(
              title: title,
              icon: icon,
              accent: accent,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_section(section).isEmpty)
                      const Text(
                          'Данные пока не загружены. Закройте окно и обновите главный экран.')
                    else if (section == 'activity') ...[
                      _summary(context, '${activity['score']} баллов',
                          activityLabels[activity['level']] ?? '', accent),
                      if (activity['blockedUntil'] != null)
                        Text(
                            'Блокировка до ${_localTime(activity['blockedUntil'])}.'),
                      _paragraph('Как меняется активность',
                          'При подключении — ${rules['initialScore']} баллов. Отказ от предложения снимает ${rules['rejectPenalty']} балла один раз за конкретный заказ. Повторный отказ от того же заказа повторно баллы не снимает. Пропуск по таймеру баллы не списывает.'),
                      _paragraph('Блокировка и восстановление',
                          'При нуле баллов заказы недоступны ${rules['blockHours']} часов. После этого активность восстанавливается до ${rules['restoredScore']} баллов. Принимайте подходящие заказы, чтобы сохранять активность. За завершённые поездки дополнительные баллы сейчас не начисляются.'),
                      _paragraph('Цвет индикатора',
                          'Зелёный — от ${rules['greenFrom']} баллов; жёлтый — от ${rules['yellowFrom']} до ${(rules['greenFrom'] as num?)?.toInt() == null ? '—' : (rules['greenFrom'] as num).toInt() - 1}; красный — меньше ${rules['yellowFrom']}; серый — доступ заблокирован.'),
                    ] else if (section == 'rating') ...[
                      _summary(
                          context,
                          rating['average'] is num
                              ? '${(rating['average'] as num).toStringAsFixed(2)} / 5'
                              : 'Нет оценок',
                          '${rating['count']} ${_reviewWord((rating['count'] as num?)?.toInt() ?? 0)}',
                          accent),
                      _paragraph('Как считается рейтинг',
                          'Среднее всех оценок пассажиров за завершённые поездки по шкале от 1 до 5. Если оценок ещё нет, показывается стартовый рейтинг.'),
                      _paragraph('Как повысить рейтинг',
                          'Приезжайте вовремя, поддерживайте чистоту автомобиля, общайтесь вежливо и ведите аккуратно. Новые высокие оценки повышают среднее, низкие — снижают. При рейтинге строго выше 4,9 добавляются 10 баллов приоритета.'),
                    ] else ...[
                      _summary(context, '${priority['total']} баллов',
                          'Ваш приоритет в очереди', accent),
                      const Text(
                          'При выборе водителя вместе с приоритетом учитываются расстояние до пассажира, рейтинг, активность и доступность.'),
                      const SizedBox(height: 12),
                      for (final raw in (priority['items'] as List? ?? []))
                        if (raw is Map)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text('${raw['label']}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w700))),
                                      Text('+${raw['points']}',
                                          style: TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w800))
                                    ]),
                                    const SizedBox(height: 4),
                                    Text('${raw['rule']}'),
                                  ])),
                      _paragraph('Как увеличить приоритет',
                          'Шашку и обклейку подтверждает администратор: обратитесь в поддержку для подтверждения. Поддерживайте высокий рейтинг. Баллы стажа растут автоматически. Условия бонуса партнёрской заправки уточните в поддержке.'),
                      _paragraph('Почему баллы уменьшаются',
                          'Бонус рейтинга снимается при рейтинге 4,9 и ниже; бонус заправки — после окончания срока. Если подтверждение шашки или обклейки снимается, соответствующие баллы также перестают действовать. Отказы влияют на активность, которая отдельно учитывается в очереди.'),
                    ],
                  ]),
            ));
  }

  Widget _summary(
          BuildContext context, String value, String caption, Color accent) =>
      Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: accent, fontWeight: FontWeight.w800)),
            Text(caption)
          ]));
  Widget _paragraph(String title, String body) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(body)
      ]));
  String _localTime(dynamic value) {
    final time = DateTime.tryParse(value.toString())?.toLocal();
    if (time == null) return 'уточнения статуса';
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _DriverMetricHelpSheet extends StatefulWidget {
  const _DriverMetricHelpSheet(
      {required this.title,
      required this.icon,
      required this.accent,
      required this.child});
  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  State<_DriverMetricHelpSheet> createState() => _DriverMetricHelpSheetState();
}

class _DriverMetricHelpSheetState extends State<_DriverMetricHelpSheet> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.75,
      decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: widget.accent.withValues(alpha: 0.25))),
      child: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(children: [
                  Icon(widget.icon, color: widget.accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(widget.title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800))),
                  IconButton(
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ])),
            Expanded(
                child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      key: const ValueKey('driver-metric-help-scroll'),
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: widget.child,
                    ))),
          ])),
    );
  }
}
