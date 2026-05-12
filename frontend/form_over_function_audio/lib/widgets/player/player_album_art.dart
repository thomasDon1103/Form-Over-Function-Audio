import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import 'vinyl_record.dart';

class PlayerAlbumArt extends StatelessWidget {
  const PlayerAlbumArt({
    super.key,
    required this.album,
    required this.recordTurns,
    required this.size,
  });

  final AlbumInfo? album;
  final Animation<double> recordTurns;
  final double size;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;
    final album = this.album;
    final artUrl = album?.artUrl ?? '';
    final artKey = ValueKey('${album?.location ?? 'no-album'}|$artUrl');

    final art = artUrl.isEmpty
        ? Icon(
            Icons.album,
            key: artKey,
            size: 72,
            color: colorScheme.onSurfaceVariant,
          )
        : Image.network(
            artUrl,
            key: artKey,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.album,
              key: artKey,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    final cover = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: collection.panelBorder),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: collection.glow.withValues(alpha: 0.18),
            blurRadius: 32,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [collection.panelStrong, colorScheme.primaryContainer],
              ),
            ),
            child: ExcludeSemantics(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 560),
                reverseDuration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: SizedBox.expand(key: artKey, child: art),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: size * 0.46,
          top: 0,
          width: size,
          height: size,
          child: RotationTransition(
            turns: recordTurns,
            child: const VinylRecord(),
          ),
        ),
        Positioned(left: 0, top: 0, width: size, height: size, child: cover),
      ],
    );
  }
}
