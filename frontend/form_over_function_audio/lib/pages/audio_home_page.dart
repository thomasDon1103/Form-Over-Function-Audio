import 'dart:async';
import 'dart:convert';

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
  final TextEditingController _serverController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final StreamPlayer _player = StreamPlayer();
  final ServerControl _serverControl = ServerControl();

  List<AlbumInfo> _albums = <AlbumInfo>[];
  List<String> _genres = <String>[];
  Map<String, String> _genreColors = <String, String>{};
  String? _selectedGenreFilter;
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
          _connectedBaseUrl = baseUrl;
          _albums = mergedAlbums;
          _genres = nextGenres;
          _selectedGenreFilter = _validGenreFilter(
            _selectedGenreFilter,
            nextGenres,
          );
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
        _genres = nextGenres;
        _selectedGenreFilter = _validGenreFilter(
          _selectedGenreFilter,
          nextGenres,
        );
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
    setState(() {
      _selectedGenreFilter = genre;
    });
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
      const Color(0xffff6f7d),
      const Color(0xffd1495b),
      const Color(0xfff97316),
      const Color(0xffffb86b),
      const Color(0xffd6b16d),
      const Color(0xffffe66d),
      const Color(0xffa3e635),
      const Color(0xff7ee787),
      const Color(0xff63e6be),
      const Color(0xff72e0ff),
      defaultColor,
      const Color(0xff8aa2ff),
      const Color(0xffb7a6ff),
      const Color(0xff2b0052),
      const Color(0xfff78cce),
      const Color(0xffc8d3f5),
      const Color(0xff8a94a6),
      const Color(0xff111827),
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
        _genres = _mergeGenres(_genres, [savedAlbum.genre]);
        _selectedGenreFilter = _validGenreFilter(_selectedGenreFilter, _genres);
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
    final filteredAlbums = _filteredAlbums;
    final libraryGrid = LibraryView(
      key: const ValueKey('album-grid'),
      albums: filteredAlbums,
      genreColors: _genreColors,
      revealingAlbumLocations: _revealingAlbumLocations,
      fadingAlbumLocations: _fadingAlbumLocations,
      hiddenAlbumLocation: _albumDetailVisible ? browsingAlbum?.location : null,
      onAlbumSelected: _showAlbum,
    );

    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (filteredAlbums.isEmpty)
          EmptyState(
            key: const ValueKey('filtered-empty-library'),
            status: 'No albums match this genre.',
          )
        else
          libraryGrid,
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
          visibleAlbumCount: filteredAlbums.length,
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

  List<AlbumInfo> get _filteredAlbums {
    final selectedGenre = _selectedGenreFilter;
    if (selectedGenre == null) {
      return _albums;
    }
    return [
      for (final album in _albums)
        if (_sameGenre(album.genre, selectedGenre)) album,
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
