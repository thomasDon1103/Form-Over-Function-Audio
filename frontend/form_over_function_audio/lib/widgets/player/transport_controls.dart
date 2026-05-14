import 'package:flutter/material.dart';

class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
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
    final compactButtonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(50),
      iconSize: 32,
    );
    final primaryButtonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(58),
      iconSize: 36,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: canPlayPrevious ? onPrevious : null,
          style: compactButtonStyle,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 14),
        IconButton.filled(
          onPressed: canPlayPause ? onPlayPause : null,
          style: primaryButtonStyle,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 14),
        IconButton(
          onPressed: canPlayNext ? onNext : null,
          style: compactButtonStyle,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}
