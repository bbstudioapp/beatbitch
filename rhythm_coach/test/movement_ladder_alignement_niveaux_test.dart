import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/l10n/enum_labels.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: SizedBox(width: 400, height: 160, child: child)),
    );

void main() {
  for (final rows in [5, 6]) {
    for (final p in Position.values.take(rows)) {
      testWidgets(
          'tenue sur ${p.name} ($rows niveaux) : curseur, libellé et ligne '
          'à la même hauteur', (tester) async {
        await tester.pumpWidget(wrap(MovementAnimation(
          mode: SessionMode.hold,
          from: p,
          to: p,
          bpm: 60,
          positionRowCount: rows,
        )));
        await tester.pump(const Duration(milliseconds: 16));

        final context = tester.element(find.byType(MovementAnimation));
        final labelY =
            tester.getCenter(find.text(p.localizedLabel(context))).dy;
        final cursorY = tester
            .getCenter(find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_OrbShape'))
            .dy;
        final lines = find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints == const BoxConstraints.tightFor(height: 1));
        final lineYs = [
          for (final e in lines.evaluate())
            tester.getCenter(find.byWidget(e.widget)).dy
        ]..sort();

        expect(lineYs, hasLength(rows));
        expect(labelY, closeTo(cursorY, 0.5));
        expect(lineYs[p.index], closeTo(cursorY, 0.5));
      });
    }
  }
}
