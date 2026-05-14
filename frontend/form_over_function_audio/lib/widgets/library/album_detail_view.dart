import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import 'album_art.dart';
import 'album_title.dart';
import 'track_tile.dart';

class AlbumDetailView extends StatefulWidget {
  const AlbumDetailView({
    super.key,
    required this.album,
    required this.visible,
    required this.selectedTrack,
    required this.onBack,
    required this.onDismissed,
    required this.onTrackSelected,
    this.openingArtRect,
  });

  final AlbumInfo album;
  final Rect? openingArtRect;
  final bool visible;
  final TrackInfo? selectedTrack;
  final VoidCallback onBack;
  final VoidCallback onDismissed;
  final void Function(AlbumInfo album, TrackInfo track) onTrackSelected;

  @override
  State<AlbumDetailView> createState() => _AlbumDetailViewState();
}

class _AlbumDetailViewState extends State<AlbumDetailView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 860),
    reverseDuration: const Duration(milliseconds: 760),
  );
  late final Animation<double> _motion = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
    reverseCurve: Curves.easeInOutCubic,
  );
  late final Animation<double> _pageOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.12, 1, curve: Curves.easeOutCubic),
    reverseCurve: const Interval(0.18, 1, curve: Curves.easeInCubic),
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_handleAnimationStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVisibility());
  }

  @override
  void didUpdateWidget(covariant AlbumDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _syncVisibility();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _syncVisibility() {
    if (!mounted) {
      return;
    }
    if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.visible) {
      widget.onDismissed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return IgnorePointer(
      ignoring: !widget.visible,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: _pageOpacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    collection.backgroundTop.withValues(alpha: 0.92),
                    collection.backgroundBottom.withValues(alpha: 0.96),
                  ],
                ),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AlbumHeader(
                album: widget.album,
                openingArtRect: widget.openingArtRect,
                visible: widget.visible,
                motion: _motion,
                pageOpacity: _pageOpacity,
                onBack: widget.onBack,
              ),
              const SizedBox(height: 16),
              FadeTransition(
                opacity: _pageOpacity,
                child: Card(
                  color: collection.panelStrong,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: collection.panelBorder),
                  ),
                  child: Column(
                    children: [
                      for (final track in widget.album.tracks)
                        TrackTile(
                          track: track,
                          selected:
                              widget.selectedTrack?.streamUrl ==
                              track.streamUrl,
                          onTap: () =>
                              widget.onTrackSelected(widget.album, track),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.openingArtRect,
    required this.visible,
    required this.motion,
    required this.pageOpacity,
    required this.onBack,
  });

  final AlbumInfo album;
  final Rect? openingArtRect;
  final bool visible;
  final Animation<double> motion;
  final Animation<double> pageOpacity;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return AnimatedBuilder(
      animation: pageOpacity,
      builder: (context, child) {
        final opacity = pageOpacity.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: collection.panelStrong.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: collection.panelBorder.withValues(alpha: opacity),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.22 * opacity),
                blurRadius: 26 * opacity,
                offset: Offset(0, 10 * opacity),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final coverSize = narrow
                ? math.min(320.0, constraints.maxWidth)
                : math.min(360.0, constraints.maxWidth * 0.42);
            final details = FadeTransition(
              opacity: pageOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton.filledTonal(
                      onPressed: onBack,
                      style: IconButton.styleFrom(
                        backgroundColor: collection.glow.withValues(
                          alpha: 0.18,
                        ),
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    albumTitle(album),
                    style: textTheme.headlineSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      album.artist.isEmpty ? 'N/A' : album.artist,
                      album.year == 0 ? 'N/A' : album.year.toString(),
                      album.genre.isEmpty ? 'N/A' : album.genre,
                    ].join(' | '),
                    style: textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );

            final art = SizedBox(
              width: coverSize,
              height: coverSize,
              child: _ZoomingAlbumArt(
                album: album,
                sourceRect: openingArtRect,
                movesFromSource: visible,
                animation: motion,
                opacity: pageOpacity,
              ),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [art, const SizedBox(height: 12), details],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                art,
                const SizedBox(width: 24),
                Expanded(
                  child: SizedBox(height: coverSize, child: details),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ZoomingAlbumArt extends StatefulWidget {
  const _ZoomingAlbumArt({
    required this.album,
    required this.sourceRect,
    required this.movesFromSource,
    required this.animation,
    required this.opacity,
  });

  final AlbumInfo album;
  final Rect? sourceRect;
  final bool movesFromSource;
  final Animation<double> animation;
  final Animation<double> opacity;

  @override
  State<_ZoomingAlbumArt> createState() => _ZoomingAlbumArtState();
}

class _ZoomingAlbumArtState extends State<_ZoomingAlbumArt> {
  final GlobalKey _targetKey = GlobalKey();
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
  }

  @override
  void didUpdateWidget(covariant _ZoomingAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.location != widget.album.location ||
        oldWidget.sourceRect != widget.sourceRect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureTarget());
    }
  }

  void _measureTarget() {
    if (!mounted) {
      return;
    }

    setState(() {
      _targetRect = _targetBounds();
    });
  }

  Rect? _targetBounds() {
    final context = _targetKey.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  double _lerp(double start, double end, double amount) {
    return start + ((end - start) * amount);
  }

  @override
  Widget build(BuildContext context) {
    final art = AlbumArt(album: widget.album);

    return KeyedSubtree(
      key: _targetKey,
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.animation, widget.opacity]),
        child: art,
        builder: (context, child) {
          final sourceRect = widget.sourceRect;
          final targetRect = _targetRect;
          if (sourceRect != null && targetRect == null) {
            return Opacity(opacity: 0, child: child);
          }
          if (sourceRect == null || targetRect == null) {
            return child!;
          }

          final amount = widget.movesFromSource ? widget.animation.value : 1.0;
          final opacity = widget.movesFromSource ? 1.0 : widget.opacity.value;
          final dx = _lerp(
            sourceRect.center.dx - targetRect.center.dx,
            0,
            amount,
          );
          final dy = _lerp(
            sourceRect.center.dy - targetRect.center.dy,
            0,
            amount,
          );
          final scaleX = _lerp(sourceRect.width / targetRect.width, 1, amount);
          final scaleY = _lerp(
            sourceRect.height / targetRect.height,
            1,
            amount,
          );

          return Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
