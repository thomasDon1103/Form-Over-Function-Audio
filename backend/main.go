package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

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

// Returns a JSON object of all of the albums in the audio dir
func getAlbumLibrary() ([]AlbumInfo, error) {
	entries, err := os.ReadDir(audioDir)
	if err != nil {
		return nil, err
	}
	var library []AlbumInfo
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if _, ok := allowedTypes[ext]; ok {
			path, _, err := safeAudioPath(e.Name())
			f, err := os.Open(path)
			if err != nil {
				log.Fatal(err)
			}
			defer f.Close()
			var album AlbumInfo

			fmt.Print(path + "\n")

			// Read metadata tags
			metadata, err := tag.ReadFrom(f)

			// @todo Need to do metadata error handling
			if err != nil {
				library = append(library, album)
				continue
			}

			album.Title = metadata.Title()
			album.Artist = metadata.Artist()

			// Handle Image
			if picture := metadata.Picture(); picture != nil {
				// Encode bytes to Base64 string
				b64 := base64.StdEncoding.EncodeToString(picture.Data)
				album.Image = b64
				album.Mime = picture.MIMEType
			}
			library = append(library, album)
		}
	}
	return library, nil
}

// indexHandler serves a JSON response for all of the albums in the Audio folder
func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	library, err := getAlbumLibrary()
	if err != nil {
		http.Error(w, "Could not list audio dir: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(library)
}

// Test endpoint for serving images via https
func imageHandler(w http.ResponseWriter, r *http.Request) {
	// Open the audio file (MP3 or FLAC)
	name := r.URL.Query().Get("file")
	if name == "" {
		name = defaultFile
	}

	path, _, err := safeAudioPath(name)
	albumFile, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	defer albumFile.Close()

	// Read metadata tags
	metadata, err := tag.ReadFrom(albumFile)

	if err != nil {
		log.Fatal(err)
	}

	// Extract the picture
	albumImage := metadata.Picture()
	if albumImage == nil {
		fmt.Println("No album art found.")
		return
	}

	// Access image metadata and raw bytes
	fmt.Printf("Format: %s\n", albumImage.MIMEType)
	fmt.Printf("Extension: %s\n", albumImage.Ext)

	w.Header().Set("Content-Type", albumImage.MIMEType)
	http.ServeContent(w, r, "cover", time.Time{}, bytes.NewReader(albumImage.Data))
}

func main() {
	if _, err := os.Stat(audioDir); os.IsNotExist(err) {
		log.Printf("warning: %q directory does not exist; create it and drop audio files in.", audioDir)
	}

	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/stream", streamHandler)
	http.HandleFunc("/art", imageHandler)

	log.Println("Listening on https://localhost:8080")
	log.Fatal(http.ListenAndServeTLS(":8080", "localhost.pem", "localhost-key.pem", nil))
}

type AlbumInfo struct {
	Artist string `json:"artist"`
	Title  string `json:"title"`
	Image  string `json:"image"`     // Base64 string
	Mime   string `json:"mime_type"` // e.g., "image/jpeg"
}
