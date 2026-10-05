import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/widgets/ic_premium.dart';
import '../widgets/passenger_bottom_nav.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.paymentsOnly = false});

  final bool paymentsOnly;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  String _selectedPayment = 'Наличные';
  String _message = '';
  int _bonusBalance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final res = await ApiClient().get('/wallet');
      final data = res.data;
      if (!mounted) return;
      if (data is Map) {
        setState(() {
          _bonusBalance = _asInt(
            data['bonuses'] ??
                data['bonusBalance'] ??
                data['points'] ??
                data['bonus'],
            fallback: _bonusBalance,
          );
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  int _asInt(Object? value, {required int fallback}) {
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  void _selectPayment(String value) {
    setState(() {
      _selectedPayment = value;
      _message = 'Основной способ оплаты: $value';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paymentsOnly) return _paymentsScreen(context);
    return _bonusScreen(context);
  }

  Widget _bonusScreen(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 2),
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => goBackOr(context, fallback: '/profile'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: ICBrandHeader(
                      compact: true,
                      subtitle: 'Бонусная программа',
                    ),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C2DFF), Color(0xFF3E1268)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x552C174C),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ваш баланс',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_bonusBalance',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'бонусов',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ICCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Как использовать бонусы',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _BonusRule(
                      icon: Icons.currency_ruble,
                      text: '1 бонус = 1 ₸',
                    ),
                    const _BonusRule(
                      icon: Icons.percent_rounded,
                      text: 'Можно оплатить до 100% стоимости поездки',
                    ),
                    const _BonusRule(
                      icon: Icons.add_card_rounded,
                      text: 'Бонусы суммируются с промокодами',
                    ),
                    const _BonusRule(
                      icon: Icons.event_available_rounded,
                      text: 'Срок действия бонусов — 12 месяцев',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'История операций',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const _BonusOperation(
                positive: true,
                title: 'Начисление бонусов',
                subtitle: 'За поездку по городу',
                value: '+300',
                date: '12.05.2024',
              ),
              const _BonusOperation(
                positive: false,
                title: 'Списание бонусов',
                subtitle: 'Оплата поездки',
                value: '-150',
                date: '12.05.2024',
              ),
              const _BonusOperation(
                positive: true,
                title: 'Начисление бонусов',
                subtitle: 'За межгород',
                value: '+200',
                date: '10.05.2024',
              ),
              const SizedBox(height: 12),
              ICGradientButton(
                label: 'Использовать в поездке',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => setState(
                  () => _message = 'Бонусы можно выбрать на экране оплаты.',
                ),
              ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 10),
                ICPremiumInfoBanner(text: _message),
              ],
              if (isDark) const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentsScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 3),
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => goBackOr(context, fallback: '/profile'),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Expanded(
                  child: ICBrandHeader(
                    compact: true,
                    subtitle: 'Способы оплаты',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF271044), Color(0xFF100B1F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x552C174C),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.credit_card_rounded,
                      color: Colors.white, size: 34),
                  SizedBox(height: 12),
                  Text(
                    'Оплата поездок',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'В поездках доступны наличные, карта и бонусы.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PaymentMethodCard(
              icon: Icons.payments_rounded,
              title: 'Наличные',
              subtitle: 'Оплата водителю после поездки',
              selected: _selectedPayment == 'Наличные',
              onTap: () => _selectPayment('Наличные'),
            ),
            const SizedBox(height: 10),
            _PaymentMethodCard(
              icon: Icons.credit_card_rounded,
              title: 'На карту',
              subtitle: 'Безналичная оплата в заказе',
              selected: _selectedPayment == 'На карту',
              onTap: () => _selectPayment('На карту'),
            ),
            const SizedBox(height: 10),
            _PaymentMethodCard(
              icon: Icons.stars_rounded,
              title: 'Бонусами',
              subtitle: 'До 100% стоимости поездки',
              selected: _selectedPayment == 'Бонусами',
              onTap: () => _selectPayment('Бонусами'),
            ),
            if (_message.isNotEmpty) ...[
              const SizedBox(height: 10),
              ICPremiumInfoBanner(text: _message),
            ],
          ],
        ),
      ),
    );
  }
}

class _BonusRule extends StatelessWidget {
  const _BonusRule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BonusOperation extends StatelessWidget {
  const _BonusOperation({
    required this.positive,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.date,
  });

  final bool positive;
  final String title;
  final String subtitle;
  final String value;
  final String date;

  @override
  Widget build(BuildContext context) {
    final color = positive ? const Color(0xFF26A269) : const Color(0xFFE04444);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ICCard(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(
                positive ? Icons.add_rounded : Icons.remove_rounded,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$subtitle · $date',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ICCard(
        selected: selected,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: selected
                    ? const LinearGradient(
                        colors: [
                          AppTheme.secondaryColor,
                          AppTheme.primaryColor,
                        ],
                      )
                    : null,
                color: selected ? null : theme.colorScheme.primaryContainer,
              ),
              child: Icon(
                icon,
                color: selected
                    ? Colors.white
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
