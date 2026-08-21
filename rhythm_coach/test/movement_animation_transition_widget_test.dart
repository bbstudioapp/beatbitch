import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

/// Alignement vertical du curseur : dernier `Align` du ladder qui n'est ni
/// une graduation (x == 0) ni un libellé de position (x == 0.92).
double? cursorY(WidgetTester tester) {
  final aligns = tester.widgetList<Align>(find.byType(Align)).toList();
  for (final a in aligns.reversed) {
    final al = a.alignment;
    if (al is Alignment && al.x != 0 && (al.x - 0.92).abs() > 0.001) {
      return al.y;
    }
  }
  return null;
}

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 400, height: 200, child: child)),
    );

void main() {
  testWidgets(
    'transition tenue au fond → rythme : le curseur rejoint sa cible sans '
    'à-coup, image par image',
    (tester) async {
      await tester.pumpWidget(wrap(const MovementAnimation(
        mode: SessionMode.hold,
        from: Position.full,
        to: Position.full,
        bpm: 60,
        elapsed: Duration(seconds: 10),
      )));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cursorY(tester), closeTo(1.0, 0.01), reason: 'tenue au fond');

      await tester.pumpWidget(wrap(const MovementAnimation(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpm: 60,
        elapsed: Duration(seconds: 12),
      )));

      var previous = cursorY(tester)!;
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 16));
        final y = cursorY(tester)!;
        expect((y - previous).abs(), lessThan(0.35),
            reason: 'pas de saut entre deux images ($previous → $y)');
        previous = y;
      }
    },
  );
}
