import 'dart:async';

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
  final StreamController<PlayerSnapshot> _snapshotController =
      StreamController<PlayerSnapshot>.broadcast();
  final StreamController<void> _endedController =
      StreamController<void>.broadcast();

  bool get supportsInlinePlayback => false;

  Stream<PlayerSnapshot> get snapshots => _snapshotController.stream;

  Stream<void> get ended => _endedController.stream;

  Stream<String> get errors => const Stream<String>.empty();

  Future<String> play(String streamUrl, {String? serverBaseUrl}) async {
    return 'Stream URL: ${serverBaseUrl ?? streamUrl}';
  }

  Future<void> resume() async {}

  void pause() {}

  void seek(Duration position) {}

  void dispose() {
    _snapshotController.close();
    _endedController.close();
  }
}
