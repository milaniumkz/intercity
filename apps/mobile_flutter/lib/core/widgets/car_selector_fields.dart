import 'package:flutter/material.dart';

import '../services/vehicle_catalog_service.dart';
import '../theme/theme_controller.dart';

class CarSelectionValue {
  const CarSelectionValue({
    required this.make,
    required this.model,
    required this.color,
  });

  final String make;
  final String model;
  final String color;

  String get displayValue => VehicleCatalogService.composeCarModelWithColor(
        make: make,
        model: model,
        color: color,
      );
}

class CarSelectorFields extends StatefulWidget {
  const CarSelectorFields({
    super.key,
    required this.onChanged,
    this.initialComposedValue,
    this.requiredFields = false,
  });

  final ValueChanged<CarSelectionValue> onChanged;
  final String? initialComposedValue;
  final bool requiredFields;

  @override
  State<CarSelectorFields> createState() => _CarSelectorFieldsState();
}

class _CarSelectorFieldsState extends State<CarSelectorFields> {
  List<Map<String, dynamic>> _makes = const [];
  List<String> _models = const [];
  bool _loadingMakes = false;
  bool _loadingModels = false;
  String? _selectedMake;
  String? _selectedModel;
  String? _selectedColor;

  @override
  void initState() {
    super.initState();
    final parsed = VehicleCatalogService.parseComposedCarModel(
      widget.initialComposedValue ?? '',
    );
    _selectedMake = parsed.make.isEmpty ? null : parsed.make;
    _selectedModel = parsed.model.isEmpty ? null : parsed.model;
    _selectedColor = parsed.color.isEmpty ? null : parsed.color;
    _loadMakes();
  }

  Future<void> _loadMakes() async {
    setState(() => _loadingMakes = true);
    try {
      final makes = await VehicleCatalogService.instance.getMakes();
      if (!mounted) return;
      final knownMakes = makes
          .map((entry) => (entry['name'] ?? '').toString())
          .where((name) => name.isNotEmpty);
      final parsed = VehicleCatalogService.parseComposedCarModel(
        widget.initialComposedValue ?? '',
        knownMakes: knownMakes,
      );
      setState(() {
        _makes = makes;
        if (parsed.make.isNotEmpty) {
          _selectedMake = parsed.make;
        }
        if (parsed.model.isNotEmpty) {
          _selectedModel = parsed.model;
        }
        if (parsed.color.isNotEmpty) {
          _selectedColor = parsed.color;
        }
      });
      if (_selectedMake != null && _selectedMake!.isNotEmpty) {
        await _loadModelsForMake(_selectedMake!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _makes = const []);
    } finally {
      if (mounted) setState(() => _loadingMakes = false);
    }
  }

  Future<void> _loadModelsForMake(String make) async {
    setState(() => _loadingModels = true);
    try {
      final models =
          await VehicleCatalogService.instance.getModelsForMake(make);
      if (!mounted) return;
      setState(() {
        _models = models;
        if (_selectedModel != null && !_models.contains(_selectedModel)) {
          _selectedModel = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _models = const [];
        _selectedModel = null;
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
    _emit();
  }

  void _emit() {
    widget.onChanged(
      CarSelectionValue(
        make: _selectedMake ?? '',
        model: _selectedModel ?? '',
        color: _selectedColor ?? '',
      ),
    );
  }

  Future<String?> _pickFromSheet({
    required String title,
    required List<String> options,
    String? selected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.directions_car_filled_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final value = options[index];
                    final isSelected = value == selected;
                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(context, value),
                        child: Ink(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [
                                      AppTheme.secondaryColor,
                                      AppTheme.primaryColor,
                                    ],
                                  )
                                : null,
                            color: isSelected
                                ? null
                                : theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: isDark ? 0.22 : 0.55),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : AppTheme.primaryColor
                                      .withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _premiumPickerField({
    required String label,
    required IconData icon,
    required String? value,
    required String placeholder,
    required VoidCallback? onTap,
    String? errorText,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasValue = (value ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF8F6FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (errorText == null
                          ? AppTheme.primaryColor
                          : theme.colorScheme.error)
                      .withValues(alpha: errorText == null ? 0.14 : 0.70),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasValue ? value! : placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasValue
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight:
                                hasValue ? FontWeight.w900 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    color: onTap == null
                        ? theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.45)
                        : AppTheme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _premiumPickerFormField({
    required String label,
    required IconData icon,
    required String? value,
    required String placeholder,
    required List<String> options,
    required Future<void> Function(String value) onPicked,
    required String? Function(String? value)? validator,
    bool enabled = true,
  }) {
    return FormField<String>(
      key: ValueKey('$label:$value:${options.length}:$enabled'),
      initialValue: value,
      autovalidateMode: AutovalidateMode.disabled,
      validator: validator,
      builder: (field) => _premiumPickerField(
        label: label,
        icon: icon,
        value: field.value,
        placeholder: placeholder,
        errorText: field.errorText,
        onTap: enabled
            ? () async {
                final picked = await _pickFromSheet(
                  title: label,
                  options: options,
                  selected: field.value,
                );
                if (picked == null) return;
                field.didChange(picked);
                await onPicked(picked);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final makeNames = _makes
        .map((e) => (e['name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final hasSelection = [
      _selectedMake,
      _selectedModel,
      _selectedColor,
    ].any((value) => (value ?? '').isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSelection) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    Icons.directions_car_filled_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Выбранный автомобиль',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          _selectedMake,
                          _selectedModel,
                          _selectedColor,
                        ]
                            .where((value) => (value ?? '').isNotEmpty)
                            .join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _premiumPickerFormField(
          label: _loadingMakes ? 'Марка (загрузка...)' : 'Марка авто',
          icon: Icons.directions_car_outlined,
          value: makeNames.contains(_selectedMake) ? _selectedMake : null,
          placeholder: 'Выберите марку',
          options: makeNames,
          enabled: !_loadingMakes,
          validator: widget.requiredFields
              ? (v) => (v == null || v.isEmpty) ? 'Выберите марку' : null
              : null,
          onPicked: (value) async {
            setState(() {
              _selectedMake = value;
              _selectedModel = null;
              _models = const [];
            });
            _emit();
            if (value.isNotEmpty) {
              await _loadModelsForMake(value);
            }
          },
        ),
        const SizedBox(height: 12),
        _premiumPickerFormField(
          label: _loadingModels ? 'Модель (загрузка...)' : 'Модель авто',
          icon: Icons.directions_car_filled_outlined,
          value: _models.contains(_selectedModel) ? _selectedModel : null,
          placeholder: (_selectedMake == null || _selectedMake!.isEmpty)
              ? 'Сначала выберите марку'
              : 'Выберите модель',
          options: _models,
          enabled: _selectedMake != null &&
              _selectedMake!.isNotEmpty &&
              !_loadingModels,
          validator: widget.requiredFields
              ? (v) => (v == null || v.isEmpty) ? 'Выберите модель' : null
              : null,
          onPicked: (value) async {
            setState(() => _selectedModel = value);
            _emit();
          },
        ),
        const SizedBox(height: 12),
        _premiumPickerFormField(
          label: 'Цвет авто',
          icon: Icons.palette_outlined,
          value: VehicleCatalogService.colorsRu.contains(_selectedColor)
              ? _selectedColor
              : null,
          placeholder: 'Выберите цвет',
          options: VehicleCatalogService.colorsRu,
          validator: widget.requiredFields
              ? (v) => (v == null || v.isEmpty) ? 'Выберите цвет' : null
              : null,
          onPicked: (value) async {
            setState(() => _selectedColor = value);
            _emit();
          },
        ),
      ],
    );
  }
}
