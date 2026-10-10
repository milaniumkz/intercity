import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/request_flow_utils.dart';

/// One booking surface: the map stays visible and the submit button stays pinned.
class CityOrderComposer extends StatelessWidget {
  const CityOrderComposer(
      {super.key,
      required this.map,
      required this.fromController,
      required this.toController,
      required this.commentController,
      required this.isFrom,
      required this.onFieldSelected,
      required this.onAddressChanged,
      required this.onAddressSubmitted,
      required this.suggestions,
      required this.onSuggestionSelected,
      required this.searching,
      required this.vehicleClass,
      required this.onClassSelected,
      required this.paymentMethod,
      required this.onPaymentSelected,
      required this.cardAvailable,
      required this.currency,
      required this.price,
      required this.routeMeta,
      required this.busy,
      required this.calculating,
      required this.canOrder,
      required this.onOrder,
      required this.message,
      required this.onRetry,
      required this.commentExpanded,
      required this.onCommentToggle,
      this.cardPanel,
      this.onBack});
  final Widget map;
  final TextEditingController fromController, toController, commentController;
  final bool isFrom,
      searching,
      busy,
      calculating,
      canOrder,
      cardAvailable,
      commentExpanded;
  final VoidCallback onCommentToggle;
  final void Function(bool) onFieldSelected;
  final void Function(String, bool) onAddressChanged;
  final void Function(bool) onAddressSubmitted;
  final List<Map<String, dynamic>> suggestions;
  final void Function(Map<String, dynamic>) onSuggestionSelected;
  final String vehicleClass, paymentMethod, currency, routeMeta, message;
  final String? price;
  final ValueChanged<String> onClassSelected, onPaymentSelected;
  final VoidCallback onOrder, onRetry;
  final VoidCallback? onBack;
  final Widget? cardPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(builder: (context, constraints) {
      final available = math.max(0.0, constraints.maxHeight - 72);
      return Column(children: [
        Expanded(
            child: Stack(children: [
          Positioned.fill(child: map),
          Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Row(children: [
                if (onBack != null) ...[
                  _mapButton(context, Icons.arrow_back_rounded,
                      'К выбору режима', onBack!),
                  const SizedBox(width: 8),
                ],
                IgnorePointer(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.surface
                                .withValues(alpha: .95),
                            borderRadius: BorderRadius.circular(16)),
                        child: const Text('Заказ поездки',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)))),
              ])),
          Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Center(
                  child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surface.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final field in [true, false])
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: ChoiceChip(
                                  key: ValueKey(
                                      field ? 'city-map-from' : 'city-map-to'),
                                  label: Text(field ? 'Откуда' : 'Куда'),
                                  avatar: Icon(
                                      field
                                          ? Icons.trip_origin_rounded
                                          : Icons.location_on_rounded,
                                      size: 16),
                                  selected: isFrom == field,
                                  onSelected: busy
                                      ? null
                                      : (_) {
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          onFieldSelected(field);
                                        },
                                  visualDensity: VisualDensity.compact,
                                  showCheckmark: false)),
                      ])))),
        ])),
        ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight:
                    math.min(430.0, available * (keyboard ? 0.70 : 0.72))),
            child: Material(
                color: theme.colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: SingleChildScrollView(
                    key: const ValueKey('city-order-controls'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _address(context, true),
                          const SizedBox(height: 6),
                          _address(context, false),
                          if (searching)
                            const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: LinearProgressIndicator(minHeight: 2)),
                          if (suggestions.isNotEmpty)
                            ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 150),
                                child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: suggestions.length,
                                    itemBuilder: (context, index) {
                                      final item = suggestions[index];
                                      return ListTile(
                                          key: ValueKey(
                                              'city-suggestion-$index'),
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 4),
                                          leading: const Icon(
                                              Icons.location_on_outlined,
                                              size: 20,
                                              color: AppTheme.primaryColor),
                                          title: Text(
                                              '${item['displayName'] ?? ''}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis),
                                          onTap: busy
                                              ? null
                                              : () {
                                                  FocusManager
                                                      .instance.primaryFocus
                                                      ?.unfocus();
                                                  onSuggestionSelected(item);
                                                });
                                    })),
                          const SizedBox(height: 10),
                          const Text('Тариф',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Row(children: [
                            for (final value in const [
                              vehicleClassEconomy,
                              vehicleClassOptimal,
                              vehicleClassComfort,
                              vehicleClassBusiness
                            ])
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: _option(context,
                                          key: ValueKey('city-class-$value'),
                                          label: vehicleClassLabel(value),
                                          icon: value == vehicleClassBusiness
                                              ? Icons.workspace_premium_rounded
                                              : Icons.directions_car_rounded,
                                          selected: vehicleClass == value,
                                          onTap: busy
                                              ? null
                                              : () => onClassSelected(value))))
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Expanded(
                                child: Text('Оплата',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700))),
                            TextButton.icon(
                                onPressed: busy ? null : onCommentToggle,
                                style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    minimumSize: const Size(0, 28)),
                                icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 14),
                                label: const Text('Комментарий',
                                    style: TextStyle(fontSize: 11)))
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            for (final value in [
                              paymentMethodCash,
                              if (currency == 'KZT') paymentMethodCard,
                              paymentMethodBonus
                            ])
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      child: _option(context,
                                          key: ValueKey('city-payment-$value'),
                                          label: switch (value) {
                                            paymentMethodCash => 'Наличные',
                                            paymentMethodCard => 'Карта',
                                            paymentMethodCardTransfer =>
                                              'Перевод',
                                            _ => 'Бонусы'
                                          },
                                          icon: switch (value) {
                                            paymentMethodCash =>
                                              Icons.payments_outlined,
                                            paymentMethodCard => cardAvailable
                                                ? Icons.credit_card
                                                : Icons.lock_outline,
                                            paymentMethodCardTransfer =>
                                              Icons.swap_horiz_rounded,
                                            _ => Icons.stars_outlined
                                          },
                                          selected: paymentMethod == value,
                                          onTap: busy
                                              ? null
                                              : () =>
                                                  onPaymentSelected(value))))
                          ]),
                          if (commentExpanded)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextField(
                                    key: const ValueKey('city-comment'),
                                    controller: commentController,
                                    maxLines: 2,
                                    maxLength: 500,
                                    decoration: const InputDecoration(
                                        hintText: 'Пожелания водителю',
                                        isDense: true))),
                          if (cardPanel != null) cardPanel!,
                          if (message.isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(message,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: theme.colorScheme.error),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis)),
                                  if (!busy && price == null)
                                    IconButton(
                                        onPressed: onRetry,
                                        tooltip: 'Повторить расчёт',
                                        icon:
                                            const Icon(Icons.refresh_rounded)),
                                ])),
                        ])))),
        Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            color: theme.colorScheme.surface,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (price != null && routeMeta.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(routeMeta,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant))),
              SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                      key: const ValueKey('city-order-submit'),
                      onPressed: canOrder && !busy ? onOrder : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                        busy
                                            ? 'Отправляем…'
                                            : calculating
                                                ? 'Рассчитываем…'
                                                : 'Заказать',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800)))),
                            const SizedBox(width: 10),
                            if (busy || calculating)
                              const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                            else
                              Flexible(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(price ?? 'Выберите адреса',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800)))),
                          ]))),
            ])),
      ]);
    });
  }

  Widget _address(BuildContext context, bool from) {
    final active = isFrom == from;
    return TextField(
        key: ValueKey(from ? 'city-address-from' : 'city-address-to'),
        controller: from ? fromController : toController,
        enabled: !busy,
        onTap: () => onFieldSelected(from),
        onChanged: (v) => onAddressChanged(v, from),
        onSubmitted: (_) => onAddressSubmitted(from),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
            labelText: from ? 'Откуда' : 'Куда',
            hintText: from ? 'Адрес подачи' : 'Адрес назначения',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            prefixIcon: IconButton(
                tooltip: from
                    ? 'Выбрать подачу на карте'
                    : 'Выбрать назначение на карте',
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onFieldSelected(from);
                },
                icon: Icon(
                    from
                        ? Icons.trip_origin_rounded
                        : Icons.location_on_rounded,
                    color: active
                        ? AppTheme.primaryColor
                        : Theme.of(context).colorScheme.onSurfaceVariant)),
            filled: true,
            fillColor: active
                ? AppTheme.primaryColor.withValues(alpha: .06)
                : Theme.of(context).colorScheme.surfaceContainerLow,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                    color: active
                        ? AppTheme.primaryColor
                        : Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: .16))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                    color: AppTheme.primaryColor, width: 1.5))));
  }

  Widget _option(BuildContext context,
          {required Key key,
          required String label,
          required IconData icon,
          required bool selected,
          VoidCallback? onTap}) =>
      Material(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: .13)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected
                              ? AppTheme.primaryColor
                              : Colors.transparent)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            size: 17,
                            color: selected
                                ? AppTheme.primaryColor
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                        const SizedBox(height: 2),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500))
                      ]))));
  Widget _mapButton(BuildContext context, IconData icon, String label,
          VoidCallback callback) =>
      Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(14),
          child: IconButton(
              tooltip: label, onPressed: callback, icon: Icon(icon, size: 20)));
}
