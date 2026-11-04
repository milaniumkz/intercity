import 'package:flutter/material.dart';

class DriverTaxNotice extends StatelessWidget {
  const DriverTaxNotice({super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Налоги и чеки водителя',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
                'Водитель самостоятельно ведёт учёт доходов, оформляет чеки и исполняет налоговые обязательства в соответствии со своим налоговым режимом. INTERCITY удерживает только комиссию сервиса.'),
            const SizedBox(height: 16),
            Text('Если вы самозанятый',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
                'Если вы применяете специальный налоговый режим для самозанятых в Казахстане, самостоятельно формируйте чеки через E-Salyq Business, учитывайте полученный доход и уплачивайте социальные платежи. Общая ставка — 4%: ОПВ 1%, ОПВР 1%, СО 1%, ОСМС 1%; ИПН по этому режиму — 0%. Применимость режима, ограничения и льготы необходимо учитывать по законодательству.'),
            const SizedBox(height: 16),
            Text('Если вы индивидуальный предприниматель',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
                'Самостоятельно ведите учёт доходов, оформляйте чеки предусмотренным для вашей деятельности способом, уплачивайте налоги и обязательные платежи, сдавайте декларации и другую отчётность в сроки вашего налогового режима. Ставка 4% для самозанятых не является общей ставкой для ИП.'),
            const SizedBox(height: 16),
            const Text(
                'Водитель самостоятельно отвечает за своевременное оформление чеков, уплату налогов и обязательных платежей, представление деклараций и соблюдение требований законодательства.'),
          ])));
}
