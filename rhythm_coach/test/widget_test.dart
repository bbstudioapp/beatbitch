import 'package:flutter_test/flutter_test.dart';

import 'package:rhythm_coach/main.dart';

void main() {
  testWidgets('Démarre sur l\'écran d\'accueil', (WidgetTester tester) async {
    await tester.pumpWidget(const RhythmCoachApp());
    await tester.pump();

    expect(find.text('RHYTHM COACH'), findsOneWidget);
  });
}
