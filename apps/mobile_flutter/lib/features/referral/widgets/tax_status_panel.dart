import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/utils/error_message_ru.dart';

class TaxStatusPanel extends StatefulWidget {
  const TaxStatusPanel(
      {super.key, this.apiClient, this.driver = false, this.onSaved});
  final ApiClient? apiClient;
  final bool driver;
  final VoidCallback? onSaved;
  @override
  State<TaxStatusPanel> createState() => _TaxStatusPanelState();
}

class _TaxStatusPanelState extends State<TaxStatusPanel> {
  final _iin = TextEditingController();
  String? _kind;
  bool _consent = false, _saving = false;
  String _error = '';
  @override
  void dispose() {
    _iin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_kind == null || _iin.text.length != 12 || !_consent) {
      setState(() =>
          _error = 'Выберите статус, укажите ИИН и подтвердите согласие.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await (widget.apiClient ?? ApiClient()).post('/tax/profile', data: {
        'countryCode': 'KZ',
        'kind': _kind,
        'iin': _iin.text,
        'activities': [if (widget.driver) '49320', '82990'],
        'consent': true,
      });
      widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Статус отправлен на проверку')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessageRu(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.verified_user_outlined,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                  child: Text('Ваш налоговый статус',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w700)))
            ]),
            const SizedBox(height: 8),
            const Text('Казахстан · выберите свой действующий статус'),
            const SizedBox(height: 16),
            SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'SELF_EMPLOYED',
                      label: Text('Самозанятый'),
                      icon: Icon(Icons.person_outline)),
                  ButtonSegment(
                      value: 'IE',
                      label: Text('ИП'),
                      icon: Icon(Icons.business_center_outlined)),
                ],
                selected: {
                  if (_kind != null) _kind!
                },
                emptySelectionAllowed: true,
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _kind = value.isEmpty ? null : value.first)),
            const SizedBox(height: 12),
            Text(_kind == 'IE'
                ? 'Социальные платежи самозанятого не удерживаются. Вы самостоятельно выдаёте чеки при расчётах и ведёте отчётность по своему налоговому режиму.'
                : 'Обычно 4% дохода: ОПВ, ОПВР, СО и ОСМС — по 1%. Платформа удерживает и перечисляет платежи после проверки статуса и запуска учёта. Льготы и месячные ограничения учитываются отдельно.'),
            const SizedBox(height: 12),
            TextField(
                controller: _iin,
                maxLength: 12,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'ИИН',
                    helperText: 'Хранится в защищённом виде')),
            TextButton.icon(
                onPressed: () => showTaxGuide(context),
                icon: const Icon(Icons.auto_stories_outlined),
                label: const Text('Нет статуса? Как оформить самозанятость')),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                    'Подтверждаю статус и согласен на учёт дохода и удержание предусмотренных законом платежей.'),
                subtitle: Text(_kind == 'IE'
                    ? 'Подтверждаю действующее ИП и самостоятельное исполнение обязанностей по своему налоговому режиму.'
                    : 'Самозанятость: без ИП и работников, разрешённая деятельность и лимит 300 МРП в месяц.')),
            if (_error.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Сохраняем…' : 'Сохранить статус'))),
          ])));
}

Future<void> showTaxGuide(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
        child: FractionallySizedBox(
            heightFactor: .85,
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Самозанятость в Казахстане',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 14),
                      const Text('1. Проверьте условия',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'Режим доступен гражданам РК и кандасам без ИП и наёмных работников. Деятельность должна входить в разрешённый перечень, общий доход — не превышать 300 МРП за месяц.'),
                      const SizedBox(height: 14),
                      const Text('2. Оформите действующий режим',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'В e-Salyq Business авторизуйтесь, проверьте данные и применяемый режим, выберите разрешённую деятельность и оформляйте расчёты по правилам приложения. Нажатие кнопки в INTERCITY не регистрирует вас в КГД.'),
                      const SizedBox(height: 8),
                      const Text(
                          'Kaspi: официальный гид указывает открытие предпринимательского счёта и получение первой оплаты. Это не регистрация ИП. Сначала прочитайте актуальную инструкцию банка.'),
                      TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(
                                  'https://guide.kaspi.kz/partner/ru/tax/conditions/self-employed/q4549'),
                              mode: LaunchMode.externalApplication),
                          child: const Text('Официальная инструкция Kaspi')),
                      const Text(
                          'Halyk и другие банки: уточните доступность счёта и сервиса именно для самозанятых. Поддержка услуг и шаги отличаются; не открывайте ИП, если выбираете режим самозанятости.'),
                      const SizedBox(height: 14),
                      const Text('3. Сохраните статус в INTERCITY',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'Укажите ИИН и действующий статус. После проверки разрешённой деятельности, договора и льгот доход попадёт в денежный учёт. До проверки начисления ожидают подтверждения.'),
                      const SizedBox(height: 14),
                      const Text('Что вы получаете',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'Законный доход без регистрации ИП при соблюдении условий режима. ИПН — 0%. Пенсионные взносы, социальные отчисления и ОСМС учитываются отдельно; медицинское страхование и социальные выплаты зависят от фактических платежей и условий закона.'),
                      const SizedBox(height: 14),
                      const Text('Что делает платформа',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Text(
                          'После запуска операторского учёта платформа рассчитывает, удерживает и перечисляет положенные платежи с учтённого ею дохода. Платёж обычно составляет 4%, с учётом льгот и ограничений. Доходы вне платформы, сведения о статусе и применимости режима остаются вашей ответственностью. Социального налога в эти 4% нет.'),
                      TextButton(
                          onPressed: () => launchUrl(
                              Uri.parse(
                                  'https://adilet.zan.kz/rus/docs/K2500000214'),
                              mode: LaunchMode.externalApplication),
                          child:
                              const Text('Налоговый кодекс · статьи 718–721')),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Понятно'))),
                    ])))));
