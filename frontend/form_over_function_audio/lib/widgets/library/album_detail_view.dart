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
    required this.availableGenres,
    required this.onGenreSelected,
    required this.onCreateGenre,
    this.openingArtRect,
  });

  final AlbumInfo album;
  final Rect? openingArtRect;
  final bool visible;
  final TrackInfo? selectedTrack;
  final VoidCallback onBack;
  final VoidCallback onDismissed;
  final void Function(AlbumInfo album, TrackInfo track) onTrackSelected;
  final List<String> availableGenres;
  final void Function(AlbumInfo album, String genre) onGenreSelected;
  final Future<String?> Function() onCreateGenre;

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
                availableGenres: widget.availableGenres,
                onGenreSelected: (genre) =>
                    widget.onGenreSelected(widget.album, genre),
                onCreateGenre: widget.onCreateGenre,
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
    required this.availableGenres,
    required this.onGenreSelected,
    required this.onCreateGenre,
  });

  final AlbumInfo album;
  final Rect? openingArtRect;
  final bool visible;
  final Animation<double> motion;
  final Animation<double> pageOpacity;
  final VoidCallback onBack;
  final List<String> availableGenres;
  final ValueChanged<String> onGenreSelected;
  final Future<String?> Function() onCreateGenre;

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
                  const SizedBox(height: 12),
                  _AlbumMetadataPanel(
                    album: album,
                    availableGenres: availableGenres,
                    onGenreSelected: onGenreSelected,
                    onCreateGenre: onCreateGenre,
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
                  child: SizedBox(
                    height: coverSize,
                    child: SingleChildScrollView(child: details),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AlbumMetadataPanel extends StatelessWidget {
  const _AlbumMetadataPanel({
    required this.album,
    required this.availableGenres,
    required this.onGenreSelected,
    required this.onCreateGenre,
  });

  final AlbumInfo album;
  final List<String> availableGenres;
  final ValueChanged<String> onGenreSelected;
  final Future<String?> Function() onCreateGenre;

  @override
  Widget build(BuildContext context) {
    final tracks = album.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetadataSection(
          title: 'Album',
          items: [
            _MetadataItemData('Title', _metadataText(album.title)),
            _MetadataItemData('Artist', _metadataText(album.artist)),
            _MetadataItemData(
              'Year',
              album.year == 0 ? noInfo : '${album.year}',
            ),
            _MetadataItemData(
              'Tracks',
              tracks.isEmpty ? noInfo : '${tracks.length}',
            ),
            _MetadataItemData('Artwork', _metadataText(album.mimeType)),
          ],
          trailing: _GenreMetadataControl(
            genre: _metadataText(album.genre),
            availableGenres: availableGenres,
            onGenreSelected: onGenreSelected,
            onCreateGenre: onCreateGenre,
          ),
        ),
        const SizedBox(height: 14),
        _MetadataSection(
          title: 'Files',
          items: [
            _MetadataItemData(
              'Formats',
              _joinedInfo(_uniqueTrackValues(tracks, (track) => track.format)),
            ),
            _MetadataItemData('Bitrate', _bitrateSummary(tracks)),
            _MetadataItemData(
              'MIME',
              _joinedInfo(
                _uniqueTrackValues(tracks, (track) => track.mimeType),
              ),
            ),
            _MetadataItemData('Total Size', _fileSizeSummary(tracks)),
          ],
        ),
      ],
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({
    required this.title,
    required this.items,
    this.trailing,
  });

  final String title;
  final List<_MetadataItemData> items;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: collection.panel.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: collection.panelBorder.withValues(alpha: 0.72),
                  ),
                ),
                child: SizedBox(
                  width: 132,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: _MetadataItem(item: item),
                  ),
                ),
              ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

class _GenreMetadataControl extends StatelessWidget {
  const _GenreMetadataControl({
    required this.genre,
    required this.availableGenres,
    required this.onGenreSelected,
    required this.onCreateGenre,
  });

  final String genre;
  final List<String> availableGenres;
  final ValueChanged<String> onGenreSelected;
  final Future<String?> Function() onCreateGenre;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;
    final displayedGenre = genre == noInfo ? noInfo : genre;
    final genres = [
      ...availableGenres.where((value) => _metadataText(value) != noInfo),
    ]..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: collection.panel.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: collection.panelBorder.withValues(alpha: 0.72),
        ),
      ),
      child: SizedBox(
        width: 166,
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                tooltip: '',
                enabled: genres.isNotEmpty,
                onSelected: onGenreSelected,
                itemBuilder: (context) => [
                  for (final genre in genres)
                    PopupMenuItem<String>(value: genre, child: Text(genre)),
                ],
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Genre',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayedGenre,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: genres.isEmpty
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final newGenre = await onCreateGenre();
                if (newGenre != null && context.mounted) {
                  onGenreSelected(newGenre);
                }
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({required this.item});

  final _MetadataItemData item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          style: textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          item.value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MetadataItemData {
  const _MetadataItemData(this.label, this.value);

  final String label;
  final String value;
}

const noInfo = 'No Info';

String _metadataText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'n/a') {
    return noInfo;
  }
  return trimmed;
}

List<String> _uniqueTrackValues(
  List<TrackInfo> tracks,
  String Function(TrackInfo track) readValue,
) {
  final values = <String>{};
  for (final track in tracks) {
    final value = _metadataText(readValue(track));
    if (value != noInfo) {
      values.add(value);
    }
  }
  return values.toList()..sort();
}

String _joinedInfo(List<String> values) {
  if (values.isEmpty) {
    return noInfo;
  }
  if (values.length <= 3) {
    return values.join(', ');
  }
  return '${values.take(3).join(', ')} +${values.length - 3}';
}

String _bitrateSummary(List<TrackInfo> tracks) {
  final bitrates =
      tracks
          .map((track) => track.bitrateKbps)
          .where((bitrate) => bitrate > 0)
          .toSet()
          .toList()
        ..sort();
  if (bitrates.isEmpty) {
    return noInfo;
  }
  return bitrates.map((bitrate) => '$bitrate kbps').join(', ');
}

String _fileSizeSummary(List<TrackInfo> tracks) {
  final totalBytes = tracks.fold<int>(
    0,
    (total, track) => total + math.max(track.fileSizeBytes, 0),
  );
  if (totalBytes == 0) {
    return noInfo;
  }

  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (totalBytes >= gb) {
    return '${(totalBytes / gb).toStringAsFixed(2)} GB';
  }
  if (totalBytes >= mb) {
    return '${(totalBytes / mb).toStringAsFixed(1)} MB';
  }
  if (totalBytes >= kb) {
    return '${(totalBytes / kb).toStringAsFixed(1)} KB';
  }
  return '$totalBytes B';
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
