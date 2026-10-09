import 'dart:async';
import 'package:flutter/widgets.dart';

/// Closes a displayed offer when its deadline passes or it leaves the feed.
class DriverOfferExpiryWatcher extends StatefulWidget {
  const DriverOfferExpiryWatcher(
      {super.key,
      required this.secondsLeft,
      required this.onTick,
      required this.onExpired,
      required this.child});
  final int Function() secondsLeft;
  final ValueChanged<int> onTick;
  final VoidCallback onExpired;
  final Widget child;
  @override
  State<DriverOfferExpiryWatcher> createState() =>
      _DriverOfferExpiryWatcherState();
}

class _DriverOfferExpiryWatcherState extends State<DriverOfferExpiryWatcher> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final seconds = widget.secondsLeft();
      if (seconds <= 0) {
        _timer?.cancel();
        widget.onExpired();
      } else {
        widget.onTick(seconds);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
