package main

import (
	"fmt"
	"html"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// audioDir is the only directory from which /stream will serve files.
// Drop your .mp3 / .flac / .wav files in here.
const audioDir = "audio"

// defaultFile is served when /stream is hit with no ?file= query.
const defaultFile = "Sonic Mega Collection Plus - Game Library, Extras, & Options.mp3"

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

	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			http.Error(w, "File not found", http.StatusNotFound)
		} else {
			http.Error(w, "Could not open file", http.StatusInternalServerError)
		}
		return
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		http.Error(w, "Could not stat file", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Accept-Ranges", "bytes")

	http.ServeContent(w, r, name, stat.ModTime(), f)
}

// listAudioFiles returns the supported audio files inside audioDir.
func listAudioFiles() ([]string, error) {
	entries, err := os.ReadDir(audioDir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if _, ok := allowedTypes[ext]; ok {
			out = append(out, e.Name())
		}
	}
	return out, nil
}

// indexHandler serves a tiny HTML page with an <audio> element per file
// so you can test /stream by visiting https://localhost:8080/ .
func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	files, err := listAudioFiles()
	if err != nil {
		http.Error(w, "Could not list audio dir: "+err.Error(), http.StatusInternalServerError)
		return
	}

	var b strings.Builder
	b.WriteString(`<!doctype html>
<html>
  <head><title>Audio Stream Test</title></head>
  <body>
    <h1>Audio Stream Test</h1>
`)
	if len(files) == 0 {
		fmt.Fprintf(&b, "    <p>No audio files found in <code>%s/</code>.</p>\n", html.EscapeString(audioDir))
	}
	for _, name := range files {
		escName := html.EscapeString(name)
		// url.QueryEscape would be more correct, but for an in-browser
		// test page using the browser's own URL handling is fine.
		fmt.Fprintf(&b, `    <section>
      <h3>%s</h3>
      <audio controls preload="none" src="/stream?file=%s"></audio>
    </section>
`, escName, escName)
	}
	b.WriteString("  </body>\n</html>")

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(b.String()))
}

func main() {
	if _, err := os.Stat(audioDir); os.IsNotExist(err) {
		log.Printf("warning: %q directory does not exist; create it and drop audio files in.", audioDir)
	}

	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/stream", streamHandler)

	log.Println("Listening on https://localhost:8080")
	log.Fatal(http.ListenAndServeTLS(":8080", "localhost.pem", "localhost-key.pem", nil))
}

