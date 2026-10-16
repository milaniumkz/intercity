import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PersonalIncomeTaxNotice extends StatelessWidget {
  const PersonalIncomeTaxNotice({super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Налоговое уведомление · Казахстан',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Если вы — резидент РК и доход подлежит самостоятельному налогообложению, '
                'вы сами отвечаете за его декларирование и уплату ИПН (ст. 362 п. 2 НК РК). '
                'Общая ставка — 10% с годового облагаемого дохода до 8 500 МРП включительно, '
                '15% с превышения (ст. 363 пп. 1). '
                'При наличии обязанности декларация о доходах и имуществе (форма 270.00) подаётся до 15 сентября следующего года, '
                'налог уплачивается в течение 10 календарных дней после срока её сдачи (ст. 417–419). '
                'Уведомление не отменяет обязанности налогового агента, когда они предусмотрены законом (ст. 362 п. 1).',
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://adilet.zan.kz/rus/docs/K2500000214'),
                  mode: LaunchMode.externalApplication,
                ),
              child: const Text('НК РК · статьи 362, 363, 417–419'),
              ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://adilet.zan.kz/rus/docs/V2500037390'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Форма 270.00 · приказ № 695, приложение 11'),
            ),
            ],
          ),
        ),
      );
}
