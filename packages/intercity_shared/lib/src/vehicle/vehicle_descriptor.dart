class VehicleDescriptor {
  const VehicleDescriptor({
    required this.make,
    required this.model,
    required this.color,
  });

  final String make;
  final String model;
  final String color;

  static const List<String> _knownMultiWordMakes = <String>[
    'Alfa Romeo',
    'Aston Martin',
    'DS Automobiles',
    'Great Wall',
    'Land Rover',
    'Range Rover',
    'Rolls Royce',
  ];

  String get displayValue {
    final base = [
      make.trim(),
      model.trim(),
    ].where((value) => value.isNotEmpty).join(' ');
    if (color.trim().isEmpty) return base;
    return '$base • ${color.trim()}';
  }

  Map<String, String> toMap() => <String, String>{
    'make': make,
    'model': model,
    'color': color,
  };

  static VehicleDescriptor parse(String raw, {Iterable<String>? knownMakes}) {
    final parts = raw.split('•');
    final base = parts.first.trim();
    final color = parts.length > 1 ? parts.sublist(1).join('•').trim() : '';
    if (base.isEmpty) {
      return VehicleDescriptor(make: '', model: '', color: color);
    }

    final candidateMakes =
        <String>{
            ..._knownMultiWordMakes,
            ...?knownMakes,
          }.where((make) => make.trim().isNotEmpty).toList()
          ..sort((left, right) => right.length.compareTo(left.length));

    final lowerBase = base.toLowerCase();
    for (final candidate in candidateMakes) {
      final normalized = candidate.trim();
      final lowerCandidate = normalized.toLowerCase();
      if (lowerBase == lowerCandidate) {
        return VehicleDescriptor(make: normalized, model: '', color: color);
      }
      if (lowerBase.startsWith('$lowerCandidate ')) {
        return VehicleDescriptor(
          make: normalized,
          model: base.substring(normalized.length).trim(),
          color: color,
        );
      }
    }

    final words = base
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length == 1) {
      return VehicleDescriptor(make: words.first, model: '', color: color);
    }

    return VehicleDescriptor(
      make: words.first,
      model: words.sublist(1).join(' '),
      color: color,
    );
  }
}
