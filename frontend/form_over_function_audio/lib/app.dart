import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'pages/audio_home_page.dart';

// Application shell: shared theme, title, and first screen.
class FormOverFunctionAudioApp extends StatelessWidget {
  const FormOverFunctionAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Form Over Function Audio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AudioHomePage(),
    );
  }
}
