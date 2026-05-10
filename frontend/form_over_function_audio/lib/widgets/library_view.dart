import 'package:flutter/material.dart';

import '../models/album_info.dart';

// Scrollable album browser. It receives already-parsed albums and reports
// track taps back to the page that owns playback state.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.albums,
    required this.selectedTrack,
    required this.onTrackSelected,
  });

  final List<AlbumInfo> albums;
  final TrackInfo? selectedTrack;
  final void Function(AlbumInfo album, TrackInfo track) onTrackSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        return _AlbumTile(
          album: album,
          selectedTrack: selectedTrack,
          onTrackSelected: onTrackSelected,
        );
      },
    );
  }
}

// Displays album metadata, art, and tracks. Missing art falls back to a simple
// album icon so incomplete folders still show in the collection.
class _AlbumTile extends StatelessWidget {
  const _AlbumTile({
    required this.album,
    required this.selectedTrack,
    required this.onTrackSelected,
  });

  final AlbumInfo album;
  final TrackInfo? selectedTrack;
  final void Function(AlbumInfo album, TrackInfo track) onTrackSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final art = ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                album.artUrl,
                width: narrow ? 96 : 132,
                height: narrow ? 96 : 132,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: narrow ? 96 : 132,
                  height: narrow ? 96 : 132,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.album, size: 42),
                ),
              ),
            );

            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.title.isEmpty ? album.location : album.title,
                  style: textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    album.artist.isEmpty ? 'N/A' : album.artist,
                    album.year == 0 ? 'N/A' : album.year.toString(),
                    album.genre.isEmpty ? 'N/A' : album.genre,
                  ].join(' | '),
                  style: textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  album.location,
                  style: textTheme.labelMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                ...album.tracks.map(
                  (track) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selectedTrack?.streamUrl == track.streamUrl
                          ? Icons.graphic_eq
                          : Icons.play_arrow,
                    ),
                    title: Text(track.title, overflow: TextOverflow.ellipsis),
                    onTap: () => onTrackSelected(album, track),
                  ),
                ),
              ],
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
