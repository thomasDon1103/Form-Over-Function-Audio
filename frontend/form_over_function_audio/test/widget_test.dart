import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_over_function_audio/main.dart';
import 'package:form_over_function_audio/models/album_info.dart';
import 'package:form_over_function_audio/widgets/library_view.dart';
import 'package:form_over_function_audio/widgets/player_bar.dart';

void main() {
  testWidgets('shows the server connection controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FormOverFunctionAudioApp());

    expect(find.text('Connect to server'), findsOneWidget);
    expect(find.text('Audio server address'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.text('Disconnect'), findsNothing);
  });

  testWidgets('shows album grid and album detail tracks', (
    WidgetTester tester,
  ) async {
    const album = AlbumInfo(
      location: 'library/sample',
      artUrl: '',
      tracks: [
        TrackInfo(
          title: 'Opening Track',
          path: 'opening.mp3',
          streamUrl: 'http://localhost:8080/stream?path=opening.mp3',
        ),
      ],
      artist: 'Sample Artist',
      title: 'Sample Album',
      year: 2026,
      genre: 'Test',
    );

    AlbumInfo? tappedAlbum;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryView(
            albums: const [album],
            onAlbumSelected: (album) => tappedAlbum = album,
          ),
        ),
      ),
    );

    expect(find.text('Sample Album'), findsOneWidget);
    expect(find.text('Opening Track'), findsNothing);

    await tester.tap(find.text('Sample Album'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(tappedAlbum, album);

    var wentBack = false;
    TrackInfo? tappedTrack;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumDetailView(
            album: album,
            selectedTrack: null,
            onBack: () => wentBack = true,
            onTrackSelected: (_, track) => tappedTrack = track,
          ),
        ),
      ),
    );

    expect(find.text('Opening Track'), findsOneWidget);
    await tester.tap(find.text('Opening Track'));
    expect(tappedTrack, album.tracks.single);

    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(wentBack, isTrue);
  });

  testWidgets('player panel expands to show album art', (
    WidgetTester tester,
  ) async {
    const album = AlbumInfo(
      location: 'library/sample',
      artUrl: '',
      tracks: [
        TrackInfo(
          title: 'Opening Track',
          path: 'opening.mp3',
          streamUrl: 'http://localhost:8080/stream?path=opening.mp3',
        ),
      ],
      artist: 'Sample Artist',
      title: 'Sample Album',
      year: 2026,
      genre: 'Test',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerBar(
              selectedAlbum: album,
              selectedTrack: album.tracks.single,
              position: const Duration(seconds: 12),
              duration: const Duration(minutes: 3),
              isPlaying: true,
              canPlayPause: true,
              canPlayPrevious: true,
              canPlayNext: false,
              status: 'Playing from http://localhost:8080',
              supportsInlinePlayback: true,
              onPlayPause: () {},
              onPrevious: () {},
              onNext: () {},
              onSeek: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.album), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
