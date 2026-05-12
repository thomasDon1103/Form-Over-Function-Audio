import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_theme.dart';
import '../models/album_info.dart';
import '../server_control.dart';
import '../stream_player.dart';
import '../widgets/connection_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_view.dart';
import '../widgets/player_bar.dart';
import '../widgets/transition_veil.dart';

// Main screen for the audio streamer. This class coordinates server access,
// library state, and player commands while the widgets render the UI sections.
class AudioHomePage extends StatefulWidget {
  const AudioHomePage({super.key});

  @override
  State<AudioHomePage> createState() => _AudioHomePageState();
}

class _AudioHomePageState extends State<AudioHomePage> {
  final TextEditingController _serverController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final StreamPlayer _player = StreamPlayer();
  final ServerControl _serverControl = ServerControl();

  List<AlbumInfo> _albums = <AlbumInfo>[];
  List<String> _revealingAlbumLocations = <String>[];
  List<String> _fadingAlbumLocations = <String>[];
  AlbumInfo? _browsingAlbum;
  Rect? _openingAlbumArtRect;
  bool _albumDetailVisible = false;
  AlbumInfo? _selectedAlbum;
  TrackInfo? _selectedTrack;
  int? _selectedTrackIndex;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  String? _connectedBaseUrl;
  String? _status;
  bool _isLoading = false;
  bool _isStartingServer = false;
  bool _isRefreshing = false;
  bool _screenVeilVisible = false;
  StreamSubscription<PlayerSnapshot>? _playerSnapshotSubscription;
  StreamSubscription<void>? _playerEndedSubscription;
  StreamSubscription<String>? _playerErrorSubscription;

  @override
  void initState() {
    super.initState();

    // The StreamPlayer emits UI snapshots so the scrubber and buttons stay in
    // sync with whichever platform playback backend is active.
    _playerSnapshotSubscription = _player.snapshots.listen((snapshot) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = snapshot.position;
        _duration = snapshot.duration;
        _isPlaying = snapshot.isPlaying;
      });
    });
    _playerEndedSubscription = _player.ended.listen((_) => _handleTrackEnded());
    _playerErrorSubscription = _player.errors.listen((error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = false;
        _status = 'Playback failed: $error';
      });
    });
  }

  @override
  void dispose() {
    _playerSnapshotSubscription?.cancel();
    _playerEndedSubscription?.cancel();
    _playerErrorSubscription?.cancel();
    _serverController.dispose();
    _player.dispose();
    _serverControl.dispose();
    super.dispose();
  }

  Future<void> _startLocalServer() async {
    setState(() {
      _isStartingServer = true;
      _status = 'Starting local audio server...';
    });

    final result = await _serverControl.start();
    if (!mounted) {
      return;
    }

    setState(() {
      _isStartingServer = false;
      _status = result.message;
    });

    if (result.started) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await _connectToServer();
    }
  }

  Future<void> _connectToServer() async {
    final baseUrl = _normalizeBaseUrl(_serverController.text);
    setState(() {
      _isLoading = true;
      _status = 'Connecting to $baseUrl...';
      _connectedBaseUrl = null;
      _albums = <AlbumInfo>[];
      _revealingAlbumLocations = <String>[];
      _fadingAlbumLocations = <String>[];
      _browsingAlbum = null;
      _openingAlbumArtRect = null;
      _albumDetailVisible = false;
      _selectedAlbum = null;
      _selectedTrack = null;
      _selectedTrackIndex = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
    });

    try {
      final health = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (health.statusCode != 200) {
        throw Exception('Server returned ${health.statusCode} from /health.');
      }

      final library = await http
          .get(Uri.parse('$baseUrl/library'))
          .timeout(const Duration(seconds: 10));
      if (library.statusCode != 200) {
        throw Exception('Server returned ${library.statusCode} from /library.');
      }

      final decoded = jsonDecode(library.body) as List<dynamic>;
      final albums = decoded
          .map((value) => AlbumInfo.fromJson(value as Map<String, dynamic>))
          .toList();

      if (!mounted) {
        return;
      }

      await _swapScreenContent(() {
        _connectedBaseUrl = baseUrl;
        _albums = _sortAlbumsByArtist(albums);
        _revealingAlbumLocations = <String>[];
        _fadingAlbumLocations = <String>[];
        _status =
            'Connected to ${albums.length} album${albums.length == 1 ? '' : 's'}.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not connect: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _disconnectFromServer() {
    _player.pause();
    unawaited(
      _swapScreenContent(() {
        _connectedBaseUrl = null;
        _albums = <AlbumInfo>[];
        _revealingAlbumLocations = <String>[];
        _fadingAlbumLocations = <String>[];
        _browsingAlbum = null;
        _openingAlbumArtRect = null;
        _albumDetailVisible = false;
        _selectedAlbum = null;
        _selectedTrack = null;
        _selectedTrackIndex = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
        _isRefreshing = false;
        _status = 'Disconnected.';
      }),
    );
  }

  Future<void> _refreshLibrary() async {
    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    setState(() {
      _isRefreshing = true;
      _status = 'Checking for new albums...';
    });

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'known_locations': _albums
                  .map((album) => album.location)
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception(
          'Server returned ${response.statusCode} from /refresh.',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final newAlbums =
          ((decoded['new_albums'] ?? <dynamic>[]) as List<dynamic>)
              .map((value) => AlbumInfo.fromJson(value as Map<String, dynamic>))
              .toList();

      if (!mounted) {
        return;
      }

      final mergedAlbums = _sortAlbumsByArtist(
        _mergeAlbums(_albums, newAlbums),
      );
      final newAlbumLocations = newAlbums
          .map((album) => album.location)
          .toList();
      final shiftedAlbumLocations = _shiftedAlbumLocations(
        currentAlbums: _albums,
        nextAlbums: mergedAlbums,
      );
      final revealLocations = _affectedAlbumLocations(
        sortedAlbums: mergedAlbums,
        newAlbumLocations: newAlbumLocations,
        shiftedAlbumLocations: shiftedAlbumLocations,
      );

      if (newAlbums.isEmpty) {
        setState(() {
          _connectedBaseUrl = baseUrl;
          _albums = mergedAlbums;
          _revealingAlbumLocations = <String>[];
          _fadingAlbumLocations = <String>[];
          _browsingAlbum = _findUpdatedBrowsingAlbum(_browsingAlbum, _albums);
          _status = 'No new albums found.';
        });
        return;
      }

      if (shiftedAlbumLocations.isNotEmpty) {
        setState(() {
          _connectedBaseUrl = baseUrl;
          _revealingAlbumLocations = <String>[];
          _fadingAlbumLocations = shiftedAlbumLocations;
          _status =
              'Adding ${newAlbums.length} new album${newAlbums.length == 1 ? '' : 's'}...';
        });

        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) {
          return;
        }
      }

      setState(() {
        _connectedBaseUrl = baseUrl;
        _albums = mergedAlbums;
        _revealingAlbumLocations = revealLocations;
        _fadingAlbumLocations = <String>[];
        _browsingAlbum = _findUpdatedBrowsingAlbum(_browsingAlbum, _albums);
        _status =
            'Added ${newAlbums.length} new album${newAlbums.length == 1 ? '' : 's'}.';
      });
      _clearRevealedAlbumsAfterAnimation(revealLocations);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not refresh: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _clearRevealedAlbumsAfterAnimation(List<String> locations) {
    if (locations.isEmpty) {
      return;
    }

    final totalDuration = Duration(
      milliseconds: 500 + ((locations.length - 1) * 140) + 80,
    );
    unawaited(
      Future<void>.delayed(totalDuration, () {
        if (!mounted || !_sameLocations(_revealingAlbumLocations, locations)) {
          return;
        }
        setState(() {
          _revealingAlbumLocations = <String>[];
        });
      }),
    );
  }

  bool _sameLocations(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i += 1) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  List<AlbumInfo> _mergeAlbums(
    List<AlbumInfo> currentAlbums,
    List<AlbumInfo> incomingAlbums,
  ) {
    final byLocation = <String, AlbumInfo>{
      for (final album in currentAlbums) album.location: album,
    };
    for (final album in incomingAlbums) {
      byLocation[album.location] = album;
    }
    return byLocation.values.toList();
  }

  List<AlbumInfo> _sortAlbumsByArtist(List<AlbumInfo> albums) {
    final sortedAlbums = [...albums];
    sortedAlbums.sort((left, right) {
      final artistCompare = _sortText(
        left.artist,
      ).compareTo(_sortText(right.artist));
      if (artistCompare != 0) {
        return artistCompare;
      }

      final titleCompare = _sortText(
        left.title,
      ).compareTo(_sortText(right.title));
      if (titleCompare != 0) {
        return titleCompare;
      }

      return _sortText(left.location).compareTo(_sortText(right.location));
    });
    return sortedAlbums;
  }

  String _sortText(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'n/a') {
      return '\uFFFF';
    }
    return normalized;
  }

  List<String> _shiftedAlbumLocations({
    required List<AlbumInfo> currentAlbums,
    required List<AlbumInfo> nextAlbums,
  }) {
    final currentIndexes = <String, int>{
      for (var i = 0; i < currentAlbums.length; i += 1)
        currentAlbums[i].location: i,
    };

    final shiftedLocations = <String>[];
    for (var i = 0; i < nextAlbums.length; i += 1) {
      final oldIndex = currentIndexes[nextAlbums[i].location];
      if (oldIndex != null && oldIndex != i) {
        shiftedLocations.add(nextAlbums[i].location);
      }
    }
    return shiftedLocations;
  }

  List<String> _affectedAlbumLocations({
    required List<AlbumInfo> sortedAlbums,
    required List<String> newAlbumLocations,
    required List<String> shiftedAlbumLocations,
  }) {
    final affectedLocations = {...newAlbumLocations, ...shiftedAlbumLocations};
    return [
      for (final album in sortedAlbums)
        if (affectedLocations.contains(album.location)) album.location,
    ];
  }

  AlbumInfo? _findUpdatedBrowsingAlbum(
    AlbumInfo? browsingAlbum,
    List<AlbumInfo> albums,
  ) {
    if (browsingAlbum == null) {
      return null;
    }
    for (final album in albums) {
      if (album.location == browsingAlbum.location) {
        return album;
      }
    }
    return null;
  }

  void _showAlbum(AlbumInfo album, Rect? openingArtRect) {
    setState(() {
      _browsingAlbum = album;
      _openingAlbumArtRect = openingArtRect;
      _albumDetailVisible = true;
    });
  }

  void _showLibraryGrid() {
    setState(() {
      _albumDetailVisible = false;
    });
  }

  void _hideAlbumDetail() {
    if (_albumDetailVisible) {
      return;
    }
    setState(() {
      _browsingAlbum = null;
      _openingAlbumArtRect = null;
    });
  }

  Future<void> _playTrack(AlbumInfo album, TrackInfo track) async {
    final trackIndex = album.tracks.indexWhere(
      (candidate) => candidate.streamUrl == track.streamUrl,
    );
    setState(() {
      _selectedAlbum = album;
      _selectedTrack = track;
      _selectedTrackIndex = trackIndex == -1 ? null : trackIndex;
      _position = Duration.zero;
      _duration = Duration.zero;
      _status = 'Loading ${track.title}...';
    });

    try {
      final result = await _player.play(
        track.streamUrl,
        serverBaseUrl: _serverBaseUrlForTrack(track),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = result;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = false;
        _status = 'Playback failed: $error';
      });
    }
  }

  Future<void> _togglePlayPause() async {
    if (_selectedTrack == null) {
      return;
    }
    if (_isPlaying) {
      _player.pause();
      setState(() {
        _isPlaying = false;
        _status = 'Paused.';
      });
      return;
    }
    await _player.resume();
    if (!mounted) {
      return;
    }
    setState(() {
      _isPlaying = true;
      _status = 'Playing from ${_serverBaseUrlForTrack(_selectedTrack!)}';
    });
  }

  Future<void> _playPreviousTrack() async {
    final album = _selectedAlbum;
    final index = _selectedTrackIndex;
    if (album == null || index == null) {
      return;
    }
    if (index <= 0) {
      _player.seek(Duration.zero);
      return;
    }
    await _playTrack(album, album.tracks[index - 1]);
  }

  Future<void> _playNextTrack() async {
    await _playNextTrackInAlbum(autoAdvance: false);
  }

  Future<void> _playNextTrackInAlbum({required bool autoAdvance}) async {
    final album = _selectedAlbum;
    final index = _selectedTrackIndex;
    if (album == null || index == null) {
      return;
    }
    final nextIndex = index + 1;
    if (nextIndex >= album.tracks.length) {
      if (autoAdvance && mounted) {
        setState(() {
          _isPlaying = false;
          _status = 'Finished album.';
        });
      }
      return;
    }
    await _playTrack(album, album.tracks[nextIndex]);
  }

  void _handleTrackEnded() {
    unawaited(_playNextTrackInAlbum(autoAdvance: true));
  }

  void _seekTo(double milliseconds) {
    _player.seek(Duration(milliseconds: milliseconds.round()));
  }

  bool get _hasPreviousTrack => _selectedTrack != null;

  bool get _hasNextTrack =>
      _selectedAlbum != null &&
      _selectedTrackIndex != null &&
      _selectedTrackIndex! < _selectedAlbum!.tracks.length - 1;

  String _serverBaseUrlForTrack(TrackInfo track) {
    final uri = Uri.tryParse(track.streamUrl);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    }
    return _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
  }

  String _normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  Widget _buildLibraryContent() {
    if (_albums.isEmpty) {
      return EmptyState(key: const ValueKey('empty-library'), status: _status);
    }

    final browsingAlbum = _browsingAlbum;
    final libraryGrid = LibraryView(
      key: const ValueKey('album-grid'),
      albums: _albums,
      revealingAlbumLocations: _revealingAlbumLocations,
      fadingAlbumLocations: _fadingAlbumLocations,
      hiddenAlbumLocation: _albumDetailVisible ? browsingAlbum?.location : null,
      onAlbumSelected: _showAlbum,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        libraryGrid,
        if (browsingAlbum != null)
          AlbumDetailView(
            key: ValueKey('album-detail-${browsingAlbum.location}'),
            album: browsingAlbum,
            openingArtRect: _openingAlbumArtRect,
            visible: _albumDetailVisible,
            selectedTrack: _selectedTrack,
            onBack: _showLibraryGrid,
            onDismissed: _hideAlbumDetail,
            onTrackSelected: _playTrack,
          ),
      ],
    );
  }

  Future<void> _swapScreenContent(VoidCallback updateContent) async {
    setState(() {
      _screenVeilVisible = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 560));
    if (!mounted) {
      return;
    }
    setState(updateContent);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    setState(() {
      _screenVeilVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final connectedBaseUrl = _connectedBaseUrl;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: DecoratedBox(
          decoration: _appBackground(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              connectedBaseUrl == null
                  ? ConnectionScreen(
                      key: const ValueKey('connection-screen'),
                      controller: _serverController,
                      status: _status,
                      isLoading: _isLoading,
                      isStartingServer: _isStartingServer,
                      canStartServer: _serverControl.canStartServer,
                      onConnect: _connectToServer,
                      onStartServer: _startLocalServer,
                    )
                  : Column(
                      key: const ValueKey('library-shell'),
                      children: [
                        LibraryToolbar(
                          connectedBaseUrl: connectedBaseUrl,
                          isRefreshing: _isRefreshing,
                          onRefresh: _refreshLibrary,
                          onDisconnect: _disconnectFromServer,
                        ),
                        Expanded(child: _buildLibraryContent()),
                        PlayerBar(
                          selectedAlbum: _selectedAlbum,
                          selectedTrack: _selectedTrack,
                          position: _position,
                          duration: _duration,
                          isPlaying: _isPlaying,
                          canPlayPause: _selectedTrack != null,
                          canPlayPrevious: _hasPreviousTrack,
                          canPlayNext: _hasNextTrack,
                          status: _status,
                          supportsInlinePlayback:
                              _player.supportsInlinePlayback,
                          onPlayPause: _togglePlayPause,
                          onPrevious: _playPreviousTrack,
                          onNext: _playNextTrack,
                          onSeek: _seekTo,
                        ),
                      ],
                    ),
              TransitionVeil(visible: _screenVeilVisible),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _appBackground(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          collection.backgroundTop,
          collection.backgroundMiddle,
          collection.backgroundBottom,
        ],
        stops: const [0, 0.48, 1],
      ),
    );
  }
}
