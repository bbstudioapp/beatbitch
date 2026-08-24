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

      // `_PositionLadder` est privé au widget — accès par nom de champ
      // public (`beatDuration`) via `dynamic`, la seule voie pour lire
      // l'intervalle réellement remonté à l'affichage.
      Duration ladderBeatDuration() => (tester
              .widgetList(find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_PositionLadder'))
              .single as dynamic)
          .beatDuration as Duration;

      // Battement émis = `to` (l'alternance démarre sur `to`) → ancre
      // `from` pas atteinte → intervalle court (0,5T = 150ms).
      final shortInterval = engine.emitOneBeatForTest(200);
      expect(shortInterval, const Duration(milliseconds: 150));
      await tester.pump();
      expect(ladderBeatDuration(), shortInterval,
          reason: 'l\'affichage doit recevoir l\'intervalle court réel, '
              'pas l\'intervalle régulier historique (300ms)');

      // Battement émis = `from` (l'alternance a basculé) → ancre `from`
      // atteinte → intervalle long (1,5T = 450ms).
      final longInterval = engine.emitOneBeatForTest(200);
      expect(longInterval, const Duration(milliseconds: 450));
      await tester.pump();
      expect(ladderBeatDuration(), longInterval,
          reason: 'l\'affichage doit recevoir l\'intervalle long réel, '
              'pas l\'intervalle régulier historique (300ms)');

      expect(shortInterval, isNot(longInterval),
          reason: 'les deux intervalles d\'un battement ancré sont inégaux — '
              'sans ça le test ne distingue rien');
    },
  );
}
