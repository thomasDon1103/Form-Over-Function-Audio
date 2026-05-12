import 'package:flutter/material.dart';

import '../../app_theme.dart';

// First screen shown before a server is connected. The parent owns networking
// and process-start behavior so this widget can stay presentation-focused.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.controller,
    required this.status,
    required this.isLoading,
    required this.isStartingServer,
    required this.canStartServer,
    required this.onConnect,
    required this.onStartServer,
  });

  final TextEditingController controller;
  final String? status;
  final bool isLoading;
  final bool isStartingServer;
  final bool canStartServer;
  final VoidCallback onConnect;
  final VoidCallback onStartServer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final textTheme = Theme.of(context).textTheme;
    final busy = isLoading || isStartingServer;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            color: collection.panelStrong,
            elevation: 18,
            shadowColor: collection.glow.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: collection.panelBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.library_music,
                    size: 52,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connect to server',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: controller,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Audio server address',
                      prefixIcon: Icon(Icons.dns),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!busy) {
                        onConnect();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : onConnect,
                    icon: isLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('Connect'),
                  ),
                  if (canStartServer) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onStartServer,
                      icon: isStartingServer
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.power_settings_new),
                      label: const Text('Start Server'),
                    ),
                  ],
                  if (status != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      status!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
