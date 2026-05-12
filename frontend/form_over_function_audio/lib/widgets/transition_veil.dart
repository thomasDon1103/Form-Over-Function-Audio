import 'package:flutter/material.dart';

import '../app_theme.dart';

class TransitionVeil extends StatelessWidget {
  const TransitionVeil({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: visible
            ? const Duration(milliseconds: 560)
            : const Duration(milliseconds: 820),
        curve: visible ? Curves.easeInOutCubic : Curves.easeOutQuart,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.25,
              colors: [
                collection.backgroundMiddle.withValues(alpha: 0.96),
                collection.backgroundBottom.withValues(alpha: 0.98),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
