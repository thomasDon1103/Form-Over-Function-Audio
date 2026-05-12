import '../../models/album_info.dart';

String albumTitle(AlbumInfo album) {
  return album.title.isEmpty ? album.location : album.title;
}
