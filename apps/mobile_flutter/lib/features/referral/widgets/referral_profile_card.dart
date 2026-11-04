import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_constants.dart';

class ReferralProfileCard extends StatefulWidget {
  const ReferralProfileCard(
      {super.key,
      required this.user,
      this.apiClient,
      this.showLegacyTotals = true});
  final Map<String, dynamic>? user;
  final ApiClient? apiClient;
  final bool showLegacyTotals;

  @override
  State<ReferralProfileCard> createState() => _ReferralProfileCardState();
}

class _ReferralProfileCardState extends State<ReferralProfileCard> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response =
          await (widget.apiClient ?? ApiClient()).get('/auth/referral');
      if (mounted && response.data is Map) {
        setState(() => _summary = Map<String, dynamic>.from(response.data));
      }
    } catch (_) {
      // The personal code still allows sharing while statistics are unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final code =
        (_summary?['refCode'] ?? widget.user?['refCode'] ?? '').toString();
    if (code.isEmpty) return const SizedBox.shrink();
    final link = (_summary?['refLink'] ??
            '${AppConstants.publicWebUrl}/#/ref/${Uri.encodeComponent(code)}')
        .toString();
    final earned =
        _summary?['earned'] is Map ? _summary!['earned'] as Map : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Пригласить друзей',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                'Приглашайте пассажиров и водителей. Вознаграждение начисляется после завершения и подтверждения поездки. Поездки на проверке начисляются после одобрения.'),
            const SizedBox(height: 8),
            SelectableText(link),
            const SizedBox(height: 8),
            Text('Код приглашения: $code'),
            if (_summary != null) ...[
              Text('Приглашено: ${_summary!["invitedCount"] ?? 0}'),
              if (earned != null && widget.showLegacyTotals)
                Text(
                    'Начислено: ${(earned["KZT"] as num? ?? 0).toStringAsFixed(2)} тг · ${(earned["RUB"] as num? ?? 0).toStringAsFixed(2)} ₽'),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Скопировать ссылку'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Реферальная ссылка скопирована')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
