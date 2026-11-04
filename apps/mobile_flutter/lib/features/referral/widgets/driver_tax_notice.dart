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
                'Сейчас INTERCITY удерживает только комиссию сервиса. Налоговая интеграция приостановлена: платформа не удерживает и не перечисляет за водителя новые налоговые и социальные платежи. Выбор налогового статуса в приложении не требуется.'),
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
                'Водитель отвечает за соблюдение применимых требований и законность своей деятельности. Информационный режим приложения не отменяет эти обязанности. После подключения интеграции порядок удержаний будет отдельно включён и отражён в приложении. Ранее учтённые удержания сохраняются в истории.'),
          ])));
}
