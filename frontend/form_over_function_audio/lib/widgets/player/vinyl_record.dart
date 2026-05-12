import 'package:flutter/material.dart';

import '../../app_theme.dart';

class VinylRecord extends StatelessWidget {
  const VinylRecord({super.key});

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return CustomPaint(
      painter: VinylRecordPainter(
        recordColor: collection.vinyl,
        grooveColor: colorScheme.primary.withValues(alpha: 0.2),
        labelColor: colorScheme.secondary.withValues(alpha: 0.82),
      ),
    );
  }
}

class VinylRecordPainter extends CustomPainter {
  const VinylRecordPainter({
    required this.recordColor,
    required this.grooveColor,
    required this.labelColor,
  });

  final Color recordColor;
  final Color grooveColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = diameter / 2;
    final recordRect = Rect.fromCircle(center: center, radius: radius);

    final recordPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(recordColor, Colors.white, 0.13)!,
          recordColor,
          Color.lerp(recordColor, Colors.white, 0.08)!,
          Color.lerp(recordColor, Colors.black, 0.46)!,
        ],
        stops: const [0, 0.42, 0.7, 1],
      ).createShader(recordRect);
    canvas.drawCircle(center, radius, recordPaint);

    final sheenPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.14),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0, 0.1, 0.23, 0.48, 1],
      ).createShader(recordRect);
    canvas.drawCircle(center, radius * 0.96, sheenPaint);

    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grooveColor;
    for (var groove = 0.34; groove <= 0.92; groove += 0.07) {
      canvas.drawCircle(center, radius * groove, groovePaint);
    }

    final labelPaint = Paint()..color = labelColor;
    canvas.drawCircle(center, radius * 0.2, labelPaint);
    canvas.drawCircle(center, radius * 0.055, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant VinylRecordPainter oldDelegate) {
    return oldDelegate.recordColor != recordColor ||
        oldDelegate.grooveColor != grooveColor ||
        oldDelegate.labelColor != labelColor;
  }
}
