// ignore_for_file: deprecated_member_use

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PlayerSnapshot {
  const PlayerSnapshot({
    required this.position,
    required this.duration,
    required this.isPlaying,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
}

class StreamPlayer {
  html.AudioElement? _audio;
  final StreamController<PlayerSnapshot> _snapshotController =
      StreamController<PlayerSnapshot>.broadcast();
  final StreamController<void> _endedController =
      StreamController<void>.broadcast();

  bool get supportsInlinePlayback => true;

  Stream<PlayerSnapshot> get snapshots => _snapshotController.stream;

  Stream<void> get ended => _endedController.stream;

  Stream<String> get errors => const Stream<String>.empty();

  Future<String> play(String streamUrl, {String? serverBaseUrl}) async {
    final audio = _audio ??= _createAudioElement();
    audio
      ..src = streamUrl
      ..load();
    await audio.play();
    _emitSnapshot();
    return 'Playing from ${serverBaseUrl ?? streamUrl}';
  }

  Future<void> resume() async {
    final audio = _audio;
    if (audio == null) {
      return;
    }
    await audio.play();
    _emitSnapshot();
  }

  void pause() {
    _audio?.pause();
    _emitSnapshot();
  }

  void seek(Duration position) {
    final audio = _audio;
    if (audio == null) {
      return;
    }
    audio.currentTime = position.inMilliseconds / 1000;
    _emitSnapshot();
  }

  html.AudioElement _createAudioElement() {
    final audio = html.AudioElement()..preload = 'metadata';
    audio.onTimeUpdate.listen((_) => _emitSnapshot());
    audio.onDurationChange.listen((_) => _emitSnapshot());
    audio.onPlay.listen((_) => _emitSnapshot());
    audio.onPause.listen((_) => _emitSnapshot());
    audio.onEnded.listen((_) {
      _emitSnapshot();
      _endedController.add(null);
    });
    return audio;
  }

  void _emitSnapshot() {
    final audio = _audio;
    if (audio == null || _snapshotController.isClosed) {
      return;
    }
    _snapshotController.add(
      PlayerSnapshot(
        position: _secondsToDuration(audio.currentTime),
        duration: _secondsToDuration(audio.duration),
        isPlaying: !audio.paused,
      ),
    );
  }

  Duration _secondsToDuration(num? seconds) {
    final value = seconds?.toDouble() ?? 0;
    if (value.isNaN || value.isInfinite || value < 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: (value * 1000).round());
  }

  void dispose() {
    _audio?.pause();
    _audio = null;
    _snapshotController.close();
    _endedController.close();
  }
}
