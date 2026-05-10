// Data models for the album library returned by the Go backend.
// Keeping these separate makes the UI files focus on presentation.
class AlbumInfo {
  const AlbumInfo({
    required this.location,
    required this.artUrl,
    required this.tracks,
    required this.artist,
    required this.title,
    required this.year,
    required this.genre,
  });

  factory AlbumInfo.fromJson(Map<String, dynamic> json) {
    return AlbumInfo(
      location: (json['location'] ?? json['folder'] ?? '') as String,
      artUrl: (json['art_url'] ?? '') as String,
      tracks: ((json['tracks'] ?? <dynamic>[]) as List<dynamic>)
          .map((value) => TrackInfo.fromJson(value as Map<String, dynamic>))
          .toList(),
      artist: (json['artist'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      year: (json['year'] ?? 0) as int,
      genre: (json['genre'] ?? '') as String,
    );
  }

  final String location;
  final String artUrl;
  final List<TrackInfo> tracks;
  final String artist;
  final String title;
  final int year;
  final String genre;
}

class TrackInfo {
  const TrackInfo({
    required this.title,
    required this.path,
    required this.streamUrl,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    final path = (json['path'] ?? '') as String;
    return TrackInfo(
      title: (json['title'] ?? path) as String,
      path: path,
      streamUrl: (json['stream_url'] ?? '') as String,
    );
  }

  final String title;
  final String path;
  final String streamUrl;
}
