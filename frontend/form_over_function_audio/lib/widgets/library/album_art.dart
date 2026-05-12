import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';

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
