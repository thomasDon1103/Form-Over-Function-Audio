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
                    // Albums always face the viewer head-on — no Y rotation
                    // as they orbit, so cover art stays fully readable.
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0014)
                      ..multiply(
                        Matrix4.diagonal3Values(
                          placement.scale,
                          placement.scale,
                          1,
                        ),
                      ),
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
    // The reflection is full-sized (matches the album) so it reads as a true
    // mirror image rather than a faint smudge.
    final reflectionWidth = albumSize * placement.scale;
    final reflectionHeight = reflectionWidth;

    // The album's bottom edge tells us where its base sits in screen space.
    final albumBottom = albumCenter.dy + (reflectionWidth / 2);
    // Push the reflection well below the album so it appears the album is
    // hovering ABOVE the water rather than resting on it. The gap grows with
    // depth so front (closer) albums float visibly higher.
    final floatGap = _lerpDouble(28, 64, placement.depth);
    final reflectionTop = math.max(horizon, albumBottom + floatGap);
    // Reflections are visibly more transparent than the originals to better
    // mimic real water — even at their brightest they only reach about half
    // the original intensity.
    final opacity = _lerpDouble(0.18, 0.5, placement.depth);

    return Positioned(
      left: albumCenter.dx - (reflectionWidth / 2),
      top: reflectionTop,
      width: reflectionWidth,
      height: reflectionHeight,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: ImageFiltered(
            // A touch of horizontal blur to suggest gentle water distortion,
            // and a slightly stronger vertical blur to fake the stretch of
            // ripples without obliterating the image.
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _lerpDouble(0.6, 1.4, 1 - placement.depth),
              sigmaY: 1.4,
            ),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white.withValues(alpha: 0.85),
                    Colors.white.withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.4, 0.75, 1],
                ).createShader(rect);
              },
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: reflectionWidth,
                  maxWidth: reflectionWidth,
                  minHeight: reflectionWidth,
                  maxHeight: reflectionWidth,
                  // Reflection also faces the viewer — only vertically
                  // flipped to mirror the album above it.
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
    final horizon = size.height * 0.56;
    final loop = shimmer * math.pi * 2;

    // Base sky gradient – deep night fading to a warmer band near the horizon.
    final skyRect = Rect.fromLTWH(0, 0, size.width, horizon);
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          collection.backgroundBottom,
          collection.backgroundTop,
          collection.backgroundMiddle.withValues(alpha: 0.92),
          Color.lerp(
            collection.backgroundMiddle,
            primary,
            0.18,
          )!.withValues(alpha: 0.95),
        ],
        stops: const [0, 0.36, 0.78, 1],
      ).createShader(skyRect);
    canvas.drawRect(skyRect, skyPaint);

    // Soft auroral glow high in the sky.
    final auroraRect = Rect.fromLTWH(0, 0, size.width, horizon);
    final auroraPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        center: const Alignment(-0.55, -0.85),
        radius: 1.15,
        colors: [
          primary.withValues(alpha: 0.22),
          primary.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0, 0.45, 1],
      ).createShader(auroraRect);
    canvas.drawRect(auroraRect, auroraPaint);

    // Moon disc — the light source for the rays and water highlight.
    final moonCenter = Offset(size.width * 0.22, horizon - size.height * 0.30);
    final moonRadius = size.shortestSide * 0.052;
    final moonHaloPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.55),
          primary.withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0, 0.35, 1],
      ).createShader(
        Rect.fromCircle(center: moonCenter, radius: moonRadius * 5.2),
      );
    canvas.drawCircle(moonCenter, moonRadius * 5.2, moonHaloPaint);
    final moonPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.3),
        radius: 0.95,
        colors: [
          const Color(0xfff4faff),
          const Color(0xffd5e7fb),
          const Color(0xff8eb2d8).withValues(alpha: 0.9),
        ],
        stops: const [0, 0.62, 1],
      ).createShader(
        Rect.fromCircle(center: moonCenter, radius: moonRadius),
      );
    canvas.drawCircle(moonCenter, moonRadius, moonPaint);

    // Stars — only above the horizon, with a parallax-friendly twinkle.
    final starPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 70; i += 1) {
      final seed = i * 53.13;
      final x = ((math.sin(seed) + 1) / 2) * size.width;
      final y = ((math.cos(seed * 1.91) + 1) / 2) * horizon * 0.82;
      // Avoid putting stars on top of the moon disc.
      if ((Offset(x, y) - moonCenter).distance < moonRadius * 3.4) {
        continue;
      }
      final twinkle =
          0.35 + ((math.sin(loop * 1.3 + seed) + 1) / 2) * 0.65;
      final radius = 0.55 + ((i % 5) * 0.32) * twinkle;
      starPaint.color = Colors.white.withValues(alpha: 0.32 + 0.5 * twinkle);
      canvas.drawCircle(Offset(x, y), radius, starPaint);
      // A faint cross-flare on the brightest stars.
      if (i % 9 == 0) {
        starPaint.strokeWidth = 0.7;
        starPaint.color = Colors.white.withValues(alpha: 0.22 * twinkle);
        final flare = radius * 4.2;
        canvas.drawLine(
          Offset(x - flare, y),
          Offset(x + flare, y),
          starPaint,
        );
        canvas.drawLine(
          Offset(x, y - flare),
          Offset(x, y + flare),
          starPaint,
        );
      }
    }

    // A whisper of horizon haze sitting just above the water — drawn BEFORE
    // the mountains so they read as the closest silhouettes.
    final hazeRect = Rect.fromLTWH(
      0,
      horizon - size.height * 0.07,
      size.width,
      size.height * 0.07,
    );
    final hazePaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          primary.withValues(alpha: 0.08),
          Colors.white.withValues(alpha: 0.05),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(hazeRect);
    canvas.drawRect(hazeRect, hazePaint);

    // Distant mountain silhouettes — three layers for depth. All baselines
    // sit EXACTLY on the horizon so the silhouettes never dip into the water.
    _paintMountainLayer(
      canvas,
      size,
      horizon: horizon,
      amplitude: size.height * 0.08,
      frequency: 1.6,
      phase: 0.4,
      color: Color.lerp(
        collection.backgroundMiddle,
        primary,
        0.18,
      )!.withValues(alpha: 0.42),
    );
    _paintMountainLayer(
      canvas,
      size,
      horizon: horizon,
      amplitude: size.height * 0.11,
      frequency: 1.05,
      phase: 1.7,
      color: Color.lerp(
        collection.backgroundTop,
        collection.backgroundBottom,
        0.35,
      )!.withValues(alpha: 0.72),
    );
    _paintMountainLayer(
      canvas,
      size,
      horizon: horizon,
      amplitude: size.height * 0.16,
      frequency: 0.7,
      phase: 2.9,
      color: collection.backgroundBottom.withValues(alpha: 0.95),
    );
  }

  void _paintMountainLayer(
    Canvas canvas,
    Size size, {
    required double horizon,
    required double amplitude,
    required double frequency,
    required double phase,
    required Color color,
  }) {
    // The baseline is EXACTLY the horizon so the silhouette meets the water
    // line cleanly and never appears to be submerged.
    final baseline = horizon;
    final path = Path()..moveTo(-size.width * 0.05, baseline);
    const steps = 48;
    for (var i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final x = -size.width * 0.05 + (size.width * 1.1 * t);
      // Combine a few sine waves to get jagged-yet-natural ridgelines.
      final ridge =
          math.sin((t * math.pi * 2 * frequency) + phase) * 0.55 +
          math.sin((t * math.pi * 2 * frequency * 2.3) + phase * 1.7) * 0.3 +
          math.sin((t * math.pi * 2 * frequency * 4.1) + phase * 0.4) * 0.15;
      final y = baseline - ((ridge + 1) / 2) * amplitude;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width * 1.05, baseline)
      ..close();
    final paint = Paint()..color = color;
    canvas.drawPath(path, paint);
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

    // Base water color – darker near the viewer, lighter at the far horizon.
    // This mimics the way real water reflects more sky as the viewing angle
    // becomes more grazing (Fresnel-like behavior).
    final deepWater = const Color(0xff020812);
    final shallowReflection = Color.lerp(
      collection.backgroundMiddle,
      primary,
      0.35,
    )!;
    final planePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          shallowReflection.withValues(alpha: 0.78),
          collection.backgroundMiddle.withValues(alpha: 0.62),
          const Color(0xff04101e).withValues(alpha: 0.96),
          deepWater,
        ],
        stops: const [0, 0.22, 0.7, 1],
      ).createShader(planeBounds);
    canvas.drawPath(planePath, planePaint);

    // A subtle, perspective-correct "sheen" near the horizon. Real bodies of
    // water appear noticeably brighter at the far edge because they reflect
    // the brighter sky almost mirror-like at grazing angles.
    final fresnelRect = Rect.fromLTWH(
      0,
      horizon,
      size.width,
      size.height * 0.18,
    );
    final fresnelPaint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.11),
          primary.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0, 0.45, 1],
      ).createShader(fresnelRect);
    canvas.drawRect(fresnelRect, fresnelPaint);

    // A soft horizon line — bright, hairline, slightly hazy. Sells the
    // impression of distant water meeting the sky.
    final horizonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.28),
          primary.withValues(alpha: 0.22),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, horizon - 16, size.width, 32));
    canvas.drawLine(
      Offset(-size.width * 0.08, horizon),
      Offset(size.width * 1.08, horizon),
      horizonPaint,
    );

    // Subtle vignette pulls the eye toward the center.
    final vignettePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.10),
          Colors.black.withValues(alpha: 0.34),
        ],
        stops: const [0, 0.55, 1],
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
    // The ambient controller is intentionally slow (driving the orbiting
    // ring), so we multiply its phase here to give the water its own,
    // much livelier sense of motion.
    final loop = shimmer * math.pi * 2 * 14;
    final waterHeight = planeBounds.height;

    canvas.save();
    canvas.clipPath(planePath);

    // ----- Layer 1: Perspective-compressed horizontal ripple bands -----
    // Real water shows compressed, near-horizontal wave bands that get thinner
    // and closer together as they recede toward the horizon. We model this
    // with rows whose vertical density follows a quadratic perspective curve.
    final bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;

    const totalBands = 60;
    for (var i = 0; i < totalBands; i += 1) {
      // "depth" goes from 0 (far, at horizon) to 1 (near, at bottom edge).
      final depth = math.pow(i / (totalBands - 1), 2.0).toDouble();
      final y =
          horizon +
          waterHeight * depth +
          math.sin(loop * 0.8 + i * 0.31) * _lerpDouble(0.3, 2.8, depth);

      // A gentle low-frequency wave that flows horizontally over time.
      final phase = loop * 0.6 + i * 0.27;
      final amplitude = _lerpDouble(0.25, 3.6, depth);

      final path = Path();
      const samples = 48;
      for (var s = 0; s <= samples; s += 1) {
        final t = s / samples;
        final x = -size.width * 0.05 + (size.width * 1.1 * t);
        final wave =
            math.sin((t * math.pi * 5.0) + phase) * amplitude +
            math.sin((t * math.pi * 13.0) + phase * 1.7) *
                amplitude * 0.35;
        final py = y + wave;
        if (s == 0) {
          path.moveTo(x, py);
        } else {
          path.lineTo(x, py);
        }
      }

      // Bands are very thin/faint near the horizon, slightly thicker near us.
      bandPaint
        ..strokeWidth = _lerpDouble(0.4, 1.05, depth)
        ..color = Colors.white.withValues(
          alpha: _lerpDouble(0.06, 0.04, depth),
        );
      canvas.drawPath(path, bandPaint);
    }

    // ----- Layer 2: Scattered specular highlights across the water -----
    // Sky reflections catching on individual wave facets — distributed across
    // the whole surface to give the water a lively, broken-mirror quality.
    final scatterPaint = Paint()
      ..blendMode = BlendMode.plus
      ..strokeCap = StrokeCap.round;
    const scatterCount = 120;
    for (var i = 0; i < scatterCount; i += 1) {
      final seed = i * 17.31;
      final depthT = ((math.sin(seed) + 1) / 2);
      final depth = math.pow(depthT, 1.8).toDouble();
      final rowY = horizon + waterHeight * depth;
      final cx =
          size.width *
          (((math.cos(seed * 1.7) + 1) / 2) * 1.04 - 0.02);
      final flicker =
          0.45 + (math.sin(loop * 1.7 + seed) + 1) / 2 * 0.55;
      final halfLength = _lerpDouble(2.4, 9, depth);
      final yWobble =
          math.sin(loop * 0.9 + seed * 0.7) * _lerpDouble(0.3, 1.6, depth);
      // Mix cool primary highlights with occasional white sparkles.
      final useWhite = i % 5 == 0;
      scatterPaint
        ..strokeWidth = _lerpDouble(0.55, 1.3, depth)
        ..color = (useWhite ? Colors.white : primary).withValues(
          alpha: _lerpDouble(0.12, 0.05, depth) * flicker,
        );
      canvas.drawLine(
        Offset(cx - halfLength, rowY + yWobble),
        Offset(cx + halfLength, rowY + yWobble),
        scatterPaint,
      );
    }

    // ----- Layer 4: A handful of expanding ripples -----
    // Like drops occasionally landing on the surface. Cycle through their
    // life much faster than the ambient controller would naturally allow.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..blendMode = BlendMode.plus;
    const ripplePhaseSpeed = 6.0;
    for (var i = 0; i < 4; i += 1) {
      // Each ripple completes ~6 life cycles per controller loop.
      final localPhase =
          ((shimmer * ripplePhaseSpeed) + i * 0.25) % 1.0;
      final pulse = localPhase; // 0 -> 1
      final fade = 1 - pulse; // dies out as it expands
      final centerSeed = i * 41.0;
      final cxFrac = 0.18 + ((math.sin(centerSeed) + 1) / 2) * 0.7;
      final cyDepthT = 0.2 + ((math.cos(centerSeed * 1.4) + 1) / 2) * 0.7;
      final cy = horizon + waterHeight * cyDepthT;
      final radiusX = size.width * (0.01 + pulse * 0.08);
      final radiusY = radiusX * _lerpDouble(0.15, 0.35, cyDepthT);
      ringPaint.color = Colors.white.withValues(alpha: 0.10 * fade);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * cxFrac, cy),
          width: radiusX * 2,
          height: radiusY * 2,
        ),
        ringPaint,
      );
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
