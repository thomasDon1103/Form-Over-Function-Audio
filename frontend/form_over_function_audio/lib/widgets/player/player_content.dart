import 'package:flutter/material.dart';

import '../../models/album_info.dart';
import 'player_album_art.dart';

class CollapsedPlayerContent extends StatelessWidget {
  const CollapsedPlayerContent({
    super.key,
    required this.narrow,
    required this.trackInfo,
    required this.scrubber,
    required this.transport,
  });

  final bool narrow;
  final Widget trackInfo;
  final Widget scrubber;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          trackInfo,
          const SizedBox(height: 8),
          scrubber,
          Align(alignment: Alignment.center, child: transport),
        ],
      );
    }

    return Row(
      children: [
        transport,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, child: trackInfo),
              scrubber,
            ],
          ),
        ),
      ],
    );
  }
}

class ExpandedPlayerContent extends StatelessWidget {
  const ExpandedPlayerContent({
    super.key,
    required this.narrow,
    required this.album,
    required this.recordTurns,
    required this.trackInfo,
    required this.scrubber,
    required this.transport,
  });

  final bool narrow;
  final AlbumInfo? album;
  final Animation<double> recordTurns;
  final Widget trackInfo;
  final Widget scrubber;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    final artSize = narrow ? 190.0 : 250.0;
    final artWidth = artSize * 1.52;
    final art = PlayerAlbumArt(
      album: album,
      recordTurns: recordTurns,
      size: artSize,
    );

    if (narrow) {
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SizedBox(width: artWidth, height: artSize, child: art),
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerLeft, child: trackInfo),
            const SizedBox(height: 12),
            scrubber,
            const SizedBox(height: 8),
            transport,
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(width: artWidth, height: artSize, child: art),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(alignment: Alignment.centerLeft, child: trackInfo),
              const SizedBox(height: 18),
              scrubber,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: transport),
            ],
          ),
        ),
      ],
    );
  }
}
