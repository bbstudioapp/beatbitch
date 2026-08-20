import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'le curseur suit les intervalles inégaux du battement ancré, '
    'pas l\'intervalle régulier historique',
    (tester) async {
      final engine = BeepEngine();
      engine.configureBeatSourceForTest(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
        anchor: BeatAnchor.from,
        ratio: 3,
      );

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MovementAnimation(
            mode: SessionMode.rhythm,
            from: Position.head,
            to: Position.mid,
            bpm: 200, // T = 300ms
            beepEngine: engine,
          ),
        ),
      ));
      // Laisse passer la mise en route initiale (durée fixe, pas pilotée
      // par le stream de battements) avant de mesurer une transition
      // pilotée par un vrai `BeatEvent`.
      await tester.pump(const Duration(milliseconds: 300));

      Finder cursorFinder() => find
          .descendant(
              of: find.byType(AnimatedAlign), matching: find.byType(Container))
          .first;
      double cursorY() => tester.getCenter(cursorFinder()).dy;

      // Battement émis = `to` (l'alternance démarre sur `to`) → ancre
      // `from` pas atteinte → intervalle court (0,5T = 150ms).
      final shortInterval = engine.emitOneBeatForTest(200);
      expect(shortInterval, const Duration(milliseconds: 150));
      await tester.pump();

      await tester.pump(shortInterval ~/ 2);
      final shortMidY = cursorY();
      await tester.pump(shortInterval - shortInterval ~/ 2);
      final shortEndY = cursorY();
      expect(shortEndY, isNot(closeTo(shortMidY, 0.5)),
          reason: 'le curseur doit avoir bougé entre le milieu et la fin');

      // Battement émis = `from` (l'alternance a basculé) → ancre `from`
      // atteinte → intervalle long (1,5T = 450ms).
      final longInterval = engine.emitOneBeatForTest(200);
      expect(longInterval, const Duration(milliseconds: 450));
      await tester.pump();

      // Avec l'ancien calcul (60000/bpm constant), la transition aurait
      // duré 300ms : à cet instant, la vraie transition (450ms) n'est pas
      // finie — c'est ce qui distingue le battement ancré du régulier.
      await tester.pump(const Duration(milliseconds: 300));
      final longAt300msY = cursorY();
      await tester.pump(const Duration(milliseconds: 150)); // franchit 450ms
      final longAt450msY = cursorY();
      await tester
          .pump(const Duration(seconds: 1)); // referme, posé sur la cible
      final longSettledY = cursorY();

      expect(longAt300msY, isNot(closeTo(longSettledY, 0.5)),
          reason: 'ne doit pas être arrivé à 300ms (durée réelle 450ms)');
      expect(longAt450msY, closeTo(longSettledY, 0.5),
          reason: 'doit être arrivé exactement à 450ms');
    },
  );
}
