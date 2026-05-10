import 'package:flutter/material.dart';

// Top-level controls for choosing, starting, refreshing, and connecting to
// an audio server. The parent owns the actual networking actions.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({
    super.key,
    required this.controller,
    required this.connectedBaseUrl,
    required this.isLoading,
    required this.isStartingServer,
    required this.isRefreshing,
    required this.canStartServer,
    required this.onConnect,
    required this.onRefresh,
    required this.onStartServer,
  });

  final TextEditingController controller;
  final String? connectedBaseUrl;
  final bool isLoading;
  final bool isStartingServer;
  final bool isRefreshing;
  final bool canStartServer;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;
  final VoidCallback onStartServer;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 1,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 760;
            final controls = [
              if (canStartServer)
                FilledButton.icon(
                  onPressed: isStartingServer ? null : onStartServer,
                  icon: isStartingServer
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: const Text('Start server'),
                ),
              FilledButton.tonalIcon(
                onPressed: isLoading ? null : onConnect,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Connect'),
              ),
              IconButton.filledTonal(
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Refresh library',
              ),
            ];

            final addressField = TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Audio server address',
                prefixIcon: const Icon(Icons.dns),
                helperText: connectedBaseUrl == null
                    ? 'Use the LAN address shown by the host server.'
                    : 'Connected to $connectedBaseUrl',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) => onConnect(),
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  addressField,
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: controls),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: addressField),
                const SizedBox(width: 12),
                Wrap(spacing: 8, runSpacing: 8, children: controls),
              ],
            );
          },
        ),
      ),
    );
  }
}
