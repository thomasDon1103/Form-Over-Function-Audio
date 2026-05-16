import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/playback_queue_item.dart';

class QueueList extends StatelessWidget {
  const QueueList({
    super.key,
    required this.queue,
    required this.onItemSelected,
  });

  final List<PlaybackQueueItem> queue;
  final ValueChanged<int> onItemSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: collection.panel.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: collection.panelBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.queue_music, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text('Queue', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${queue.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        'No songs queued',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: queue.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        return _QueueTile(
                          item: queue[index],
                          playing: index == 0,
                          onTap: () => onItemSelected(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.item,
    required this.playing,
    required this.onTap,
  });

  final PlaybackQueueItem item;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final albumLabel = '${item.album.artist} | ${item.album.title}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: playing
            ? colorScheme.primary.withValues(alpha: 0.18)
            : collection.panelStrong.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: playing ? colorScheme.primary : collection.panelBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                playing ? Icons.play_arrow : Icons.music_note,
                color: playing
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: playing ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      albumLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
