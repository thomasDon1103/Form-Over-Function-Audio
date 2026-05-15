import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app_theme.dart';
import '../genre_color_utils.dart';
import '../models/album_info.dart';
import '../server_control.dart';
import '../stream_player.dart';
import '../widgets/connection_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/library_sidebar.dart';
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
  static const Duration _genreFilterFadeDuration = Duration(milliseconds: 500);

  final TextEditingController _serverController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final StreamPlayer _player = StreamPlayer();
  final ServerControl _serverControl = ServerControl();

  List<AlbumInfo> _albums = <AlbumInfo>[];
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
  bool _librarySidebarCollapsed = false;
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
      final genreCatalog = await _loadGenreCatalog(baseUrl, albums);

      if (!mounted) {
        return;
      }

      await _swapScreenContent(() {
        _connectedBaseUrl = baseUrl;
        _albums = _sortAlbumsByArtist(albums);
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

  Future<void> _selectGenreColor(String genre) async {
    final defaultColor = Theme.of(context).colorScheme.primary;
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

  void _replaceAlbums(List<AlbumInfo> albums) {
    if (!mounted) {
      return;
    }
    setState(() {
      _albums = _sortAlbumsByArtist(albums);
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

  String albumTitleForStatus(AlbumInfo album) {
    final title = album.title.trim();
    if (title.isNotEmpty && title.toLowerCase() != 'n/a') {
      return title;
    }
    return album.location;
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
            onTrackSelected: _playTrack,
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
    return [
      for (final album in _albums)
        if (_sameGenre(album.genre, genre)) album,
    ];
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

    return baseTheme.copyWith(
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
