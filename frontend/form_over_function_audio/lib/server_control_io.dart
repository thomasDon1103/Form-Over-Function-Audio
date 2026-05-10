import 'dart:io';

class ServerStartResult {
  const ServerStartResult({required this.started, required this.message});

  final bool started;
  final String message;
}

class ServerControl {
  Process? _process;

  bool get canStartServer => true;

  Future<ServerStartResult> start() async {
    if (_process != null) {
      return const ServerStartResult(
        started: true,
        message: 'Audio server is already starting or running.',
      );
    }

    final backendDir = _findBackendDirectory();
    if (backendDir == null) {
      return const ServerStartResult(
        started: false,
        message:
            'Could not find the backend directory. Start the backend manually and connect to its LAN address.',
      );
    }

    try {
      _process = await Process.start(
        'go',
        <String>['run', '.'],
        workingDirectory: backendDir.path,
        environment: <String, String>{
          'FOF_HOST': '0.0.0.0',
          'FOF_PORT': '8080',
        },
      );
      _process!.exitCode.then((_) => _process = null);
      return const ServerStartResult(
        started: true,
        message: 'Local audio server started on http://localhost:8080.',
      );
    } on Object catch (error) {
      _process = null;
      return ServerStartResult(
        started: false,
        message: 'Could not start the local server: $error',
      );
    }
  }

  Directory? _findBackendDirectory() {
    final candidates = <Directory>[
      Directory('../../backend'),
      Directory('../backend'),
      Directory('backend'),
    ];
    for (final candidate in candidates) {
      if (File('${candidate.path}/main.go').existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  void dispose() {
    _process?.kill();
  }
}
