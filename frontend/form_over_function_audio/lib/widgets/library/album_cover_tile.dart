import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/album_info.dart';
import 'album_art.dart';
import 'album_title.dart';

class AlbumCoverTile extends StatefulWidget {
  const AlbumCoverTile({super.key, required this.album, required this.onTap});

  final AlbumInfo album;
  final VoidCallback onTap;

  @override
  State<AlbumCoverTile> createState() => _AlbumCoverTileState();
}

class _AlbumCoverTileState extends State<AlbumCoverTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _spin = CurvedAnimation(
    parent: _spinController,
    curve: Curves.easeInOutCubic,
  );

  bool _hovered = false;
  bool _selecting = false;

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() {
      _hovered = hovered;
    });
  }

  Future<void> _handleTap() async {
    if (_selecting) {
      return;
    }
    setState(() {
      _selecting = true;
    });
    await _spinController.forward(from: 0);
    if (!mounted) {
      return;
    }
    widget.onTap();
    _spinController.value = 0;
    setState(() {
      _selecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;

    return MouseRegion(
      cursor: _selecting ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, child) {
          final angle = _spin.value * math.pi * 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: child,
          );
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 1, end: _hovered ? 1.035 : 1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutQuart,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              transformHitTests: false,
              child: child,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutQuart,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered
                    ? colorScheme.primary.withValues(alpha: 0.62)
                    : collection.panelBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(
                    alpha: _hovered ? 0.46 : 0.28,
                  ),
                  blurRadius: _hovered ? 28 : 18,
                  offset: Offset(0, _hovered ? 16 : 9),
                ),
                BoxShadow(
                  color: collection.glow.withValues(
                    alpha: _hovered ? 0.24 : 0.1,
                  ),
                  blurRadius: _hovered ? 30 : 18,
                  spreadRadius: _hovered ? 1 : 0,
                ),
              ],
            ),
            child: Material(
              color: collection.panel,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _selecting ? null : _handleTap,
                onHighlightChanged: _setHovered,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AlbumArt(album: widget.album, borderRadius: 0),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            albumTitle(widget.album),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.album.artist.isEmpty
                                ? 'N/A'
                                : widget.album.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall,
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
      ),
    );
  }
}
