import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/album_info.dart';

// Persistent bottom playback surface. It renders transport controls and the
// scrubber while the page owns the actual player commands.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.selectedAlbum,
    required this.selectedTrack,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.canPlayPause,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.status,
    required this.supportsInlinePlayback,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onSeek,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool canPlayPause;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final String? status;
  final bool supportsInlinePlayback;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final maxMilliseconds = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final positionMilliseconds = position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();

    return Material(
      elevation: 18,
      shadowColor: collection.glow.withValues(alpha: 0.24),
      color: collection.panelStrong,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 680;
            final transport = _TransportControls(
              isPlaying: isPlaying,
              canPlayPause: canPlayPause,
              canPlayPrevious: canPlayPrevious,
              canPlayNext: canPlayNext,
              onPlayPause: onPlayPause,
              onPrevious: onPrevious,
              onNext: onNext,
            );

            final trackInfo = _TrackStatus(
              selectedAlbum: selectedAlbum,
              selectedTrack: selectedTrack,
              status: status,
              supportsInlinePlayback: supportsInlinePlayback,
            );

            final scrubber = _Scrubber(
              position: position,
              duration: duration,
              positionMilliseconds: positionMilliseconds,
              maxMilliseconds: maxMilliseconds,
              enabled: selectedTrack != null,
              onSeek: onSeek,
            );

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
          },
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.isPlaying,
    required this.canPlayPause,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isPlaying;
  final bool canPlayPause;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: canPlayPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          onPressed: canPlayPause ? onPlayPause : null,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          onPressed: canPlayNext ? onNext : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}

class _TrackStatus extends StatelessWidget {
  const _TrackStatus({
    required this.selectedAlbum,
    required this.selectedTrack,
    required this.status,
    required this.supportsInlinePlayback,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;
  final String? status;
  final bool supportsInlinePlayback;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          selectedTrack?.title ?? 'No track selected',
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (selectedAlbum != null)
          Text(
            '${selectedAlbum!.artist} | ${selectedAlbum!.title}',
            overflow: TextOverflow.ellipsis,
          ),
        if (selectedTrack != null)
          Text(status ?? '', overflow: TextOverflow.ellipsis)
        else
          Text(
            supportsInlinePlayback
                ? 'Connect to a server and choose a track.'
                : 'This build can browse the server; use the stream URL for playback.',
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.position,
    required this.duration,
    required this.positionMilliseconds,
    required this.maxMilliseconds,
    required this.enabled,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final double positionMilliseconds;
  final double maxMilliseconds;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(_formatDuration(position), textAlign: TextAlign.right),
        ),
        Expanded(
          child: Slider(
            value: positionMilliseconds,
            max: maxMilliseconds,
            onChanged: enabled ? onSeek : null,
          ),
        ),
        SizedBox(width: 48, child: Text(_formatDuration(duration))),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
