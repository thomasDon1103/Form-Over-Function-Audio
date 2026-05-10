class ServerStartResult {
  const ServerStartResult({required this.started, required this.message});

  final bool started;
  final String message;
}

class ServerControl {
  bool get canStartServer => false;

  Future<ServerStartResult> start() async {
    return const ServerStartResult(
      started: false,
      message:
          'This build cannot start a local process. Start the audio server on the host computer, then connect to its LAN address.',
    );
  }

  void dispose() {}
}
