import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/album_info.dart';

// Persistent bottom playback surface. It renders transport controls and the
// scrubber while the page owns the actual player commands.
class PlayerBar extends StatefulWidget {
  const PlayerBar({
    super.key,
    required this.selectedAlbum,
    required this.selectedTrack,
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
    required this.onSeek,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;
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
  final ValueChanged<double> onSeek;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _panelController.dispose();
    super.dispose();
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
            final collapsedHeight = narrow ? 220.0 : 178.0;
            final expandedHeight = narrow
                ? (screenHeight * 0.68).clamp(420.0, 560.0)
                : (screenHeight * 0.54).clamp(360.0, 460.0);
            final travel = expandedHeight - collapsedHeight;

            final transport = _TransportControls(
              isPlaying: widget.isPlaying,
              canPlayPause: widget.canPlayPause,
              canPlayPrevious: widget.canPlayPrevious,
              canPlayNext: widget.canPlayNext,
              onPlayPause: widget.onPlayPause,
              onPrevious: widget.onPrevious,
              onNext: widget.onNext,
            );

            final trackInfo = _TrackStatus(
              selectedAlbum: widget.selectedAlbum,
              selectedTrack: widget.selectedTrack,
              status: widget.status,
              supportsInlinePlayback: widget.supportsInlinePlayback,
            );

            final scrubber = _Scrubber(
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
                                        child: _CollapsedPlayerContent(
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
                                        child: _ExpandedPlayerContent(
                                          narrow: narrow,
                                          album: widget.selectedAlbum,
                                          trackInfo: trackInfo,
                                          scrubber: scrubber,
                                          transport: transport,
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

class _CollapsedPlayerContent extends StatelessWidget {
  const _CollapsedPlayerContent({
    required this.narrow,
    required this.trackInfo,
    required this.scrubber,
    required this.transport,
  });

  final bool narrow;
  final Widget trackInfo;
  final Widget scrubber;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          trackInfo,
          const SizedBox(height: 8),
          scrubber,
          Align(alignment: Alignment.center, child: transport),
        ],
      );
    }

    return Row(
      children: [
        transport,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(alignment: Alignment.centerLeft, child: trackInfo),
              scrubber,
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedPlayerContent extends StatelessWidget {
  const _ExpandedPlayerContent({
    required this.narrow,
    required this.album,
    required this.trackInfo,
    required this.scrubber,
    required this.transport,
  });

  final bool narrow;
  final AlbumInfo? album;
  final Widget trackInfo;
  final Widget scrubber;
  final Widget transport;

  @override
  Widget build(BuildContext context) {
    final artSize = narrow ? 190.0 : 250.0;
    final art = _PlayerAlbumArt(album: album);

    if (narrow) {
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            SizedBox.square(dimension: artSize, child: art),
            const SizedBox(height: 18),
            Align(alignment: Alignment.centerLeft, child: trackInfo),
            const SizedBox(height: 12),
            scrubber,
            const SizedBox(height: 8),
            transport,
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox.square(dimension: artSize, child: art),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(alignment: Alignment.centerLeft, child: trackInfo),
              const SizedBox(height: 18),
              scrubber,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: transport),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerAlbumArt extends StatelessWidget {
  const _PlayerAlbumArt({required this.album});

  final AlbumInfo? album;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;
    final album = this.album;
    final artUrl = album?.artUrl ?? '';
    final artKey = ValueKey('${album?.location ?? 'no-album'}|$artUrl');

    final art = artUrl.isEmpty
        ? Icon(
            Icons.album,
            key: artKey,
            size: 72,
            color: colorScheme.onSurfaceVariant,
          )
        : Image.network(
            artUrl,
            key: artKey,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.album,
              key: artKey,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: collection.panelBorder),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: collection.glow.withValues(alpha: 0.18),
            blurRadius: 32,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [collection.panelStrong, colorScheme.primaryContainer],
              ),
            ),
            child: ExcludeSemantics(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 560),
                reverseDuration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: SizedBox.expand(key: artKey, child: art),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.isPlaying,
    required this.canPlayPause,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  final bool isPlaying;
  final bool canPlayPause;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: canPlayPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous),
        ),
        IconButton.filled(
          onPressed: canPlayPause ? onPlayPause : null,
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          onPressed: canPlayNext ? onNext : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }
}

class _TrackStatus extends StatelessWidget {
  const _TrackStatus({
    required this.selectedAlbum,
    required this.selectedTrack,
    required this.status,
    required this.supportsInlinePlayback,
  });

  final AlbumInfo? selectedAlbum;
  final TrackInfo? selectedTrack;
  final String? status;
  final bool supportsInlinePlayback;

  @override
  Widget build(BuildContext context) {
    final albumLabel = selectedAlbum == null
        ? null
        : '${selectedAlbum!.artist} | ${selectedAlbum!.title}';
    final trackTitle = selectedTrack?.title ?? 'No track selected';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AnimatedPlayerText(
          text: trackTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (albumLabel != null) _AnimatedPlayerText(text: albumLabel),
        if (selectedTrack != null)
          Text(status ?? '', overflow: TextOverflow.ellipsis)
        else
          Text(
            supportsInlinePlayback
                ? 'Connect to a server and choose a track.'
                : 'This build can browse the server; use the stream URL for playback.',
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _AnimatedPlayerText extends StatelessWidget {
  const _AnimatedPlayerText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 430),
            reverseDuration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.36),
                end: Offset.zero,
              ).animate(animation);

              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: SizedBox(
              key: ValueKey(text),
              width: double.infinity,
              child: Text(text, overflow: TextOverflow.ellipsis, style: style),
            ),
          ),
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
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
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(_formatDuration(position), textAlign: TextAlign.right),
        ),
        Expanded(
          child: Slider(
            value: positionMilliseconds,
            max: maxMilliseconds,
            onChanged: enabled ? onSeek : null,
          ),
        ),
        SizedBox(width: 48, child: Text(_formatDuration(duration))),
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
