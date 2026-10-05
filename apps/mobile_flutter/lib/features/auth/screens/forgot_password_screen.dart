import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/navigation_back.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/widgets/ic_premium.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  void _goBackToLogin() {
    goBackOr(context, fallback: '/login');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient();
      await apiClient.post(
        '/auth/reset-password',
        data: {
          'phone': normalizeKzLocalPhone(_phoneController.text.trim()),
          'password': _passwordController.text,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пароль обновлён. Теперь можно войти с новым паролем.'),
        ),
      );
      context.go('/login');
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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('forgot_password_back_button'),
                  onPressed: _goBackToLogin,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const Expanded(
                  child: ICBrandHeader(
                    compact: true,
                    subtitle: 'Безопасный доступ',
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: ICCard(
                      padding: EdgeInsets.zero,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: const BoxDecoration(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(22),
                                ),
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF1B0D33),
                                    Color(0xFF0B0817),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 62,
                                        height: 62,
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
                                        child: const Icon(
                                          Icons.lock_reset_rounded,
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Text(
                                          'Восстановление доступа',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 22,
                                            height: 1.05,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Введите телефон и новый пароль. После обновления вернём вас на экран входа.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Row(
                                    children: [
                                      _ResetStep(
                                          label: 'Телефон', active: true),
                                      _ResetStep(label: 'Пароль', active: true),
                                      _ResetStep(label: 'Вход', active: false),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Сменить пароль',
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Новый пароль должен быть не короче 6 символов.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  const ICPremiumInfoBanner(
                                    icon: Icons.shield_outlined,
                                    text:
                                        'Мы не показываем пароль и не отправляем его третьим лицам.',
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: _inputDecoration(
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
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: !_showPassword,
                                    decoration: _inputDecoration(
                                      hintText: 'Новый пароль',
                                      icon: Icons.lock_rounded,
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
                                        icon: Icon(
                                          _showPassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Введите новый пароль';
                                      }
                                      if (value.length < 6) {
                                        return 'Минимум 6 символов';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _confirmPasswordController,
                                    obscureText: !_showConfirmPassword,
                                    decoration: _inputDecoration(
                                      hintText: 'Повторите новый пароль',
                                      icon: Icons.verified_user_rounded,
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _showConfirmPassword =
                                              !_showConfirmPassword,
                                        ),
                                        icon: Icon(
                                          _showConfirmPassword
                                              ? Icons.visibility_off_rounded
                                              : Icons.visibility_rounded,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Повторите новый пароль';
                                      }
                                      if (value != _passwordController.text) {
                                        return 'Пароли не совпадают';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                  ICGradientButton(
                                    label: 'Обновить пароль',
                                    loading: _isLoading,
                                    onPressed:
                                        _isLoading ? null : _resetPassword,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
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
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.36,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
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
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}

class _ResetStep extends StatelessWidget {
  const _ResetStep({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? 0.22 : 0.10),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? Colors.white : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
