import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intercity_shared/intercity_shared.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/payment_modal.dart';
import '../../../core/utils/route_query.dart';
import '../../../core/widgets/ic_premium.dart';
import '../widgets/driver_bottom_nav.dart';

class _BoardWalletOperation {
  const _BoardWalletOperation({
    required this.type,
    required this.date,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountColor,
    required this.time,
  });

  final String type;
  final String date;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String amount;
  final Color amountColor;
  final String time;
}

const _boardWalletOperationData = <_BoardWalletOperation>[
  _BoardWalletOperation(
    type: 'Списания',
    date: 'Сегодня',
    icon: Icons.link_rounded,
    iconColor: AppTheme.primaryColor,
    title: 'Списание за принятую заявку',
    subtitle: 'Алматы -> Астана',
    amount: '-270 ₸',
    amountColor: Color(0xFFE34060),
    time: '10:15',
  ),
  _BoardWalletOperation(
    type: 'Пополнения',
    date: 'Сегодня',
    icon: Icons.account_balance_wallet_rounded,
    iconColor: Color(0xFF26B36A),
    title: 'Пополнение баланса',
    subtitle: 'Банковская карта **** 4242',
    amount: '+1 000 ₸',
    amountColor: Color(0xFF26B36A),
    time: '09:40',
  ),
  _BoardWalletOperation(
    type: 'Списания',
    date: '23 мая',
    icon: Icons.link_rounded,
    iconColor: AppTheme.primaryColor,
    title: 'Списание за принятую заявку',
    subtitle: 'Костанай -> Павлодар',
    amount: '-220 ₸',
    amountColor: Color(0xFFE34060),
    time: '23.05, 15:10',
  ),
  _BoardWalletOperation(
    type: 'Пополнения',
    date: '23 мая',
    icon: Icons.account_balance_wallet_rounded,
    iconColor: Color(0xFF26B36A),
    title: 'Пополнение баланса',
    subtitle: 'Банковская карта **** 4242',
    amount: '+500 ₸',
    amountColor: Color(0xFF26B36A),
    time: '23.05, 12:30',
  ),
];

class DriverWalletPage extends StatefulWidget {
  const DriverWalletPage({super.key, this.routeStage, this.apiClient});

  final String? routeStage;

  final ApiClient? apiClient;

  @override
  State<DriverWalletPage> createState() => _DriverWalletPageState();
}

class _DriverWalletPageState extends State<DriverWalletPage> {
  Map<String, dynamic>? _wallet;
  String _currency = 'KZT';
  String get _currencySymbol => _currency == 'RUB' ? '₽' : '₸';
  final _topupCtrl = TextEditingController(text: '1000');
  final _payoutCtrl = TextEditingController(text: '1000');
  final _cardCtrl = TextEditingController();
  String _message = '';
  bool _loading = false;
  bool _topupBusy = false;
  bool _initialized = false;
  int _boardWalletTab = 0;
  String _boardWalletFilter = 'Все';
  num _bonusBalance = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    if (_routeStage('seed')) {
      _wallet = {'money': 2860, 'bonuses': 2450};
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _topupCtrl.dispose();
    _payoutCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  bool _routeStage(String marker) {
    return widget.routeStage == marker || routeHas(context, 'wallet_$marker=1');
  }

  bool get _useIntercityBoardUi => true;

  num _asAmount(Object? value, {required num fallback}) {
    if (value is num) return value;
    return num.tryParse((value ?? '').toString()) ?? fallback;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await (widget.apiClient ?? ApiClient())
          .get('/wallet?currency=$_currency');
      if (!mounted) return;
      setState(() {
        _wallet = Map<String, dynamic>.from(res.data as Map);
        _bonusBalance = _asAmount(
          _wallet?['bonuses'] ??
              _wallet?['bonusBalance'] ??
              _wallet?['points'] ??
              _wallet?['bonus'],
          fallback: _bonusBalance,
        );
        _message = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topup() async {
    if (_topupBusy) return;
    try {
      final amount = double.tryParse(_topupCtrl.text.replaceAll(',', '.')) ?? 0;
      if (amount <= 0) {
        setState(() => _message = 'Введите сумму пополнения больше нуля.');
        return;
      }
      setState(() {
        _topupBusy = true;
        _message = 'Создаём заявку на пополнение...';
      });
      final res = await (widget.apiClient ?? ApiClient())
          .post('/wallet/topup-request', data: {
        'amount': amount,
        'currency': _currency,
      });
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final paymentUrl = (data['paymentUrl'] ?? '').toString();
      final remoteMessage = (data['message'] ?? '').toString();
      if (mounted) {
        setState(() {
          _message = remoteMessage.isNotEmpty
              ? remoteMessage
              : 'Заявка на пополнение создана';
        });
        if (paymentUrl.isNotEmpty) {
          await showPaymentModal(context, paymentUrl);
        } else {
          await _showWalletInfoDialog(
            title: 'Пополнение баланса',
            message: _message,
            copyValue: null,
            copyLabel: 'Скопировать ссылку',
          );
        }
      }
      await _load();
    } catch (e) {
      setState(() => _message = errorMessageRu(e));
    } finally {
      if (mounted) setState(() => _topupBusy = false);
    }
  }

  Future<bool> _openPaymentUrl(String value) async {
    final opened = await showPaymentModal(context, value);
    if (!opened && mounted) {
      setState(
        () => _message =
            'Не удалось открыть оплату автоматически. Скопируйте ссылку и откройте её в браузере.',
      );
    }
    return opened;
  }

  Future<void> _payout() async {
    try {
      final amount =
          double.tryParse(_payoutCtrl.text.replaceAll(',', '.')) ?? 0;
      if (amount <= 0) {
        if (!mounted) return;
        await _showWalletInfoDialog(
          title: 'Вывод средств',
          message: 'Введите сумму вывода больше нуля.',
          copyValue: null,
        );
        return;
      }
      final res = await (widget.apiClient ?? ApiClient())
          .post('/wallet/payout-request', data: {
        'amount': amount,
        'currency': _currency,
        'cardNumber': _cardCtrl.text.trim(),
      });
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final withdrawId = (data['withdrawId'] ?? '').toString();
      final remoteMessage = (data['message'] ?? '').toString();
      if (!mounted) return;
      setState(() => _message = '');
      if (mounted) {
        await _showWalletInfoDialog(
          title: 'Вывод средств',
          message: remoteMessage.isNotEmpty
              ? remoteMessage
              : 'Заявка на вывод создана и отправлена на обработку.',
          copyValue: withdrawId.isEmpty ? null : withdrawId,
          copyLabel: 'Скопировать ID',
        );
      }
      await _load();
    } catch (e) {
      final message = errorMessageRu(e);
      if (!mounted) return;
      setState(() => _message = '');
      await _showWalletInfoDialog(
        title: 'Вывод средств',
        message: message,
        copyValue: null,
      );
    }
  }

  Future<void> _showWalletInfoDialog({
    required String title,
    required String message,
    String? copyValue,
    String copyLabel = 'Скопировать',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.secondaryColor.withValues(alpha: 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: AppTheme.primaryColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if ((copyValue ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppTheme.secondaryColor.withValues(alpha: 0.12),
                          ),
                        ),
                        child: SelectableText(
                          copyValue!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: (copyValue ?? '').startsWith('http')
                              ? ICPremiumTextButton(
                                  label: 'Открыть оплату',
                                  icon: Icons.open_in_new_rounded,
                                  onPressed: () => _openPaymentUrl(copyValue!),
                                )
                              : ICPremiumTextButton(
                                  label: copyLabel,
                                  icon: Icons.copy_rounded,
                                  onPressed: (copyValue ?? '').isEmpty
                                      ? null
                                      : () async {
                                          await Clipboard.setData(
                                            ClipboardData(text: copyValue!),
                                          );
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                ),
                        ),
                        if ((copyValue ?? '').startsWith('http')) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: ICPremiumTextButton(
                              label: copyLabel,
                              icon: Icons.copy_rounded,
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: copyValue!),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        Expanded(
                          child: ICGradientButton(
                            label: 'Закрыть',
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return ICCard(child: child);
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFF8F6FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.14),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.4),
      ),
    );
  }

  Widget _driverBonusCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF11101D) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF141326);
    final muted = isDark ? Colors.white70 : const Color(0xFF7C7590);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.14),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Бонусы',
                      style: TextStyle(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '1 бонус = 1 $_currencySymbol',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _moneyText(_bonusBalance),
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _bonusLine(
            icon: Icons.trending_up_rounded,
            title: 'Начисление бонусов',
            subtitle: 'За завершённые поездки и активность',
            value: '+120',
            positive: true,
          ),
          _bonusLine(
            icon: Icons.rocket_launch_rounded,
            title: 'Списание бонусов',
            subtitle: 'Поднятие заявки в топ',
            value: '-80',
            positive: false,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(
                () =>
                    _message = 'Бонусы можно использовать для поднятия в топ.',
              ),
              icon: const Icon(Icons.rocket_launch_rounded),
              label: const Text('Поднять заявку в топ за бонусы'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverPayoutCard({bool compact = false}) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            icon: Icons.outbox_rounded,
            title: 'Вывод средств',
            subtitle:
                'Доступно: ${_moneyText(_wallet?["withdrawable"])} $_currencySymbol. Бонусы не выводятся.',
          ),
          SizedBox(height: compact ? 10 : 12),
          TextField(
            controller: _payoutCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _inputDecoration(
              label: 'Сумма вывода',
              icon: Icons.payments_outlined,
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          TextField(
            controller: _cardCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDecoration(
              label: 'Номер карты для вывода',
              icon: Icons.credit_card_rounded,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ICGradientButton(
              label: 'Создать заявку на вывод',
              icon: Icons.outbox_rounded,
              onPressed: _payout,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bonusLine({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required bool positive,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final color = positive ? const Color(0xFF26B36A) : const Color(0xFFE34060);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverWalletHero({required String money}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF271044), Color(0xFF100B1F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x552C174C),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                  ),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Кошелёк',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Комиссии, пополнения и выплаты',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: _heroAmountTile(
              label: 'Доступно на балансе',
              value: '$money $_currencySymbol',
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroAmountTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7C7590),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _currencySelector() => SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'KZT', label: Text('Тенге ₸')),
          ButtonSegment(value: 'RUB', label: Text('Рубли ₽')),
        ],
        selected: {_currency},
        onSelectionChanged: _loading
            ? null
            : (values) {
                setState(() {
                  _currency = values.single;
                  _bonusBalance = 0;
                  _wallet = null;
                  _loading = true;
                });
                _load();
              },
      );

  @override
  Widget build(BuildContext context) {
    if (_routeStage('seed') || _useIntercityBoardUi) {
      return _boardWalletScreen();
    }

    final money = (_wallet?['money'] ?? 0).toString();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 2),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ICPremiumBackground(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/home'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Expanded(
                    child: ICBrandHeader(
                      compact: true,
                      subtitle: 'Кошелёк водителя',
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              _currencySelector(),
              if (_loading) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              _driverWalletHero(money: money),
              const SizedBox(height: 12),
              _driverBonusCard(),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      icon: Icons.add_card_rounded,
                      title: 'Пополнение баланса',
                      subtitle: 'Ссылка для оплаты баланса',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _topupCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration(
                        label: 'Сумма пополнения',
                        icon: Icons.add_card_rounded,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ICGradientButton(
                      label: 'Пополнить',
                      onPressed: _topupBusy ? null : _topup,
                      icon: Icons.add_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      icon: Icons.outbox_rounded,
                      title: 'Вывод средств',
                      subtitle:
                          'Доступно: ${_moneyText(_wallet?["withdrawable"])} $_currencySymbol. Бонусы не выводятся.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _payoutCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration(
                        label: 'Сумма вывода',
                        icon: Icons.payments_outlined,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cardCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDecoration(
                        label: 'Номер карты для вывода',
                        icon: Icons.credit_card_rounded,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'После отправки заявка появится в админке и будет обработана онлайн или вручную.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ICGradientButton(
                        label: 'Создать заявку на вывод',
                        icon: Icons.outbox_rounded,
                        onPressed: _payout,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_message.isNotEmpty) ICPremiumInfoBanner(text: _message),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boardWalletScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF11101D) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF141326);
    final muted = isDark ? Colors.white70 : const Color(0xFF7C7590);
    final money = _moneyText(_wallet?['money']);
    final blocked = _moneyText(
      _wallet?['blocked'] ??
          _wallet?['locked'] ??
          _wallet?['reserved'] ??
          (_routeStage('seed') && _currency == 'KZT' ? 540 : 0),
    );
    final payout = _moneyText(
      _wallet?['payout'] ??
          _wallet?['availablePayout'] ??
          (_routeStage('seed') && _currency == 'KZT' ? 5130 : 0),
    );
    final earned = _moneyText(
      _wallet?['earnedTotal'] ??
          _wallet?['totalEarned'] ??
          (_routeStage('seed') && _currency == 'KZT' ? 45680 : 0),
    );
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: const DriverBottomNav(currentIndex: 2),
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () =>
                        goBackOr(context, fallback: '/driver/home'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Кошелёк',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              _currencySelector(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Баланс',
                            style: TextStyle(
                              color: muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$money $_currencySymbol',
                            style: TextStyle(
                              color: text,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 132,
                      child: ICGradientButton(
                        label: 'Пополнить',
                        onPressed: _topupBusy ? null : _topup,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _boardStatCard(
                          'Заблокировано', '$blocked $_currencySymbol')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _boardStatCard(
                          'К выплате', '$payout $_currencySymbol')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _boardStatCard(
                          'Всего заработано', '$earned $_currencySymbol')),
                ],
              ),
              const SizedBox(height: 10),
              _driverBonusCard(),
              const SizedBox(height: 10),
              _driverPayoutCard(compact: true),
              if (_loading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                height: 38,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _boardSegment(
                        'История операций',
                        _boardWalletTab == 0,
                        onTap: () => setState(() => _boardWalletTab = 0),
                      ),
                    ),
                    Expanded(
                      child: _boardSegment(
                        'Статистика',
                        _boardWalletTab == 1,
                        onTap: () => setState(() => _boardWalletTab = 1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_boardWalletTab == 0) ...[
                Row(
                  children: [
                    _boardWalletChip('Все'),
                    _boardWalletChip('Списания'),
                    _boardWalletChip('Пополнения'),
                  ],
                ),
                const SizedBox(height: 14),
                ..._boardWalletOperations(),
              ] else
                _boardWalletStatsDetails(
                  blocked: blocked,
                  payout: payout,
                  earned: earned,
                ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 8),
                ICPremiumInfoBanner(text: _message),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _moneyText(dynamic value) => formatWalletAmount(value);

  Widget _boardStatCard(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 72,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF7C7590),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF141326),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _boardSegment(String label, bool selected, {VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF211538) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppTheme.primaryColor
                : (isDark ? Colors.white70 : const Color(0xFF7C7590)),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _boardWalletChip(String label) {
    final selected = _boardWalletFilter == label;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _boardWalletFilter = label),
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: selected
                  ? const LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    )
                  : null,
              color: selected
                  ? null
                  : (isDark ? const Color(0xFF11101D) : Colors.white),
              border: Border.all(
                color: AppTheme.primaryColor
                    .withValues(alpha: selected ? 0 : 0.12),
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF7C7590)),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _boardWalletOperations() {
    if (!_routeStage('seed') || _currency == 'RUB') {
      final rows = (_wallet?['transactions'] as List? ?? []).whereType<Map>();
      final visible = rows.where((row) {
        final type = row['type'].toString();
        return _boardWalletFilter == 'Все' ||
            (_boardWalletFilter == 'Пополнения' && type.startsWith('TOPUP')) ||
            (_boardWalletFilter == 'Списания' && row['direction'] == 'DEBIT') ||
            (_boardWalletFilter == 'Выплаты' && type.startsWith('PAYOUT')) ||
            (_boardWalletFilter == 'Комиссии' &&
                (type.contains('COMMISSION') || type.contains('INTERCITY')));
      }).toList();
      if (visible.isEmpty) {
        return [
          const ICPremiumInfoBanner(text: 'Операций по выбранному фильтру нет.')
        ];
      }
      return visible
          .map((row) => _boardOperationCard(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: AppTheme.primaryColor,
                title: (row['note'] ?? row['type']).toString(),
                subtitle: row['balanceSource'] == 'BONUS' ? 'Бонусы' : 'Деньги',
                amount:
                    '${row['direction'] == 'DEBIT' ? '-' : '+'}${_moneyText(row['amount'])} $_currencySymbol',
                amountColor: AppTheme.primaryColor,
                time: (row['createdAt'] ?? '').toString().split('T').first,
              ))
          .toList();
    }
    final items = _boardWalletOperationData.where((item) {
      return _boardWalletFilter == 'Все' || item.type == _boardWalletFilter;
    }).toList();
    if (items.isEmpty) {
      return [
        const SizedBox(height: 20),
        const ICPremiumInfoBanner(text: 'Операций по выбранному фильтру нет.'),
      ];
    }
    var lastDate = '';
    final widgets = <Widget>[];
    for (final item in items) {
      if (item.date != lastDate) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
        widgets.add(_boardDateLabel(item.date));
        lastDate = item.date;
      }
      widgets.add(_boardOperationCard(
        icon: item.icon,
        iconColor: item.iconColor,
        title: item.title,
        subtitle: item.subtitle,
        amount: item.amount,
        amountColor: item.amountColor,
        time: item.time,
      ));
    }
    return widgets;
  }

  Widget _boardWalletStatsDetails({
    required String blocked,
    required String payout,
    required String earned,
  }) {
    return Column(
      children: [
        _boardOperationCard(
          icon: Icons.lock_rounded,
          iconColor: AppTheme.primaryColor,
          title: 'Заблокировано под комиссии',
          subtitle: 'Средства резервируются при принятии заявок',
          amount: '$blocked $_currencySymbol',
          amountColor: AppTheme.primaryColor,
          time: 'сейчас',
        ),
        _boardOperationCard(
          icon: Icons.payments_rounded,
          iconColor: const Color(0xFF26B36A),
          title: 'Доступно к выплате',
          subtitle: 'Можно вывести на карту',
          amount: '$payout $_currencySymbol',
          amountColor: const Color(0xFF26B36A),
          time: 'сейчас',
        ),
        _boardOperationCard(
          icon: Icons.trending_up_rounded,
          iconColor: const Color(0xFF7C2DFF),
          title: 'Всего заработано',
          subtitle: 'Сумма завершённых поездок',
          amount: '$earned $_currencySymbol',
          amountColor: const Color(0xFF7C2DFF),
          time: 'всего',
        ),
      ],
    );
  }

  Widget _boardDateLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7C7590),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _boardOperationCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String amount,
    required Color amountColor,
    required String time,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF141326),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF7C7590),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF7C7590),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
