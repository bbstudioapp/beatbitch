import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verrouille le comportement de l'étape 2 du chantier aimant : sous une
/// rampe BPM intra-step, le curseur suit le BPM **interpolé** porté par
/// `BeatEvent.nextInterval`, pas le BPM affiché au montage du widget
/// (`widget.bpm`, qui reste le BPM de départ pendant toute la rampe — cf.
/// `BeepEngine.currentBpm` qui retourne `_bpm`, jamais interpolé). Sans
/// test, ce changement — mesuré en production par la relecture adverse des
/// étapes 1-2 (widget à 120, loop à 200 : glissement 500 ms avant, 300 ms
/// après) — n'était tenu par rien.
void main() {
  testWidgets(
    'le curseur suit le BPM interpolé du battement, pas le BPM affiché au '
    'montage du widget (rampe BPM)',
    (tester) async {
      final engine = BeepEngine();
      engine.configureBeatSourceForTest(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.mid,
      ); // anchor: none, ratio: 1 par défaut — seul le BPM varie ici.

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MovementAnimation(
            mode: SessionMode.rhythm,
            from: Position.head,
            to: Position.mid,
            bpm: 120, // BPM de départ affiché au montage — durée = 500 ms.
            beepEngine: engine,
          ),
        ),
      ));
      // Laisse passer la mise en route initiale (durée fixe à 500 ms, pas
      // pilotée par le stream de battements) avant de mesurer une
      // transition pilotée par un vrai `BeatEvent`.
      await tester.pump(const Duration(milliseconds: 500));

      Finder cursorFinder() => find
          .descendant(
              of: find.byType(AnimatedAlign), matching: find.byType(Container))
          .first;
      double cursorY() => tester.getCenter(cursorFinder()).dy;

      // Le loop tourne maintenant à 200 BPM interpolé (rampe en cours) —
      // l'intervalle réel est donc 300 ms, pas les 500 ms qu'aurait donné
      // le BPM de départ affiché au montage.
      final interval = engine.emitOneBeatForTest(200);
      expect(interval, const Duration(milliseconds: 300));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 300));
      final at300msY = cursorY();
      await tester
          .pump(const Duration(seconds: 1)); // referme, posé sur la cible
      final settledY = cursorY();

      expect(at300msY, closeTo(settledY, 0.5),
          reason: 'doit être arrivé à 300ms (BPM interpolé 200), pas être '
              'encore à mi-chemin d\'une transition de 500ms (BPM de '
              'montage 120)');
    },
  );
}
