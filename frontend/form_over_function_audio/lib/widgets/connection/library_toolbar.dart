import 'package:flutter/material.dart';

import '../../app_theme.dart';

// Library-page controls shown after a successful connection.
class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.connectedBaseUrl,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onDisconnect,
  });

  final String connectedBaseUrl;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Material(
      elevation: 14,
      shadowColor: collection.glow.withValues(alpha: 0.18),
      color: collection.panelStrong,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final status = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_done, color: colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    connectedBaseUrl,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            );

            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: isRefreshing ? null : onRefresh,
                  style: IconButton.styleFrom(
                    backgroundColor: collection.glow.withValues(alpha: 0.18),
                    foregroundColor: colorScheme.primary,
                    disabledBackgroundColor: collection.panel,
                    disabledForegroundColor: colorScheme.onSurfaceVariant,
                  ),
                  icon: isRefreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                FilledButton.icon(
                  onPressed: onDisconnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
                  ),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            );

            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  status,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: actions),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: status),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
