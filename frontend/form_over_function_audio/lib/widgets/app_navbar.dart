import 'package:flutter/material.dart';

import '../app_theme.dart';

class AppNavDestination {
  const AppNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// Console-menu inspired navigation ribbon.
///
/// Visual language borrows from the PlayStation 3 XrossMediaBar and the
/// GameCube main menu: a glossy dark ribbon with bubbly icons, a soft cyan
/// rim-light, and a strongly emphasized "selected" tab that scales up,
/// gains an icon halo, and surfaces a thin top spine highlight.
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
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Subtle horizontal sheen — gives the bar its "console glass" feel.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              collection.panelStrong.withValues(alpha: 0.96),
              collection.backgroundTop.withValues(alpha: 0.96),
              collection.panelStrong.withValues(alpha: 0.96),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
          border: Border(
            top: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.55),
              width: 1.4,
            ),
            bottom: BorderSide(
              color: collection.panelBorder.withValues(alpha: 0.85),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: collection.glow.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Glossy highlight along the very top edge (PS3-style sheen).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      colorScheme.primary.withValues(alpha: 0.7),
                      Colors.white.withValues(alpha: 0.45),
                      colorScheme.primary.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return _XmbTab(
                    destination: destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
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

class _XmbTab extends StatefulWidget {
  const _XmbTab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_XmbTab> createState() => _XmbTabState();
}

class _XmbTabState extends State<_XmbTab> with SingleTickerProviderStateMixin {
  bool _hovering = false;
  // A breathing glow on the selected tab — very PS3.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    final selected = widget.selected;
    final scale = selected ? 1.0 : (_hovering ? 0.97 : 0.92);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          scale: scale,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final pulse = selected
                  ? 0.5 + 0.5 * _pulseController.value
                  : 0.0;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minWidth: 168),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: selected
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.42),
                            colorScheme.primary.withValues(alpha: 0.18),
                            collection.panelStrong.withValues(alpha: 0.7),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            collection.panel.withValues(
                              alpha: _hovering ? 0.62 : 0.4,
                            ),
                            collection.panelStrong.withValues(
                              alpha: _hovering ? 0.5 : 0.32,
                            ),
                          ],
                        ),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary.withValues(
                            alpha: 0.7 + 0.3 * pulse,
                          )
                        : (_hovering
                              ? collection.panelBorder.withValues(alpha: 0.9)
                              : collection.panelBorder.withValues(alpha: 0.6)),
                    width: selected ? 1.6 : 1.0,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: collection.glow.withValues(
                              alpha: 0.25 + 0.18 * pulse,
                            ),
                            blurRadius: 24 + 8 * pulse,
                            spreadRadius: 0.5,
                          ),
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.32),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: child,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  if (selected)
                    Positioned(
                      top: 0,
                      left: 8,
                      right: 8,
                      height: 1.2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GlowingIcon(
                          icon: widget.destination.icon,
                          selected: selected,
                          hovering: _hovering,
                        ),
                        const SizedBox(width: 12),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          style:
                              Theme.of(context).textTheme.titleSmall!.copyWith(
                                color: selected
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                letterSpacing: selected ? 0.5 : 0.2,
                                fontSize: selected ? 15 : 14,
                                shadows: selected
                                    ? [
                                        Shadow(
                                          color: colorScheme.primary
                                              .withValues(alpha: 0.55),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                              ),
                          child: Text(widget.destination.label),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowingIcon extends StatelessWidget {
  const _GlowingIcon({
    required this.icon,
    required this.selected,
    required this.hovering,
  });

  final IconData icon;
  final bool selected;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final size = selected ? 26.0 : 22.0;
    final color = selected
        ? colorScheme.primary
        : (hovering
              ? colorScheme.onSurface
              : colorScheme.onSurfaceVariant);

    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (selected)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    collection.glow.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          Icon(icon, size: size, color: color),
        ],
      ),
    );
  }
}
