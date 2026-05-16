import 'package:flutter/material.dart';

import '../../models/album_info.dart';
import '../../models/playback_queue_item.dart';
import 'player_album_art.dart';
import 'queue_list.dart';

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
    required this.queue,
    required this.onQueueItemSelected,
  });

  final bool narrow;
  final AlbumInfo? album;
  final Animation<double> recordTurns;
  final Widget trackInfo;
  final Widget scrubber;
  final Widget transport;
  final List<PlaybackQueueItem> queue;
  final ValueChanged<int> onQueueItemSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = narrow || constraints.maxWidth < 980;
        final artSize = compact ? 190.0 : 250.0;
        final artWidth = artSize * 1.52;
        final art = PlayerAlbumArt(
          album: album,
          recordTurns: recordTurns,
          size: artSize,
        );
        final queueList = QueueList(
          queue: queue,
          onItemSelected: onQueueItemSelected,
        );

        if (compact) {
          return Column(
            children: [
              SizedBox(width: artWidth, height: artSize, child: art),
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft, child: trackInfo),
              const SizedBox(height: 12),
              scrubber,
              const SizedBox(height: 8),
              transport,
              const SizedBox(height: 12),
              Expanded(child: queueList),
            ],
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
            const SizedBox(width: 24),
            SizedBox(width: 330, child: queueList),
          ],
        );
      },
    );
  }
}
