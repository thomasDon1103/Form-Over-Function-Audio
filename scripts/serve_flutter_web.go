package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	root := flag.String("root", `C:\Development\Form-Over-Function-Audio\frontend\form_over_function_audio\build\web`, "Flutter web build directory")
	addr := flag.String("addr", "127.0.0.1:55231", "listen address")
	flag.Parse()

	rootPath, err := filepath.Abs(*root)
	if err != nil {
		log.Fatal(err)
	}

	indexPath := filepath.Join(rootPath, "index.html")
	if _, err := os.Stat(indexPath); err != nil {
		log.Fatalf("index.html is not available in %s: %v", rootPath, err)
	}

	fileServer := http.FileServer(http.Dir(rootPath))
	handler := http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/" {
			fileServer.ServeHTTP(response, request)
			return
		}

		cleanPath := filepath.Clean(strings.TrimPrefix(request.URL.Path, "/"))
		targetPath := filepath.Join(rootPath, cleanPath)
		if _, err := os.Stat(targetPath); err == nil {
			fileServer.ServeHTTP(response, request)
			return
		}

		http.ServeFile(response, request, indexPath)
	})

	fmt.Printf("Serving %s at http://%s/\n", rootPath, *addr)
	log.Fatal(http.ListenAndServe(*addr, handler))
}
