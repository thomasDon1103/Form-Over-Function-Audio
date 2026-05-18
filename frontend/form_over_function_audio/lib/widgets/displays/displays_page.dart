import 'dart:math' as math;
import 'dart:ui' as ui;

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
        AnimationController(vsync: this, duration: const Duration(seconds: 56))
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
      _manualRotation -= details.delta.dx * 0.0065;
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

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
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
                    shimmer: _ambientController.value,
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
      ),
    );
  }
}

class _CollectionRing extends StatelessWidget {
  const _CollectionRing({
    required this.albums,
    required this.rotation,
    required this.shimmer,
  });

  final List<AlbumInfo> albums;
  final double rotation;
  final double shimmer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final collection =
            Theme.of(context).extension<CollectionTheme>() ??
            AppTheme.collection;
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
        final radiusY = size.height * 0.14;
        final waterHorizon = size.height * 0.56;
        final placements = <_RingAlbumPlacement>[];

        for (var slot = 0; slot < visibleCount; slot += 1) {
          final albumIndex = (baseIndex + slot) % albums.length;
          final normalizedIndex = albumIndex < 0
              ? albumIndex + albums.length
              : albumIndex;
          final angle = (slot - residual) * step;
          final depth = ((math.cos(angle) + 1) / 2).clamp(0.0, 1.0);
          final x = math.sin(angle) * radiusX;
          final y = _lerpDouble(-radiusY * 0.28, radiusY * 0.78, depth);
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
        final frontPlacement = placements.last;
        final frontLabelOpacity = _smoothStep(0.72, 0.98, frontPlacement.depth);

        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _WaterPlanePainter(
                collection: collection,
                primary: Theme.of(context).colorScheme.primary,
                shimmer: shimmer,
                horizon: waterHorizon,
              ),
            ),
            ClipPath(
              clipper: _WaterPlaneClipper(horizon: waterHorizon),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (final placement in placements)
                    _WaterAlbumReflection(
                      key: ValueKey(
                        'display-reflection-${placement.album.location}',
                      ),
                      placement: placement,
                      albumSize: albumSize,
                      size: size,
                      horizon: waterHorizon,
                    ),
                ],
              ),
            ),
            CustomPaint(
              painter: _WaterSurfacePainter(
                primary: Theme.of(context).colorScheme.primary,
                shimmer: shimmer,
                horizon: waterHorizon,
              ),
            ),
            for (final placement in placements)
              Positioned(
                key: ValueKey('display-placement-${placement.album.location}'),
                left: (size.width / 2) + placement.x - (albumSize / 2),
                top: (size.height * 0.545) + placement.y - (albumSize / 2),
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
            _FrontAlbumLabel(
              album: frontPlacement.album,
              opacity: frontLabelOpacity,
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

class _FrontAlbumLabel extends StatelessWidget {
  const _FrontAlbumLabel({required this.album, required this.opacity});

  final AlbumInfo album;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final title = _displayAlbumTitle(album);
    final artist = _displayAlbumArtist(album);

    return Positioned(
      left: 24,
      right: 24,
      bottom: 34,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 820),
          curve: Curves.easeInOutCubic,
          opacity: opacity,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 980),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: DecoratedBox(
              key: ValueKey('front-label-${album.location}'),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    collection.backgroundBottom.withValues(alpha: 0.0),
                    collection.backgroundBottom.withValues(alpha: 0.34),
                    collection.backgroundBottom.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                            shadows: [
                              Shadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.6,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.74),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterAlbumReflection extends StatelessWidget {
  const _WaterAlbumReflection({
    super.key,
    required this.placement,
    required this.albumSize,
    required this.size,
    required this.horizon,
  });

  final _RingAlbumPlacement placement;
  final double albumSize;
  final Size size;
  final double horizon;

  @override
  Widget build(BuildContext context) {
    final albumCenter = Offset(
      (size.width / 2) + placement.x,
      (size.height * 0.545) + placement.y,
    );
    final reflectionSize =
        albumSize * placement.scale * _lerpDouble(0.72, 1.02, placement.depth);
    final reflectionHeight =
        reflectionSize * _lerpDouble(0.56, 0.98, placement.depth);
    final distanceFromHorizon = math.max(0.0, albumCenter.dy - horizon);
    final reflectionTop =
        horizon +
        (distanceFromHorizon * 0.46) +
        _lerpDouble(6, 22, placement.depth);
    final opacity = _lerpDouble(0.1, 0.42, placement.depth);

    return Positioned(
      left: albumCenter.dx - (reflectionSize / 2),
      top: reflectionTop,
      width: reflectionSize,
      height: reflectionHeight,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _lerpDouble(0.4, 1.1, 1 - placement.depth),
              sigmaY: 1.8,
            ),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white.withValues(alpha: 0.48),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.36, 1],
                ).createShader(rect);
              },
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: reflectionSize,
                  maxWidth: reflectionSize,
                  minHeight: reflectionSize,
                  maxHeight: reflectionSize,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..rotateY(-math.sin(placement.angle) * 0.26),
                    child: Transform.scale(
                      scaleY: -1,
                      child: _GlassAlbumCover(
                        album: placement.album,
                        depth: placement.depth,
                        foilPhase: placement.foilPhase,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaterPlaneClipper extends CustomClipper<Path> {
  const _WaterPlaneClipper({required this.horizon});

  final double horizon;

  @override
  Path getClip(Size size) {
    return _waterPlanePath(size, horizon);
  }

  @override
  bool shouldReclip(covariant _WaterPlaneClipper oldClipper) {
    return oldClipper.horizon != horizon;
  }
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

class _WaterPlanePainter extends CustomPainter {
  const _WaterPlanePainter({
    required this.collection,
    required this.primary,
    required this.shimmer,
    required this.horizon,
  });

  final CollectionTheme collection;
  final Color primary;
  final double shimmer;
  final double horizon;

  @override
  void paint(Canvas canvas, Size size) {
    final planePath = _waterPlanePath(size, horizon);
    final planeBounds = planePath.getBounds();
    final loop = shimmer * math.pi * 2;

    final planePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          collection.backgroundMiddle.withValues(alpha: 0.48),
          primary.withValues(alpha: 0.14),
          const Color(0xff06111f).withValues(alpha: 0.9),
          collection.backgroundBottom.withValues(alpha: 0.98),
        ],
        stops: const [0, 0.18, 0.62, 1],
      ).createShader(planeBounds);
    canvas.drawPath(planePath, planePaint);

    final mistRect = Rect.fromLTWH(
      -size.width * 0.05,
      horizon - (size.height * 0.08),
      size.width * 1.1,
      size.height * 0.095,
    );
    final distantMistPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.075),
          primary.withValues(alpha: 0.035),
          Colors.transparent,
        ],
        stops: const [0, 0.34, 0.64, 1],
      ).createShader(mistRect);
    canvas.drawRect(mistRect, distantMistPaint);

    final glowPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: Alignment(
          -0.72 + (math.sin(loop + 0.6) * 0.06),
          -0.46 + (math.cos(loop + 0.45) * 0.035),
        ),
        radius: 1.12,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          primary.withValues(alpha: 0.15),
          Colors.transparent,
        ],
        stops: const [0, 0.42, 1],
      ).createShader(planeBounds);
    canvas.drawPath(planePath, glowPaint);

    final horizonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.16),
          primary.withValues(alpha: 0.14),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, horizon - 16, size.width, 32));
    canvas.drawLine(
      Offset(-size.width * 0.08, horizon),
      Offset(size.width * 1.08, horizon),
      horizonPaint,
    );

    final surfacePaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.transparent,
          primary.withValues(alpha: 0.12),
        ],
        stops: const [0, 0.36, 1],
      ).createShader(planeBounds);
    canvas.drawPath(planePath, surfacePaint);

    final vignettePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.08),
          Colors.black.withValues(alpha: 0.28),
        ],
        stops: const [0, 0.58, 1],
      ).createShader(planeBounds);
    canvas.drawPath(planePath, vignettePaint);
  }

  @override
  bool shouldRepaint(covariant _WaterPlanePainter oldDelegate) {
    return oldDelegate.collection != collection ||
        oldDelegate.primary != primary ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.horizon != horizon;
  }
}

class _WaterSurfacePainter extends CustomPainter {
  const _WaterSurfacePainter({
    required this.primary,
    required this.shimmer,
    required this.horizon,
  });

  final Color primary;
  final double shimmer;
  final double horizon;

  @override
  void paint(Canvas canvas, Size size) {
    final planePath = _waterPlanePath(size, horizon);
    final planeBounds = planePath.getBounds();
    final loop = shimmer * math.pi * 2;

    canvas.save();
    canvas.clipPath(planePath);

    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1
      ..blendMode = BlendMode.plus;

    final distantShimmerPaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.7;
    for (var i = 0; i < 38; i += 1) {
      final row = i ~/ 2;
      final side = i.isEven ? -1.0 : 1.0;
      final depth = row / 18;
      final span = planeBounds.width * _lerpDouble(0.06, 0.24, depth);
      final centerX =
          (size.width * 0.5) +
          side * planeBounds.width * _lerpDouble(0.04, 0.42, depth) +
          math.sin(loop + (i * 1.37)) * 8;
      final y =
          horizon +
          (planeBounds.height *
              _lerpDouble(0.012, 0.22, math.pow(depth, 1.7).toDouble()));
      distantShimmerPaint.color = Colors.white.withValues(
        alpha: _lerpDouble(0.09, 0.025, depth),
      );
      canvas.drawLine(
        Offset(centerX - span, y),
        Offset(centerX + span, y + math.sin(loop + i) * 1.6),
        distantShimmerPaint,
      );
    }

    for (var i = 0; i < 26; i += 1) {
      final depth = i / 25;
      final y =
          planeBounds.top +
          (planeBounds.height * (0.05 + (math.pow(depth, 1.56) * 0.9))) +
          (math.sin(loop + (i * 0.72)) * _lerpDouble(0.4, 4.8, depth));
      final inset = planeBounds.width * _lerpDouble(0.04, 0.0, depth);
      final amplitude = _lerpDouble(0.35, 6.6, depth);
      final waveShift =
          math.sin((loop * 2) + (i * 1.1)) * _lerpDouble(1, 18, depth);
      final path = Path()..moveTo(planeBounds.left + inset, y);
      for (var step = 1; step <= 14; step += 1) {
        final t = step / 14;
        final x =
            planeBounds.left + inset + ((planeBounds.width - inset * 2) * t);
        final wave = math.sin((t * math.pi * 3.4) + loop + (i * 0.51));
        path.lineTo(
          x + waveShift * (1 - (t - 0.5).abs()),
          y + wave * amplitude,
        );
      }
      ripplePaint.color = Colors.white.withValues(
        alpha: _lerpDouble(0.018, 0.11, depth),
      );
      ripplePaint.strokeWidth = _lerpDouble(0.45, 1.2, depth);
      canvas.drawPath(path, ripplePaint);
    }

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..blendMode = BlendMode.plus;
    for (var i = 0; i < 5; i += 1) {
      final pulse = (math.sin(loop + (i * 1.26)) + 1) / 2;
      final center = Offset(
        planeBounds.left + planeBounds.width * (0.16 + ((i * 0.17) % 0.68)),
        planeBounds.top + planeBounds.height * (0.18 + ((i * 0.14) % 0.64)),
      );
      final radiusX = planeBounds.width * (0.018 + (pulse * 0.045));
      final radiusY = planeBounds.height * (0.006 + (pulse * 0.028));
      ringPaint.color = primary.withValues(alpha: 0.08 * (1 - pulse));
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radiusX * 2,
          height: radiusY * 2,
        ),
        ringPaint,
      );
    }

    final reflectionPaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;
    for (var row = 0; row < 18; row += 1) {
      final depth = row / 17;
      final y =
          horizon +
          (planeBounds.height * _lerpDouble(0.018, 0.34, depth)) +
          (math.sin(loop + row) * _lerpDouble(0.4, 2.8, depth));
      final segmentCount = 4 + (depth * 9).round();
      for (var segment = 0; segment < segmentCount; segment += 1) {
        final seed = (row * 23.17) + (segment * 11.61);
        final center =
            size.width * (0.08 + (((math.sin(seed + loop) + 1) / 2) * 0.84));
        final halfLength =
            planeBounds.width *
            _lerpDouble(0.018, 0.075, depth) *
            (0.55 + ((math.cos(seed) + 1) * 0.28));
        final wave = math.sin(loop + seed) * _lerpDouble(0.6, 3.2, depth);
        reflectionPaint
          ..strokeWidth = _lerpDouble(0.55, 1.35, depth)
          ..color = Colors.white.withValues(
            alpha: _lerpDouble(0.06, 0.015, depth),
          );
        canvas.drawLine(
          Offset(center - halfLength, y),
          Offset(center + halfLength, y + wave),
          reflectionPaint,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterSurfacePainter oldDelegate) {
    return oldDelegate.primary != primary ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.horizon != horizon;
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

double _smoothStep(double edge0, double edge1, double value) {
  final t = _clampDouble((value - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - (2 * t));
}

String _displayAlbumTitle(AlbumInfo album) {
  final title = album.title.trim();
  if (title.isNotEmpty) {
    return title;
  }
  final location = album.location.replaceAll('\\', '/');
  final parts = location.split('/').where((part) => part.isNotEmpty).toList();
  final fallback = parts.isEmpty ? null : parts.last;
  return fallback ?? 'Unknown Album';
}

String _displayAlbumArtist(AlbumInfo album) {
  final artist = album.artist.trim();
  return artist.isNotEmpty ? artist : 'Unknown Artist';
}

Path _waterPlanePath(Size size, double horizon) {
  return Path()
    ..moveTo(0, horizon)
    ..lineTo(size.width, horizon)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();
}

double _stableAlbumPhase(AlbumInfo album) {
  var hash = 0;
  for (final unit in album.location.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return (hash % 6283) / 1000;
}
