import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';

class PassengerOffersPanel extends StatelessWidget {
  const PassengerOffersPanel(
      {super.key,
      required this.offerCount,
      required this.itemBuilder,
      this.panelKey});
  final int offerCount;
  final IndexedWidgetBuilder itemBuilder;
  final Key? panelKey;
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final visibleHeight = (offerCount.clamp(1, 6) * 200.0) + 66;
    final maxHeight = math.min(screenHeight * 0.45, visibleHeight);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(190, 690)),
      child: Container(
        key: panelKey,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF261044), Color(0xFF100B1F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.42),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xAA000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.secondaryColor, AppTheme.primaryColor],
                    ),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Предложения водителей',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        offerCount == 1
                            ? 'Выберите водителя для поездки'
                            : '$offerCount предложений · прокрутите для выбора',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: offerCount,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: itemBuilder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
