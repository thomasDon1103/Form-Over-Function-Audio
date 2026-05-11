# Form Over Function Audio

Form Over Function Audio is split into a Go audio server and a Flutter client.
The server owns the music library, reads album metadata from the host computer,
and exposes safe HTTP endpoints for browsers, phones, tablets, and desktop
clients on the same home network. MP3, FLAC, and WAV files are supported.

## Backend

From the host computer:

```sh
cd backend
go run .
```

By default the server listens on `http://0.0.0.0:8080`, which makes it reachable
from other devices on the same LAN. The startup log prints usable LAN URLs such
as `http://192.168.1.25:8080`.

Configuration:

- `FOF_HOST`: bind address, default `0.0.0.0`
- `FOF_PORT`: bind port, default `8080`
- `FOF_AUDIO_DIR`: audio library directory, default `audio`

Endpoints:

- `GET /health`: basic server health check.
- `GET /server-info`: host, port, audio directory, and detected LAN URLs.
- `GET /library`: all album metadata, album art URLs, and track stream URLs.
- `POST /refresh`: rescans the audio directory and returns albums not listed in
  the request's `known_locations` array.
- `GET /albumArt?path=<albumArtPath>`: album art from metadata.
- `GET /stream?path=<trackPath>`: MP3, FLAC, and WAV streaming with byte-range support.

The server only serves files inside `FOF_AUDIO_DIR`. Metadata paths are relative
to that library root, so clients can stream music without receiving arbitrary
absolute filesystem access.

## Frontend

From the Flutter app:

```sh
cd frontend/form_over_function_audio
flutter run -d chrome
```

Use the host computer's LAN URL in the server address field, then connect. Web
builds can connect to an already running server and play streams through the
browser audio element. Desktop builds can also try to start the local Go backend
during development when the backend source directory is present.

### Windows Desktop Builds

The `media_kit_libs_windows_audio` plugin generates deep MSBuild paths. On
Windows, those paths can exceed the classic 260-character limit when Flutter
uses the default nested `build/windows/...` directory. Configure Flutter to use
a shorter build directory before running the Windows desktop app:

```powershell
cd frontend/form_over_function_audio
.\tool\windows_flutter_build_dir.ps1
flutter run -d windows
```

The script sets Flutter's relative `build-dir` to `..\..\..\..\b\fof`, which
resolves to `C:\b\fof` for this repo layout. After that one-time
configuration, plain `flutter run -d windows` will keep generated Windows build
files in the shorter directory. You can also use the wrapper below, which applies
the setting and then runs Flutter:

```powershell
.\tool\windows_flutter.ps1
```

Pass any Flutter arguments after the wrapper name when needed, for example:

```powershell
.\tool\windows_flutter.ps1 build windows
```

## Home Network Notes

The host computer and client devices must be on the same network. If another
device cannot reach the server URL, allow inbound TCP traffic for the selected
port, usually `8080`, through the host firewall.

Use HTTP for normal home-network streaming unless you set up trusted TLS
certificates yourself. Self-signed HTTPS often fails on phones and browsers
because the certificate is not trusted for the host computer's LAN IP address.
