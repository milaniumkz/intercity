import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/ic_premium.dart';

class ReferralLandingPage extends StatefulWidget {
  const ReferralLandingPage({super.key, required this.referralCode});

  final String referralCode;

  @override
  State<ReferralLandingPage> createState() => _ReferralLandingPageState();
}

class _ReferralLandingPageState extends State<ReferralLandingPage> {
  late final String _code = _normalizeCode(widget.referralCode);
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _saveReferral();
  }

  String _normalizeCode(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  String get _referralLink => '${AppConstants.publicWebUrl}/#/ref/$_code';

  Future<void> _saveReferral() async {
    if (_code.isEmpty) return;
    await AppPreferences.setPendingReferralCode(_code);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _referralLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Реферальная ссылка скопирована')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      body: ICPremiumBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                const ICBrandHeader(
                  compact: true,
                  subtitle: 'Реферальная система',
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: LinearGradient(
                      colors: theme.brightness == Brightness.dark
                          ? const [Color(0xFF201138), Color(0xFF0D0818)]
                          : const [Colors.white, Color(0xFFF7F0FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.16),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.secondaryColor,
                              AppTheme.primaryColor,
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.group_add_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Ваш реферал сохранён',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _saved
                            ? 'При регистрации по этой ссылке приглашение будет закреплено автоматически.'
                            : 'Сохраняем приглашение...',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.14),
                          ),
                        ),
                        child: SelectableText(
                          _referralLink,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ICGradientButton(
                        label: 'Зарегистрироваться',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () =>
                            context.go('/register/passenger?ref=$_code'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ICPremiumTextButton(
                              label: 'Скопировать ссылку',
                              icon: Icons.copy_rounded,
                              onPressed: _copyLink,
                            ),
                          ),
                          Expanded(
                            child: ICPremiumTextButton(
                              label: 'Войти',
                              icon: Icons.login_rounded,
                              onPressed: () => context.go('/login?ref=$_code'),
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
      ),
    );
  }
}
