import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/album_info.dart';

// Cover-first album browser. Track playback stays owned by the page so the
// persistent player can survive navigation between this grid and album detail.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.albums,
    required this.onAlbumSelected,
  });

  final List<AlbumInfo> albums;
  final ValueChanged<AlbumInfo> onAlbumSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(22),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisSpacing: 24,
        crossAxisSpacing: 24,
        childAspectRatio: 0.76,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _AlbumCoverTile(
          album: album,
          onTap: () => onAlbumSelected(album),
        );
      },
    );
  }
}

class _AlbumCoverTile extends StatefulWidget {
  const _AlbumCoverTile({required this.album, required this.onTap});

  final AlbumInfo album;
  final VoidCallback onTap;

  @override
  State<_AlbumCoverTile> createState() => _AlbumCoverTileState();
}

class _AlbumCoverTileState extends State<_AlbumCoverTile> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1, end: _hovered ? 1.035 : 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutQuart,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            transformHitTests: false,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutQuart,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? colorScheme.primary.withValues(alpha: 0.62)
                  : collection.panelBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(
                  alpha: _hovered ? 0.46 : 0.28,
                ),
                blurRadius: _hovered ? 28 : 18,
                offset: Offset(0, _hovered ? 16 : 9),
              ),
              BoxShadow(
                color: collection.glow.withValues(alpha: _hovered ? 0.24 : 0.1),
                blurRadius: _hovered ? 30 : 18,
                spreadRadius: _hovered ? 1 : 0,
              ),
            ],
          ),
          child: Material(
            color: collection.panel,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _setHovered,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: AlbumArt(album: widget.album, borderRadius: 0),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _albumTitle(widget.album),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.album.artist.isEmpty
                              ? 'N/A'
                              : widget.album.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AlbumDetailView extends StatelessWidget {
  const AlbumDetailView({
    super.key,
    required this.album,
    required this.selectedTrack,
    required this.onBack,
    required this.onTrackSelected,
  });

  final AlbumInfo album;
  final TrackInfo? selectedTrack;
  final VoidCallback onBack;
  final void Function(AlbumInfo album, TrackInfo track) onTrackSelected;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _EntranceFadeSlide(
          interval: const Interval(0, 0.72, curve: Curves.easeOutQuart),
          child: _AlbumHeader(album: album, onBack: onBack),
        ),
        const SizedBox(height: 16),
        _EntranceFadeSlide(
          interval: const Interval(0.18, 1, curve: Curves.easeOutQuart),
          startOffset: 10,
          child: Card(
            color: collection.panelStrong,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: collection.panelBorder),
            ),
            child: Column(
              children: [
                for (final track in album.tracks)
                  _TrackTile(
                    track: track,
                    selected: selectedTrack?.streamUrl == track.streamUrl,
                    onTap: () => onTrackSelected(album, track),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EntranceFadeSlide extends StatelessWidget {
  const _EntranceFadeSlide({
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

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({required this.album, required this.onBack});

  final AlbumInfo album;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Card(
      color: collection.panelStrong,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton.filledTonal(
                    onPressed: onBack,
                    style: IconButton.styleFrom(
                      backgroundColor: collection.glow.withValues(alpha: 0.18),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _albumTitle(album),
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
                const SizedBox(height: 12),
                Text(
                  album.location,
                  style: textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: AlbumArt(album: album),
                  ),
                  const SizedBox(height: 12),
                  details,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: AlbumArt(album: album),
                ),
                const SizedBox(width: 16),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackTile extends StatefulWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final TrackInfo track;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final titleStyle = Theme.of(context).textTheme.bodyLarge;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hovered
              ? collection.glow.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            splashColor: collection.glow.withValues(alpha: 0.12),
            highlightColor: collection.glow.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    widget.selected ? Icons.graphic_eq : Icons.play_arrow,
                    color: widget.selected
                        ? colorScheme.secondary
                        : colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _HoverMarqueeText(
                      text: widget.track.title,
                      hovered: _hovered,
                      style: titleStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverMarqueeText extends StatefulWidget {
  const _HoverMarqueeText({
    required this.text,
    required this.hovered,
    this.style,
  });

  final String text;
  final bool hovered;
  final TextStyle? style;

  @override
  State<_HoverMarqueeText> createState() => _HoverMarqueeTextState();
}

class _HoverMarqueeTextState extends State<_HoverMarqueeText>
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

class AlbumArt extends StatelessWidget {
  const AlbumArt({super.key, required this.album, this.borderRadius = 6});

  final AlbumInfo album;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final art = album.artUrl.isEmpty
        ? const _AlbumArtFallback()
        : Image.network(
            album.artUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const _AlbumArtFallback(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.expand(child: art),
    );
  }
}

class _AlbumArtFallback extends StatelessWidget {
  const _AlbumArtFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [collection.panelStrong, colorScheme.primaryContainer],
        ),
      ),
      child: Center(
        child: Icon(Icons.album, size: 48, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

String _albumTitle(AlbumInfo album) {
  return album.title.isEmpty ? album.location : album.title;
}
