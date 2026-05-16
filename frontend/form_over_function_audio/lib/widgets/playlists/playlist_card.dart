import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import '../../models/playlist_info.dart';
import '../library/album_art.dart';

class PlaylistCard extends StatefulWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.previewAlbums,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final PlaylistInfo playlist;
  final List<AlbumInfo> previewAlbums;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
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
              color: colorScheme.primary.withValues(
                alpha: _hovered ? 0.95 : 0.72,
              ),
              width: _hovered ? 1.6 : 1.1,
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
                    child: PlaylistPreview(albums: widget.previewAlbums),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.playlist.tracks.length} song${widget.playlist.tracks.length == 1 ? '' : 's'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<_PlaylistAction>(
                          tooltip: '',
                          position: PopupMenuPosition.under,
                          onSelected: (action) {
                            switch (action) {
                              case _PlaylistAction.rename:
                                widget.onRename();
                              case _PlaylistAction.delete:
                                widget.onDelete();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _PlaylistAction.rename,
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: _PlaylistAction.delete,
                              child: Text('Delete'),
                            ),
                          ],
                          icon: const Icon(Icons.more_horiz),
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

enum _PlaylistAction { rename, delete }

class PlaylistPreview extends StatelessWidget {
  const PlaylistPreview({super.key, required this.albums});

  final List<AlbumInfo> albums;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final previewAlbums = albums.take(4).toList();

    if (previewAlbums.isEmpty) {
      return ColoredBox(
        color: collection.panelStrong,
        child: Center(
          child: Icon(
            Icons.queue_music,
            color: colorScheme.primary.withValues(alpha: 0.74),
            size: 52,
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: previewAlbums.length == 1 ? 1 : 2,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      children: [
        for (final album in previewAlbums)
          AlbumArt(album: album, borderRadius: 0),
      ],
    );
  }
}
