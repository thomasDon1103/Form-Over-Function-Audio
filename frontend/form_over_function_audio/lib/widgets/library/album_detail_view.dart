import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import 'album_art.dart';
import 'album_title.dart';
import 'entrance_fade_slide.dart';
import 'track_tile.dart';

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
        EntranceFadeSlide(
          interval: const Interval(0, 0.72, curve: Curves.easeOutQuart),
          child: _AlbumHeader(album: album, onBack: onBack),
        ),
        const SizedBox(height: 16),
        EntranceFadeSlide(
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
                  TrackTile(
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
