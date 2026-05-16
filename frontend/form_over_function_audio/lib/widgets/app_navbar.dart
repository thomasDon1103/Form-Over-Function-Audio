import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppNavDestination {
  const AppNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class AppNavbar extends StatelessWidget {
  const AppNavbar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return Material(
      color: collection.panelStrong.withValues(alpha: 0.78),
      elevation: 8,
      shadowColor: collection.glow.withValues(alpha: 0.12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: collection.panelBorder.withValues(alpha: 0.7),
            ),
            bottom: BorderSide(
              color: collection.panelBorder.withValues(alpha: 0.85),
            ),
          ),
        ),
        child: SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: destinations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return _NavbarSection(
                destination: destinations[index],
                selected: index == selectedIndex,
                onTap: () => onSelected(index),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavbarSection extends StatelessWidget {
  const _NavbarSection({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minWidth: 150),
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.18)
            : collection.panel.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? colorScheme.primary : collection.panelBorder,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: collection.glow.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                destination.icon,
                size: 19,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Text(
                destination.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
