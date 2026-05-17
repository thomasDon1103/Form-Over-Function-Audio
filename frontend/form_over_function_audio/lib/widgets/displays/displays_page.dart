import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import '../empty_state.dart';
import '../library/album_art.dart';

class DisplaysPage extends StatefulWidget {
  const DisplaysPage({super.key, required this.albums});

  final List<AlbumInfo> albums;

  @override
  State<DisplaysPage> createState() => _DisplaysPageState();
}

class _DisplaysPageState extends State<DisplaysPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;

  bool _ambientMode = true;
  double _manualRotation = 0;
  double _ambientRotation = 0;
  double _lastAmbientValue = 0;

  @override
  void initState() {
    super.initState();
    _ambientController =
        AnimationController(vsync: this, duration: const Duration(seconds: 42))
          ..addListener(_advanceAmbientRotation)
          ..repeat();
  }

  @override
  void dispose() {
    _ambientController.removeListener(_advanceAmbientRotation);
    _ambientController.dispose();
    super.dispose();
  }

  void _advanceAmbientRotation() {
    final currentValue = _ambientController.value;
    if (!_ambientMode) {
      _lastAmbientValue = currentValue;
      return;
    }

    var delta = currentValue - _lastAmbientValue;
    if (delta < 0) {
      delta += 1;
    }
    _ambientRotation += delta * math.pi * 2;
    _lastAmbientValue = currentValue;
  }

  void _toggleAmbientMode() {
    setState(() {
      _ambientMode = !_ambientMode;
      if (_ambientMode) {
        _lastAmbientValue = _ambientController.value;
        _ambientController.repeat();
      } else {
        _ambientController.stop();
      }
    });
  }

  void _handleDragStart(DragStartDetails details) {
    if (_ambientMode) {
      _lastAmbientValue = _ambientController.value;
      _ambientController.stop();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _manualRotation += details.delta.dx * 0.009;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_ambientMode) {
      _lastAmbientValue = _ambientController.value;
      _ambientController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.albums.isEmpty) {
      return const EmptyState(status: 'No albums available for displays.');
    }

    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _ambientController,
          builder: (context, _) {
            return CustomPaint(
              painter: _DisplayAtmospherePainter(
                collection: collection,
                primary: colorScheme.primary,
                shimmer: _ambientController.value,
              ),
            );
          },
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _handleDragStart,
          onHorizontalDragUpdate: _handleDragUpdate,
          onHorizontalDragEnd: _handleDragEnd,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                return _CollectionRing(
                  albums: widget.albums,
                  rotation: _manualRotation + _ambientRotation,
                );
              },
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 18,
          child: Semantics(
            label: _ambientMode
                ? 'Pause ambient viewing'
                : 'Start ambient viewing',
            button: true,
            child: IconButton.filledTonal(
              onPressed: _toggleAmbientMode,
              style: IconButton.styleFrom(
                backgroundColor: collection.glow.withValues(alpha: 0.18),
                foregroundColor: colorScheme.primary,
                hoverColor: collection.glow.withValues(alpha: 0.28),
                fixedSize: const Size.square(44),
                minimumSize: const Size.square(44),
              ),
              icon: Icon(
                _ambientMode
                    ? Icons.motion_photos_pause
                    : Icons.motion_photos_auto,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionRing extends StatelessWidget {
  const _CollectionRing({required this.albums, required this.rotation});

  final List<AlbumInfo> albums;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final visibleCount = _visibleAlbumCount(size, albums.length);
        final step = (math.pi * 2) / visibleCount;
        final progress = rotation / step;
        final baseIndex = progress.floor();
        final residual = progress - baseIndex;
        final albumSize = _clampDouble(
          math.min(size.width * 0.18, size.height * 0.34),
          102,
          224,
        );
        final radiusX = math.max(
          albumSize * 1.35,
          (size.width - albumSize) * 0.39,
        );
        final radiusY = size.height * 0.2;
        final placements = <_RingAlbumPlacement>[];

        for (var slot = 0; slot < visibleCount; slot += 1) {
          final albumIndex = (baseIndex + slot) % albums.length;
          final normalizedIndex = albumIndex < 0
              ? albumIndex + albums.length
              : albumIndex;
          final angle = (slot - residual) * step;
          final depth = ((math.cos(angle) + 1) / 2).clamp(0.0, 1.0);
          final x = math.sin(angle) * radiusX;
          final y = _lerpDouble(-radiusY * 0.9, radiusY * 0.82, depth);
          final scale = _lerpDouble(0.5, 1.12, depth);
          placements.add(
            _RingAlbumPlacement(
              album: albums[normalizedIndex],
              x: x,
              y: y,
              depth: depth,
              scale: scale,
              angle: angle,
              foilPhase:
                  (rotation * 0.42) +
                  _stableAlbumPhase(albums[normalizedIndex]),
            ),
          );
        }

        placements.sort((left, right) => left.depth.compareTo(right.depth));

        return Stack(
          fit: StackFit.expand,
          children: [
            for (final placement in placements)
              Positioned(
                key: ValueKey('display-placement-${placement.album.location}'),
                left: (size.width / 2) + placement.x - (albumSize / 2),
                top: (size.height * 0.48) + placement.y - (albumSize / 2),
                width: albumSize,
                height: albumSize,
                child: Opacity(
                  opacity: _lerpDouble(0.38, 1, placement.depth),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..multiply(
                        Matrix4.diagonal3Values(
                          placement.scale,
                          placement.scale,
                          1,
                        ),
                      )
                      ..rotateY(-math.sin(placement.angle) * 0.42),
                    child: _GlassAlbumCover(
                      key: ValueKey(
                        'display-album-${placement.album.location}',
                      ),
                      album: placement.album,
                      depth: placement.depth,
                      foilPhase: placement.foilPhase,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  int _visibleAlbumCount(Size size, int total) {
    if (total <= 1) {
      return total;
    }
    final target = size.width < 680
        ? 8
        : size.width < 1040
        ? 12
        : 16;
    return math.min(total, target);
  }
}

class _RingAlbumPlacement {
  const _RingAlbumPlacement({
    required this.album,
    required this.x,
    required this.y,
    required this.depth,
    required this.scale,
    required this.angle,
    required this.foilPhase,
  });

  final AlbumInfo album;
  final double x;
  final double y;
  final double depth;
  final double scale;
  final double angle;
  final double foilPhase;
}

class _GlassAlbumCover extends StatelessWidget {
  const _GlassAlbumCover({
    super.key,
    required this.album,
    required this.depth,
    required this.foilPhase,
  });

  final AlbumInfo album;
  final double depth;
  final double foilPhase;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: _lerpDouble(0.26, 0.52, depth),
            ),
            blurRadius: _lerpDouble(16, 42, depth),
            offset: Offset(0, _lerpDouble(12, 26, depth)),
          ),
          BoxShadow(
            color: collection.glow.withValues(
              alpha: _lerpDouble(0.06, 0.22, depth),
            ),
            blurRadius: _lerpDouble(12, 34, depth),
            spreadRadius: _lerpDouble(0, 1.5, depth),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AlbumArt(album: album, borderRadius: 0),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.25),
                    Colors.white.withValues(alpha: 0.04),
                    Colors.transparent,
                    collection.glow.withValues(alpha: 0.13),
                  ],
                  stops: const [0.0, 0.22, 0.56, 1.0],
                ),
              ),
            ),
            CustomPaint(
              painter: _HolographicFoilPainter(
                phase: foilPhase,
                intensity: _lerpDouble(0.34, 0.78, depth),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: _lerpDouble(0.18, 0.36, depth),
                  ),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayAtmospherePainter extends CustomPainter {
  const _DisplayAtmospherePainter({
    required this.collection,
    required this.primary,
    required this.shimmer,
  });

  final CollectionTheme collection;
  final Color primary;
  final double shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.82, -0.82),
        radius: 1.05,
        colors: [
          primary.withValues(alpha: 0.2),
          collection.backgroundMiddle.withValues(alpha: 0.74),
          collection.backgroundBottom,
        ],
        stops: const [0, 0.42, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final rayPaint = Paint()..blendMode = BlendMode.plus;
    final origin = Offset(size.width * 0.06, -size.height * 0.04);
    final rayLength = math.max(size.width, size.height) * 1.8;
    final loop = shimmer * math.pi * 2;
    for (var i = 0; i < 10; i += 1) {
      final startAngle =
          (0.12 + (i * 0.115)) + (math.sin(loop + (i * 0.34)) * 0.03);
      final width = 0.075 + ((i % 3) * 0.032);
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + math.cos(startAngle) * rayLength,
          origin.dy + math.sin(startAngle) * rayLength,
        )
        ..lineTo(
          origin.dx + math.cos(startAngle + width) * rayLength,
          origin.dy + math.sin(startAngle + width) * rayLength,
        )
        ..close();
      rayPaint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          primary.withValues(alpha: 0.064),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
      canvas.drawPath(path, rayPaint);
    }

    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.54)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    for (var i = 0; i < 28; i += 1) {
      final seed = i * 37.41;
      final x = ((math.sin(seed) + 1) / 2) * size.width;
      final y =
          ((math.cos(seed * 1.73 + shimmer * math.pi * 2) + 1) / 2) *
          size.height *
          0.78;
      final pulse =
          0.45 + (math.sin((shimmer * math.pi * 2) + seed) + 1) * 0.28;
      final radius = 1.2 + ((i % 4) * 0.55) * pulse;
      final center = Offset(x, y + size.height * 0.08);
      canvas.drawLine(
        center.translate(-radius, 0),
        center.translate(radius, 0),
        starPaint,
      );
      canvas.drawLine(
        center.translate(0, -radius),
        center.translate(0, radius),
        starPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DisplayAtmospherePainter oldDelegate) {
    return oldDelegate.collection != collection ||
        oldDelegate.primary != primary ||
        oldDelegate.shimmer != shimmer;
  }
}

class _HolographicFoilPainter extends CustomPainter {
  const _HolographicFoilPainter({required this.phase, required this.intensity});

  final double phase;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final loop = phase;
    final foilPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        tileMode: TileMode.mirror,
        transform: GradientRotation(loop + 0.42),
        colors: [
          const Color(0xffff4fd8).withValues(alpha: 0.0),
          const Color(0xffff4fd8).withValues(alpha: 0.18 * intensity),
          const Color(0xff65f4ff).withValues(alpha: 0.23 * intensity),
          const Color(0xfffff27a).withValues(alpha: 0.18 * intensity),
          const Color(0xff8c7dff).withValues(alpha: 0.24 * intensity),
          const Color(0xff45ff9a).withValues(alpha: 0.14 * intensity),
          const Color(0xffff4fd8).withValues(alpha: 0.0),
        ],
        stops: const [0, 0.12, 0.28, 0.44, 0.61, 0.78, 1],
      ).createShader(rect);
    canvas.drawRect(rect, foilPaint);

    final prismPaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = -8; i < 18; i += 1) {
      final phase = i * 0.071;
      final wave = math.sin(loop + (i * 0.53));
      final color = HSVColor.fromAHSV(
        0.18 *
            intensity *
            (0.65 + math.sin(loop + (phase * math.pi * 2)) * 0.35),
        ((phase * 360) + (math.sin(loop + (i * 0.27)) * 38) + 190) % 360,
        0.58,
        1,
      ).toColor();
      prismPaint.color = color;
      final y =
          (i * size.height * 0.075) +
          (size.height * 0.055 * wave) +
          size.height * 0.07;
      canvas.drawLine(
        Offset(-size.width * 0.22, y),
        Offset(size.width * 1.22, y + size.height * 0.44),
        prismPaint,
      );
    }

    final flareCenter = Offset(
      size.width * (0.5 + (math.sin(loop - 0.7) * 0.38)),
      size.height * (0.42 + (math.cos(loop + 0.36) * 0.24)),
    );
    final flareRect = Rect.fromCircle(
      center: flareCenter,
      radius: size.shortestSide * 0.34,
    );
    final flarePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.26 * intensity),
          const Color(0xffb8f7ff).withValues(alpha: 0.14 * intensity),
          const Color(0xffff79dc).withValues(alpha: 0.08 * intensity),
          Colors.transparent,
        ],
        stops: const [0, 0.26, 0.54, 1],
      ).createShader(flareRect);
    canvas.drawCircle(flareCenter, size.shortestSide * 0.34, flarePaint);

    final sparklePaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.55;
    for (var i = 0; i < 4; i += 1) {
      final phase = loop + (i * math.pi * 0.58);
      final pulse = (math.sin((loop * 2) + (i * 1.7)) + 1) / 2;
      final center = Offset(
        size.width * (0.5 + (math.sin(phase) * 0.34)),
        size.height * (0.44 + (math.cos(phase + i) * 0.25)),
      );
      final radius = size.shortestSide * (0.018 + (0.026 * pulse));
      sparklePaint.color = HSVColor.fromAHSV(
        0.22 * intensity,
        ((math.sin(phase) + 1) * 180 + 170) % 360,
        0.34,
        1,
      ).toColor();
      canvas.drawLine(
        center.translate(-radius, 0),
        center.translate(radius, 0),
        sparklePaint,
      );
      canvas.drawLine(
        center.translate(0, -radius),
        center.translate(0, radius),
        sparklePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HolographicFoilPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.intensity != intensity;
  }
}

double _lerpDouble(double start, double end, double amount) {
  return start + ((end - start) * amount);
}

double _clampDouble(double value, double minimum, double maximum) {
  return math.max(minimum, math.min(maximum, value));
}

double _stableAlbumPhase(AlbumInfo album) {
  var hash = 0;
  for (final unit in album.location.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return (hash % 6283) / 1000;
}
