import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import '../../models/playlist_info.dart';
import '../empty_state.dart';
import '../library/track_tile.dart';
import 'playlist_card.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({
    super.key,
    required this.playlists,
    required this.previewAlbumsByPlaylist,
    required this.selectedPlaylist,
    required this.selectedTracks,
    required this.selectedTrack,
    required this.onPlaylistSelected,
    required this.onCreatePlaylist,
    required this.onBack,
    required this.onRenamePlaylist,
    required this.onDeletePlaylist,
    required this.onTrackSelected,
    required this.onTrackQueued,
    required this.onTrackRemoved,
  });

  final List<PlaylistInfo> playlists;
  final Map<String, List<AlbumInfo>> previewAlbumsByPlaylist;
  final PlaylistInfo? selectedPlaylist;
  final List<ResolvedPlaylistTrack> selectedTracks;
  final TrackInfo? selectedTrack;
  final ValueChanged<PlaylistInfo> onPlaylistSelected;
  final VoidCallback onCreatePlaylist;
  final VoidCallback onBack;
  final ValueChanged<PlaylistInfo> onRenamePlaylist;
  final ValueChanged<PlaylistInfo> onDeletePlaylist;
  final ValueChanged<ResolvedPlaylistTrack> onTrackSelected;
  final ValueChanged<ResolvedPlaylistTrack> onTrackQueued;
  final ValueChanged<ResolvedPlaylistTrack> onTrackRemoved;

  @override
  Widget build(BuildContext context) {
    final playlist = selectedPlaylist;
    if (playlist != null) {
      return _PlaylistDetail(
        playlist: playlist,
        previewAlbums: previewAlbumsByPlaylist[playlist.id] ?? const [],
        tracks: selectedTracks,
        selectedTrack: selectedTrack,
        onBack: onBack,
        onRename: () => onRenamePlaylist(playlist),
        onDelete: () => onDeletePlaylist(playlist),
        onTrackSelected: onTrackSelected,
        onTrackQueued: onTrackQueued,
        onTrackRemoved: onTrackRemoved,
      );
    }

    return Column(
      children: [
        _PlaylistsActions(onCreatePlaylist: onCreatePlaylist),
        Expanded(
          child: playlists.isEmpty
              ? const EmptyState(
                  key: ValueKey('empty-playlists'),
                  status: 'No playlists yet.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 24,
                    childAspectRatio: 0.76,
                  ),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return PlaylistCard(
                      key: ValueKey('playlist-${playlist.id}'),
                      playlist: playlist,
                      previewAlbums:
                          previewAlbumsByPlaylist[playlist.id] ?? const [],
                      onTap: () => onPlaylistSelected(playlist),
                      onRename: () => onRenamePlaylist(playlist),
                      onDelete: () => onDeletePlaylist(playlist),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlaylistsActions extends StatelessWidget {
  const _PlaylistsActions({required this.onCreatePlaylist});

  final VoidCallback onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: onCreatePlaylist,
          style: FilledButton.styleFrom(
            backgroundColor: collection.glow.withValues(alpha: 0.2),
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: collection.panelBorder),
          ),
          icon: const Icon(Icons.add),
          label: const Text('New Playlist'),
        ),
      ),
    );
  }
}

class _PlaylistDetail extends StatelessWidget {
  const _PlaylistDetail({
    required this.playlist,
    required this.previewAlbums,
    required this.tracks,
    required this.selectedTrack,
    required this.onBack,
    required this.onRename,
    required this.onDelete,
    required this.onTrackSelected,
    required this.onTrackQueued,
    required this.onTrackRemoved,
  });

  final PlaylistInfo playlist;
  final List<AlbumInfo> previewAlbums;
  final List<ResolvedPlaylistTrack> tracks;
  final TrackInfo? selectedTrack;
  final VoidCallback onBack;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<ResolvedPlaylistTrack> onTrackSelected;
  final ValueChanged<ResolvedPlaylistTrack> onTrackQueued;
  final ValueChanged<ResolvedPlaylistTrack> onTrackRemoved;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: collection.panelStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: collection.panelBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;
                final art = SizedBox.square(
                  dimension: narrow ? 180 : 240,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: collection.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: collection.panelBorder),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PlaylistPreview(albums: previewAlbums),
                    ),
                  ),
                );
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: onBack,
                          style: IconButton.styleFrom(
                            backgroundColor: collection.glow.withValues(
                              alpha: 0.18,
                            ),
                            foregroundColor: colorScheme.primary,
                          ),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          onPressed: onRename,
                          style: IconButton.styleFrom(
                            backgroundColor: collection.glow.withValues(
                              alpha: 0.18,
                            ),
                            foregroundColor: colorScheme.primary,
                          ),
                          icon: const Icon(Icons.edit),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: onDelete,
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.error.withValues(
                              alpha: 0.16,
                            ),
                            foregroundColor: colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      playlist.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${tracks.length} song${tracks.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
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
                    const SizedBox(width: 24),
                    Expanded(child: details),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: collection.panelStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: collection.panelBorder),
          ),
          child: tracks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No songs in this playlist yet.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final item in tracks)
                      TrackTile(
                        track: item.track,
                        selected:
                            selectedTrack?.streamUrl == item.track.streamUrl,
                        onTap: () => onTrackSelected(item),
                        onQueueTap: () => onTrackQueued(item),
                        onRemoveTap: () => onTrackRemoved(item),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
