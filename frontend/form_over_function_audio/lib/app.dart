import 'package:flutter/material.dart';

import 'pages/audio_home_page.dart';

// Application shell: shared theme, title, and first screen.
class FormOverFunctionAudioApp extends StatelessWidget {
  const FormOverFunctionAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Form Over Function Audio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2f6f6d),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AudioHomePage(),
    );
  }
}
