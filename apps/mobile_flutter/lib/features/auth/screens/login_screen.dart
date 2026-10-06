import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/push_notifications_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_mode_manager.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/widgets/ic_premium.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient();
      final response = await apiClient.post(
        '/auth/login',
        data: {
          'phone': normalizeKzLocalPhone(_phoneController.text.trim()),
          'password': _passwordController.text,
        },
      );
      await apiClient.setTokens(
        response.data['accessToken'] as String,
        response.data['refreshToken'] as String,
      );
      await PushNotificationsService.instance.syncTokenIfAuthorized();
      final role = (response.data['user']?['role'] ?? '').toString();
      final route = await AppModeManager.resolveHomeRoute(apiClient,
          role: role, userId: response.data['user']?['id']?.toString());
      if (!mounted) return;
      context.go(route);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessageRu(e))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: ICPremiumBackground(
        padding: EdgeInsets.zero,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Form(
                  key: _formKey,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _CircleBackButton(
                            onTap: () => context.go('/register'),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Text(
                          'Войдите\nв аккаунт',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            fontSize: 30,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Введите номер телефона и пароль, чтобы продолжить.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: compact ? 18 : 26),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(
                            hintText: '(999) 123-45-67',
                            icon: Icons.flag_rounded,
                            compact: compact,
                            prefixText: '+7 ',
                          ),
                          inputFormatters: <TextInputFormatter>[
                            KzLocalPhoneInputFormatter(),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Введите телефон';
                            }
                            if (!isValidKzPhone(normalizeKzLocalPhone(value))) {
                              return 'Формат: (###) ###-##-##';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isLoading) _login();
                          },
                          decoration: _inputDecoration(
                            hintText: 'Пароль',
                            icon: Icons.lock_outline_rounded,
                            compact: compact,
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: ICPremiumTextButton(
                            label: 'Забыли пароль?',
                            onPressed: _isLoading
                                ? null
                                : () => context.push('/forgot-password'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ICGradientButton(
                          label: 'Войти',
                          loading: _isLoading,
                          onPressed: _isLoading ? null : _login,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Продолжая, вы соглашаетесь с Условиями использования и Политикой конфиденциальности.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.3,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(flex: 3),
                        ICPremiumTextButton(
                          label: 'Создать аккаунт',
                          icon: Icons.person_add_alt_1_rounded,
                          onPressed: _isLoading
                              ? null
                              : () => context.push('/register'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required bool compact,
    Widget? suffixIcon,
    String? prefixText,
  }) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      prefixText: prefixText,
      prefixStyle: TextStyle(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w800,
      ),
      suffixIcon: suffixIcon,
      isDense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 12 : 16,
      ),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.36,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: AppTheme.primaryColor,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.54),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded,
              color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
