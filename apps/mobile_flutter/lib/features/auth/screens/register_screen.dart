import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
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
      this.downloadAfterRegistration = false});

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
  final _referralController = TextEditingController();
  final _carModelController = TextEditingController();
  final _carNumberController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  bool get _isDriver => widget.role.toLowerCase() == 'driver';

  @override
  void initState() {
    super.initState();
    _loadReferralCode();
  }

  Future<void> _loadReferralCode() async {
    final routeCode = _normalizeReferralInput(widget.referralCode);
    final storedCode =
        _normalizeReferralInput(await AppPreferences.getPendingReferralCode());
    final code = routeCode ?? storedCode;
    if (code == null || _referralController.text.trim().isNotEmpty) return;
    _referralController.text = code;
  }

  String? _normalizeReferralInput(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    final fromQuery = uri?.queryParameters['ref'] ??
        uri?.queryParameters['referral'] ??
        uri?.queryParameters['referralCode'];
    if ((fromQuery ?? '').trim().isNotEmpty) {
      return fromQuery!.trim().toUpperCase();
    }
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.isNotEmpty && segments.first.toLowerCase() == 'ref') {
      return segments.last.trim().toUpperCase();
    }
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').trim().toUpperCase();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _referralController.dispose();
    _carModelController.dispose();
    _carNumberController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final apiClient = ApiClient();
      final normalizedPhone =
          normalizeKzLocalPhone(_phoneController.text.trim());
      final password = _passwordController.text;
      double? lat;
      double? lng;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission().timeout(
            const Duration(seconds: 2),
            onTimeout: () => LocationPermission.denied,
          );
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            timeLimit: Duration(seconds: 3),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {}

      final response = await apiClient.post(
        '/auth/register',
        data: {
          'phone': normalizedPhone,
          'password': password,
          'name': _nameController.text,
          'referralCode': _referralController.text.isNotEmpty
              ? _normalizeReferralInput(_referralController.text)
              : null,
          'lat': lat,
          'lng': lng,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
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

        if (loginResponse.statusCode == 200) {
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
        await AppPreferences.clearPendingReferralCode();
        if (mounted) {
          final code = _normalizeReferralInput(_referralController.text);
          context.go(widget.downloadAfterRegistration && code != null
              ? '/ref/$code/download'
              : (_isDriver ? '/driver/verification' : '/order'));
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
      body: ICPremiumBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: _formKey,
              child: ListView(
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
                  const SizedBox(height: 22),
                  _RegisterHero(isDriver: _isDriver),
                  const SizedBox(height: 12),
                  _RegisterProgressStrip(isDriver: _isDriver),
                  const SizedBox(height: 22),
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
                                          ? 'Личные данные'
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
                                subtitle: 'Контакты для связи с пассажирами',
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
                              if (!_isDriver) ...[
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _referralController,
                                  decoration: _inputDecoration(
                                    labelText:
                                        'Реферальная ссылка или код (опционально)',
                                    icon: Icons.card_giftcard_rounded,
                                  ),
                                ),
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

class _RegisterHero extends StatelessWidget {
  const _RegisterHero({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final title = isDriver ? 'Регистрация водителя' : 'Аккаунт пассажира';
    final subtitle = isDriver
        ? 'Заполните профиль и автомобиль. Документы добавим следующим шагом.'
        : 'Заказывайте город, межгород и доставку.';
    final icon =
        isDriver ? Icons.directions_car_filled_rounded : Icons.person_rounded;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF21113E), AppTheme.primaryColor],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x407C2DFF),
            blurRadius: 24,
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
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(
                      icon: Icons.verified_user_outlined,
                      text: isDriver ? 'Проверка' : 'Безопасно',
                    ),
                    _HeroChip(
                      icon: Icons.shield_outlined,
                      text: isDriver ? 'Надёжно' : 'Комфорт',
                    ),
                    _HeroChip(
                      icon: Icons.route_rounded,
                      text: isDriver ? 'Заказы' : 'Поездки',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterProgressStrip extends StatelessWidget {
  const _RegisterProgressStrip({required this.isDriver});

  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    final steps = isDriver
        ? const [
            ('1', 'Личные данные'),
            ('2', 'Автомобиль'),
            ('3', 'Проверка'),
          ]
        : const [
            ('1', 'Аккаунт'),
            ('2', 'Поездки'),
            ('3', 'Готово'),
          ];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF11101D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          if (!isDark)
            const BoxShadow(
              color: Color(0x142C174C),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
        ],
      ),
      child: Row(
        children: steps.map((step) {
          final index = steps.indexOf(step);
          final selected = index == 0;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: selected
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.secondaryColor,
                                    AppTheme.primaryColor,
                                  ],
                                )
                              : null,
                          color: selected
                              ? null
                              : AppTheme.primaryColor.withValues(alpha: 0.08),
                        ),
                        child: Text(
                          step.$1,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : theme.colorScheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.$2,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != steps.length - 1)
                  Container(
                    width: 22,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: AppTheme.primaryColor.withValues(alpha: 0.22),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
