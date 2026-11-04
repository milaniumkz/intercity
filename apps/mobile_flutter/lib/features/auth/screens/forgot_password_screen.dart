import 'face_verification_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _videoRecovery() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normalizeKzLocalPhone(_phoneController.text.trim());
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FaceVerificationPage(phone: phone)));
  }

  Future<void> _copyRequest() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = normalizeKzLocalPhone(_phoneController.text.trim());
    final message = 'Восстановление доступа InterCity\n'
        'Телефон аккаунта: $phone\n'
        'Не могу войти в аккаунт. Прошу помочь восстановить доступ. '
        'Готов подтвердить, что аккаунт принадлежит мне.';
    try {
      await Clipboard.setData(ClipboardData(text: message));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:
            Text('Текст скопирован. Отправьте его администратору InterCity.'),
      ));
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Обращение администратору'),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
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
                                  'Восстановите доступ по новой видеозаписи. Лицо сравнивается с эталоном, сохранённым при первичной проверке.',
                            ),
                            const SizedBox(height: 16),
                            const Text('1. Укажите телефон своего аккаунта.\n'
                                '2. Пройдите видеопроверку по случайным подсказкам.\n'
                                '3. После подтверждения лица придумайте новый пароль. Если эталона ещё нет или лицо не совпадает, сброс не разрешается.'),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _phoneController,
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
                            ICGradientButton(
                              label: 'Восстановить по видеопроверке',
                              icon: Icons.videocam_outlined,
                              onPressed: _videoRecovery,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              label: const Text('Обратиться к администратору'),
                              icon: const Icon(Icons.support_agent),
                              onPressed: _copyRequest,
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
