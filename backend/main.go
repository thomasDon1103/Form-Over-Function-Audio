package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/dhowden/tag"
)

// audioDir is the only directory from which /stream will serve files.
// Drop your .mp3 / .flac / .wav files in here.
const audioDir = "audio"

// defaultFile is served when /stream is hit with no ?file= query.
const defaultFile = "Florida Rains - Smoked Old Fashioned - 01 Lowball Glass.mp3"

// allowedTypes maps a file extension (lowercase, with dot) to the
// Content-Type we'll advertise. Anything not in this map is rejected.
var allowedTypes = map[string]string{
	".mp3":  "audio/mpeg",
	".flac": "audio/flac",
	".wav":  "audio/wav",
}

// safeAudioPath validates a user-supplied filename and returns the
// absolute path to the file inside audioDir. It rejects anything that
// looks like a path-traversal attempt or has an unsupported extension.
func safeAudioPath(name string) (path, contentType string, err error) {
	if name == "" {
		return "", "", fmt.Errorf("empty filename")
	}
	// Disallow any path separators or parent-dir refs; only a basename is OK.
	if strings.ContainsAny(name, `/\`) || name == "." || name == ".." {
		return "", "", fmt.Errorf("invalid filename")
	}
	// filepath.Base is a defense-in-depth: even if something slipped through.
	if filepath.Base(name) != name {
		return "", "", fmt.Errorf("invalid filename")
	}

	ext := strings.ToLower(filepath.Ext(name))
	ct, ok := allowedTypes[ext]
	if !ok {
		return "", "", fmt.Errorf("unsupported file type %q", ext)
	}

	return filepath.Join(audioDir, name), ct, nil
}

// streamHandler serves an audio file from audioDir, selected by ?file=.
// http.ServeContent handles Range requests so <audio> can seek and the
// browser can buffer progressively.
func streamHandler(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("file")
	if name == "" {
		name = defaultFile
	}

	path, contentType, err := safeAudioPath(name)
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

	http.ServeContent(w, r, name, stat.ModTime(), audioFile)
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

		// Skip if both exist already
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

		for _, af := range albumFiles {
			if af.IsDir() {
				continue
			}
			ext := strings.ToLower(filepath.Ext(af.Name()))
			if ext != ".mp3" && ext != ".flac" {
				continue
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
				album := AlbumInfo{
					Folder: e.Name(),
					Title:  metadata.Album(),
					Artist: metadata.Artist(),
					Year:   metadata.Year(),
					Genre:  metadata.Genre(),
				}
				if picture := metadata.Picture(); picture != nil {
					album.Mime = picture.MIMEType
				}

				data, err := json.MarshalIndent(album, "", "  ")
				if err != nil {
					log.Printf("writeAlbumMetaData: could not marshal metadata for %q: %v", albumDir, err)
				} else if err := os.WriteFile(metadataPath, data, 0644); err != nil {
					log.Printf("writeAlbumMetaData: could not write %q: %v", metadataPath, err)
				} else {
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
	}
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

		metadataPath := filepath.Join(audioDir, e.Name(), "albumMetadata.json")
		data, err := os.ReadFile(metadataPath)
		if err != nil {
			log.Printf("getAlbumLibraryFromMetadata: skipping %q: %v", e.Name(), err)
			continue
		}

		var album AlbumInfo
		if err := json.Unmarshal(data, &album); err != nil {
			log.Printf("getAlbumLibraryFromMetadata: could not parse %q: %v", metadataPath, err)
			continue
		}

		// Make sure folder is populated even if the JSON pre-dates the field.
		if album.Folder == "" {
			album.Folder = e.Name()
		}
		library = append(library, album)
	}
	return library, nil
}

// libraryHandler serves the aggregated metadata for all albums as JSON.
func libraryHandler(w http.ResponseWriter, r *http.Request) {
	library, err := getAlbumLibraryFromMetadata()
	if err != nil {
		http.Error(w, "Could not read library: "+err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-cache")
	json.NewEncoder(w).Encode(library)
}

// albumArtHandler serves the albumArt.jpg for the album folder named in ?folder=.
func albumArtHandler(w http.ResponseWriter, r *http.Request) {
	folder := r.URL.Query().Get("folder")
	albumDir, err := safeAlbumDir(folder)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	artPath := filepath.Join(albumDir, "albumArt.jpg")
	if _, err := os.Stat(artPath); err != nil {
		http.Error(w, "album art not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFile(w, r, artPath)
}

func main() {
	if _, err := os.Stat(audioDir); os.IsNotExist(err) {
		log.Printf("warning: %q directory does not exist; create it and drop audio files in.", audioDir)
	}
	// Preprocessing for albums the user has already added
	writeAlbumMetaData()

	http.HandleFunc("/stream", streamHandler)
	http.HandleFunc("/library", libraryHandler)
	http.HandleFunc("/albumArt", albumArtHandler)

	log.Println("Listening on https://localhost:8080")
	log.Fatal(http.ListenAndServeTLS(":8080", "localhost.pem", "localhost-key.pem", nil))
}

type AlbumInfo struct {
	Folder string `json:"folder"` // Album folder name within audioDir
	Artist string `json:"artist"`
	Title  string `json:"title"`
	Year   int    `json:"year"`
	Genre  string `json:"genre"`
	Mime   string `json:"mime_type"` // e.g., "image/jpeg"
}
