import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

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

Widget wrap(int serial) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: MovementAnimation(
            mode: SessionMode.rhythm,
            from: Position.head,
            to: Position.throat,
            bpm: 60,
            stepSerial: serial,
            elapsed: const Duration(seconds: 10),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'un step réappliqué à configuration identique remet la courbe sur le '
    'gap du moteur au lieu de la laisser extrapoler',
    (tester) async {
      await tester.pumpWidget(wrap(1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump(const Duration(milliseconds: 16));
      final avant = cursorY(tester)!;

      // Seul `stepSerial` change : mode, positions et tempo sont identiques.
      await tester.pumpWidget(wrap(2));
      await tester.pump(const Duration(milliseconds: 16));
      final justeApres = cursorY(tester)!;
      expect(justeApres, closeTo(avant, 0.05),
          reason: 'le gel part de la position affichée, pas d\'un saut');

      // Pendant le gap (300 ms), le curseur rejoint `to` (gorge → 0.5) au
      // lieu de poursuivre l'alternance de l'ancien step.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 320)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cursorY(tester)!, closeTo(0.5, 0.06));
    },
  );
}
