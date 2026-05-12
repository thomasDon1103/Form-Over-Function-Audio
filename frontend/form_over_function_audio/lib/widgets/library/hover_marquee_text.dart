import 'package:flutter/material.dart';

class HoverMarqueeText extends StatefulWidget {
  const HoverMarqueeText({
    super.key,
    required this.text,
    required this.hovered,
    this.style,
  });

  final String text;
  final bool hovered;
  final TextStyle? style;

  @override
  State<HoverMarqueeText> createState() => _HoverMarqueeTextState();
}

class _HoverMarqueeTextState extends State<HoverMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: direction,
        )..layout();
        final overflows = painter.width > constraints.maxWidth;

        if (!widget.hovered || !overflows) {
          if (_controller.isAnimating) {
            _controller.stop();
            _controller.value = 0;
          }
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        const gap = 44.0;
        final distance = painter.width + gap;
        final durationSeconds = (distance / 34).clamp(7.0, 18.0);
        final duration = Duration(
          milliseconds: (durationSeconds * 1000).round(),
        );

        if (_controller.duration != duration) {
          _controller.duration = duration;
        }
        if (!_controller.isAnimating) {
          _controller.repeat();
        }

        final totalWidth = (painter.width * 2) + gap;

        return ClipRect(
          child: SizedBox(
            height: painter.height,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-_controller.value * distance, 0),
                  child: child,
                );
              },
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: totalWidth,
                maxWidth: totalWidth,
                child: SizedBox(
                  width: totalWidth,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: painter.width,
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      ),
                      const SizedBox(width: gap),
                      SizedBox(
                        width: painter.width,
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
