import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:media_kit/media_kit.dart' as mk;

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
  StreamPlayer() {
    try {
      if (Platform.isLinux) {
        _initializeGStreamerPlayer();
      } else {
        _initializeMediaKitPlayer();
      }
    } on Object catch (error) {
      _startupError = error;
    }
  }

  ap.AudioPlayer? _gstreamerPlayer;
  mk.Player? _mediaKitPlayer;
  final StreamController<PlayerSnapshot> _snapshotController =
      StreamController<PlayerSnapshot>.broadcast();
  final StreamController<void> _endedController =
      StreamController<void>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  Object? _startupError;

  bool get supportsInlinePlayback =>
      _gstreamerPlayer != null || _mediaKitPlayer != null;

  Stream<PlayerSnapshot> get snapshots => _snapshotController.stream;

  Stream<void> get ended => _endedController.stream;

  Stream<String> get errors => _errorController.stream;

  Future<String> play(String streamUrl, {String? serverBaseUrl}) async {
    if (_gstreamerPlayer != null) {
      await _playWithGStreamer(streamUrl);
    } else if (_mediaKitPlayer != null) {
      await _playWithMediaKit(streamUrl);
    } else {
      return 'Audio backend unavailable: $_startupError';
    }

    return 'Playing from ${serverBaseUrl ?? streamUrl}';
  }

  Future<void> resume() async {
    if (_gstreamerPlayer != null) {
      await _gstreamerPlayer!.resume();
    } else {
      await _mediaKitPlayer?.play();
    }
  }

  void pause() {
    if (_gstreamerPlayer != null) {
      unawaited(_gstreamerPlayer!.pause());
    } else {
      unawaited(_mediaKitPlayer?.pause());
    }
  }

  void seek(Duration position) {
    _position = position;
    _emitSnapshot();
    if (_gstreamerPlayer != null) {
      unawaited(_gstreamerPlayer!.seek(position));
    } else {
      unawaited(_mediaKitPlayer?.seek(position));
    }
  }

  void _initializeGStreamerPlayer() {
    final player = ap.AudioPlayer(playerId: 'form_over_function_audio');
    _gstreamerPlayer = player;
    _subscriptions.addAll([
      player.onPositionChanged.listen((position) {
        _position = position;
        _emitSnapshot();
      }),
      player.onDurationChanged.listen((duration) {
        _duration = duration;
        _emitSnapshot();
      }),
      player.onPlayerStateChanged.listen((state) {
        _isPlaying = state == ap.PlayerState.playing;
        _emitSnapshot();
      }),
      player.onPlayerComplete.listen((_) {
        _position = _duration;
        _isPlaying = false;
        _emitSnapshot();
        _endedController.add(null);
      }),
    ]);
  }

  void _initializeMediaKitPlayer() {
    mk.MediaKit.ensureInitialized();
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(
        bufferSize: 64 * 1024 * 1024,
        protocolWhitelist: ['file', 'http', 'https', 'tcp', 'tls'],
        title: 'Form Over Function Audio',
      ),
    );
    _mediaKitPlayer = player;
    _subscriptions.addAll([
      player.stream.position.listen((position) {
        _position = position;
        _emitSnapshot();
      }),
      player.stream.duration.listen((duration) {
        _duration = duration;
        _emitSnapshot();
      }),
      player.stream.playing.listen((playing) {
        _isPlaying = playing;
        _emitSnapshot();
      }),
      player.stream.completed.listen((completed) {
        if (!completed) {
          return;
        }
        _position = _duration;
        _isPlaying = false;
        _emitSnapshot();
        _endedController.add(null);
      }),
      player.stream.error.listen((error) {
        _isPlaying = false;
        _emitSnapshot();
        _errorController.add(error);
      }),
    ]);
  }

  Future<void> _playWithGStreamer(String streamUrl) async {
    final player = _gstreamerPlayer!;
    await player.stop();
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _emitSnapshot();
    final cachedFile = await _cacheStreamForLinux(streamUrl);
    await player.play(
      ap.DeviceFileSource(
        cachedFile.path,
        mimeType: _mimeTypeForStreamURL(streamUrl),
      ),
      mode: ap.PlayerMode.mediaPlayer,
    );
    _isPlaying = true;
    _emitSnapshot();
  }

  Future<void> _playWithMediaKit(String streamUrl) async {
    final player = _mediaKitPlayer!;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _emitSnapshot();
    await player.open(mk.Media(streamUrl), play: true);
    _isPlaying = true;
    _emitSnapshot();
  }

  Future<File> _cacheStreamForLinux(String streamUrl) async {
    final cacheDir = Directory('${Directory.systemTemp.path}/fof_audio_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = _extensionForStreamURL(streamUrl);
    final cacheFile = File(
      '${cacheDir.path}/${streamUrl.hashCode.toUnsigned(32).toRadixString(16)}$ext',
    );
    if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
      return cacheFile;
    }

    final partialFile = File('${cacheFile.path}.part');
    if (partialFile.existsSync()) {
      partialFile.deleteSync();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(streamUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'server returned ${response.statusCode}',
          uri: Uri.parse(streamUrl),
        );
      }

      await response.pipe(partialFile.openWrite());
      if (cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
      partialFile.renameSync(cacheFile.path);
      return cacheFile;
    } finally {
      client.close(force: true);
    }
  }

  String _extensionForStreamURL(String streamUrl) {
    final uri = Uri.tryParse(streamUrl);
    final streamedPath = uri?.queryParameters['path'];
    final path =
        streamedPath ??
        (uri?.pathSegments.isNotEmpty == true
            ? uri!.pathSegments.last
            : streamUrl);
    final match = RegExp(r'\.[A-Za-z0-9]+$').firstMatch(path);
    return match == null ? '.audio' : match.group(0)!.toLowerCase();
  }

  String? _mimeTypeForStreamURL(String streamUrl) {
    return switch (_extensionForStreamURL(streamUrl)) {
      '.mp3' => 'audio/mpeg',
      '.flac' => 'audio/flac',
      '.wav' => 'audio/wav',
      _ => null,
    };
  }

  void _emitSnapshot() {
    if (_snapshotController.isClosed) {
      return;
    }
    _snapshotController.add(
      PlayerSnapshot(
        position: _position,
        duration: _duration,
        isPlaying: _isPlaying,
      ),
    );
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final gstreamerPlayer = _gstreamerPlayer;
    if (gstreamerPlayer != null) {
      unawaited(gstreamerPlayer.stop());
      unawaited(gstreamerPlayer.dispose());
    }
    final mediaKitPlayer = _mediaKitPlayer;
    if (mediaKitPlayer != null) {
      unawaited(mediaKitPlayer.stop());
      unawaited(mediaKitPlayer.dispose());
    }
    _snapshotController.close();
    _endedController.close();
    _errorController.close();
  }
}
