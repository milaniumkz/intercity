import '../../../core/utils/app_mode_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import 'package:go_router/go_router.dart';

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

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? challenge;
  String? grant;
  String code = '';
  String password = '';
  String notice = '';
  final api = ApiClient();

  Future<void> advance() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    setState(() { _sending = true; notice = ''; });
    try {
      if (challenge == null) {
        final result = await api.post('/auth/recovery/whatsapp/start', data: {
          'phone': normalizeKzLocalPhone(_phoneController.text),
        });
        if (!mounted) return;
        setState(() { challenge = result.data['challenge'] as String; notice = 'Проверьте WhatsApp на указанном номере. Код действует 5 минут.'; });
      } else if (grant == null) {
        final result = await api.post('/auth/recovery/whatsapp/verify', data: {'challenge':challenge,'code':code.trim()});
        if (!mounted) return;
        setState(() {grant = result.data['grant'] as String; notice = '';});
      } else {
        final result = await api.post('/auth/recovery/password', data: {'grant':grant,'password':password});
        await api.setTokens(result.data['accessToken'] as String, result.data['refreshToken'] as String);
        final user = result.data['user'];
        final route = await AppModeManager.resolveHomeRoute(api,role:user['role'] as String,userId:user['id'] as String);
        if (mounted) context.go(route);
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      final reason = body is Map ? body['message'] : null;
      if (mounted) setState(() => notice = reason is String && RegExp('[А-Яа-я]').hasMatch(reason) ? reason : 'Не удалось выполнить действие. Проверьте соединение.');
    } catch (_) {
      if (mounted) setState(() => notice = 'Не удалось завершить восстановление. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _sending = false;

  Future<void> _sendRequest() async {
    if (_sending) return;
    if (!isValidKzPhone(normalizeKzLocalPhone(_phoneController.text))) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiClient().post('/auth/recovery/admin-request', data: {
        'phone': normalizeKzLocalPhone(_phoneController.text.trim()),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Если аккаунт найден, обращение передано администратору.'),
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Не удалось отправить обращение. Проверьте связь и повторите.'),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: ICPremiumBackground(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Row(children: [
              IconButton(
                key: const ValueKey('forgot_password_back_button'),
                tooltip: 'Вернуться ко входу',
                onPressed: () => goBackOr(context, fallback: '/login'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const Expanded(child: ICBrandHeader(compact: true)),
            ]),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: ICCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Восстановление доступа',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 16),
                            const ICPremiumInfoBanner(
                              icon: Icons.info_outline_rounded,
                              text:
                                  'Одноразовый код придёт сообщением в WhatsApp на номер вашего аккаунта InterCity.',
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              readOnly: challenge != null || _sending,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [
                                AutofillHints.telephoneNumberNational
                              ],
                              inputFormatters: [KzLocalPhoneInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: 'Телефон аккаунта',
                                hintText: '(999) 123-45-67',
                                prefixText: '+7 ',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (value) => isValidKzPhone(
                                      normalizeKzLocalPhone(value ?? ''))
                                  ? null
                                  : 'Введите телефон аккаунта полностью',
                            ),
                            const SizedBox(height: 16),
                            if (challenge != null && grant == null) TextFormField(
                              key: const ValueKey('whatsapp-code'), keyboardType: TextInputType.number, maxLength: 6,
                              decoration: const InputDecoration(labelText:'Код из WhatsApp'),
                              onChanged:(value) => code = value,
                              validator:(value) => RegExp(r'^\d{6}
                            ),
                            const SizedBox(height: 12),
                            if (challenge != null) TextButton(onPressed: _sending ? null : () => setState(() {challenge = null; grant = null; code = ''; password = ''; notice = ''; }), child: const Text('Запросить новый код')),
                            OutlinedButton.icon(
                              label: const Text('Написать в техподдержку'),
                              icon: const Icon(Icons.support_agent),
                              onPressed: _sending ? null : _sendRequest,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Вернуться ко входу'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Никому не сообщайте пароль от аккаунта. '
                              'Если вы уже вошли и знаете текущий пароль, '
                              'измените его в профиле: '
                              'Настройки → Безопасность.',
                              style: theme.textTheme.bodySmall,
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
}
).hasMatch(value ?? '') ? null : 'Введите шесть цифр',
                            ),
                            if (grant != null) TextFormField(
                              key: const ValueKey('new-password'), obscureText: true,
                              decoration: const InputDecoration(labelText:'Новый пароль'),
                              onChanged:(value) => password = value,
                              validator:(value) => (value ?? '').length >= 12 ? null : 'Введите не менее 12 символов',
                            ),
                            if (notice.isNotEmpty) Text(notice),
                            ICGradientButton(
                              label: grant != null ? 'Сохранить пароль и войти' : challenge != null ? 'Проверить код' : 'Отправить код на WhatsApp',
                              icon: Icons.lock_outline,
                              onPressed: _sending ? null : advance,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              label: const Text('Обратиться к администратору'),
                              icon: const Icon(Icons.support_agent),
                              onPressed: _sending ? null : _sendRequest,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Вернуться ко входу'),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Никому не сообщайте пароль от аккаунта. '
                              'Если вы уже вошли и знаете текущий пароль, '
                              'измените его в профиле: '
                              'Настройки → Безопасность.',
                              style: theme.textTheme.bodySmall,
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
}
