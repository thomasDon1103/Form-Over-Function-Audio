import 'package:flutter/material.dart';

import '../models/album_info.dart';
import 'library/album_cover_tile.dart';
import 'library/album_reveal.dart';

export 'library/album_art.dart';
export 'library/album_detail_view.dart';

// Cover-first album browser. Track playback stays owned by the page so the
// persistent player can survive navigation between this grid and album detail.
class LibraryView extends StatelessWidget {
  const LibraryView({
    super.key,
    required this.albums,
    required this.onAlbumSelected,
    this.revealingAlbumLocations = const <String>[],
    this.fadingAlbumLocations = const <String>[],
    this.hiddenAlbumLocation,
  });

  final List<AlbumInfo> albums;
  final void Function(AlbumInfo album, Rect? artBounds) onAlbumSelected;
  final List<String> revealingAlbumLocations;
  final List<String> fadingAlbumLocations;
  final String? hiddenAlbumLocation;

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
        final tile = AlbumCoverTile(
          key: ValueKey('album-${album.location}'),
          album: album,
          onTap: (artBounds) => onAlbumSelected(album, artBounds),
        );
        final hidden = album.location == hiddenAlbumLocation;
        final visibleTile = AnimatedOpacity(
          opacity: hidden ? 0 : 1,
          duration: const Duration(milliseconds: 420),
          curve: hidden ? Curves.easeOutCubic : Curves.easeInCubic,
          child: IgnorePointer(ignoring: hidden, child: tile),
        );

        final revealIndex = revealingAlbumLocations.indexOf(album.location);
        final fadeIndex = fadingAlbumLocations.indexOf(album.location);
        if (fadeIndex != -1) {
          return AlbumFadeOut(
            key: ValueKey('album-fade-out-${album.location}'),
            child: visibleTile,
          );
        }

        if (revealIndex == -1) {
          return visibleTile;
        }

        return AlbumReveal(
          key: ValueKey('album-reveal-${album.location}'),
          delay: Duration(milliseconds: revealIndex * 140),
          child: visibleTile,
        );
      },
    );
  }
}
