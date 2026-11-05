import '../../../core/services/pwa_support.dart';
import '../../../core/utils/referral_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/ic_premium.dart';
import '../../../core/widgets/car_selector_fields.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/phone_input_formatter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen(
      {super.key,
      this.role = 'passenger',
      this.referralCode,
      this.downloadAfterRegistration = false,
      this.apiClient});

  final ApiClient? apiClient;
  final String role;
  final String? referralCode;
  final bool downloadAfterRegistration;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  String? _referralCode;
  int _referralGeneration = 0;
  final _carModelController = TextEditingController();
  final _carNumberController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;
  late Future<void> _referralReady;

  bool get _isDriver => widget.role.toLowerCase() == 'driver';

  @override
  void initState() {
    super.initState();
    _referralReady = _loadReferralCode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void didUpdateWidget(covariant RegisterScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_normalizeReferralInput(oldWidget.referralCode) !=
        _normalizeReferralInput(widget.referralCode)) {
      _referralReady = _loadReferralCode();
    }
  }

  Future<void> _loadReferralCode() async {
    final generation = ++_referralGeneration;
    // A referral supplied by the current link must not wait for browser storage.
    final routeCode = _normalizeReferralInput(widget.referralCode);
    if (routeCode != null) {
      _referralCode = routeCode;
      try {
        await AppPreferences.setPendingReferralCode(routeCode);
      } catch (_) {
        // The current link still supplies the code directly to registration.
      }
      if (mounted && generation == _referralGeneration) {
        setState(() {});
      }
      return;
    }
    final storedCode =
        _normalizeReferralInput(await AppPreferences.getPendingReferralCode());
    if (!mounted ||
        generation != _referralGeneration ||
        storedCode == null ||
        (_referralCode ?? '').trim().isNotEmpty) {
      return;
    }
    // Only discard an old browser invitation after a definitive server answer.
    // A current link is never replaced with storage or silently removed.
    try {
      final check = await (widget.apiClient ?? ApiClient()).get(
          '/auth/referral-validity',
          queryParameters: {'code': storedCode});
      if (check.data is Map && check.data['valid'] == false) {
        if (!mounted || generation != _referralGeneration) return;
        await AppPreferences.clearPendingReferralCode();
        if (mounted && generation == _referralGeneration) {
          setState(() => _referralCode = null);
        }
        return;
      }
    } catch (_) {
      /* A network error is not proof that an invitation is invalid. */
    }
    if (mounted && generation == _referralGeneration) {
      setState(() => _referralCode = storedCode);
    }
  }

  String? _normalizeReferralInput(String? raw) => normalizeReferralCode(raw);

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _carModelController.dispose();
    _carNumberController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    await _referralReady;
    if (!mounted) {
      return;
    }
    if (_isLoading || !_formKey.currentState!.validate()) return;
    final submittedReferral = _normalizeReferralInput(_referralCode);

    setState(() => _isLoading = true);

    try {
      final apiClient = widget.apiClient ?? ApiClient();
      final normalizedPhone =
          normalizeKzLocalPhone(_phoneController.text.trim());
      final password = _passwordController.text;
      final response = await apiClient.post(
        '/auth/register',
        data: {
          'phone': normalizedPhone,
          'password': password,
          'name': _nameController.text,
          'referralCode': submittedReferral,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // The server already bound the inviter. Clear the temporary browser code
        // before login or any later step can fail.
        _referralCode = null;
        await AppPreferences.clearPendingReferralCode();
        final accessToken = response.data['accessToken']?.toString();
        final refreshToken = response.data['refreshToken']?.toString();

        if (accessToken != null && refreshToken != null) {
          await apiClient.setTokens(accessToken, refreshToken);
        }

        // Complete registration with a normal login so the app always enters
        // the same authenticated flow regardless of register response shape.
        final loginResponse = await apiClient.post(
          '/auth/login',
          data: {
            'phone': normalizedPhone,
            'password': password,
          },
        );

        if (loginResponse.statusCode == 200 ||
            loginResponse.statusCode == 201) {
          await apiClient.setTokens(
            loginResponse.data['accessToken'].toString(),
            loginResponse.data['refreshToken'].toString(),
          );
        }

        if (_isDriver) {
          await apiClient.post(
            '/driver/profile',
            data: {
              'carModel': _carModelController.text.trim(),
              'carNumber': _carNumberController.text.trim().toUpperCase(),
            },
          );
        }
        if (mounted) {
          final code = submittedReferral;
          final next = widget.downloadAfterRegistration && code != null
              ? '/ref/$code/download'
              : (_isDriver ? '/driver/verification' : '/order');
          final required =
              loginResponse.data['user']?['identityRequired'] == true ||
                  response.data['user']?['identityRequired'] == true;
          context.go(required
              ? Uri(path: '/identity', queryParameters: {
                  'next': next,
                  'driver': _isDriver ? '1' : '0'
                }).toString()
              : next);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessageRu(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Chrome may retain a keyboard inset after its visual viewport changes.
      // Keep the web background full-height and reserve scroll space instead.
      resizeToAvoidBottomInset: !kIsWeb,
      body: ICPremiumBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(
                    bottom:
                        kIsWeb ? MediaQuery.viewInsetsOf(context).bottom : 0),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            goBackOr(context, fallback: '/register'),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ICBrandHeader(
                    compact: true,
                    subtitle: _isDriver ? 'Водитель' : 'Пассажир',
                  ),
                  const SizedBox(height: 16),
                  ICCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                            gradient: LinearGradient(
                              colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
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
                                      color: AppTheme.primaryColor
                                          .withValues(alpha: 0.28),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isDriver
                                      ? Icons.drive_eta_rounded
                                      : Icons.person_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isDriver
                                          ? 'Регистрация водителя'
                                          : 'Регистрация пассажира',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isDriver
                                          ? 'Заполните информацию о себе'
                                          : 'Заполните данные для безопасного входа',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
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
                              _formSectionTitle(
                                icon: Icons.person_rounded,
                                title: 'Личные данные',
                                subtitle: _isDriver
                                    ? 'Контакты для связи с пассажирами'
                                    : 'Имя и номер вашего аккаунта',
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _nameController,
                                decoration: _inputDecoration(
                                  labelText: 'Имя',
                                  icon: Icons.person_rounded,
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Введите имя';
                                  }
                                  return null;
                                },
                              ),
                              if (_isDriver) ...[
                                const SizedBox(height: 18),
                                _formSectionTitle(
                                  icon: Icons.directions_car_filled_rounded,
                                  title: 'Автомобиль',
                                  subtitle: 'Марка, модель, цвет и госномер',
                                ),
                                const SizedBox(height: 14),
                                CarSelectorFields(
                                  requiredFields: true,
                                  onChanged: (value) {
                                    _carModelController.text =
                                        value.displayValue;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _carNumberController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: _inputDecoration(
                                    labelText: 'Госномер',
                                    hintText: '123ABC02',
                                    icon: Icons.pin_outlined,
                                  ),
                                  validator: (value) {
                                    if (_isDriver &&
                                        (value == null ||
                                            value.trim().isEmpty)) {
                                      return 'Введите номер авто';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: _inputDecoration(
                                  labelText: 'Телефон',
                                  hintText: '(999) 123-45-67',
                                  icon: Icons.phone_rounded,
                                  prefixText: '+7 ',
                                ),
                                inputFormatters: <TextInputFormatter>[
                                  KzLocalPhoneInputFormatter(),
                                ],
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Введите телефон';
                                  }
                                  if (!isValidKzPhone(
                                      normalizeKzLocalPhone(value))) {
                                    return 'Формат: (###) ###-##-##';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              _formSectionTitle(
                                icon: Icons.lock_rounded,
                                title: 'Доступ',
                                subtitle: 'Пароль для входа',
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_showPassword,
                                decoration: _inputDecoration(
                                  labelText: 'Пароль',
                                  icon: Icons.lock_rounded,
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                        () => _showPassword = !_showPassword),
                                    icon: Icon(
                                      _showPassword
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Введите пароль';
                                  }
                                  if (value.length < 6) {
                                    return 'Минимум 6 символов';
                                  }
                                  return null;
                                },
                              ),
                              if ((_referralCode ?? '').isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Row(children: [
                                  Icon(Icons.card_giftcard_rounded),
                                  SizedBox(width: 10),
                                  Expanded(
                                      child: Text(
                                          'Приглашение сохранено. Оно применится автоматически, если ссылка действительна. Недействительное приглашение не мешает регистрации.')),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  ICGradientButton(
                    label: _isDriver ? 'Далее' : 'Создать аккаунт',
                    onPressed: _isLoading ? null : _register,
                    loading: _isLoading,
                    icon: Icons.arrow_forward_rounded,
                  ),
                  const SizedBox(height: 14),
                  if (PwaSupport.isWeb)
                    TextButton.icon(
                        onPressed: PwaSupport.showHelp,
                        icon: const Icon(Icons.add_to_home_screen),
                        label: const Text('Установить приложение')),
                  ICPremiumTextButton(
                    label: 'Уже есть аккаунт? Войти',
                    icon: Icons.login_rounded,
                    onPressed: _isLoading ? null : () => context.go('/login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
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
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String labelText,
    required IconData icon,
    String? hintText,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      prefixText: prefixText,
      prefixStyle: TextStyle(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.36,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppTheme.primaryColor,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}
