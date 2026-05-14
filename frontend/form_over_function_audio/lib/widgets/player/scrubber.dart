import 'package:flutter/material.dart';

class Scrubber extends StatelessWidget {
  const Scrubber({
    super.key,
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
    final timestampStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);

    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            _formatDuration(position),
            textAlign: TextAlign.right,
            style: timestampStyle,
          ),
        ),
        Expanded(
          child: Slider(
            value: positionMilliseconds,
            max: maxMilliseconds,
            onChanged: enabled ? onSeek : null,
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(_formatDuration(duration), style: timestampStyle),
        ),
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
