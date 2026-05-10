import 'package:flutter/material.dart';

import 'app.dart';

export 'app.dart';

// Flutter entry point. The app structure lives in app.dart and the screen
// implementation lives under pages/ and widgets/.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FormOverFunctionAudioApp());
}
