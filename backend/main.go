package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gopxl/beep/mp3"
	"github.com/gopxl/beep/wav"
)

type nopSeeker struct {
	http.ResponseWriter
}

func (n *nopSeeker) Seek(offset int64, whence int) (int64, error) {
	return 0, nil // Lie to the encoder that we seeked successfully
}

func streamHandler(w http.ResponseWriter, r *http.Request) {
	f, err := os.Open("Sonic Mega Collection Plus - Game Library, Extras, & Options.mp3")
	if err != nil {
		http.Error(w, "File not found", 404)
		return
	}
	defer f.Close()

	// Decode the MP3
	streamer, format, err := mp3.Decode(f)
	if err != nil {
		http.Error(w, "Decode error", 500)
		return
	}
	defer streamer.Close()

	// Set headers for audio streaming
	w.Header().Set("Content-Type", "audio/mpeg")
	w.Header().Set("Transfer-Encoding", "chunked")

	writer := &nopSeeker{w}
	// Encode Beep's streamer back into a WAV stream for the browser
	if err := wav.Encode(writer, streamer, format); err != nil {
		log.Println("Streaming error:", err)
	}
}

func main() {
	http.HandleFunc("/stream", streamHandler)
	// Provide paths to your SSL certificate and key
	log.Fatal(http.ListenAndServeTLS(":8080", "localhost.pem", "localhost-key.pem", nil))
}

// func main() {
// 	f, err := os.Open("Sonic Mega Collection Plus - Game Library, Extras, & Options.mp3")
// 	if err != nil {
// 		log.Fatal(err)
// 	}

// 	streamer, format, err := mp3.Decode(f)
// 	if err != nil {
// 		log.Fatal(err)
// 	}
// 	defer streamer.Close()

// 	speaker.Init(format.SampleRate, format.SampleRate.N(time.Second))

// 	loop := beep.Loop(3, streamer)

// 	done := make(chan bool)
// 	speaker.Play(beep.Seq(loop, beep.Callback(func() {
// 		done <- true
// 	})))

// 	<-done
// }
