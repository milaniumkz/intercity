import 'dart:async';
import 'package:flutter/material.dart';

class DriverAutoActionButton extends StatefulWidget {
  const DriverAutoActionButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.eligible = false,
      this.busy = false,
      this.seconds = 15,
      this.clock});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool eligible, busy;
  final int seconds;
  final DateTime Function()? clock;
  @override
  State<DriverAutoActionButton> createState() => _DriverAutoActionButtonState();
}

class _DriverAutoActionButtonState extends State<DriverAutoActionButton> {
  Timer? _timer;
  DateTime? _deadline;
  int _left = 0;
  bool _fired = false;
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DriverAutoActionButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (!widget.eligible || widget.busy || widget.onPressed == null || _fired) {
      _timer?.cancel();
      _timer = null;
      _deadline = null;
      _left = 0;
      return;
    }
    if (_timer != null) return;
    _left = widget.seconds;
    _deadline = (widget.clock?.call() ?? DateTime.now())
        .add(Duration(seconds: widget.seconds));
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final left = (_deadline!
                  .difference((widget.clock?.call() ?? DateTime.now()))
                  .inMilliseconds /
              1000)
          .ceil()
          .clamp(0, widget.seconds);
      if (left != _left) setState(() => _left = left);
      if (left == 0) {
        _timer?.cancel();
        _timer = null;
        _fired = true;
        widget.onPressed?.call();
      }
    });
  }

  void _press() {
    _fired = true;
    _timer?.cancel();
    _timer = null;
    setState(() => _left = 0);
    widget.onPressed?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FilledButton(
        key: const ValueKey('driver-primary-ride-action'),
        style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56), padding: EdgeInsets.zero),
        onPressed: widget.busy || widget.onPressed == null ? null : _press,
        child: SizedBox(
            height: 56,
            child: Stack(alignment: Alignment.center, children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (widget.busy)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(widget.icon),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(
                        '${widget.label}${_left > 0 ? ' · $_left с' : ''}',
                        maxLines: 2,
                        textAlign: TextAlign.center)),
              ]),
              if (_left > 0)
                Positioned(
                    left: 12,
                    right: 12,
                    bottom: 4,
                    child: LinearProgressIndicator(
                        value: _left / widget.seconds,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                        borderRadius: BorderRadius.circular(3))),
            ])),
      );
}
