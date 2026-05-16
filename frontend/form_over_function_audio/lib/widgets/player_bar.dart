import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/album_info.dart';
import '../models/playback_queue_item.dart';
import 'player/player_content.dart';
import 'player/scrubber.dart';
import 'player/track_status.dart';
import 'player/transport_controls.dart';

// Persistent bottom playback surface. It renders transport controls and the
// scrubber while the page owns the actual player commands.
class PlayerBar extends StatefulWidget {
  const PlayerBar({
    super.key,
    required this.selectedAlbum,
    required this.selectedTrack,
    required this.queue,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.canPlayPause,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.status,
    required this.supportsInlinePlayback,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onQueueItemSelected,
    required this.onSeek,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;
  final List<PlaybackQueueItem> queue;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool canPlayPause;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final String? status;
  final bool supportsInlinePlayback;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int> onQueueItemSelected;
  final ValueChanged<double> onSeek;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> with TickerProviderStateMixin {
  late final AnimationController _panelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _recordController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    _syncRecordRotation();
  }

  @override
  void didUpdateWidget(covariant PlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncRecordRotation();
    }
  }

  @override
  void dispose() {
    _panelController.dispose();
    _recordController.dispose();
    super.dispose();
  }

  void _syncRecordRotation() {
    if (widget.isPlaying) {
      _recordController.repeat();
    } else {
      _recordController.stop();
    }
  }

  void _togglePanel() {
    if (_panelController.value > 0.5) {
      _animatePanelTo(0);
    } else {
      _animatePanelTo(1);
    }
  }

  void _handleDragUpdate(DragUpdateDetails details, double travel) {
    _panelController.value -= details.primaryDelta! / travel;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -240) {
      _animatePanelTo(1);
      return;
    }
    if (velocity > 240) {
      _animatePanelTo(0);
      return;
    }
    _animatePanelTo(_panelController.value >= 0.5 ? 1 : 0);
  }

  void _animatePanelTo(double value) {
    _panelController.animateTo(
      value,
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final maxMilliseconds = widget.duration.inMilliseconds <= 0
        ? 1.0
        : widget.duration.inMilliseconds.toDouble();
    final positionMilliseconds = widget.position.inMilliseconds
        .clamp(0, maxMilliseconds.toInt())
        .toDouble();
    final playerLabel = _playerSemanticsLabel(
      album: widget.selectedAlbum,
      track: widget.selectedTrack,
      supportsInlinePlayback: widget.supportsInlinePlayback,
    );

    return Semantics(
      container: true,
      label: playerLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 680;
            final screenHeight = MediaQuery.sizeOf(context).height;
            final collapsedHeight = narrow ? 236.0 : 194.0;
            final expandedHeight = narrow
                ? (screenHeight * 0.68).clamp(420.0, 560.0)
                : (screenHeight * 0.54).clamp(360.0, 460.0);
            final travel = expandedHeight - collapsedHeight;

            final transport = TransportControls(
              isPlaying: widget.isPlaying,
              canPlayPause: widget.canPlayPause,
              canPlayPrevious: widget.canPlayPrevious,
              canPlayNext: widget.canPlayNext,
              onPlayPause: widget.onPlayPause,
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
            );

            final trackInfo = TrackStatus(
              selectedAlbum: widget.selectedAlbum,
              selectedTrack: widget.selectedTrack,
            );

            final scrubber = Scrubber(
              position: widget.position,
              duration: widget.duration,
              positionMilliseconds: positionMilliseconds,
              maxMilliseconds: maxMilliseconds,
              enabled: widget.selectedTrack != null,
              onSeek: widget.onSeek,
            );

            return AnimatedBuilder(
              animation: _panelController,
              builder: (context, child) {
                final extent = Curves.easeOutCubic.transform(
                  _panelController.value,
                );
                final height =
                    collapsedHeight +
                    ((expandedHeight - collapsedHeight) * extent);
                final collapsedOpacity = (1 - (extent / 0.36)).clamp(0.0, 1.0);
                final expandedOpacity = ((extent - 0.32) / 0.68).clamp(
                  0.0,
                  1.0,
                );

                return Material(
                  elevation: 18,
                  shadowColor: collection.glow.withValues(alpha: 0.24),
                  color: collection.panelStrong,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: collection.panelBorder,
                          width: 1.2,
                        ),
                      ),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      excludeFromSemantics: true,
                      onTap: _togglePanel,
                      onVerticalDragUpdate: (details) =>
                          _handleDragUpdate(details, travel),
                      onVerticalDragEnd: _handleDragEnd,
                      child: SizedBox(
                        height: height,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            children: [
                              _PlayerHandle(
                                expanded: _panelController.value > 0.5,
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (collapsedOpacity > 0)
                                      Opacity(
                                        opacity: collapsedOpacity,
                                        child: IgnorePointer(
                                          ignoring: extent > 0.08,
                                          child: CollapsedPlayerContent(
                                            narrow: narrow,
                                            trackInfo: trackInfo,
                                            scrubber: scrubber,
                                            transport: transport,
                                          ),
                                        ),
                                      ),
                                    if (expandedOpacity > 0)
                                      Opacity(
                                        opacity: expandedOpacity,
                                        child: IgnorePointer(
                                          ignoring: extent < 0.92,
                                          child: ExpandedPlayerContent(
                                            narrow: narrow,
                                            album: widget.selectedAlbum,
                                            recordTurns: _recordController,
                                            trackInfo: trackInfo,
                                            scrubber: scrubber,
                                            transport: transport,
                                            queue: widget.queue,
                                            onQueueItemSelected:
                                                widget.onQueueItemSelected,
                                          ),
                                        ),
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
              },
            );
          },
        ),
      ),
    );
  }

  String _playerSemanticsLabel({
    required AlbumInfo? album,
    required TrackInfo? track,
    required bool supportsInlinePlayback,
  }) {
    if (track == null) {
      return supportsInlinePlayback
          ? 'Player. No track selected.'
          : 'Player. No track selected. This build can browse the server.';
    }

    final albumText = album == null
        ? ''
        : ' from ${album.artist}, ${album.title}';
    return 'Player. ${track.title}$albumText.';
  }
}

class _PlayerHandle extends StatelessWidget {
  const _PlayerHandle({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Icon(
      expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
      size: 28,
      color: colorScheme.primary,
    );
  }
}
