/// Régression : la garde de transition vers `atSeuil` doit ignorer les
/// phases `ended` / `none` / `breath` / `countdown` / `atSeuil` /
/// `openExtension`. Sans cette garde, après un `_completeChallenge`
/// (phase=ended), `_challengeStepStartedAtSec` restant posé pendant le
/// breath post-défi de 10 s faisait re-déclencher la transition vers
/// `atSeuil` à chaque tick — d'où une boucle infinie d'acquittements
/// (`_completeChallenge` rappelé toutes les 8 s par timeout du seuil),
/// chacun re-excisant `-shift` de `durationSeconds` jusqu'au `_finish`.
///
/// Observé sur device : défi tuto hold throat → 12 min de séance terminées
/// en 7 min de timeline (13 itérations × −18 s d'excision sur 720 s).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/session_controller.dart';

void main() {
  group('SessionController.shouldEnterAtSeuilPhase', () {
    test('phase live + elapsedInStep ≥ stepEnd → transitionne', () {
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.live,
          elapsedInStep: 5,
          stepEnd: 5,
        ),
        isTrue,
      );
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.live,
          elapsedInStep: 12,
          stepEnd: 10,
        ),
        isTrue,
      );
    });

    test('phase preExtend + elapsedInStep ≥ stepEnd → transitionne', () {
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.preExtend,
          elapsedInStep: 5,
          stepEnd: 5,
        ),
        isTrue,
      );
    });

    test('phase live + elapsedInStep < stepEnd → ne transitionne pas', () {
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.live,
          elapsedInStep: 4,
          stepEnd: 5,
        ),
        isFalse,
      );
    });

    test(
      'phase ended (post-completeChallenge) → bloquée même si elapsedInStep '
      'a dépassé stepEnd (bug boucle infinie évité)',
      () {
        // Scénario exact de la régression : défi tuto hold throat
        // (stepEnd = 5 s), `_completeChallenge` appelé alors qu'on était à
        // elapsedInStep = 6. `_challengeStepStartedAtSec` reste posé pendant
        // le breath post-défi → elapsedInStep continue à grandir
        // (8, 12, 20, 30…) en wallclock. La garde DOIT bloquer.
        for (final elapsed in [6, 8, 12, 20, 30, 100]) {
          expect(
            SessionController.shouldEnterAtSeuilPhase(
              phase: ChallengePhase.ended,
              elapsedInStep: elapsed,
              stepEnd: 5,
            ),
            isFalse,
            reason: 'phase=ended elapsedInStep=$elapsed stepEnd=5 → '
                'doit rester false pour éviter la boucle',
          );
        }
      },
    );

    test('phase atSeuil → ne re-transitionne pas (déjà au seuil)', () {
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.atSeuil,
          elapsedInStep: 100,
          stepEnd: 5,
        ),
        isFalse,
      );
    });

    test('phase openExtension → ne transitionne pas (géré ailleurs)', () {
      expect(
        SessionController.shouldEnterAtSeuilPhase(
          phase: ChallengePhase.openExtension,
          elapsedInStep: 100,
          stepEnd: 5,
        ),
        isFalse,
      );
    });

    test('phase none / breath / countdown → jamais', () {
      for (final phase in [
        ChallengePhase.none,
        ChallengePhase.breath,
        ChallengePhase.countdown,
      ]) {
        expect(
          SessionController.shouldEnterAtSeuilPhase(
            phase: phase,
            elapsedInStep: 100,
            stepEnd: 5,
          ),
          isFalse,
          reason: 'phase=$phase ne doit pas pouvoir transitionner vers atSeuil',
        );
      }
    });
  });
}
