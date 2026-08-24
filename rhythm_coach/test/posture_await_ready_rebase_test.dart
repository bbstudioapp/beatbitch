import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

/// Une posture imposée fige la séance jusqu'à confirmation (`awaitReady`,
/// issue #77). Les rebases de timeline reconstruisent les steps champ à
/// champ : si l'un d'eux oublie ce champ, la posture s'enchaîne sans attendre.
Session sessionAvecPosture() => const Session(
      id: 'up',
      name: 'suite',
      description: '',
      durationSeconds: 60,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(
          time: 0,
          text: 'Mets-toi à quatre pattes.',
          mode: SessionMode.breath,
          duration: 5,
          awaitReady: true,
        ),
        SessionStep(
          time: 5,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          bpm: 60,
          duration: 30,
        ),
      ],
    );

void main() {
  test(
    'rebased ne perd aucun champ — garde-fou pour tout champ ajouté plus tard',
    () {
      const complet = SessionStep(
        time: 3,
        text: 'à quatre pattes',
        from: Position.head,
        to: Position.throat,
        bpm: 72,
        bpmEnd: 96,
        duration: 20,
        mode: SessionMode.rhythm,
        chainAction: SessionStep(time: 0, text: 'enchaîne'),
        swallowMode: SwallowMode.forbidden,
        background: 'bg_x',
        awaitReady: true,
      );

      final avant = Map<String, dynamic>.from(complet.toJson())..remove('time');
      final apres = Map<String, dynamic>.from(complet.rebased(41).toJson())
        ..remove('time');

      expect(apres.toString(), avant.toString());
      expect(complet.rebased(41).time, 41);
    },
  );

  test(
    'supplication insistante : la posture garde son attente de confirmation',
    () {
      final upgraded = SessionController.buildUpgradedSession(
        previous: sessionAvecPosture(),
        upcoming: sessionAvecPosture(),
        insistentBeg: const SessionStep(
          time: 0,
          mode: SessionMode.beg,
          to: Position.throat,
          duration: 12,
        ),
        start: 10,
      );

      final postures = upgraded.steps.where((s) => s.awaitReady);
      expect(postures, hasLength(1),
          reason: 'la posture doit survivre au rebase');
    },
  );

  test(
    'régénération après un défi : la posture garde son attente de confirmation',
    () {
      final regen = SessionController.buildPostChallengeRegenSession(
        previous: sessionAvecPosture(),
        upcoming: sessionAvecPosture(),
        breathEnd: 8,
      );

      final postures = regen.steps.where((s) => s.awaitReady);
      expect(postures, hasLength(1),
          reason: 'la posture doit survivre à la régénération');
    },
  );
}
