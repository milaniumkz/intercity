import 'package:flutter/material.dart';
import '../../../core/api/admin_api_client.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _phoneCtrl = TextEditingController(text: '+70000000000');
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String _message = '';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final user = await AdminApiClient.instance.login(
        _phoneCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (user['role'] != 'ADMIN') {
        setState(() => _message = 'У пользователя нет прав администратора');
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      setState(() => _message = _loginErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _loginErrorMessage(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('401') ||
        text.contains('unauthorized') ||
        text.contains('invalid credentials')) {
      return 'Неверный телефон или пароль администратора.';
    }
    if (text.contains('xmlhttprequest') ||
        text.contains('connection') ||
        text.contains('socket') ||
        text.contains('timeout')) {
      return 'Нет соединения с сервером. Проверьте интернет или адрес API.';
    }
    return 'Не удалось войти. Попробуйте ещё раз.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEAF2F7), Color(0xFFF4F7FB), Color(0xFFDCE9F2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const SizedBox(
                    width: 420,
                    child: _LoginIntro(),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Вход',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                                'Используйте учётную запись администратора для входа в панель.'),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Телефон (+7XXXXXXXXXX)'),
                              onSubmitted: (_) => _loading ? null : _login(),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: true,
                              decoration:
                                  const InputDecoration(labelText: 'Пароль'),
                              onSubmitted: (_) => _loading ? null : _login(),
                            ),
                            const SizedBox(height: 20),
                            if (_loading) const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _loading ? null : _login,
                                child: Text(
                                    _loading ? 'Выполняется вход...' : 'Войти'),
                              ),
                            ),
                            if (_message.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _message
                                              .toLowerCase()
                                              .contains('failed') ||
                                          _message.contains('not ADMIN') ||
                                          _message.contains('Неверный')
                                      ? const Color(0xFFFFF1F0)
                                      : const Color(0xFFEAF6FF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(_message),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginIntro extends StatelessWidget {
  const _LoginIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'INTERCITY Admin',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0B2239),
              ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Удобная админка для диспетчеризации, платежей, тарифов и контроля операций.',
          style: TextStyle(fontSize: 18, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _IntroChip(
                icon: Icons.grid_view_rounded, label: 'Панель показателей'),
            _IntroChip(
                icon: Icons.verified_user_outlined,
                label: 'Проверка водителей'),
            _IntroChip(
                icon: Icons.payments_outlined, label: 'Финансовые действия'),
            _IntroChip(
                icon: Icons.notifications_active_outlined,
                label: 'Управление рассылками'),
          ],
        ),
      ],
    );
  }
}

class _IntroChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _IntroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E2EC)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0F5B7A)),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
