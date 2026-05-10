import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:form_over_function_audio/main.dart';

void main() {
  testWidgets('shows the server connection controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FormOverFunctionAudioApp());

    expect(find.text('Audio server address'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.textContaining('Connect to an audio server'), findsOneWidget);
  });
}
