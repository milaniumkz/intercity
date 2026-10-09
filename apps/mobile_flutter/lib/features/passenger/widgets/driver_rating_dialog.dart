import 'package:flutter/material.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/ic_premium.dart';

Future<bool> showDriverRatingDialog({
  required BuildContext context,
  required Future<void> Function(int rating) onSubmit,
  Future<void> Function(int rating, String reason)? onSubmitWithReason,
  String? driverName,
  bool allowSkip = false,
  bool barrierDismissible = false,
}) async {
  final submitted = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _DriverRatingDialog(
      driverName: driverName,
      allowSkip: allowSkip,
      onSubmit: onSubmit,
      onSubmitWithReason: onSubmitWithReason,
    ),
  );
  return submitted == true;
}

class _DriverRatingDialog extends StatefulWidget {
  const _DriverRatingDialog({
    required this.onSubmit,
    this.onSubmitWithReason,
    this.driverName,
    this.allowSkip = false,
  });

  final Future<void> Function(int rating) onSubmit;
  final Future<void> Function(int rating, String reason)? onSubmitWithReason;
  final String? driverName;
  final bool allowSkip;

  @override
  State<_DriverRatingDialog> createState() => _DriverRatingDialogState();
}

class _DriverRatingDialogState extends State<_DriverRatingDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int _selectedRating = 5;
  bool _submitting = false;
  String _errorText = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driverName = widget.driverName?.trim();
    final visibleName =
        driverName != null && driverName.isNotEmpty ? driverName : 'Водитель';

    return PopScope(
      canPop: widget.allowSkip && !_submitting,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(
              maxWidth: 430,
              maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1B0D33), Color(0xFF0B0817)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.secondaryColor,
                            AppTheme.primaryColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppTheme.primaryColor.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Поездка завершена',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            visibleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$_selectedRating.0',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 42,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _ratingLabel(_selectedRating),
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Оцените поездку, чтобы мы показывали вам лучших водителей.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final star = index + 1;
                        final selected = star <= _selectedRating;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: InkWell(
                            onTap: _submitting
                                ? null
                                : () => setState(() {
                                      _selectedRating = star;
                                      _errorText = '';
                                    }),
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.amberAccent.withValues(alpha: 0.16)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? Colors.amberAccent
                                      : theme.colorScheme.outline
                                          .withValues(alpha: 0.18),
                                ),
                              ),
                              child: Icon(
                                selected
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: Colors.amberAccent,
                                size: 30,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_selectedRating <= 2) ...[
                      const SizedBox(height: 12),
                      TextField(
                          controller: _reason,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                              labelText: 'Что произошло?',
                              hintText:
                                  'Опишите действия водителя и обстоятельства поездки')),
                      const Text(
                          'Оценка поступит на разбор. До решения администратора рейтинг водителя не изменится.',
                          style: TextStyle(fontSize: 12)),
                    ],
                    if (_errorText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (widget.allowSkip) ...[
                          Expanded(
                            child: ICPremiumTextButton(
                              label: 'Позже',
                              icon: Icons.schedule_rounded,
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ICGradientButton(
                            label: 'Отправить',
                            loading: _submitting,
                            icon: Icons.check_rounded,
                            onPressed: _submitting ? null : _submit,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          )),
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Очень плохо';
      case 2:
        return 'Плохо';
      case 3:
        return 'Нормально';
      case 4:
        return 'Хорошо';
      default:
        return 'Отличная поездка';
    }
  }

  Future<void> _submit() async {
    if (_selectedRating <= 2 && _reason.text.trim().length < 10) {
      setState(
          () => _errorText = 'Опишите случившееся — не менее 10 символов.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = '';
    });
    try {
      if (widget.onSubmitWithReason != null) {
        await widget.onSubmitWithReason!(_selectedRating, _reason.text.trim());
      } else {
        await widget.onSubmit(_selectedRating);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString().replaceFirst('Exception: ', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
