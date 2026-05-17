import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_theme.dart';
import '../genre_color_utils.dart';
import '../models/album_info.dart';
import '../models/playback_queue_item.dart';
import '../models/playlist_info.dart';
import '../server_control.dart';
import '../stream_player.dart';
import '../widgets/app_navbar.dart';
import '../widgets/connection_bar.dart';
import '../widgets/displays/displays_page.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sidebar.dart';
import '../widgets/library_view.dart';
import '../widgets/player_bar.dart';
import '../widgets/playlists/playlists_page.dart';
import '../widgets/transition_veil.dart';

// Main screen for the audio streamer. This class coordinates server access,
// library state, and player commands while the widgets render the UI sections.
class AudioHomePage extends StatefulWidget {
  const AudioHomePage({super.key});

  @override
  State<AudioHomePage> createState() => _AudioHomePageState();
}

class _AudioHomePageState extends State<AudioHomePage> {
  static const Duration _genreFilterFadeDuration = Duration(milliseconds: 500);
  static const List<AppNavDestination> _appDestinations = [
    AppNavDestination(label: 'Library', icon: Icons.album),
    AppNavDestination(label: 'Playlists', icon: Icons.queue_music),
    AppNavDestination(label: 'Displays', icon: Icons.monitor),
  ];

  final TextEditingController _serverController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final StreamPlayer _player = StreamPlayer();
  final ServerControl _serverControl = ServerControl();
  final Map<String, _FilteredAlbumCache> _filteredAlbumCache =
      <String, _FilteredAlbumCache>{};

  List<AlbumInfo> _albums = <AlbumInfo>[];
  int _albumFilterVersion = 0;
  List<PlaylistInfo> _playlists = <PlaylistInfo>[];
  List<String> _genres = <String>[];
  Map<String, String> _genreColors = <String, String>{};
  String? _selectedGenreFilter;
  String? _displayedGenreFilter;
  bool _libraryFilterContentVisible = true;
  int _genreFilterTransitionId = 0;
  List<String> _revealingAlbumLocations = <String>[];
  List<String> _fadingAlbumLocations = <String>[];
  AlbumInfo? _browsingAlbum;
  Rect? _openingAlbumArtRect;
  bool _albumDetailVisible = false;
  PlaylistInfo? _browsingPlaylist;
  AlbumInfo? _selectedAlbum;
  TrackInfo? _selectedTrack;
  int? _selectedTrackIndex;
  String? _activePlaylistId;
  int? _selectedPlaylistTrackIndex;
  List<PlaybackQueueItem> _songQueue = <PlaybackQueueItem>[];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  String? _connectedBaseUrl;
  String? _status;
  bool _isLoading = false;
  bool _isStartingServer = false;
  bool _isRefreshing = false;
  bool _screenVeilVisible = false;
  bool _librarySidebarCollapsed = false;
  _AppPage _selectedAppPage = _AppPage.library;
  int _appPageTransitionDirection = 1;
  String? _cachedGenreThemeKey;
  ThemeData? _cachedGenreTheme;
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
      _markAlbumsChanged();
      _playlists = <PlaylistInfo>[];
      _genres = <String>[];
      _genreColors = <String, String>{};
      _selectedGenreFilter = null;
      _displayedGenreFilter = null;
      _libraryFilterContentVisible = true;
      _genreFilterTransitionId++;
      _revealingAlbumLocations = <String>[];
      _fadingAlbumLocations = <String>[];
      _browsingAlbum = null;
      _openingAlbumArtRect = null;
      _albumDetailVisible = false;
      _browsingPlaylist = null;
      _selectedAlbum = null;
      _selectedTrack = null;
      _selectedTrackIndex = null;
      _activePlaylistId = null;
      _selectedPlaylistTrackIndex = null;
      _songQueue = <PlaybackQueueItem>[];
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      _selectedAppPage = _AppPage.library;
      _appPageTransitionDirection = 1;
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
      final genreCatalog = await _loadGenreCatalog(baseUrl, albums);
      final playlists = await _loadPlaylists(baseUrl);

      if (!mounted) {
        return;
      }

      await _swapScreenContent(() {
        _connectedBaseUrl = baseUrl;
        _albums = _sortAlbumsByArtist(albums);
        _markAlbumsChanged();
        _playlists = playlists;
        _genres = genreCatalog.genres;
        _genreColors = genreCatalog.colors;
        _selectedGenreFilter = null;
        _displayedGenreFilter = null;
        _libraryFilterContentVisible = true;
        _genreFilterTransitionId++;
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
        _markAlbumsChanged();
        _playlists = <PlaylistInfo>[];
        _genres = <String>[];
        _genreColors = <String, String>{};
        _selectedGenreFilter = null;
        _displayedGenreFilter = null;
        _libraryFilterContentVisible = true;
        _genreFilterTransitionId++;
        _revealingAlbumLocations = <String>[];
        _fadingAlbumLocations = <String>[];
        _browsingAlbum = null;
        _openingAlbumArtRect = null;
        _albumDetailVisible = false;
        _browsingPlaylist = null;
        _selectedAlbum = null;
        _selectedTrack = null;
        _selectedTrackIndex = null;
        _activePlaylistId = null;
        _selectedPlaylistTrackIndex = null;
        _songQueue = <PlaybackQueueItem>[];
        _position = Duration.zero;
        _duration = Duration.zero;
        _isPlaying = false;
        _isRefreshing = false;
        _selectedAppPage = _AppPage.library;
        _appPageTransitionDirection = 1;
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
      final nextGenres = _mergeGenres(_genres, _genresFromAlbums(mergedAlbums));
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
          final validFilter = _validGenreFilter(
            _selectedGenreFilter,
            nextGenres,
          );
          _connectedBaseUrl = baseUrl;
          _albums = mergedAlbums;
          _markAlbumsChanged();
          _genres = nextGenres;
          _selectedGenreFilter = validFilter;
          _displayedGenreFilter = validFilter;
          _libraryFilterContentVisible = true;
          _genreFilterTransitionId++;
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
        final validFilter = _validGenreFilter(_selectedGenreFilter, nextGenres);
        _connectedBaseUrl = baseUrl;
        _albums = mergedAlbums;
        _markAlbumsChanged();
        _genres = nextGenres;
        _selectedGenreFilter = validFilter;
        _displayedGenreFilter = validFilter;
        _libraryFilterContentVisible = true;
        _genreFilterTransitionId++;
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

  Future<_GenreCatalog> _loadGenreCatalog(
    String baseUrl,
    List<AlbumInfo> albums,
  ) async {
    final albumGenres = _genresFromAlbums(albums);
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/genres'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return _GenreCatalog(genres: albumGenres);
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final serverGenres = ((decoded['genres'] ?? <dynamic>[]) as List<dynamic>)
          .map((value) => value as String)
          .toList();
      final genres = _mergeGenres(albumGenres, serverGenres);
      return _GenreCatalog(
        genres: genres,
        colors: _genreColorsFromJson(decoded['colors']),
      );
    } on Object {
      return _GenreCatalog(genres: albumGenres);
    }
  }

  Future<List<PlaylistInfo>> _loadPlaylists(String baseUrl) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/playlists'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return <PlaylistInfo>[];
      }
      return _playlistsFromResponse(response.body);
    } on Object {
      return <PlaylistInfo>[];
    }
  }

  List<PlaylistInfo> _playlistsFromResponse(String body) {
    final decoded = jsonDecode(body);
    final values = decoded is Map<String, dynamic>
        ? (decoded['playlists'] ?? <dynamic>[]) as List<dynamic>
        : decoded as List<dynamic>;
    return values
        .map((value) => PlaylistInfo.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Map<String, String> _genreColorsFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return <String, String>{};
    }
    final colors = <String, String>{};
    for (final entry in value.entries) {
      final color = entry.value;
      if (color is! String) {
        continue;
      }
      if (genreColorFromHex(color) == null) {
        continue;
      }
      colors[genreKey(entry.key)] = color;
    }
    return colors;
  }

  List<String> _genresFromAlbums(List<AlbumInfo> albums) {
    return _mergeGenres(
      const <String>[],
      albums.map((album) => album.genre).toList(),
    );
  }

  List<String> _mergeGenres(List<String> left, List<String> right) {
    final byKey = <String, String>{};
    for (final genre in [...left, ...right]) {
      final normalized = genre.trim();
      if (_isEmptyGenre(normalized)) {
        continue;
      }
      byKey[normalized.toLowerCase()] = normalized;
    }
    final genres = byKey.values.toList();
    genres.sort(
      (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
    );
    return genres;
  }

  List<String> _removeGenreFromList(List<String> genres, String genre) {
    return [
      for (final candidate in genres)
        if (!_sameGenre(candidate, genre)) candidate,
    ];
  }

  Map<String, String> _removeGenreColor(
    Map<String, String> colors,
    String genre,
  ) {
    final nextColors = {...colors};
    nextColors.remove(genreKey(genre));
    return nextColors;
  }

  String? _validGenreFilter(String? genre, List<String> genres) {
    if (genre == null) {
      return null;
    }
    return genres.any((candidate) => candidate == genre) ? genre : null;
  }

  bool _isEmptyGenre(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty || normalized == 'n/a' || normalized == 'no info';
  }

  bool _sameGenre(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
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

  void _selectGenreFilter(String? genre) {
    if (_selectedGenreFilter == genre && _displayedGenreFilter == genre) {
      return;
    }

    final transitionId = ++_genreFilterTransitionId;
    setState(() {
      _selectedGenreFilter = genre;
      _libraryFilterContentVisible = false;
    });

    unawaited(
      Future<void>.delayed(_genreFilterFadeDuration, () {
        if (!mounted || transitionId != _genreFilterTransitionId) {
          return;
        }
        setState(() {
          _displayedGenreFilter = genre;
          _libraryFilterContentVisible = true;
        });
      }),
    );
  }

  void _toggleLibrarySidebar() {
    setState(() {
      _librarySidebarCollapsed = !_librarySidebarCollapsed;
    });
  }

  void _selectAppPage(int index) {
    final pages = _AppPage.values;
    if (index < 0 || index >= pages.length) {
      return;
    }
    final nextPage = pages[index];
    if (_selectedAppPage == nextPage) {
      return;
    }
    final direction = nextPage.index > _selectedAppPage.index ? 1 : -1;
    setState(() {
      _appPageTransitionDirection = direction;
      _selectedAppPage = nextPage;
      _browsingAlbum = null;
      _openingAlbumArtRect = null;
      _albumDetailVisible = false;
    });
  }

  void _showPlaylist(PlaylistInfo playlist) {
    setState(() {
      _browsingPlaylist = playlist;
    });
  }

  void _showPlaylistGrid() {
    setState(() {
      _browsingPlaylist = null;
    });
  }

  Future<String?> _promptForPlaylistName({
    required String title,
    String initialName = '',
  }) async {
    return showDialog<String>(
      context: context,
      builder: (context) =>
          _PlaylistNameDialog(title: title, initialName: initialName),
    );
  }

  Future<PlaylistInfo?> _createPlaylistFromPrompt() async {
    final name = await _promptForPlaylistName(title: 'New Playlist');
    if (!mounted || name == null || name.isEmpty) {
      return null;
    }
    return _createPlaylist(name);
  }

  Future<void> _createPlaylistFromPlaylistsPage() async {
    final playlist = await _createPlaylistFromPrompt();
    if (!mounted || playlist == null) {
      return;
    }
    setState(() {
      _browsingPlaylist = _playlistById(playlist.id) ?? playlist;
    });
  }

  Future<PlaylistInfo?> _createPlaylist(String name) async {
    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/playlists'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final playlists = _playlistsFromResponse(response.body);
      final createdJson = decoded['playlist'];
      final created = createdJson is Map<String, dynamic>
          ? PlaylistInfo.fromJson(createdJson)
          : null;
      if (!mounted) {
        return created;
      }
      setState(() {
        _replacePlaylists(playlists);
        _status = 'Created playlist ${created?.name ?? name}.';
      });
      return _playlistById(created?.id) ?? created;
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Could not create playlist: $error';
        });
      }
      return null;
    }
  }

  Future<void> _showSaveTrackToPlaylistDialog(
    AlbumInfo album,
    TrackInfo track,
  ) async {
    var dialogPlaylists = _playlists;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add to Playlist'),
              content: SizedBox(
                width: 420,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: dialogPlaylists.isEmpty
                      ? Center(
                          child: Text(
                            'Create a playlist to save this song.',
                            style: Theme.of(context).textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: dialogPlaylists.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final playlist = dialogPlaylists[index];
                            return ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              leading: const Icon(Icons.queue_music),
                              title: Text(playlist.name),
                              subtitle: Text(
                                '${playlist.tracks.length} song${playlist.tracks.length == 1 ? '' : 's'}',
                              ),
                              onTap: () async {
                                await _addTrackToPlaylist(
                                  playlist,
                                  album,
                                  track,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                            );
                          },
                        ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    final playlist = await _createPlaylistFromPrompt();
                    if (playlist == null || !context.mounted) {
                      return;
                    }
                    setDialogState(() {
                      dialogPlaylists = _playlists;
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New Playlist'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addTrackToPlaylist(
    PlaylistInfo playlist,
    AlbumInfo album,
    TrackInfo track,
  ) async {
    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/playlists/add-track'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'playlist_id': playlist.id,
              'track': PlaylistTrackRef.fromTrack(album, track).toJson(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }
      final playlists = _playlistsFromResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _replacePlaylists(playlists);
        _status = 'Added ${track.title} to ${playlist.name}.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not add track to playlist: $error';
      });
    }
  }

  Future<void> _removeTrackFromPlaylist(
    PlaylistInfo playlist,
    ResolvedPlaylistTrack item,
  ) async {
    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/playlists/remove-track'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'playlist_id': playlist.id,
              'track': item.ref.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }
      final playlists = _playlistsFromResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _replacePlaylists(playlists);
        _status = 'Removed ${item.track.title} from ${playlist.name}.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not remove track from playlist: $error';
      });
    }
  }

  Future<void> _renamePlaylist(PlaylistInfo playlist) async {
    final name = await _promptForPlaylistName(
      title: 'Rename Playlist',
      initialName: playlist.name,
    );
    if (!mounted || name == null || name.isEmpty || name == playlist.name) {
      return;
    }

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/playlists/rename'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playlist_id': playlist.id, 'name': name}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }
      final playlists = _playlistsFromResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _replacePlaylists(playlists);
        _status = 'Renamed playlist to $name.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not rename playlist: $error';
      });
    }
  }

  Future<void> _deletePlaylist(PlaylistInfo playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Playlist'),
          content: Text('Delete ${playlist.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/playlists/delete'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playlist_id': playlist.id}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }
      final playlists = _playlistsFromResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _replacePlaylists(playlists);
        _status = 'Deleted ${playlist.name}.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not delete playlist: $error';
      });
    }
  }

  Future<void> _selectGenreColor(String genre) async {
    const defaultColor = defaultGenreSwatchColor;
    final currentColor = genreColorFor(genre, _genreColors, defaultColor);
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Color for $genre'),
          content: SizedBox(
            width: 458,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in _genreColorChoices(defaultColor))
                  _GenreColorChoice(
                    color: color,
                    selected: color.toARGB32() == currentColor.toARGB32(),
                    onTap: () => Navigator.of(context).pop(color),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (selectedColor == null) {
      return;
    }

    final hex = genreColorToHex(selectedColor);
    setState(() {
      _genreColors = {..._genreColors, genreKey(genre): hex};
      _status = 'Updating $genre color...';
    });

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/genres/color'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'genre': genre, 'color': hex}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }
      setState(() {
        _genres = _mergeGenres(
          _genres,
          ((decoded['genres'] ?? <dynamic>[]) as List<dynamic>)
              .map((value) => value as String)
              .toList(),
        );
        _genreColors = {
          ..._genreColors,
          ..._genreColorsFromJson(decoded['colors']),
        };
        _status = 'Updated $genre color.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Color saved locally, but server update failed: $error';
      });
    }
  }

  List<Color> _genreColorChoices(Color defaultColor) {
    return [
      const Color(0xffff9aa6),
      const Color(0xffd1495b),
      const Color(0xfff97316),
      const Color(0xffffb86b),
      const Color(0xffd6b16d),
      const Color(0xffffe66d),
      const Color(0xff84cc16),
      const Color(0xff34d399),
      const Color(0xff2dd4bf),
      const Color(0xff72e0ff),
      defaultColor,
      const Color(0xffa9beff),
      const Color(0xffd0c7ff),
      const Color(0xff5b21b6),
      const Color(0xfff78cce),
      const Color(0xffffffff),
      const Color(0xff8f9092),
      const Color(0xff050505),
    ];
  }

  Future<String?> _createGenre() async {
    var genreInput = '';
    final genre = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Genre'),
          content: TextField(
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Genre name'),
            onChanged: (value) {
              genreInput = value;
            },
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(genreInput),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    final normalized = genre?.trim() ?? '';
    if (_isEmptyGenre(normalized)) {
      return null;
    }

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    var nextGenres = _mergeGenres(_genres, [normalized]);
    var nextColors = _genreColors;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/genres'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'genre': normalized}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        nextGenres = _mergeGenres(
          nextGenres,
          ((decoded['genres'] ?? <dynamic>[]) as List<dynamic>)
              .map((value) => value as String)
              .toList(),
        );
        nextColors = {
          ...nextColors,
          ..._genreColorsFromJson(decoded['colors']),
        };
      }
    } on Object {
      // Keep the genre available locally even if the catalog write fails.
    }

    if (mounted) {
      setState(() {
        _genres = nextGenres;
        _genreColors = nextColors;
      });
    }
    return normalized;
  }

  Future<void> _assignAlbumGenre(AlbumInfo album, String genre) async {
    final normalized = genre.trim();
    if (_isEmptyGenre(normalized)) {
      return;
    }

    final updatedAlbum = album.copyWith(genre: normalized);
    _applyUpdatedAlbum(updatedAlbum);
    setState(() {
      _genres = _mergeGenres(_genres, [normalized]);
      _status = 'Updating ${albumTitleForStatus(album)} genre...';
    });

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/album/genre'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'location': album.location, 'genre': normalized}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }

      final savedAlbum = AlbumInfo.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (!mounted) {
        return;
      }
      _applyUpdatedAlbum(savedAlbum);
      setState(() {
        final nextGenres = _mergeGenres(_genres, [savedAlbum.genre]);
        final validFilter = _validGenreFilter(_selectedGenreFilter, nextGenres);
        _genres = nextGenres;
        _selectedGenreFilter = validFilter;
        _displayedGenreFilter = validFilter;
        _libraryFilterContentVisible = true;
        _genreFilterTransitionId++;
        _status = 'Updated ${albumTitleForStatus(savedAlbum)} genre.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Genre saved locally, but server update failed: $error';
      });
    }
  }

  Future<void> _removeSelectedGenre() async {
    final genre = _selectedGenreFilter;
    if (genre == null) {
      return;
    }

    final locallyUpdatedAlbums = [
      for (final album in _albums)
        if (_sameGenre(album.genre, genre))
          album.copyWith(genre: '')
        else
          album,
    ];
    _replaceAlbums(locallyUpdatedAlbums);
    setState(() {
      _genres = _removeGenreFromList(_genres, genre);
      _genreColors = _removeGenreColor(_genreColors, genre);
      _selectedGenreFilter = null;
      _displayedGenreFilter = null;
      _libraryFilterContentVisible = true;
      _genreFilterTransitionId++;
      _status = 'Removing $genre from matching albums...';
    });

    final baseUrl =
        _connectedBaseUrl ?? _normalizeBaseUrl(_serverController.text);
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/genres/remove'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'genre': genre}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final serverAlbums = ((decoded['albums'] ?? <dynamic>[]) as List<dynamic>)
          .map((value) => AlbumInfo.fromJson(value as Map<String, dynamic>))
          .toList();
      final serverGenres = ((decoded['genres'] ?? <dynamic>[]) as List<dynamic>)
          .map((value) => value as String)
          .toList();
      final serverColors = _genreColorsFromJson(decoded['colors']);

      if (!mounted) {
        return;
      }
      _replaceAlbums(serverAlbums);
      setState(() {
        _genres = _mergeGenres(serverGenres, _genresFromAlbums(serverAlbums));
        _genreColors = serverColors;
        _selectedGenreFilter = null;
        _displayedGenreFilter = null;
        _libraryFilterContentVisible = true;
        _genreFilterTransitionId++;
        _status = 'Removed $genre.';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Genre removed locally, but server update failed: $error';
      });
    }
  }

  void _applyUpdatedAlbum(AlbumInfo updatedAlbum) {
    if (!mounted) {
      return;
    }
    _replaceAlbums([
      for (final album in _albums)
        if (album.location == updatedAlbum.location) updatedAlbum else album,
    ]);
  }

  void _markAlbumsChanged() {
    _albumFilterVersion++;
    _filteredAlbumCache.clear();
  }

  void _replacePlaylists(List<PlaylistInfo> playlists) {
    _playlists = playlists;
    _browsingPlaylist = _playlistById(_browsingPlaylist?.id);
    final activePlaylist = _playlistById(_activePlaylistId);
    if (activePlaylist == null) {
      _activePlaylistId = null;
      _selectedPlaylistTrackIndex = null;
      return;
    }

    final selectedTrack = _selectedTrack;
    if (selectedTrack == null) {
      return;
    }
    final activeTracks = _resolvedPlaylistTracks(activePlaylist);
    final activeIndex = activeTracks.indexWhere(
      (item) => item.track.streamUrl == selectedTrack.streamUrl,
    );
    if (activeIndex == -1) {
      _activePlaylistId = null;
      _selectedPlaylistTrackIndex = null;
      return;
    }
    _selectedPlaylistTrackIndex = activeIndex;
  }

  PlaylistInfo? _playlistById(String? playlistId) {
    if (playlistId == null) {
      return null;
    }
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) {
        return playlist;
      }
    }
    return null;
  }

  void _replaceAlbums(List<AlbumInfo> albums) {
    if (!mounted) {
      return;
    }
    setState(() {
      _albums = _sortAlbumsByArtist(albums);
      _markAlbumsChanged();
      _songQueue = _updatedQueueForAlbums(_songQueue, _albums);
      _browsingAlbum = _findUpdatedBrowsingAlbum(_browsingAlbum, _albums);
      final selectedAlbumLocation = _selectedAlbum?.location;
      if (selectedAlbumLocation != null) {
        _selectedAlbum = _findUpdatedBrowsingAlbum(_selectedAlbum, _albums);
        final selectedAlbum = _selectedAlbum;
        if (selectedAlbum != null &&
            _selectedTrackIndex != null &&
            _selectedTrackIndex! < selectedAlbum.tracks.length) {
          _selectedTrack = selectedAlbum.tracks[_selectedTrackIndex!];
        }
      }
    });
  }

  List<PlaybackQueueItem> _updatedQueueForAlbums(
    List<PlaybackQueueItem> queue,
    List<AlbumInfo> albums,
  ) {
    final updatedQueue = <PlaybackQueueItem>[];
    for (final item in queue) {
      final updatedItem = _updatedQueueItemForAlbums(item, albums);
      if (updatedItem != null) {
        updatedQueue.add(updatedItem);
      }
    }
    return updatedQueue;
  }

  PlaybackQueueItem? _updatedQueueItemForAlbums(
    PlaybackQueueItem item,
    List<AlbumInfo> albums,
  ) {
    AlbumInfo? album;
    for (final candidate in albums) {
      if (candidate.location == item.album.location) {
        album = candidate;
        break;
      }
    }
    if (album == null) {
      return null;
    }

    final trackIndex = album.tracks.indexWhere(
      (track) => track.streamUrl == item.track.streamUrl,
    );
    if (trackIndex == -1) {
      return null;
    }

    return PlaybackQueueItem(
      album: album,
      track: album.tracks[trackIndex],
      trackIndex: trackIndex,
    );
  }

  String albumTitleForStatus(AlbumInfo album) {
    final title = album.title.trim();
    if (title.isNotEmpty && title.toLowerCase() != 'n/a') {
      return title;
    }
    return album.location;
  }

  Future<void> _playSelectedTrack(AlbumInfo album, TrackInfo track) async {
    if (_songQueue.isEmpty) {
      await _playTrackDirect(album, track, clearQueue: false);
      return;
    }

    final action = await _chooseQueuedTrackAction(track);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _QueuedTrackAction.playNow:
        await _playTrackDirect(album, track, clearQueue: true);
      case _QueuedTrackAction.addToQueue:
        await _addTrackToQueue(album, track);
    }
  }

  Future<_QueuedTrackAction?> _chooseQueuedTrackAction(TrackInfo track) {
    return showDialog<_QueuedTrackAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Queue Active'),
          content: Text(
            'Play "${track.title}" now and clear the queue, or add it to the end of the queue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_QueuedTrackAction.addToQueue),
              child: const Text('Add to Queue'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_QueuedTrackAction.playNow),
              child: const Text('Play Now'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addTrackToQueue(AlbumInfo album, TrackInfo track) async {
    final queueItem = _queueItemForTrack(album, track);
    if (_songQueue.isEmpty) {
      final currentItem = _isPlaying ? _currentQueueItem() : null;
      if (currentItem == null) {
        setState(() {
          _songQueue = [queueItem];
          _status = 'Queued ${track.title}.';
        });
        await _playQueueHead();
        return;
      }

      setState(() {
        _songQueue = [currentItem, queueItem];
        _status = 'Added ${track.title} to queue.';
      });
      return;
    }

    setState(() {
      _songQueue = [..._songQueue, queueItem];
      _status = 'Added ${track.title} to queue.';
    });
  }

  PlaybackQueueItem _queueItemForTrack(AlbumInfo album, TrackInfo track) {
    final trackIndex = album.tracks.indexWhere(
      (candidate) => candidate.streamUrl == track.streamUrl,
    );
    return PlaybackQueueItem(
      album: album,
      track: track,
      trackIndex: trackIndex == -1 ? null : trackIndex,
    );
  }

  List<ResolvedPlaylistTrack> _resolvedPlaylistTracks(PlaylistInfo playlist) {
    final resolved = <ResolvedPlaylistTrack>[];
    for (final ref in playlist.tracks) {
      final album = _albumByLocation(ref.albumLocation);
      if (album == null) {
        continue;
      }
      final trackIndex = album.tracks.indexWhere(
        (track) => track.path == ref.trackPath,
      );
      if (trackIndex == -1) {
        continue;
      }
      resolved.add(
        ResolvedPlaylistTrack(
          ref: ref,
          album: album,
          track: album.tracks[trackIndex],
          trackIndex: trackIndex,
        ),
      );
    }
    return resolved;
  }

  AlbumInfo? _albumByLocation(String location) {
    for (final album in _albums) {
      if (album.location == location) {
        return album;
      }
    }
    return null;
  }

  Map<String, List<AlbumInfo>> _playlistPreviewAlbums() {
    final previews = <String, List<AlbumInfo>>{};
    for (final playlist in _playlists) {
      final albums = <AlbumInfo>[];
      final seenLocations = <String>{};
      for (final ref in playlist.tracks) {
        if (seenLocations.contains(ref.albumLocation)) {
          continue;
        }
        final album = _albumByLocation(ref.albumLocation);
        if (album == null) {
          continue;
        }
        seenLocations.add(ref.albumLocation);
        albums.add(album);
        if (albums.length == 4) {
          break;
        }
      }
      previews[playlist.id] = albums;
    }
    return previews;
  }

  List<ResolvedPlaylistTrack> _activePlaylistTracks() {
    final playlist = _playlistById(_activePlaylistId);
    if (playlist == null) {
      return const <ResolvedPlaylistTrack>[];
    }
    return _resolvedPlaylistTracks(playlist);
  }

  PlaybackQueueItem? _currentQueueItem() {
    final album = _selectedAlbum;
    final track = _selectedTrack;
    if (album == null || track == null) {
      return null;
    }
    return PlaybackQueueItem(
      album: album,
      track: track,
      trackIndex: _selectedTrackIndex,
    );
  }

  Future<void> _playTrackDirect(
    AlbumInfo album,
    TrackInfo track, {
    required bool clearQueue,
  }) async {
    final trackIndex = album.tracks.indexWhere(
      (candidate) => candidate.streamUrl == track.streamUrl,
    );
    if (clearQueue) {
      setState(() {
        _songQueue = <PlaybackQueueItem>[];
      });
    }
    await _playTrack(
      album: album,
      track: track,
      trackIndex: trackIndex == -1 ? null : trackIndex,
      playlistId: null,
      playlistTrackIndex: null,
    );
  }

  Future<void> _playPlaylistTrack(ResolvedPlaylistTrack item) async {
    final playlist = _browsingPlaylist ?? _playlistById(_activePlaylistId);
    final playlistId = playlist?.id;
    final playlistTrackIndex = playlist == null
        ? null
        : _resolvedPlaylistTracks(
            playlist,
          ).indexWhere((candidate) => candidate.ref.id == item.ref.id);
    final effectivePlaylistTrackIndex = playlistTrackIndex == -1
        ? null
        : playlistTrackIndex;
    final effectivePlaylistId = effectivePlaylistTrackIndex == null
        ? null
        : playlistId;

    if (_songQueue.isEmpty) {
      await _playPlaylistTrackDirect(
        item,
        playlistId: effectivePlaylistId,
        playlistTrackIndex: effectivePlaylistTrackIndex,
        clearQueue: false,
      );
      return;
    }

    final action = await _chooseQueuedTrackAction(item.track);
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _QueuedTrackAction.playNow:
        await _playPlaylistTrackDirect(
          item,
          playlistId: effectivePlaylistId,
          playlistTrackIndex: effectivePlaylistTrackIndex,
          clearQueue: true,
        );
      case _QueuedTrackAction.addToQueue:
        await _addTrackToQueue(item.album, item.track);
    }
  }

  Future<void> _queuePlaylistTrack(ResolvedPlaylistTrack item) async {
    await _addTrackToQueue(item.album, item.track);
  }

  Future<void> _playPlaylistTrackDirect(
    ResolvedPlaylistTrack item, {
    required String? playlistId,
    required int? playlistTrackIndex,
    required bool clearQueue,
  }) async {
    if (clearQueue) {
      setState(() {
        _songQueue = <PlaybackQueueItem>[];
      });
    }
    await _playTrack(
      album: item.album,
      track: item.track,
      trackIndex: item.trackIndex,
      playlistId: playlistId,
      playlistTrackIndex: playlistTrackIndex,
    );
  }

  Future<void> _playTrack({
    required AlbumInfo album,
    required TrackInfo track,
    required int? trackIndex,
    required String? playlistId,
    required int? playlistTrackIndex,
  }) async {
    setState(() {
      _selectedAlbum = album;
      _selectedTrack = track;
      _selectedTrackIndex = trackIndex;
      _activePlaylistId = playlistId;
      _selectedPlaylistTrackIndex = playlistTrackIndex;
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

  Future<void> _playQueueHead() async {
    if (_songQueue.isEmpty) {
      _finishQueue('Queue finished.');
      return;
    }
    await _playQueueItem(_songQueue.first);
  }

  Future<void> _playQueueItem(PlaybackQueueItem item) async {
    await _playTrack(
      album: item.album,
      track: item.track,
      trackIndex: item.trackIndex,
      playlistId: null,
      playlistTrackIndex: null,
    );
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
    if (_songQueue.isNotEmpty) {
      _player.seek(Duration.zero);
      return;
    }
    if (_activePlaylistId != null) {
      await _playPreviousTrackInPlaylist();
      return;
    }

    final album = _selectedAlbum;
    final index = _selectedTrackIndex;
    if (album == null || index == null) {
      return;
    }
    if (index <= 0) {
      _player.seek(Duration.zero);
      return;
    }
    await _playTrackDirect(album, album.tracks[index - 1], clearQueue: false);
  }

  Future<void> _playNextTrack() async {
    if (_songQueue.isNotEmpty) {
      await _consumeQueueHead(finishedNaturally: false);
      return;
    }
    if (_activePlaylistId != null) {
      await _playNextTrackInPlaylist();
      return;
    }
    await _playNextTrackInAlbum();
  }

  Future<void> _playPreviousTrackInPlaylist() async {
    final activeTracks = _activePlaylistTracks();
    final index = _selectedPlaylistTrackIndex;
    if (activeTracks.isEmpty || index == null || index <= 0) {
      _player.seek(Duration.zero);
      return;
    }

    await _playPlaylistTrackDirect(
      activeTracks[index - 1],
      playlistId: _activePlaylistId,
      playlistTrackIndex: index - 1,
      clearQueue: false,
    );
  }

  Future<void> _playNextTrackInPlaylist() async {
    final activeTracks = _activePlaylistTracks();
    final index = _selectedPlaylistTrackIndex;
    if (activeTracks.isEmpty || index == null) {
      _finishPlaybackContext('Finished playlist.');
      return;
    }

    final nextIndex = index + 1;
    if (nextIndex >= activeTracks.length) {
      _finishPlaybackContext('Finished playlist.');
      return;
    }

    await _playPlaylistTrackDirect(
      activeTracks[nextIndex],
      playlistId: _activePlaylistId,
      playlistTrackIndex: nextIndex,
      clearQueue: false,
    );
  }

  Future<void> _playNextTrackInAlbum() async {
    final album = _selectedAlbum;
    final index = _selectedTrackIndex;
    if (album == null || index == null) {
      _finishPlaybackContext('Finished album.');
      return;
    }
    final nextIndex = index + 1;
    if (nextIndex >= album.tracks.length) {
      _finishPlaybackContext('Finished album.');
      return;
    }
    await _playTrackDirect(album, album.tracks[nextIndex], clearQueue: false);
  }

  Future<void> _consumeQueueHead({required bool finishedNaturally}) async {
    if (_songQueue.isEmpty) {
      _finishQueue('Queue finished.');
      return;
    }

    setState(() {
      _songQueue = _songQueue.skip(1).toList();
    });

    if (_songQueue.isEmpty) {
      _finishQueue(finishedNaturally ? 'Queue finished.' : 'Queue ended.');
      return;
    }

    await _playQueueHead();
  }

  Future<void> _selectQueueItem(int index) async {
    if (index < 0 || index >= _songQueue.length) {
      return;
    }
    if (index == 0) {
      return;
    }

    setState(() {
      _songQueue = _songQueue.skip(index).toList();
    });
    await _playQueueHead();
  }

  void _finishQueue(String status) {
    _finishPlaybackContext(status, clearQueue: true);
  }

  void _finishPlaybackContext(String status, {bool clearQueue = false}) {
    _player.pause();
    if (!mounted) {
      return;
    }
    setState(() {
      if (clearQueue) {
        _songQueue = <PlaybackQueueItem>[];
      }
      _selectedAlbum = null;
      _selectedTrack = null;
      _selectedTrackIndex = null;
      _activePlaylistId = null;
      _selectedPlaylistTrackIndex = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _isPlaying = false;
      _status = status;
    });
  }

  void _handleTrackEnded() {
    if (_songQueue.isNotEmpty) {
      unawaited(_consumeQueueHead(finishedNaturally: true));
      return;
    }
    if (_activePlaylistId != null) {
      unawaited(_playNextTrackInPlaylist());
      return;
    }
    unawaited(_playNextTrackInAlbum());
  }

  void _seekTo(double milliseconds) {
    _player.seek(Duration(milliseconds: milliseconds.round()));
  }

  bool get _hasPreviousTrack => _selectedTrack != null;

  bool get _hasNextTrack => _selectedTrack != null;

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
    final filteredAlbums = _displayedFilteredAlbums;
    final selectedFilteredAlbums = _selectedFilteredAlbums;
    final libraryGrid = LibraryView(
      key: const ValueKey('album-grid'),
      albums: filteredAlbums,
      genreColors: _genreColors,
      revealingAlbumLocations: _revealingAlbumLocations,
      fadingAlbumLocations: _fadingAlbumLocations,
      hiddenAlbumLocation: _albumDetailVisible ? browsingAlbum?.location : null,
      onAlbumSelected: _showAlbum,
    );
    final librarySurface = AnimatedOpacity(
      opacity: _libraryFilterContentVisible ? 1 : 0,
      duration: _genreFilterFadeDuration,
      curve: _libraryFilterContentVisible
          ? Curves.easeOutCubic
          : Curves.easeInCubic,
      child: IgnorePointer(
        ignoring: !_libraryFilterContentVisible,
        child: filteredAlbums.isEmpty
            ? EmptyState(
                key: const ValueKey('filtered-empty-library'),
                status: 'No albums match this genre.',
              )
            : libraryGrid,
      ),
    );

    final content = Stack(
      fit: StackFit.expand,
      children: [
        librarySurface,
        if (browsingAlbum != null)
          AlbumDetailView(
            key: ValueKey('album-detail-${browsingAlbum.location}'),
            album: browsingAlbum,
            openingArtRect: _openingAlbumArtRect,
            visible: _albumDetailVisible,
            selectedTrack: _selectedTrack,
            availableGenres: _genres,
            onBack: _showLibraryGrid,
            onDismissed: _hideAlbumDetail,
            onTrackSelected: _playSelectedTrack,
            onTrackQueued: (album, track) =>
                unawaited(_addTrackToQueue(album, track)),
            onTrackPlaylist: (album, track) =>
                unawaited(_showSaveTrackToPlaylistDialog(album, track)),
            onGenreSelected: _assignAlbumGenre,
            onCreateGenre: _createGenre,
          ),
      ],
    );

    return Row(
      children: [
        LibrarySidebar(
          genres: _genres,
          selectedGenre: _selectedGenreFilter,
          albumCount: _albums.length,
          visibleAlbumCount: selectedFilteredAlbums.length,
          genreColors: _genreColors,
          onGenreSelected: _selectGenreFilter,
          onGenreColorSelected: (genre) => unawaited(_selectGenreColor(genre)),
          onAddGenre: () => unawaited(_createGenre()),
          onRemoveSelectedGenre: () => unawaited(_removeSelectedGenre()),
          collapsed: _librarySidebarCollapsed,
          onToggleCollapsed: _toggleLibrarySidebar,
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _buildPlaylistsContent() {
    final browsingPlaylist = _browsingPlaylist;
    return PlaylistsPage(
      playlists: _playlists,
      previewAlbumsByPlaylist: _playlistPreviewAlbums(),
      selectedPlaylist: browsingPlaylist,
      selectedTracks: browsingPlaylist == null
          ? const <ResolvedPlaylistTrack>[]
          : _resolvedPlaylistTracks(browsingPlaylist),
      selectedTrack: _selectedTrack,
      onPlaylistSelected: _showPlaylist,
      onCreatePlaylist: () => unawaited(_createPlaylistFromPlaylistsPage()),
      onBack: _showPlaylistGrid,
      onRenamePlaylist: (playlist) => unawaited(_renamePlaylist(playlist)),
      onDeletePlaylist: (playlist) => unawaited(_deletePlaylist(playlist)),
      onTrackSelected: (item) => unawaited(_playPlaylistTrack(item)),
      onTrackQueued: (item) => unawaited(_queuePlaylistTrack(item)),
      onTrackRemoved: (item) {
        final playlist = _browsingPlaylist;
        if (playlist == null) {
          return;
        }
        unawaited(_removeTrackFromPlaylist(playlist, item));
      },
    );
  }

  Widget _buildSelectedAppContent() {
    return switch (_selectedAppPage) {
      _AppPage.library => _buildLibraryContent(),
      _AppPage.playlists => _buildPlaylistsContent(),
      _AppPage.displays => DisplaysPage(
        key: const ValueKey('displays-page'),
        albums: _albums,
      ),
    };
  }

  Widget _buildAppPageSwitcher() {
    final pageKey = ValueKey('app-page-${_selectedAppPage.name}');
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 520),
        reverseDuration: const Duration(milliseconds: 520),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [...previousChildren, ?currentChild],
          );
        },
        transitionBuilder: (child, animation) {
          final entering = child.key == pageKey;
          final direction = _appPageTransitionDirection.toDouble();
          final begin = Offset(entering ? direction : -direction, 0);
          return SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(key: pageKey, child: _buildSelectedAppContent()),
      ),
    );
  }

  List<AlbumInfo> get _selectedFilteredAlbums {
    return _albumsForGenre(_selectedGenreFilter);
  }

  List<AlbumInfo> get _displayedFilteredAlbums {
    return _albumsForGenre(_displayedGenreFilter);
  }

  List<AlbumInfo> _albumsForGenre(String? genre) {
    if (genre == null) {
      return _albums;
    }
    final cacheKey = genreKey(genre);
    final cached = _filteredAlbumCache[cacheKey];
    if (cached != null && cached.version == _albumFilterVersion) {
      return cached.albums;
    }

    final filteredAlbums = [
      for (final album in _albums)
        if (_sameGenre(album.genre, genre)) album,
    ];
    _filteredAlbumCache[cacheKey] = _FilteredAlbumCache(
      version: _albumFilterVersion,
      albums: filteredAlbums,
    );
    return filteredAlbums;
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
    final theme = _themeForActiveGenre(Theme.of(context));
    return AnimatedTheme(
      data: theme,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeInOutCubic,
      child: Builder(
        builder: (context) {
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
                              AppNavbar(
                                destinations: _appDestinations,
                                selectedIndex: _selectedAppPage.index,
                                onSelected: _selectAppPage,
                              ),
                              Expanded(child: _buildAppPageSwitcher()),
                              PlayerBar(
                                selectedAlbum: _selectedAlbum,
                                selectedTrack: _selectedTrack,
                                queue: _songQueue,
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
                                onQueueItemSelected: (index) =>
                                    unawaited(_selectQueueItem(index)),
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
        },
      ),
    );
  }

  ThemeData _themeForActiveGenre(ThemeData baseTheme) {
    final selectedGenre = _selectedGenreFilter;
    if (selectedGenre == null) {
      return baseTheme;
    }

    final accent = genreColorFor(
      selectedGenre,
      _genreColors,
      baseTheme.colorScheme.primary,
    );
    final themeKey = [
      selectedGenre,
      accent.toARGB32(),
      baseTheme.colorScheme.primary.toARGB32(),
      baseTheme.brightness.name,
    ].join('|');
    final cachedTheme = _cachedGenreTheme;
    if (_cachedGenreThemeKey == themeKey && cachedTheme != null) {
      return cachedTheme;
    }

    final greenAccent = _isGreenAccent(accent);
    final blackAccent = _isBlackAccent(accent);
    final whiteAccent = _isWhiteAccent(accent);
    final primary = _accentTone(
      accent,
      saturation: blackAccent ? 0 : null,
      lightness: blackAccent
          ? 0.56
          : whiteAccent
          ? 0.90
          : greenAccent
          ? 0.64
          : 0.72,
    );
    final secondary = _shiftedAccent(
      accent,
      degrees: 18,
      lightness: blackAccent
          ? 0.48
          : whiteAccent
          ? 0.82
          : greenAccent
          ? 0.62
          : 0.70,
    );
    final collection = _collectionForAccent(accent, primary);
    final primaryContainer = _accentTone(
      accent,
      saturation: blackAccent ? 0 : null,
      lightness: blackAccent
          ? 0.16
          : whiteAccent
          ? 0.42
          : greenAccent
          ? 0.24
          : 0.30,
    );
    final secondaryContainer = _shiftedAccent(
      accent,
      degrees: 18,
      lightness: blackAccent
          ? 0.12
          : whiteAccent
          ? 0.34
          : greenAccent
          ? 0.22
          : 0.28,
    );

    final theme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: primary,
        onPrimary: _onColor(primary),
        primaryContainer: primaryContainer,
        onPrimaryContainer: _onColor(primaryContainer),
        secondary: secondary,
        onSecondary: _onColor(secondary),
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: _onColor(secondaryContainer),
        outline: _accentTone(
          accent,
          saturation: blackAccent
              ? 0
              : greenAccent
              ? 0.28
              : 0.32,
          lightness: blackAccent
              ? 0.40
              : whiteAccent
              ? 0.72
              : greenAccent
              ? 0.50
              : 0.58,
        ),
        surfaceContainerHighest: _accentTone(
          accent,
          saturation: blackAccent
              ? 0
              : greenAccent
              ? 0.20
              : 0.24,
          lightness: blackAccent
              ? 0.10
              : whiteAccent
              ? 0.26
              : greenAccent
              ? 0.16
              : 0.20,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[collection],
    );
    _cachedGenreThemeKey = themeKey;
    _cachedGenreTheme = theme;
    return theme;
  }

  CollectionTheme _collectionForAccent(Color accent, Color primary) {
    final base = HSLColor.fromColor(accent);
    final neutral = _isNeutralAccent(accent);
    final greenAccent = _isGreenAccent(accent);
    final blackAccent = _isBlackAccent(accent);
    final whiteAccent = _isWhiteAccent(accent);
    final toneBase = neutral ? base.withSaturation(0) : base;
    final double backgroundSaturation = neutral
        ? 0
        : greenAccent
        ? math.max(0.40, math.min(0.86, base.saturation))
        : math.max(0.48, math.min(1, base.saturation * 1.18));
    final double panelSaturation = neutral
        ? 0
        : greenAccent
        ? math.max(0.30, math.min(0.76, base.saturation * 0.82))
        : math.max(0.34, base.saturation);

    return AppTheme.collection.copyWith(
      backgroundTop: toneBase
          .withSaturation(backgroundSaturation)
          .withLightness(
            neutral
                ? blackAccent
                      ? 0.035
                      : whiteAccent
                      ? 0.16
                      : 0.10
                : greenAccent
                ? 0.09
                : 0.12,
          )
          .toColor(),
      backgroundMiddle: toneBase
          .withSaturation(backgroundSaturation)
          .withLightness(
            neutral
                ? blackAccent
                      ? 0.075
                      : whiteAccent
                      ? 0.28
                      : 0.18
                : greenAccent
                ? 0.19
                : 0.24,
          )
          .toColor(),
      backgroundBottom: toneBase
          .withSaturation(backgroundSaturation)
          .withLightness(
            blackAccent
                ? 0.01
                : whiteAccent
                ? 0.065
                : 0.035,
          )
          .toColor(),
      panel: toneBase
          .withSaturation(panelSaturation)
          .withLightness(
            neutral
                ? blackAccent
                      ? 0.055
                      : whiteAccent
                      ? 0.24
                      : 0.15
                : greenAccent
                ? 0.13
                : 0.16,
          )
          .toColor()
          .withValues(alpha: 0.86),
      panelStrong: toneBase
          .withSaturation(panelSaturation)
          .withLightness(
            neutral
                ? blackAccent
                      ? 0.09
                      : whiteAccent
                      ? 0.31
                      : 0.19
                : greenAccent
                ? 0.17
                : 0.21,
          )
          .toColor()
          .withValues(alpha: 0.94),
      panelBorder: primary.withValues(alpha: 0.42),
      glow: _accentTone(accent, saturation: neutral ? 0 : null),
    );
  }

  Color _accentTone(Color color, {double? saturation, double? lightness}) {
    final hsl = HSLColor.fromColor(color);
    final neutral = _isNeutralAccent(color);
    final nextSaturation = saturation ?? (neutral ? 0 : hsl.saturation);
    final nextLightness = lightness ?? math.max(0.50, hsl.lightness);
    return hsl
        .withSaturation(nextSaturation.clamp(0.0, 1.0))
        .withLightness(nextLightness.clamp(0.0, 1.0))
        .toColor();
  }

  Color _shiftedAccent(
    Color color, {
    required double degrees,
    required double lightness,
  }) {
    final hsl = HSLColor.fromColor(color);
    if (_isNeutralAccent(color)) {
      return _accentTone(color, saturation: 0, lightness: lightness);
    }
    return hsl
        .withHue((hsl.hue + degrees) % 360)
        .withLightness(lightness)
        .toColor();
  }

  bool _isGreenAccent(Color color) {
    final hue = HSLColor.fromColor(color).hue;
    return hue >= 75 && hue <= 165;
  }

  bool _isNeutralAccent(Color color) {
    return HSLColor.fromColor(color).saturation < 0.08 || _isBlackAccent(color);
  }

  bool _isBlackAccent(Color color) {
    final hsl = HSLColor.fromColor(color);
    final savedSlateBlack =
        color.toARGB32() == const Color(0xff111827).toARGB32();
    return savedSlateBlack || (hsl.lightness <= 0.16 && hsl.saturation < 0.45);
  }

  bool _isWhiteAccent(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.lightness >= 0.86 && hsl.saturation < 0.16;
  }

  Color _onColor(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
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

class _GenreCatalog {
  const _GenreCatalog({
    required this.genres,
    this.colors = const <String, String>{},
  });

  final List<String> genres;
  final Map<String, String> colors;
}

class _FilteredAlbumCache {
  const _FilteredAlbumCache({required this.version, required this.albums});

  final int version;
  final List<AlbumInfo> albums;
}

enum _QueuedTrackAction { playNow, addToQueue }

enum _AppPage { library, playlists, displays }

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({required this.title, required this.initialName});

  final String title;
  final String initialName;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Playlist name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _GenreColorChoice extends StatelessWidget {
  const _GenreColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final collection =
        Theme.of(context).extension<CollectionTheme>() ?? AppTheme.collection;
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.onSurface : collection.panelBorder,
            width: selected ? 2.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: selected ? 0.42 : 0.22),
              blurRadius: selected ? 18 : 10,
            ),
          ],
        ),
        child: selected
            ? Icon(Icons.check, color: colorScheme.surface, size: 20)
            : null,
      ),
    );
  }
}
