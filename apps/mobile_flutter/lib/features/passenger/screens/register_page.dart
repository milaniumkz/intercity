import 'package:flutter/material.dart';
import '../../auth/screens/register_screen.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage(
      {super.key,
      this.role = 'passenger',
      this.referralCode,
      this.downloadAfterRegistration = false});

  final String role;
  final String? referralCode;
  final bool downloadAfterRegistration;

  @override
  Widget build(BuildContext context) => RegisterScreen(
      role: role,
      referralCode: referralCode,
      downloadAfterRegistration: downloadAfterRegistration);
}
