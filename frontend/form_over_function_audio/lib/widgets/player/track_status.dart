import 'package:flutter/material.dart';

import '../../models/album_info.dart';
import 'animated_player_text.dart';

class TrackStatus extends StatelessWidget {
  const TrackStatus({
    super.key,
    required this.selectedAlbum,
    required this.selectedTrack,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final albumLabel = selectedAlbum == null
        ? null
        : '${selectedAlbum!.artist} | ${selectedAlbum!.title}';
    final trackTitle = selectedTrack?.title ?? 'No track selected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedPlayerText(
          text: trackTitle,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        Opacity(
          opacity: albumLabel == null ? 0 : 1,
          child: AnimatedPlayerText(
            text: albumLabel ?? ' ',
            style: textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}
