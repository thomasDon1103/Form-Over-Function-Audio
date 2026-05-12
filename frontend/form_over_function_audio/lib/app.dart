import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
      builder: (context, child) {
        final app = child ?? const SizedBox.shrink();
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          return ExcludeSemantics(child: app);
        }
        return app;
      },
      home: const AudioHomePage(),
    );
  }
}
