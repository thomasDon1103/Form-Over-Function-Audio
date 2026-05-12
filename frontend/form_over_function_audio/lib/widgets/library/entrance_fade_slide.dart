import 'package:flutter/material.dart';

class EntranceFadeSlide extends StatelessWidget {
  const EntranceFadeSlide({
    super.key,
    required this.child,
    required this.interval,
    this.startOffset = 6,
  });

  final Widget child;
  final Curve interval;
  final double startOffset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 760),
      curve: Curves.linear,
      builder: (context, value, child) {
        final curved = interval.transform(value);
        return Opacity(
          opacity: curved,
          child: Transform.translate(
            offset: Offset(0, (1 - curved) * startOffset),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
