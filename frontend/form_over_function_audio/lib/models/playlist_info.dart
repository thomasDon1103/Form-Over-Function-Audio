import 'album_info.dart';

class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.name,
    required this.tracks,
  });

  factory PlaylistInfo.fromJson(Map<String, dynamic> json) {
    return PlaylistInfo(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      tracks: ((json['tracks'] ?? <dynamic>[]) as List<dynamic>)
          .map(
            (value) => PlaylistTrackRef.fromJson(value as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  PlaylistInfo copyWith({
    String? id,
    String? name,
    List<PlaylistTrackRef>? tracks,
  }) {
    return PlaylistInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
    );
  }

  final String id;
  final String name;
  final List<PlaylistTrackRef> tracks;
}

class PlaylistTrackRef {
  const PlaylistTrackRef({
    required this.albumLocation,
    required this.trackPath,
  });

  factory PlaylistTrackRef.fromJson(Map<String, dynamic> json) {
    return PlaylistTrackRef(
      albumLocation: (json['album_location'] ?? '') as String,
      trackPath: (json['track_path'] ?? '') as String,
    );
  }

  factory PlaylistTrackRef.fromTrack(AlbumInfo album, TrackInfo track) {
    return PlaylistTrackRef(
      albumLocation: album.location,
      trackPath: track.path,
    );
  }

  Map<String, String> toJson() {
    return {'album_location': albumLocation, 'track_path': trackPath};
  }

  final String albumLocation;
  final String trackPath;

  String get id => '$albumLocation::$trackPath';
}

class ResolvedPlaylistTrack {
  const ResolvedPlaylistTrack({
    required this.ref,
    required this.album,
    required this.track,
    required this.trackIndex,
  });

  final PlaylistTrackRef ref;
  final AlbumInfo album;
  final TrackInfo track;
  final int? trackIndex;
}
