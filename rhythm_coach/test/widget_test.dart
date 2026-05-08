import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/main.dart';

void main() {
  testWidgets('Démarre sur l\'écran d\'accueil', (WidgetTester tester) async {
    await tester.pumpWidget(const RhythmCoachApp());
    await tester.pump();

    // L'AppBar affiche désormais le logo BeatBitch en haut à gauche
    // (via Image.asset) au lieu du texte "BEATBITCH".
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });
}
