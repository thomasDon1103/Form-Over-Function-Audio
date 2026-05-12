import 'package:flutter/material.dart';

class AnimatedPlayerText extends StatelessWidget {
  const AnimatedPlayerText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 430),
            reverseDuration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.36),
                end: Offset.zero,
              ).animate(animation);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: SizedBox(
              key: ValueKey(text),
              width: double.infinity,
              child: Text(text, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
        ),
      ),
    );
  }
}
