import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import 'hover_marquee_text.dart';

class TrackTile extends StatefulWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final TrackInfo track;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final titleStyle = Theme.of(context).textTheme.bodyLarge;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hovered
              ? collection.glow.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            splashColor: collection.glow.withValues(alpha: 0.12),
            highlightColor: collection.glow.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    widget.selected ? Icons.graphic_eq : Icons.play_arrow,
                    color: widget.selected
                        ? colorScheme.secondary
                        : colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: HoverMarqueeText(
                      text: widget.track.title,
                      hovered: _hovered,
                      style: titleStyle,
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
