import 'package:flutter/material.dart';

/// Search a previously loaded database catalog without building every option.
class DatabaseCityField extends StatelessWidget {
  const DatabaseCityField(
      {super.key,
      required this.cities,
      required this.decoration,
      required this.onChanged,
      this.value,
      this.allowAutomatic = false});
  final List<Map<String, dynamic>> cities;
  final InputDecoration decoration;
  final String? value;
  final bool allowAutomatic;
  final ValueChanged<String?> onChanged;
  static String _normal(String text) => text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  @override
  Widget build(BuildContext context) {
    final selected = cities.where((city) => city['id'] == value).firstOrNull;
    return InkWell(
      onTap: () async {
        var query = '';
        final picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => StatefulBuilder(builder: (context, update) {
                  final matches = cities
                      .where((city) => [
                            city['name'],
                            city['region'],
                            ...(city['aliases'] as List? ?? [])
                          ].any((name) =>
                              _normal((name ?? '').toString()).contains(query)))
                      .toList();
                  return SafeArea(
                      child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * .75,
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                TextField(
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Название города или посёлка',
                                        prefixIcon: Icon(Icons.search)),
                                    onChanged: (text) =>
                                        update(() => query = _normal(text))),
                                if (allowAutomatic)
                                  ListTile(
                                      title: const Text(
                                          'Определять автоматически'),
                                      onTap: () => Navigator.pop(
                                          context, '__automatic__')),
                                Expanded(
                                    child: ListView.builder(
                                        itemCount: matches.length,
                                        itemBuilder: (context, index) {
                                          final city = matches[index];
                                          final country =
                                              city['countryCode'] == 'RU'
                                                  ? 'Россия'
                                                  : 'Казахстан';
                                          return ListTile(
                                              title: Text((city['name'] ?? '')
                                                  .toString()),
                                              subtitle: Text(
                                                  '${city['region'] ?? '${city['lat']}, ${city['lng']}'}, $country'),
                                              trailing: city['id'] == value
                                                  ? const Icon(Icons.check)
                                                  : null,
                                              onTap: () => Navigator.pop(
                                                  context,
                                                  city['id'].toString()));
                                        })),
                              ]))));
                }));
        if (!context.mounted || picked == null) return;
        onChanged(picked == '__automatic__' ? null : picked);
      },
      child: InputDecorator(
          decoration: decoration,
          child: Row(children: [
            Expanded(
                child: Text(
                    selected?['name']?.toString() ??
                        (allowAutomatic
                            ? 'Определять автоматически'
                            : 'Выберите город'),
                    overflow: TextOverflow.ellipsis)),
            const Icon(Icons.search),
          ])),
    );
  }
}
