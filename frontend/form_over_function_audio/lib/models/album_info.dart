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
    this.mimeType = '',
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
      mimeType: (json['mime_type'] ?? '') as String,
    );
  }

  AlbumInfo copyWith({
    String? location,
    String? artUrl,
    List<TrackInfo>? tracks,
    String? artist,
    String? title,
    int? year,
    String? genre,
    String? mimeType,
  }) {
    return AlbumInfo(
      location: location ?? this.location,
      artUrl: artUrl ?? this.artUrl,
      tracks: tracks ?? this.tracks,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      mimeType: mimeType ?? this.mimeType,
    );
  }

  final String location;
  final String artUrl;
  final List<TrackInfo> tracks;
  final String artist;
  final String title;
  final int year;
  final String genre;
  final String mimeType;
}

class TrackInfo {
  const TrackInfo({
    required this.title,
    required this.path,
    required this.streamUrl,
    this.format = '',
    this.mimeType = '',
    this.metadataFormat = '',
    this.fileSizeBytes = 0,
    this.bitrateKbps = 0,
    this.artist = '',
    this.album = '',
    this.year = 0,
    this.genre = '',
    this.trackNumber = 0,
    this.trackTotal = 0,
    this.discNumber = 0,
    this.discTotal = 0,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    final path = (json['path'] ?? '') as String;
    return TrackInfo(
      title: (json['title'] ?? path) as String,
      path: path,
      streamUrl: (json['stream_url'] ?? '') as String,
      format: (json['format'] ?? '') as String,
      mimeType: (json['mime_type'] ?? '') as String,
      metadataFormat: (json['metadata_format'] ?? '') as String,
      fileSizeBytes: (json['file_size_bytes'] ?? 0) as int,
      bitrateKbps: (json['bitrate_kbps'] ?? 0) as int,
      artist: (json['artist'] ?? '') as String,
      album: (json['album'] ?? '') as String,
      year: (json['year'] ?? 0) as int,
      genre: (json['genre'] ?? '') as String,
      trackNumber: (json['track_number'] ?? 0) as int,
      trackTotal: (json['track_total'] ?? 0) as int,
      discNumber: (json['disc_number'] ?? 0) as int,
      discTotal: (json['disc_total'] ?? 0) as int,
    );
  }

  final String title;
  final String path;
  final String streamUrl;
  final String format;
  final String mimeType;
  final String metadataFormat;
  final int fileSizeBytes;
  final int bitrateKbps;
  final String artist;
  final String album;
  final int year;
  final String genre;
  final int trackNumber;
  final int trackTotal;
  final int discNumber;
  final int discTotal;
}
