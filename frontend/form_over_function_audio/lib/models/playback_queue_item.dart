import 'album_info.dart';

class PlaybackQueueItem {
  const PlaybackQueueItem({
    required this.album,
    required this.track,
    required this.trackIndex,
  });

  final AlbumInfo album;
  final TrackInfo track;
  final int? trackIndex;

  String get id => '${album.location}::${track.streamUrl}';
}
