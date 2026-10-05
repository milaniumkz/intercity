import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/error_message_ru.dart';
import '../../../core/utils/phone_input_formatter.dart';
import '../../../core/widgets/ic_premium.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '+7 (000) 000-00-00');
  final _passwordController = TextEditingController(text: '123456');
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient();
      final response = await apiClient.post(
        '/auth/login',
        data: {
          'phone': normalizeKzPhone(_phoneController.text.trim()),
          'password': _passwordController.text,
        },
      );

      final role = (response.data['user']?['role'] ?? '').toString();
      if (role != 'ADMIN') {
        throw Exception('Пользователь не является администратором');
      }

      await apiClient.setTokens(
        response.data['accessToken'] as String,
        response.data['refreshToken'] as String,
      );

      if (!mounted) return;
      context.go('/admin/dashboard');
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Form(
              key: _formKey,
              child: ICCard(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  'assets/branding/adaptive-icon.png',
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'InterCity',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 28,
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Вход администратора',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Управление заказами, финансами, сервером и ролями',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDecoration(
                              label: 'Телефон',
                              icon: Icons.phone_rounded,
                            ),
                            inputFormatters: <TextInputFormatter>[
                              KzPhoneInputFormatter(),
                            ],
                            validator: (value) {
                              if (!isValidKzPhone(value ?? '')) {
                                return 'Формат: +7 (###) ###-##-##';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: _inputDecoration(
                              label: 'Пароль',
                              icon: Icons.lock_rounded,
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? 'Введите пароль'
                                    : null,
                          ),
                          const SizedBox(height: 24),
                          ICGradientButton(
                            label: 'Войти в админку',
                            loading: _isLoading,
                            onPressed: _isLoading ? null : _login,
                          ),
                          const SizedBox(height: 12),
                          ICPremiumTextButton(
                            label: 'Назад к обычному входу',
                            icon: Icons.arrow_back_rounded,
                            onPressed: () => context.go('/login'),
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
    );
  }
}
