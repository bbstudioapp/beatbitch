import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/main.dart';

void main() {
  testWidgets('Démarre sur l\'écran d\'accueil', (WidgetTester tester) async {
    await tester.pumpWidget(const RhythmCoachApp());
    await tester.pump();

    expect(find.text('BEATBITCH'), findsOneWidget);
  });
}
