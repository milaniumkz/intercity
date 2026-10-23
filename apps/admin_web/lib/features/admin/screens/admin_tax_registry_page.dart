import 'package:flutter/material.dart';
import '../../../core/utils/csv_export.dart';
import 'package:dio/dio.dart';
import '../../../core/api/admin_api_client.dart';
import 'admin_dashboard_page.dart';

class AdminTaxRegistryPage extends StatefulWidget {
  const AdminTaxRegistryPage({super.key, this.kind = 'SELF_EMPLOYED'});
  final String kind;
  @override
  State<AdminTaxRegistryPage> createState() => _AdminTaxRegistryPageState();
}

class _AdminTaxRegistryPageState extends State<AdminTaxRegistryPage> {
  late final _period = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}');
  Map<String, dynamic> _registry = {};
  String _error = '';
  bool _loading = false;
  String _status = 'PENDING';
  final Set<String> _savingProfiles = {};
  static const _statuses = {
    'PENDING': 'На проверке',
    'VERIFIED': 'Активные',
    'REJECTED': 'Отклонённые'
  };
  List<Map> get _visibleRows => _rows
      .where((row) => (row['profile'] as Map?)?['status'] == _status)
      .toList();
  String _errorMessage(Object error) {
    if (error is DioException && error.response?.data is Map) {
      final message = (error.response!.data as Map)['message'];
      if (message is List) return message.join('\n');
      if (message is String) return message;
    }
    return 'Не удалось сохранить. Проверьте соединение и попробуйте ещё раз.';
  }

  List<Map> get _rows =>
      ((_registry['rows'] as List?) ?? []).whereType<Map>().toList();
  String _money(dynamic value) =>
      (double.tryParse('$value') ?? 0).toStringAsFixed(2);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _period.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await AdminApiClient.instance.get('/admin/tax/registry',
          query: {'period': _period.text.trim(), 'kind': widget.kind});
      if (mounted) {
        setState(() {
          _registry = Map<String, dynamic>.from(response.data);
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось загрузить реестр: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _form(String title, Map<String, String> fields,
      Future<void> Function(Map<String, String>) submit,
      {Widget? extra}) async {
    final controllers = fields
        .map((key, value) => MapEntry(key, TextEditingController(text: value)));
    var saving = false;
    var error = '';
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text(title),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (extra != null) extra,
                        for (final entry in controllers.entries)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                  controller: entry.value,
                                  decoration:
                                      InputDecoration(labelText: entry.key))),
                        if (error.isNotEmpty)
                          Text(error,
                              style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.error)),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: const Text('Отмена')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                update(() => saving = true);
                                try {
                                  await submit(controllers.map((key, value) =>
                                      MapEntry(key, value.text.trim())));
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  await _load();
                                } catch (e) {
                                  if (ctx.mounted) {
                                    update(() {
                                      saving = false;
                                      error = _errorMessage(e);
                                    });
                                  }
                                }
                              },
                        child: Text(saving ? 'Сохраняем…' : 'Сохранить'))
                  ],
                )));
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _verify(Map row, bool approve) async {
    final id = '${row['ownerKey']}';
    if (_savingProfiles.contains(id)) return;
    setState(() => _savingProfiles.add(id));
    try {
      await AdminApiClient.instance
          .post('/admin/tax/profiles/$id/verify', data: {
        'status': approve ? 'VERIFIED' : 'REJECTED',
        'quickApproval': true,
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(approve ? 'Профиль подтверждён' : 'Профиль отклонён')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _savingProfiles.remove(id));
    }
  }

  Future<void> _basis(Map row) => _form('Внешний доход за месяц', {
        'Сумма внешнего дохода, тг': '0',
        'Документ подтверждения': ''
      }, (values) async {
        await AdminApiClient.instance
            .post('/admin/tax/profiles/${row['ownerKey']}/basis', data: {
          'period': _period.text.trim(),
          'externalGross': double.tryParse(
              values['Сумма внешнего дохода, тг']!.replaceAll(',', '.')),
          'reference': values['Документ подтверждения']
        });
      },
          extra: const Text(
              'Укажите также подтверждение нулевого внешнего дохода. После начала учёта месяца база не перезаписывается.'));
  Future<void> _release(Map row) async {
    try {
      final response = await AdminApiClient.instance
          .post('/admin/tax/profiles/${row['ownerKey']}/release');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Учтено: ${response.data['released']}, ожидают проверки: ${response.data['remaining']}')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Ошибка учёта: $e');
      }
    }
  }

  Future<void> _collect(Map row) async {
    try {
      final response = await AdminApiClient.instance
          .post('/admin/tax/profiles/${row['ownerKey']}/collect-debt');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Удержано: ${response.data['collected']} тг')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось удержать долг: $e');
      }
    }
  }

  Future<void> _payment(Map row) =>
      _form('Зафиксировать фактическое перечисление', {
        'Компонент: OPV, OPVR, SO или OSMS': 'OPV',
        'Сумма, тг': '',
        'Дата YYYY-MM-DD': DateTime.now().toIso8601String().substring(0, 10),
        'Уникальный номер платёжного документа': '',
        'Пояснение': '',
      }, (values) async {
        await AdminApiClient.instance.post('/admin/tax/remittances', data: {
          'period': _period.text.trim(),
          'ownerKey': row['ownerKey'],
          'component':
              values['Компонент: OPV, OPVR, SO или OSMS']!.toUpperCase(),
          'amount': double.tryParse(values['Сумма, тг']!.replaceAll(',', '.')),
          'paidAt': values['Дата YYYY-MM-DD'],
          'reference': values['Уникальный номер платёжного документа'],
          'note': values['Пояснение']
        });
      },
          extra: const Text(
              'Это запись подтверждённого банковского платежа. Кнопка не отправляет деньги и не сдаёт отчёт в КГД.'));
  Future<void> _settings() async {
    try {
      final response = await AdminApiClient.instance.get('/admin/tax/settings');
      final data = response.data as Map;
      if (!mounted) {
        return;
      }
      await _form('Настройки учёта Казахстана', {
        'Включить учёт (true / false)': '${data['enabled']}',
        'Документ готовности оператора': '${data['operatorReference'] ?? ''}',
        'Договор рефералов и квалификация деятельности':
            '${data['referralContractReference'] ?? ''}',
        'Минимум вывода рефералов, тг': '${data['minPayout']}',
        'Год': '${data['year']}',
        'МРП': '${data['mrp'] ?? ''}',
        'МЗП': '${data['mzp'] ?? ''}',
        'Официальный источник годовых параметров': '${data['reference'] ?? ''}',
      }, (values) async {
        if (!['true', 'false']
            .contains(values['Включить учёт (true / false)'])) {
          throw Exception('Укажите true или false');
        }
        await AdminApiClient.instance.post('/admin/tax/settings', data: {
          'enabled': values['Включить учёт (true / false)'] == 'true',
          'operatorReference': values['Документ готовности оператора'],
          'referralContractReference':
              values['Договор рефералов и квалификация деятельности'],
          'minPayout': double.tryParse(values['Минимум вывода рефералов, тг']!),
          'year': values['Год'],
          'mrp': double.tryParse(values['МРП']!),
          'mzp': double.tryParse(values['МЗП']!),
          'policyReference': values['Официальный источник годовых параметров']
        });
      },
          extra: const Text(
              'Включайте после подтверждения готовности удерживать и перечислять платежи. Государственная интеграция сама от этого не подключается.'));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Ошибка настроек: $e');
      }
    }
  }

  Future<void> _identity(Map row) async {
    try {
      final response = await AdminApiClient.instance
          .get('/admin/tax/profiles/${row['ownerKey']}/identity');
      if (!mounted) {
        return;
      }
      await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Защищённые налоговые данные'),
                  content: SelectableText(
                      'ИИН: ${response.data['iin']}\nДоступ зарегистрирован в журнале администратора.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Закрыть'))
                  ]));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось открыть ИИН: $e');
      }
    }
  }

  Future<void> _export() async {
    try {
      final response = await AdminApiClient.instance.get(
          '/admin/tax/registry/csv',
          query: {'period': _period.text.trim(), 'kind': widget.kind});
      final downloaded = await exportCsv('${response.data['csv']}',
          filename: 'tax-registry-${widget.kind}-${_period.text.trim()}.csv');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Учётный CSV с ИИН ${downloaded ? 'скачан' : 'скопирован'}. Доступ записан в журнал. Это не сдача отчёта в КГД.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Не удалось выгрузить реестр: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final self = widget.kind == 'SELF_EMPLOYED';
    double total(String field) => _rows.fold(
        0, (sum, row) => sum + (double.tryParse('${row[field]}') ?? 0));
    return AdminShell(
        title: self ? 'Самозанятые · Казахстан' : 'ИП · Казахстан',
        subtitle:
            'Месячный учёт доходов и социальных платежей. Перечисления подтверждаются вручную.',
        child: ListView(children: [
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 180,
                    child: TextField(
                        controller: _period,
                        decoration:
                            const InputDecoration(labelText: 'Месяц YYYY-MM'),
                        onSubmitted: (_) => _load())),
                FilledButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Обновить')),
                OutlinedButton.icon(
                    onPressed: _export,
                    icon: const Icon(Icons.copy),
                    label: const Text('Учётный CSV')),
                OutlinedButton.icon(
                    onPressed: _settings,
                    icon: const Icon(Icons.tune),
                    label: const Text('Настройки и порог вывода')),
              ]),
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(_error,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final item in [
              (self ? 'Обязательство' : 'Доход', self ? 'liability' : 'gross'),
              ('Удержано', 'withheld'),
              ('Перечислено', 'paid'),
              ('К перечислению', 'payable')
            ])
              SizedBox(
                  width: 220,
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$1),
                                const SizedBox(height: 8),
                                Text('${total(item.$2).toStringAsFixed(2)} тг',
                                    style:
                                        Theme.of(context).textTheme.titleLarge)
                              ])))),
          ]),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final entry in _statuses.entries)
              ChoiceChip(
                label: Text(
                    '${entry.value} (${_rows.where((row) => (row['profile'] as Map?)?['status'] == entry.key).length})'),
                selected: _status == entry.key,
                onSelected: (_) => setState(() => _status = entry.key),
              ),
          ]),
          const SizedBox(height: 12),
          if (_visibleRows.isEmpty && !_loading)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('В этой вкладке пока нет профилей')),
          Card(
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                      columnSpacing: 16,
                      horizontalMargin: 16,
                      dataTextStyle: Theme.of(context).textTheme.bodySmall,
                      headingTextStyle: Theme.of(context).textTheme.labelMedium,
                      columns: [
                        for (final label in [
                          'Пользователь / статус',
                          'Поездки',
                          'Доход, тг',
                          if (self) 'ОПВ / ОПВР / СО / ОСМС',
                          'Удержано, тг',
                          'Долг, тг',
                          'Перечислено, тг',
                          'Проверка',
                          'Действия'
                        ])
                          DataColumn(label: Text(label)),
                      ],
                      rows: _visibleRows.map((row) {
                        final profile = row['profile'] as Map?;
                        final user = profile?['user'] as Map?;
                        return DataRow(cells: [
                          DataCell(Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${user?['name'] ?? 'Удалённый аккаунт'}'),
                                Text(
                                    '${user?['phone'] ?? ''} · ${_statuses[profile?['status']] ?? 'Не указан'}',
                                    style: const TextStyle(fontSize: 11))
                              ])),
                          DataCell(Text('${row['trips']}')),
                          DataCell(Text(_money(row['gross']))),
                          if (self)
                            DataCell(Text(['opv', 'opvr', 'so', 'osms']
                                .map((key) => _money(row[key]))
                                .join(' / '))),
                          DataCell(Text(_money(row['withheld']))),
                          DataCell(Text(_money(row['debt']))),
                          DataCell(Text(_money(row['paid']))),
                          DataCell(Text('${row['reviewCount'] ?? 0}')),
                          DataCell(
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            if (profile?['status'] != 'VERIFIED')
                              FilledButton(
                                  onPressed: _savingProfiles
                                          .contains('${row['ownerKey']}')
                                      ? null
                                      : () => _verify(row, true),
                                  child: const Text('Подтвердить')),
                            if (profile?['status'] != 'REJECTED')
                              TextButton(
                                  onPressed: _savingProfiles
                                          .contains('${row['ownerKey']}')
                                      ? null
                                      : () => _verify(row, false),
                                  child: const Text('Отклонить')),
                            PopupMenuButton<String>(
                                tooltip: 'Действия',
                                onSelected: (value) {
                                  switch (value) {
                                    case 'identity':
                                      _identity(row);
                                    case 'approve':
                                      _verify(row, true);
                                    case 'reject':
                                      _verify(row, false);
                                    case 'basis':
                                      _basis(row);
                                    case 'collect':
                                      _collect(row);
                                    case 'release':
                                      _release(row);
                                    case 'payment':
                                      _payment(row);
                                  }
                                },
                                itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'identity',
                                          child: Text(
                                              'Проверить ИИН (доступ с аудитом)')),
                                      if (profile != null)
                                        const PopupMenuItem(
                                            value: 'approve',
                                            child: Text('Подтвердить статус')),
                                      if (profile != null)
                                        const PopupMenuItem(
                                            value: 'reject',
                                            child: Text('Отклонить статус')),
                                      const PopupMenuItem(
                                          value: 'basis',
                                          child: Text(
                                              'Подтвердить внешний доход')),
                                      const PopupMenuItem(
                                          value: 'collect',
                                          child: Text(
                                              'Удержать долг из собственных денег')),
                                      const PopupMenuItem(
                                          value: 'release',
                                          child: Text(
                                              'Учесть ожидающие начисления')),
                                      if (self)
                                        const PopupMenuItem(
                                            value: 'payment',
                                            child: Text(
                                                'Зафиксировать перечисление')),
                                    ]),
                          ])),
                        ]);
                      }).toList()))),
          if (_rows.isEmpty && !_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'В этом месяце записей нет. Новые подтверждённые профили появятся здесь.')),
          const SizedBox(height: 16),
          const Text(
              'Стандартные ставки самозанятого: по 1% ОПВ, ОПВР, СО и ОСМС. Льготы, месячные пределы и внешние доходы учитываются отдельно. Для ИП эти удержания не применяются.'),
          if (((_registry['entries'] as List?) ?? [])
              .any((e) => e['status'] == 'REVIEW')) ...[
            const SizedBox(height: 20),
            Text('Начисления на проверке',
                style: Theme.of(context).textTheme.titleLarge),
            ...((_registry['entries'] as List?) ?? [])
                .where((e) => e['status'] == 'REVIEW')
                .take(100)
                .map((entry) => Card(
                    child: ListTile(
                        title: Text(
                            '${entry['sourceKind']} · ${_money(entry['gross'])} ${entry['currency']}'),
                        subtitle: Text(
                            '${entry['reviewReason']} · ${entry['sourceId']}')))),
          ],
        ]));
  }
}
