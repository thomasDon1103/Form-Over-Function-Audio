package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/dhowden/tag"
)

const (
	defaultAudioDir  = "audio"
	defaultHost      = "0.0.0.0"
	defaultPort      = "8080"
	genreCatalogFile = "genreCatalog.json"
	genreColorsFile  = "genreColors.json"
	playlistsFile    = "playlists.json"
)

var audioDir = getEnv("FOF_AUDIO_DIR", defaultAudioDir)

// allowedTypes maps a file extension (lowercase, with dot) to the
// Content-Type we'll advertise. Anything not in this map is rejected.
var allowedTypes = map[string]string{
	".mp3":  "audio/mpeg",
	".flac": "audio/flac",
	".wav":  "audio/wav",
}

func isAudioFile(name string) bool {
	_, ok := allowedTypes[strings.ToLower(filepath.Ext(name))]
	return ok
}

func getEnv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func safeLibraryPath(relativePath string) (string, string, error) {
	if relativePath == "" {
		return "", "", fmt.Errorf("empty path")
	}

	clean := filepath.Clean(filepath.FromSlash(relativePath))
	if clean == "." || filepath.IsAbs(clean) || strings.HasPrefix(clean, ".."+string(filepath.Separator)) || clean == ".." {
		return "", "", fmt.Errorf("invalid library path")
	}

	root, err := filepath.Abs(audioDir)
	if err != nil {
		return "", "", fmt.Errorf("could not resolve audio directory")
	}
	target, err := filepath.Abs(filepath.Join(audioDir, clean))
	if err != nil {
		return "", "", fmt.Errorf("could not resolve library path")
	}

	relativeToRoot, err := filepath.Rel(root, target)
	if err != nil || strings.HasPrefix(relativeToRoot, ".."+string(filepath.Separator)) || relativeToRoot == ".." {
		return "", "", fmt.Errorf("library path escapes audio directory")
	}

	return target, filepath.ToSlash(relativeToRoot), nil
}

func contentTypeForAudioPath(relativePath string) (string, error) {
	ext := strings.ToLower(filepath.Ext(relativePath))
	contentType, ok := allowedTypes[ext]
	if !ok {
		return "", fmt.Errorf("unsupported file type %q", ext)
	}
	return contentType, nil
}

func requestBaseURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	return scheme + "://" + r.Host
}

// streamHandler serves an audio file from audioDir, selected by ?file=.
// http.ServeContent handles Range requests so <audio> can seek and the
// browser can buffer progressively.
func streamHandler(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("path")
	if name == "" {
		name = r.URL.Query().Get("file")
	}
	path, relativePath, err := safeLibraryPath(name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	contentType, err := contentTypeForAudioPath(relativePath)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	audioFile, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			http.Error(w, "File not found", http.StatusNotFound)
		} else {
			http.Error(w, "Could not open file", http.StatusInternalServerError)
		}
		return
	}
	defer audioFile.Close()

	stat, err := audioFile.Stat()
	if err != nil {
		http.Error(w, "Could not stat file", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Accept-Ranges", "bytes")

	http.ServeContent(w, r, filepath.Base(relativePath), stat.ModTime(), audioFile)
}

func writeAlbumMetaData() {
	albumFolders, err := os.ReadDir(audioDir)
	// Audio dir is broken
	if err != nil {
		log.Printf("writeAlbumMetaData: could not read audio dir: %v", err)
		return
	}

	for _, e := range albumFolders {
		// Should be a directory of albums in the audio dir
		if !e.IsDir() {
			continue
		}

		albumDir := filepath.Join(audioDir, e.Name())
		metadataPath := filepath.Join(albumDir, "albumMetadata.json")
		artPath := filepath.Join(albumDir, "albumArt.jpg")

		_, metaErr := os.Stat(metadataPath)
		_, artErr := os.Stat(artPath)
		metadataExists := metaErr == nil
		artExists := artErr == nil

		// Skip if both exist already. Albums without embedded art still keep a
		// metadata file so they can be listed by the frontend.
		if metadataExists && artExists {
			continue
		}

		// Loop over files in album dir
		albumFiles, err2 := os.ReadDir(albumDir)
		// Somehow this dir is broken
		if err2 != nil {
			log.Printf("writeAlbumMetaData: could not read album dir %q: %v", albumDir, err2)
			continue
		}

		var fallbackAlbum *AlbumInfo
		for _, af := range albumFiles {
			if af.IsDir() {
				continue
			}
			if !isAudioFile(af.Name()) {
				continue
			}

			if fallbackAlbum == nil {
				album := defaultAlbumInfo(e.Name())
				fallbackAlbum = &album
			}

			filePath := filepath.Join(albumDir, af.Name())
			f, err := os.Open(filePath)
			if err != nil {
				log.Printf("writeAlbumMetaData: could not open %q: %v", filePath, err)
				continue
			}

			metadata, err := tag.ReadFrom(f)
			f.Close()
			if err != nil {
				log.Printf("writeAlbumMetaData: could not read tags from %q: %v", filePath, err)
				continue
			}

			// Write metadata JSON if it doesn't already exist
			if !metadataExists {
				album := albumInfoFromTags(e.Name(), metadata)
				if picture := metadata.Picture(); picture != nil {
					album.Mime = picture.MIMEType
				}

				if writeAlbumMetadataFile(metadataPath, album) {
					metadataExists = true
				}
			}

			// Write album art JPEG if it doesn't already exist
			if !artExists {
				if picture := metadata.Picture(); picture != nil {
					if err := os.WriteFile(artPath, picture.Data, 0644); err != nil {
						log.Printf("writeAlbumMetaData: could not write %q: %v", artPath, err)
					} else {
						artExists = true
					}
				}
			}

			// We have what we need from this album
			break
		}

		if !metadataExists && fallbackAlbum != nil {
			writeAlbumMetadataFile(metadataPath, *fallbackAlbum)
		}
	}
}

func defaultAlbumInfo(folder string) AlbumInfo {
	return AlbumInfo{
		Folder:   folder,
		Location: folder,
		ArtPath:  filepath.ToSlash(filepath.Join(folder, "albumArt.jpg")),
		Title:    folder,
		Artist:   "N/A",
		Genre:    "N/A",
	}
}

func albumInfoFromTags(folder string, metadata tag.Metadata) AlbumInfo {
	album := defaultAlbumInfo(folder)
	if metadata.Album() != "" {
		album.Title = metadata.Album()
	}
	if metadata.Artist() != "" {
		album.Artist = metadata.Artist()
	}
	if metadata.Year() != 0 {
		album.Year = metadata.Year()
	}
	if metadata.Genre() != "" {
		album.Genre = metadata.Genre()
	}
	return album
}

func writeAlbumMetadataFile(path string, album AlbumInfo) bool {
	data, err := json.MarshalIndent(album, "", "  ")
	if err != nil {
		log.Printf("writeAlbumMetaData: could not marshal metadata for %q: %v", path, err)
		return false
	}
	if err := os.WriteFile(path, data, 0644); err != nil {
		log.Printf("writeAlbumMetaData: could not write %q: %v", path, err)
		return false
	}
	return true
}

func genreCatalogPath() string {
	return filepath.Join(audioDir, genreCatalogFile)
}

func genreColorsPath() string {
	return filepath.Join(audioDir, genreColorsFile)
}

func playlistsPath() string {
	return filepath.Join(audioDir, playlistsFile)
}

func normalizeGenre(value string) string {
	return strings.TrimSpace(value)
}

func genreSortText(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}

func isKnownEmptyGenre(value string) bool {
	normalized := strings.ToLower(strings.TrimSpace(value))
	return normalized == "" || normalized == "n/a" || normalized == "no info"
}

func readGenreCatalog() []string {
	data, err := os.ReadFile(genreCatalogPath())
	if err != nil {
		return nil
	}

	var genres []string
	if err := json.Unmarshal(data, &genres); err != nil {
		log.Printf("readGenreCatalog: could not parse %q: %v", genreCatalogPath(), err)
		return nil
	}
	return genres
}

func writeGenreCatalog(genres []string) error {
	data, err := json.MarshalIndent(genres, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(genreCatalogPath(), data, 0644)
}

func readGenreColors() map[string]string {
	data, err := os.ReadFile(genreColorsPath())
	if err != nil {
		return map[string]string{}
	}

	var colors map[string]string
	if err := json.Unmarshal(data, &colors); err != nil {
		log.Printf("readGenreColors: could not parse %q: %v", genreColorsPath(), err)
		return map[string]string{}
	}
	return colors
}

func writeGenreColors(colors map[string]string) error {
	data, err := json.MarshalIndent(colors, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(genreColorsPath(), data, 0644)
}

func normalizeColorHex(value string) (string, error) {
	trimmed := strings.TrimSpace(value)
	trimmed = strings.TrimPrefix(trimmed, "#")
	if len(trimmed) != 6 {
		return "", fmt.Errorf("color must be a 6-digit hex value")
	}
	for _, char := range trimmed {
		isDigit := char >= '0' && char <= '9'
		isLowerHex := char >= 'a' && char <= 'f'
		isUpperHex := char >= 'A' && char <= 'F'
		if !isDigit && !isLowerHex && !isUpperHex {
			return "", fmt.Errorf("color must be a 6-digit hex value")
		}
	}
	return "#" + strings.ToUpper(trimmed), nil
}

func collectGenreColors(genres []string) map[string]string {
	storedColors := readGenreColors()
	colorsByKey := map[string]string{}
	for genre, color := range storedColors {
		normalizedColor, err := normalizeColorHex(color)
		if err != nil {
			continue
		}
		colorsByKey[genreSortText(genre)] = normalizedColor
	}

	colors := map[string]string{}
	for _, genre := range genres {
		if color := colorsByKey[genreSortText(genre)]; color != "" {
			colors[genre] = color
		}
	}
	return colors
}

func setGenreColor(genre string, color string) (GenreCatalogResponse, error) {
	normalizedGenre := normalizeGenre(genre)
	if isKnownEmptyGenre(normalizedGenre) {
		return GenreCatalogResponse{}, fmt.Errorf("genre is required")
	}
	normalizedColor, err := normalizeColorHex(color)
	if err != nil {
		return GenreCatalogResponse{}, err
	}

	genres, err := addGenreToCatalog(normalizedGenre)
	if err != nil {
		return GenreCatalogResponse{}, err
	}

	colors := collectGenreColors(genres)
	colors[normalizedGenre] = normalizedColor
	if err := writeGenreColors(colors); err != nil {
		return GenreCatalogResponse{}, err
	}

	return GenreCatalogResponse{
		Genres: genres,
		Colors: collectGenreColors(genres),
	}, nil
}

func collectGenres() []string {
	genresByKey := map[string]string{}
	for _, genre := range readGenreCatalog() {
		normalized := normalizeGenre(genre)
		if isKnownEmptyGenre(normalized) {
			continue
		}
		genresByKey[genreSortText(normalized)] = normalized
	}

	entries, err := os.ReadDir(audioDir)
	if err != nil {
		return sortedGenreValues(genresByKey)
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		metadataPath := filepath.Join(audioDir, entry.Name(), "albumMetadata.json")
		data, err := os.ReadFile(metadataPath)
		if err != nil {
			continue
		}
		var album AlbumInfo
		if err := json.Unmarshal(data, &album); err != nil {
			continue
		}
		normalized := normalizeGenre(album.Genre)
		if isKnownEmptyGenre(normalized) {
			continue
		}
		genresByKey[genreSortText(normalized)] = normalized
	}

	return sortedGenreValues(genresByKey)
}

func sortedGenreValues(genresByKey map[string]string) []string {
	genres := make([]string, 0, len(genresByKey))
	for _, genre := range genresByKey {
		genres = append(genres, genre)
	}
	sort.Slice(genres, func(i, j int) bool {
		return genreSortText(genres[i]) < genreSortText(genres[j])
	})
	return genres
}

func addGenreToCatalog(genre string) ([]string, error) {
	normalized := normalizeGenre(genre)
	if isKnownEmptyGenre(normalized) {
		return nil, fmt.Errorf("genre is required")
	}

	genresByKey := map[string]string{}
	for _, existing := range collectGenres() {
		genresByKey[genreSortText(existing)] = existing
	}
	genresByKey[genreSortText(normalized)] = normalized
	genres := sortedGenreValues(genresByKey)
	if err := writeGenreCatalog(genres); err != nil {
		return nil, err
	}
	return genres, nil
}

func removeGenreFromCatalog(genre string) ([]string, error) {
	normalized := normalizeGenre(genre)
	if isKnownEmptyGenre(normalized) {
		return nil, fmt.Errorf("genre is required")
	}

	genresByKey := map[string]string{}
	targetKey := genreSortText(normalized)
	for _, existing := range collectGenres() {
		if genreSortText(existing) == targetKey {
			continue
		}
		genresByKey[genreSortText(existing)] = existing
	}
	genres := sortedGenreValues(genresByKey)
	if err := writeGenreCatalog(genres); err != nil {
		return nil, err
	}
	colors := collectGenreColors(genres)
	if err := writeGenreColors(colors); err != nil {
		return nil, err
	}
	return genres, nil
}

func normalizePlaylistName(value string) string {
	return strings.TrimSpace(value)
}

func readPlaylists() []PlaylistInfo {
	data, err := os.ReadFile(playlistsPath())
	if err != nil {
		return []PlaylistInfo{}
	}

	var playlists []PlaylistInfo
	if err := json.Unmarshal(data, &playlists); err != nil {
		log.Printf("readPlaylists: could not parse %q: %v", playlistsPath(), err)
		return []PlaylistInfo{}
	}
	return normalizePlaylists(playlists)
}

func writePlaylists(playlists []PlaylistInfo) error {
	data, err := json.MarshalIndent(normalizePlaylists(playlists), "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(playlistsPath(), data, 0644)
}

func normalizePlaylists(playlists []PlaylistInfo) []PlaylistInfo {
	normalized := make([]PlaylistInfo, 0, len(playlists))
	seen := map[string]bool{}
	for _, playlist := range playlists {
		playlist.Name = normalizePlaylistName(playlist.Name)
		if playlist.Name == "" {
			playlist.Name = "Untitled Playlist"
		}
		if playlist.ID == "" {
			playlist.ID = uniquePlaylistID(playlist.Name, seen)
		}
		if seen[playlist.ID] {
			playlist.ID = uniquePlaylistID(playlist.Name, seen)
		}
		seen[playlist.ID] = true

		tracks := make([]PlaylistTrackRef, 0, len(playlist.Tracks))
		trackSeen := map[string]bool{}
		for _, track := range playlist.Tracks {
			track.AlbumLocation = filepath.ToSlash(filepath.Clean(filepath.FromSlash(track.AlbumLocation)))
			track.TrackPath = filepath.ToSlash(filepath.Clean(filepath.FromSlash(track.TrackPath)))
			if track.AlbumLocation == "." || track.TrackPath == "." {
				continue
			}
			key := playlistTrackKey(track)
			if trackSeen[key] {
				continue
			}
			trackSeen[key] = true
			tracks = append(tracks, track)
		}
		playlist.Tracks = tracks
		normalized = append(normalized, playlist)
	}
	sort.Slice(normalized, func(i, j int) bool {
		return strings.ToLower(normalized[i].Name) < strings.ToLower(normalized[j].Name)
	})
	return normalized
}

func uniquePlaylistID(name string, existing map[string]bool) string {
	base := playlistIDBase(name)
	if base == "" {
		base = "playlist"
	}
	id := base
	for suffix := 2; existing[id]; suffix++ {
		id = fmt.Sprintf("%s-%d", base, suffix)
	}
	return id
}

func playlistIDBase(name string) string {
	var builder strings.Builder
	lastWasDash := false
	for _, char := range strings.ToLower(name) {
		if (char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') {
			builder.WriteRune(char)
			lastWasDash = false
			continue
		}
		if !lastWasDash {
			builder.WriteRune('-')
			lastWasDash = true
		}
	}
	return strings.Trim(builder.String(), "-")
}

func playlistTrackKey(track PlaylistTrackRef) string {
	return track.AlbumLocation + "::" + track.TrackPath
}

func createPlaylist(name string) ([]PlaylistInfo, PlaylistInfo, error) {
	normalizedName := normalizePlaylistName(name)
	if normalizedName == "" {
		return nil, PlaylistInfo{}, fmt.Errorf("playlist name is required")
	}

	playlists := readPlaylists()
	ids := map[string]bool{}
	for _, playlist := range playlists {
		ids[playlist.ID] = true
	}
	playlist := PlaylistInfo{
		ID:     uniquePlaylistID(normalizedName, ids),
		Name:   normalizedName,
		Tracks: []PlaylistTrackRef{},
	}
	playlists = append(playlists, playlist)
	if err := writePlaylists(playlists); err != nil {
		return nil, PlaylistInfo{}, err
	}
	return readPlaylists(), playlist, nil
}

func renamePlaylist(playlistID string, name string) ([]PlaylistInfo, error) {
	normalizedName := normalizePlaylistName(name)
	if playlistID == "" {
		return nil, fmt.Errorf("playlist id is required")
	}
	if normalizedName == "" {
		return nil, fmt.Errorf("playlist name is required")
	}

	playlists := readPlaylists()
	found := false
	for i := range playlists {
		if playlists[i].ID == playlistID {
			playlists[i].Name = normalizedName
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("playlist not found")
	}
	if err := writePlaylists(playlists); err != nil {
		return nil, err
	}
	return readPlaylists(), nil
}

func deletePlaylist(playlistID string) ([]PlaylistInfo, error) {
	if playlistID == "" {
		return nil, fmt.Errorf("playlist id is required")
	}

	playlists := readPlaylists()
	next := make([]PlaylistInfo, 0, len(playlists))
	found := false
	for _, playlist := range playlists {
		if playlist.ID == playlistID {
			found = true
			continue
		}
		next = append(next, playlist)
	}
	if !found {
		return nil, fmt.Errorf("playlist not found")
	}
	if err := writePlaylists(next); err != nil {
		return nil, err
	}
	return readPlaylists(), nil
}

func addTrackToPlaylist(playlistID string, track PlaylistTrackRef) ([]PlaylistInfo, error) {
	if playlistID == "" {
		return nil, fmt.Errorf("playlist id is required")
	}
	albumPath, albumLocation, err := safeLibraryPath(track.AlbumLocation)
	if err != nil {
		return nil, err
	}
	if info, err := os.Stat(albumPath); err != nil || !info.IsDir() {
		return nil, fmt.Errorf("album folder not found")
	}
	trackPath, trackRelativePath, err := safeLibraryPath(track.TrackPath)
	if err != nil {
		return nil, err
	}
	if _, err := contentTypeForAudioPath(trackRelativePath); err != nil {
		return nil, err
	}
	if info, err := os.Stat(trackPath); err != nil || info.IsDir() {
		return nil, fmt.Errorf("track not found")
	}
	if !strings.HasPrefix(trackRelativePath, albumLocation+"/") {
		return nil, fmt.Errorf("track is not in album")
	}

	track.AlbumLocation = albumLocation
	track.TrackPath = trackRelativePath
	playlists := readPlaylists()
	found := false
	for i := range playlists {
		if playlists[i].ID != playlistID {
			continue
		}
		found = true
		key := playlistTrackKey(track)
		exists := false
		for _, existing := range playlists[i].Tracks {
			if playlistTrackKey(existing) == key {
				exists = true
				break
			}
		}
		if !exists {
			playlists[i].Tracks = append(playlists[i].Tracks, track)
		}
		break
	}
	if !found {
		return nil, fmt.Errorf("playlist not found")
	}
	if err := writePlaylists(playlists); err != nil {
		return nil, err
	}
	return readPlaylists(), nil
}

func removeTrackFromPlaylist(playlistID string, track PlaylistTrackRef) ([]PlaylistInfo, error) {
	if playlistID == "" {
		return nil, fmt.Errorf("playlist id is required")
	}
	track.AlbumLocation = filepath.ToSlash(filepath.Clean(filepath.FromSlash(track.AlbumLocation)))
	track.TrackPath = filepath.ToSlash(filepath.Clean(filepath.FromSlash(track.TrackPath)))
	targetKey := playlistTrackKey(track)

	playlists := readPlaylists()
	found := false
	for i := range playlists {
		if playlists[i].ID != playlistID {
			continue
		}
		found = true
		nextTracks := make([]PlaylistTrackRef, 0, len(playlists[i].Tracks))
		for _, existing := range playlists[i].Tracks {
			if playlistTrackKey(existing) == targetKey {
				continue
			}
			nextTracks = append(nextTracks, existing)
		}
		playlists[i].Tracks = nextTracks
		break
	}
	if !found {
		return nil, fmt.Errorf("playlist not found")
	}
	if err := writePlaylists(playlists); err != nil {
		return nil, err
	}
	return readPlaylists(), nil
}

func clearGenreFromAlbums(genre string) error {
	normalized := normalizeGenre(genre)
	if isKnownEmptyGenre(normalized) {
		return fmt.Errorf("genre is required")
	}
	targetKey := genreSortText(normalized)

	entries, err := os.ReadDir(audioDir)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		metadataPath := filepath.Join(audioDir, entry.Name(), "albumMetadata.json")
		data, err := os.ReadFile(metadataPath)
		if err != nil {
			continue
		}

		album := defaultAlbumInfo(entry.Name())
		if err := json.Unmarshal(data, &album); err != nil {
			log.Printf("clearGenreFromAlbums: could not parse %q: %v", metadataPath, err)
			continue
		}
		if genreSortText(album.Genre) != targetKey {
			continue
		}

		if album.Folder == "" {
			album.Folder = entry.Name()
		}
		if album.Location == "" {
			album.Location = album.Folder
		}
		if album.ArtPath == "" {
			album.ArtPath = filepath.ToSlash(filepath.Join(album.Location, "albumArt.jpg"))
		}
		if album.Title == "" {
			album.Title = entry.Name()
		}
		if album.Artist == "" {
			album.Artist = "N/A"
		}
		album.Genre = ""

		if !writeAlbumMetadataFile(metadataPath, album) {
			return fmt.Errorf("could not update album metadata for %q", entry.Name())
		}
	}

	return nil
}

// safeAlbumDir validates a user-supplied album folder name and returns
// the path to that album folder inside audioDir. It rejects path-traversal
// attempts and any name that doesn't correspond to an existing directory.
func safeAlbumDir(name string) (string, error) {
	if name == "" {
		return "", fmt.Errorf("empty folder name")
	}
	if strings.ContainsAny(name, `/\`) || name == "." || name == ".." {
		return "", fmt.Errorf("invalid folder name")
	}
	if filepath.Base(name) != name {
		return "", fmt.Errorf("invalid folder name")
	}

	path := filepath.Join(audioDir, name)
	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("album folder not found")
	}
	if !info.IsDir() {
		return "", fmt.Errorf("not an album folder")
	}
	return path, nil
}

// getAlbumLibraryFromMetadata reads each album subdirectory's
// albumMetadata.json file and aggregates them into a single slice.
// Albums missing a metadata file are skipped (call writeAlbumMetaData first).
func getAlbumLibraryFromMetadata() ([]AlbumInfo, error) {
	entries, err := os.ReadDir(audioDir)
	if err != nil {
		return nil, err
	}

	var library []AlbumInfo
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}

		album := defaultAlbumInfo(e.Name())
		metadataPath := filepath.Join(audioDir, e.Name(), "albumMetadata.json")
		data, err := os.ReadFile(metadataPath)
		if err == nil {
			if err := json.Unmarshal(data, &album); err != nil {
				log.Printf("getAlbumLibraryFromMetadata: could not parse %q: %v", metadataPath, err)
				album = defaultAlbumInfo(e.Name())
			}
		} else {
			log.Printf("getAlbumLibraryFromMetadata: using folder defaults for %q: %v", e.Name(), err)
		}

		// Make sure folder is populated even if the JSON pre-dates the field.
		if album.Folder == "" {
			album.Folder = e.Name()
		}
		if album.Location == "" {
			album.Location = album.Folder
		}
		if album.ArtPath == "" {
			album.ArtPath = filepath.ToSlash(filepath.Join(album.Location, "albumArt.jpg"))
		}
		if album.Title == "" {
			album.Title = album.Folder
		}
		if album.Artist == "" {
			album.Artist = "N/A"
		}
		if album.Genre == "" {
			album.Genre = "N/A"
		}
		album.Tracks = getAlbumTracks(album.Location)
		library = append(library, album)
	}
	return library, nil
}

func getAlbumTracks(albumLocation string) []TrackInfo {
	albumDir, _, err := safeLibraryPath(albumLocation)
	if err != nil {
		log.Printf("getAlbumTracks: invalid album location %q: %v", albumLocation, err)
		return nil
	}

	files, err := os.ReadDir(albumDir)
	if err != nil {
		log.Printf("getAlbumTracks: could not read album dir %q: %v", albumLocation, err)
		return nil
	}

	var tracks []TrackInfo
	for _, file := range files {
		if file.IsDir() || !isAudioFile(file.Name()) {
			continue
		}

		trackPath := filepath.ToSlash(filepath.Join(albumLocation, file.Name()))
		tracks = append(tracks, trackInfoFromFile(filepath.Join(albumDir, file.Name()), trackPath, file.Name()))
	}
	return tracks
}

func trackInfoFromFile(path string, relativePath string, fileName string) TrackInfo {
	track := TrackInfo{
		Title:  fileNameWithoutExt(fileName),
		Path:   relativePath,
		Format: formatFromExt(fileName),
	}

	if contentType, err := contentTypeForAudioPath(relativePath); err == nil {
		track.MimeType = contentType
	}
	if stat, err := os.Stat(path); err == nil {
		track.FileSizeBytes = stat.Size()
	}
	if bitrate, err := audioBitrateKbps(path, relativePath); err == nil && bitrate > 0 {
		track.BitrateKbps = bitrate
	}

	f, err := os.Open(path)
	if err != nil {
		return track
	}
	defer f.Close()

	metadata, err := tag.ReadFrom(f)
	if err != nil {
		return track
	}

	if title := strings.TrimSpace(metadata.Title()); title != "" {
		track.Title = title
	}
	if fileType := strings.TrimSpace(string(metadata.FileType())); fileType != "" {
		track.Format = strings.ToUpper(fileType)
	}
	if metadataFormat := strings.TrimSpace(string(metadata.Format())); metadataFormat != "" {
		track.MetadataFormat = metadataFormat
	}
	if artist := strings.TrimSpace(metadata.Artist()); artist != "" {
		track.Artist = artist
	}
	if album := strings.TrimSpace(metadata.Album()); album != "" {
		track.Album = album
	}
	if genre := strings.TrimSpace(metadata.Genre()); genre != "" {
		track.Genre = genre
	}
	if year := metadata.Year(); year != 0 {
		track.Year = year
	}
	if number, total := metadata.Track(); number != 0 || total != 0 {
		track.TrackNumber = number
		track.TrackTotal = total
	}
	if number, total := metadata.Disc(); number != 0 || total != 0 {
		track.DiscNumber = number
		track.DiscTotal = total
	}

	return track
}

func fileNameWithoutExt(name string) string {
	return strings.TrimSuffix(name, filepath.Ext(name))
}

func formatFromExt(name string) string {
	ext := strings.TrimPrefix(filepath.Ext(name), ".")
	if ext == "" {
		return ""
	}
	return strings.ToUpper(ext)
}

func audioBitrateKbps(path string, relativePath string) (int, error) {
	switch strings.ToLower(filepath.Ext(relativePath)) {
	case ".mp3":
		return mp3BitrateKbps(path)
	case ".wav":
		return wavBitrateKbps(path)
	default:
		return 0, fmt.Errorf("bitrate unavailable")
	}
}

func mp3BitrateKbps(path string) (int, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	data := make([]byte, 64*1024)
	n, err := file.Read(data)
	if err != nil && err != io.EOF {
		return 0, err
	}
	data = data[:n]

	for i := 0; i+4 <= len(data); i++ {
		header := binary.BigEndian.Uint32(data[i : i+4])
		if header&0xffe00000 != 0xffe00000 {
			continue
		}

		versionID := (header >> 19) & 0x3
		layerIndex := (header >> 17) & 0x3
		bitrateIndex := (header >> 12) & 0xf
		if versionID == 1 || layerIndex == 0 || bitrateIndex == 0 || bitrateIndex == 15 {
			continue
		}

		bitrate := mp3BitrateFromHeader(versionID, layerIndex, bitrateIndex)
		if bitrate > 0 {
			return bitrate, nil
		}
	}

	return 0, fmt.Errorf("mp3 bitrate frame not found")
}

func mp3BitrateFromHeader(versionID uint32, layerIndex uint32, bitrateIndex uint32) int {
	mpeg1Layer1 := []int{0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448}
	mpeg1Layer2 := []int{0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384}
	mpeg1Layer3 := []int{0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320}
	mpeg2Layer1 := []int{0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256}
	mpeg2Layer23 := []int{0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160}

	index := int(bitrateIndex)
	if versionID == 3 {
		switch layerIndex {
		case 3:
			return mpeg1Layer1[index]
		case 2:
			return mpeg1Layer2[index]
		default:
			return mpeg1Layer3[index]
		}
	}

	if layerIndex == 3 {
		return mpeg2Layer1[index]
	}
	return mpeg2Layer23[index]
}

func wavBitrateKbps(path string) (int, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()

	header := make([]byte, 12)
	if _, err := io.ReadFull(file, header); err != nil {
		return 0, err
	}
	if string(header[0:4]) != "RIFF" || string(header[8:12]) != "WAVE" {
		return 0, fmt.Errorf("not a wav file")
	}

	chunkHeader := make([]byte, 8)
	for {
		if _, err := io.ReadFull(file, chunkHeader); err != nil {
			return 0, err
		}
		chunkID := string(chunkHeader[0:4])
		chunkSize := int64(binary.LittleEndian.Uint32(chunkHeader[4:8]))

		if chunkID == "fmt " {
			data := make([]byte, chunkSize)
			if _, err := io.ReadFull(file, data); err != nil {
				return 0, err
			}
			if len(data) < 12 {
				return 0, fmt.Errorf("invalid wav fmt chunk")
			}
			byteRate := binary.LittleEndian.Uint32(data[8:12])
			return int((byteRate * 8) / 1000), nil
		}

		skip := chunkSize
		if skip%2 == 1 {
			skip++
		}
		if _, err := file.Seek(skip, io.SeekCurrent); err != nil {
			return 0, err
		}
	}
}

func hydrateAlbumURLs(r *http.Request, album *AlbumInfo) {
	baseURL := requestBaseURL(r)
	album.ArtURL = baseURL + "/albumArt?path=" + url.QueryEscape(album.ArtPath)
	for i := range album.Tracks {
		album.Tracks[i].StreamURL = baseURL + "/stream?path=" + url.QueryEscape(album.Tracks[i].Path)
	}
}

func hydrateLibraryURLs(r *http.Request, library []AlbumInfo) {
	for i := range library {
		hydrateAlbumURLs(r, &library[i])
	}
}

// libraryHandler serves the aggregated metadata for all albums as JSON.
func libraryHandler(w http.ResponseWriter, r *http.Request) {
	library, err := getAlbumLibraryFromMetadata()
	if err != nil {
		http.Error(w, "Could not read library: "+err.Error(), http.StatusInternalServerError)
		return
	}
	hydrateLibraryURLs(r, library)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(library)
}

func refreshLibraryHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request RefreshLibraryRequest
	if r.Body != nil {
		defer r.Body.Close()
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, "invalid refresh request: "+err.Error(), http.StatusBadRequest)
			return
		}
	}

	known := map[string]bool{}
	for _, location := range request.KnownLocations {
		known[filepath.ToSlash(filepath.Clean(filepath.FromSlash(location)))] = true
	}

	writeAlbumMetaData()
	library, err := getAlbumLibraryFromMetadata()
	if err != nil {
		http.Error(w, "Could not refresh library: "+err.Error(), http.StatusInternalServerError)
		return
	}

	newAlbums := []AlbumInfo{}
	for _, album := range library {
		location := filepath.ToSlash(filepath.Clean(filepath.FromSlash(album.Location)))
		if known[location] {
			continue
		}
		newAlbums = append(newAlbums, album)
	}
	hydrateLibraryURLs(r, newAlbums)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(RefreshLibraryResponse{
		NewAlbums: newAlbums,
		Count:     len(newAlbums),
	})
}

func genresHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		genres := collectGenres()
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		json.NewEncoder(w).Encode(GenreCatalogResponse{
			Genres: genres,
			Colors: collectGenreColors(genres),
		})
	case http.MethodPost:
		var request GenreRequest
		if r.Body != nil {
			defer r.Body.Close()
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, "invalid genre request: "+err.Error(), http.StatusBadRequest)
			return
		}
		genres, err := addGenreToCatalog(request.Genre)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		json.NewEncoder(w).Encode(GenreCatalogResponse{
			Genres: genres,
			Colors: collectGenreColors(genres),
		})
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func genreColorHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request GenreColorRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid genre color request: "+err.Error(), http.StatusBadRequest)
		return
	}

	response, err := setGenreColor(request.Genre, request.Color)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(response)
}

func removeGenreHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request GenreRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid genre request: "+err.Error(), http.StatusBadRequest)
		return
	}

	if err := clearGenreFromAlbums(request.Genre); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	genres, err := removeGenreFromCatalog(request.Genre)
	if err != nil {
		http.Error(w, "could not remove genre: "+err.Error(), http.StatusInternalServerError)
		return
	}

	library, err := getAlbumLibraryFromMetadata()
	if err != nil {
		http.Error(w, "could not refresh library: "+err.Error(), http.StatusInternalServerError)
		return
	}
	hydrateLibraryURLs(r, library)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(GenreRemovalResponse{
		Genres: genres,
		Colors: collectGenreColors(genres),
		Albums: library,
	})
}

func updateAlbumGenreHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request UpdateAlbumGenreRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid album genre request: "+err.Error(), http.StatusBadRequest)
		return
	}

	genre := normalizeGenre(request.Genre)
	if isKnownEmptyGenre(genre) {
		http.Error(w, "genre is required", http.StatusBadRequest)
		return
	}

	albumDir, relativeLocation, err := safeLibraryPath(request.Location)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	info, err := os.Stat(albumDir)
	if err != nil || !info.IsDir() {
		http.Error(w, "album folder not found", http.StatusBadRequest)
		return
	}

	folder := filepath.Base(albumDir)
	album := defaultAlbumInfo(folder)
	metadataPath := filepath.Join(albumDir, "albumMetadata.json")
	if data, err := os.ReadFile(metadataPath); err == nil {
		if err := json.Unmarshal(data, &album); err != nil {
			log.Printf("updateAlbumGenreHandler: could not parse %q: %v", metadataPath, err)
			album = defaultAlbumInfo(folder)
		}
	}
	album.Folder = folder
	album.Location = relativeLocation
	if album.ArtPath == "" {
		album.ArtPath = filepath.ToSlash(filepath.Join(album.Location, "albumArt.jpg"))
	}
	if album.Title == "" {
		album.Title = folder
	}
	if album.Artist == "" {
		album.Artist = "N/A"
	}
	album.Genre = genre

	if _, err := addGenreToCatalog(genre); err != nil {
		http.Error(w, "could not save genre: "+err.Error(), http.StatusInternalServerError)
		return
	}
	if !writeAlbumMetadataFile(metadataPath, album) {
		http.Error(w, "could not update album metadata", http.StatusInternalServerError)
		return
	}

	album.Tracks = getAlbumTracks(album.Location)
	hydrateAlbumURLs(r, &album)
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(album)
}

func playlistsHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		json.NewEncoder(w).Encode(PlaylistsResponse{Playlists: readPlaylists()})
	case http.MethodPost:
		var request PlaylistNameRequest
		if r.Body != nil {
			defer r.Body.Close()
		}
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			http.Error(w, "invalid playlist request: "+err.Error(), http.StatusBadRequest)
			return
		}
		playlists, playlist, err := createPlaylist(request.Name)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		json.NewEncoder(w).Encode(PlaylistMutationResponse{
			Playlists: playlists,
			Playlist:  &playlist,
		})
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func renamePlaylistHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request PlaylistNameRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid playlist request: "+err.Error(), http.StatusBadRequest)
		return
	}
	playlists, err := renamePlaylist(request.PlaylistID, request.Name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(PlaylistsResponse{Playlists: playlists})
}

func deletePlaylistHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request PlaylistIDRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid playlist request: "+err.Error(), http.StatusBadRequest)
		return
	}
	playlists, err := deletePlaylist(request.PlaylistID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(PlaylistsResponse{Playlists: playlists})
}

func addPlaylistTrackHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request PlaylistTrackRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid playlist track request: "+err.Error(), http.StatusBadRequest)
		return
	}
	playlists, err := addTrackToPlaylist(request.PlaylistID, request.Track)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(PlaylistsResponse{Playlists: playlists})
}

func removePlaylistTrackHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var request PlaylistTrackRequest
	if r.Body != nil {
		defer r.Body.Close()
	}
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid playlist track request: "+err.Error(), http.StatusBadRequest)
		return
	}
	playlists, err := removeTrackFromPlaylist(request.PlaylistID, request.Track)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(PlaylistsResponse{Playlists: playlists})
}

// albumArtHandler serves album art from a metadata-provided ?path= value.
// It also supports the older ?folder=AlbumName shape.
func albumArtHandler(w http.ResponseWriter, r *http.Request) {
	artPathQuery := r.URL.Query().Get("path")
	if artPathQuery == "" {
		folder := r.URL.Query().Get("folder")
		albumDir, err := safeAlbumDir(folder)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		artPathQuery = filepath.ToSlash(filepath.Join(folder, "albumArt.jpg"))
		_ = albumDir
	}

	artPath, _, err := safeLibraryPath(artPathQuery)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	artName := strings.ToLower(filepath.Base(artPath))
	if artName != "albumart.jpg" && artName != "albumart.jpeg" && artName != "albumart.png" {
		http.Error(w, "invalid album art path", http.StatusBadRequest)
		return
	}
	if _, err := os.Stat(artPath); err != nil {
		http.Error(w, "album art not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFile(w, r, artPath)
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "ok",
		"audio_dir": audioDir,
	})
}

func serverInfoHandler(w http.ResponseWriter, r *http.Request) {
	port := getEnv("FOF_PORT", defaultPort)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ServerInfo{
		BaseURL:  requestBaseURL(r),
		AudioDir: audioDir,
		Host:     getEnv("FOF_HOST", defaultHost),
		Port:     port,
		LANURLs:  localNetworkURLs(port),
	})
}

func localNetworkURLs(port string) []string {
	var urls []string
	interfaces, err := net.Interfaces()
	if err != nil {
		return urls
	}

	for _, iface := range interfaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch value := addr.(type) {
			case *net.IPNet:
				ip = value.IP
			case *net.IPAddr:
				ip = value.IP
			}
			if ip == nil || ip.To4() == nil {
				continue
			}
			urls = append(urls, "http://"+ip.String()+":"+port)
		}
	}
	return urls
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Range")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	if _, err := os.Stat(audioDir); os.IsNotExist(err) {
		log.Printf("warning: %q directory does not exist; create it and drop audio files in.", audioDir)
	}
	// Preprocessing for albums the user has already added
	writeAlbumMetaData()

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/server-info", serverInfoHandler)
	mux.HandleFunc("/stream", streamHandler)
	mux.HandleFunc("/library", libraryHandler)
	mux.HandleFunc("/refresh", refreshLibraryHandler)
	mux.HandleFunc("/genres", genresHandler)
	mux.HandleFunc("/genres/color", genreColorHandler)
	mux.HandleFunc("/genres/remove", removeGenreHandler)
	mux.HandleFunc("/album/genre", updateAlbumGenreHandler)
	mux.HandleFunc("/playlists", playlistsHandler)
	mux.HandleFunc("/playlists/rename", renamePlaylistHandler)
	mux.HandleFunc("/playlists/delete", deletePlaylistHandler)
	mux.HandleFunc("/playlists/add-track", addPlaylistTrackHandler)
	mux.HandleFunc("/playlists/remove-track", removePlaylistTrackHandler)
	mux.HandleFunc("/albumArt", albumArtHandler)

	host := getEnv("FOF_HOST", defaultHost)
	port := getEnv("FOF_PORT", defaultPort)
	addr := net.JoinHostPort(host, port)
	log.Printf("Listening on http://%s", addr)
	for _, lanURL := range localNetworkURLs(port) {
		log.Printf("LAN URL: %s", lanURL)
	}
	log.Fatal(http.ListenAndServe(addr, withCORS(mux)))
}

type AlbumInfo struct {
	Folder   string      `json:"folder"`   // Album folder name within audioDir
	Location string      `json:"location"` // Relative album path inside the host's audio library
	ArtPath  string      `json:"art_path"`
	ArtURL   string      `json:"art_url,omitempty"`
	Tracks   []TrackInfo `json:"tracks"`
	Artist   string      `json:"artist"`
	Title    string      `json:"title"`
	Year     int         `json:"year"`
	Genre    string      `json:"genre"`
	Mime     string      `json:"mime_type"` // e.g., "image/jpeg"
}

type TrackInfo struct {
	Title          string `json:"title"`
	Path           string `json:"path"`
	StreamURL      string `json:"stream_url,omitempty"`
	Format         string `json:"format,omitempty"`
	MimeType       string `json:"mime_type,omitempty"`
	MetadataFormat string `json:"metadata_format,omitempty"`
	FileSizeBytes  int64  `json:"file_size_bytes,omitempty"`
	BitrateKbps    int    `json:"bitrate_kbps,omitempty"`
	Artist         string `json:"artist,omitempty"`
	Album          string `json:"album,omitempty"`
	Year           int    `json:"year,omitempty"`
	Genre          string `json:"genre,omitempty"`
	TrackNumber    int    `json:"track_number,omitempty"`
	TrackTotal     int    `json:"track_total,omitempty"`
	DiscNumber     int    `json:"disc_number,omitempty"`
	DiscTotal      int    `json:"disc_total,omitempty"`
}

type ServerInfo struct {
	BaseURL  string   `json:"base_url"`
	AudioDir string   `json:"audio_dir"`
	Host     string   `json:"host"`
	Port     string   `json:"port"`
	LANURLs  []string `json:"lan_urls"`
}

type RefreshLibraryRequest struct {
	KnownLocations []string `json:"known_locations"`
}

type RefreshLibraryResponse struct {
	NewAlbums []AlbumInfo `json:"new_albums"`
	Count     int         `json:"count"`
}

type GenreCatalogResponse struct {
	Genres []string          `json:"genres"`
	Colors map[string]string `json:"colors"`
}

type GenreRemovalResponse struct {
	Genres []string          `json:"genres"`
	Colors map[string]string `json:"colors"`
	Albums []AlbumInfo       `json:"albums"`
}

type GenreRequest struct {
	Genre string `json:"genre"`
}

type GenreColorRequest struct {
	Genre string `json:"genre"`
	Color string `json:"color"`
}

type UpdateAlbumGenreRequest struct {
	Location string `json:"location"`
	Genre    string `json:"genre"`
}

type PlaylistInfo struct {
	ID     string             `json:"id"`
	Name   string             `json:"name"`
	Tracks []PlaylistTrackRef `json:"tracks"`
}

type PlaylistTrackRef struct {
	AlbumLocation string `json:"album_location"`
	TrackPath     string `json:"track_path"`
}

type PlaylistsResponse struct {
	Playlists []PlaylistInfo `json:"playlists"`
}

type PlaylistMutationResponse struct {
	Playlists []PlaylistInfo `json:"playlists"`
	Playlist  *PlaylistInfo  `json:"playlist,omitempty"`
}

type PlaylistIDRequest struct {
	PlaylistID string `json:"playlist_id"`
}

type PlaylistNameRequest struct {
	PlaylistID string `json:"playlist_id,omitempty"`
	Name       string `json:"name"`
}

type PlaylistTrackRequest struct {
	PlaylistID string           `json:"playlist_id"`
	Track      PlaylistTrackRef `json:"track"`
}
