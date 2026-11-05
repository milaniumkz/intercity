import '../../../core/services/pwa_support.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/ic_premium.dart';

class ReferralLandingPage extends StatefulWidget {
  const ReferralLandingPage(
      {super.key,
      required this.referralCode,
      this.downloadOnly = false,
      this.apiClient});

  final String referralCode;
  final bool downloadOnly;
  final ApiClient? apiClient;

  @override
  State<ReferralLandingPage> createState() => _ReferralLandingPageState();
}

class _ReferralLandingPageState extends State<ReferralLandingPage> {
  String get _code => _normalizeCode(widget.referralCode);
  bool _saved = false;
  String? _appStoreUrl;
  String? _testFlightUrl;
  String _iosMode = 'web';
  bool _accountReady = false;
  bool _invitationConfirmed = false;
  bool _hasInvitation = false;
  String? _accountError;
  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;
  String? _googlePlayUrl;

  @override
  void initState() {
    super.initState();
    if (!widget.downloadOnly) _saveReferral();
    _loadStores();
    if (widget.downloadOnly) {
      _confirmAccount();
    }
  }

  @override
  void didUpdateWidget(covariant ReferralLandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.referralCode != widget.referralCode ||
        oldWidget.downloadOnly != widget.downloadOnly) {
      _saved = false;
      _accountReady = false;
      _invitationConfirmed = false;
      _accountError = null;
      if (!widget.downloadOnly) {
        _saveReferral();
      } else {
        _confirmAccount();
      }
      _loadStores();
    }
  }

  Future<void> _loadStores() async {
    try {
      final response =
          await (widget.apiClient ?? ApiClient()).get('/app/runtime-settings');
      if (!mounted || response.data is! Map) return;
      setState(() {
        _appStoreUrl = response.data['appStoreUrl'] as String?;
        _testFlightUrl = response.data['testFlightUrl'] as String?;
        _iosMode = response.data['iosDistributionMode'] as String? ?? 'web';
        final play = response.data['googlePlayUrl'] as String?;
        if (play != null) {
          final uri = Uri.parse(play);
          _googlePlayUrl = uri.replace(queryParameters: {
            ...uri.queryParameters,
            'referrer': Uri(queryParameters: {'ref': _code}).query,
          }).toString();
        }
      });
    } catch (_) {
      // Registration remains available independently of store settings.
    }
  }

  Future<void> _confirmAccount() async {
    setState(() => _accountError = null);
    try {
      final response = await (widget.apiClient ?? ApiClient()).get('/me');
      if (!mounted) {
        return;
      }
      setState(() {
        _accountReady = true;
        _hasInvitation =
            (response.data['referredBy'] ?? '').toString().isNotEmpty;
        _invitationConfirmed = response.data['referredBy'] == _code;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _accountError =
            'Не удалось проверить аккаунт. Повторите проверку перед установкой.');
      }
    }
  }

  Future<void> _openStore(String url) async {
    final opened =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть магазин приложений')),
      );
    }
  }

  String _normalizeCode(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  String get _referralLink => '${AppConstants.publicWebUrl}/#/ref/$_code';

  Future<void> _saveReferral() async {
    final code = _code;
    if (code.isEmpty) return;
    await AppPreferences.setPendingReferralCode(code);
    if (!mounted || code != _code) return;
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
                        widget.downloadOnly
                            ? (_invitationConfirmed
                                ? 'Приглашение закреплено'
                                : _accountReady
                                    ? 'Ваш аккаунт готов'
                                    : 'Проверяем аккаунт')
                            : 'Вас пригласили в INTERCITY',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.downloadOnly
                            ? (_accountReady
                                ? (!_invitationConfirmed
                                    ? (_hasInvitation ? 'У вас уже есть аккаунт. Ранее закреплённое приглашение сохраняется. Новая ссылка не меняет пригласившего. После установки войдите с тем же номером телефона и паролем.' : 'Аккаунт создан без приглашения. Вы можете пользоваться InterCity.')
                                    : _isIos && _iosMode == 'web'
                                        ? 'Пользуйтесь веб-версией на iPhone. При переходе в приложение позже войдите в тот же аккаунт — приглашение сохранится.'
                                        : 'Установите приложение и войдите с тем же номером телефона и паролем. Приглашение хранится в аккаунте и не потеряется при установке.')
                                : 'Подтверждаем сохранение вашего аккаунта на сервере.')
                            : _saved
                                ? 'Зарегистрируйтесь по этой ссылке — приглашение применится автоматически. На Android затем установите приложение из Google Play и войдите в тот же аккаунт. На iPhone продолжайте в веб-версии.'
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
                      if (!widget.downloadOnly)
                        ICGradientButton(
                          label: 'Зарегистрироваться',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () => context
                              .go('/register/passenger?ref=$_code&download=1'),
                        ),
                      const SizedBox(height: 10),
                      if (widget.downloadOnly &&
                          _accountReady &&
                          !_isIos &&
                          _googlePlayUrl != null) ...[
                        ICGradientButton(
                            label: 'Скачать в Google Play',
                            icon: Icons.android,
                            onPressed: () => _openStore(_googlePlayUrl!)),
                        const SizedBox(height: 10),
                      ],
                      if (widget.downloadOnly &&
                          _accountReady &&
                          _isIos &&
                          _iosMode == 'appstore' &&
                          _appStoreUrl != null) ...[
                        ICGradientButton(
                            label: 'Скачать в App Store',
                            icon: Icons.apple,
                            onPressed: () => _openStore(_appStoreUrl!)),
                        const SizedBox(height: 10),
                      ],
                      if (widget.downloadOnly &&
                          _accountReady &&
                          _isIos &&
                          _iosMode == 'testflight' &&
                          _testFlightUrl != null) ...[
                        ICGradientButton(
                            label: 'Установить через TestFlight',
                            icon: Icons.apple,
                            onPressed: () => _openStore(_testFlightUrl!)),
                        const SizedBox(height: 10),
                      ],
                      if (_accountError != null) ...[
                        Text(_accountError!),
                        TextButton(
                            onPressed: _confirmAccount,
                            child: const Text('Повторить проверку')),
                      ],
                      if (widget.downloadOnly && PwaSupport.isIosWeb)
                        const ICGradientButton(
                            label: 'На главный экран iPhone',
                            icon: Icons.add_to_home_screen,
                            onPressed: PwaSupport.showHelp),
                      if (widget.downloadOnly)
                        ICGradientButton(
                          label: 'Продолжить в веб-версии',
                          icon: Icons.public,
                          onPressed: () => context.go('/order'),
                        ),
                      if (widget.downloadOnly && _isIos && _iosMode == 'web')
                        const Text(
                            'Приложение для iPhone проходит одобрение. Веб-версия уже доступна.'),
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
