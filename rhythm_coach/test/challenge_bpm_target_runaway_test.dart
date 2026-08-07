/// Test de **caractérisation** du retour utilisateur 0.6.0 « ramp up to
/// 956 BPM » : la cible d'un défi BPM diverge d'un défi à l'autre parce
/// que la valeur créditée au profil de capacités est la cible *demandée*
/// (`Challenge.bpmEnd`), jamais bornée, et non le BPM réellement jouable
/// (le `BeepEngine` clampe à 300).
///
/// ⚠️ Ces tests décrivent le défaut tel qu'il existe aujourd'hui. Ils
/// devront être inversés quand le correctif sera livré.
///
/// Cf. `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md`.
library;

import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';

/// Borne haute du `BeepEngine` (`beep_engine.dart:314` / `:324`).
const int kBeepEngineMaxBpm = 300;

const CapabilityAxis _axis = CapabilityAxis.rhythmBpmCeilShallow;

/// Rejoue un défi BPM réussi (`netSuccess`, aucune extension) et renvoie
/// `(cible affichée, état du profil après commit)`.
///
/// Réplique fidèlement la chaîne réelle :
/// - `ChallengeService._buildChallenge` → `bpmEnd = thresholdFor(comfort)`
///   (`challenge_service.dart:445-450`) ;
/// - `SessionController._completeChallenge` → `recordChallengeReached(axis,
///   ch.bpmEnd)` (`session_controller_challenge.dart:713-721`) ;
/// - `CapabilityService.commit` → `CapabilityRegulator.regulate`.
(int, CapabilityAxisState) _playOneSuccessfulChallenge(
  CapabilityAxisState prev,
  int sessionIndex,
) {
  final target = ChallengeService.thresholdFor(
    ChallengeAxisKind.bpm,
    prev.comfort!,
    _axis,
  );
  final next = CapabilityRegulator.regulate(
    axis: _axis,
    prev: prev,
    reached: target.toDouble(), // ← la cible demandée, pas le BPM joué
    sessionIndex: sessionIndex,
  );
  return (target, next);
}

void main() {
  group('Défi BPM — la cible s\'emballe d\'un défi à l\'autre', () {
    test('chaque succès repart de la cible précédente, sans borne', () {
      var state = const CapabilityAxisState(
        best: 120,
        comfort: 120,
        successRate: CapabilityService.defaultSuccessRate,
        lastSeenSession: 0,
      );

      final targets = <int>[];
      for (var i = 1; i <= 12; i++) {
        final (target, next) = _playOneSuccessfulChallenge(state, i);
        targets.add(target);
        state = next;
      }

      // Strictement croissante : rien ne la ramène jamais vers une valeur
      // jouable.
      for (var i = 1; i < targets.length; i++) {
        expect(targets[i], greaterThan(targets[i - 1]),
            reason: 'cible du défi ${i + 1} vs $i: $targets');
      }

      // Dépasse la borne du BeepEngine, puis part très au-delà.
      expect(targets.first, lessThan(kBeepEngineMaxBpm));
      expect(targets.last, greaterThan(900),
          reason: 'ordre de grandeur du 956 BPM rapporté — $targets');
    });

    test('la cible passe la borne 300 du BeepEngine en quelques défis', () {
      var state = const CapabilityAxisState(
        best: 120,
        comfort: 120,
        successRate: CapabilityService.defaultSuccessRate,
        lastSeenSession: 0,
      );

      var challengesToPassCap = 0;
      for (var i = 1; i <= 20; i++) {
        final (target, next) = _playOneSuccessfulChallenge(state, i);
        state = next;
        if (target > kBeepEngineMaxBpm) {
          challengesToPassCap = i;
          break;
        }
      }

      expect(challengesToPassCap, inInclusiveRange(1, 6),
          reason: 'quelques défis réussis suffisent à sortir du jouable');
    });

    test('aucun garde-fou du régulateur ne borne la montée', () {
      // `kRatchetAnchorHeadroom` (× reached) et le cap `bestRef ×
      // kSurchargeMax` sont tous deux **relatifs** à `reached` : comme
      // `reached = comfort × 1.30`, ils sont toujours au-dessus du comfort
      // visé, donc jamais contraignants.
      const comfort = 400.0;
      const state = CapabilityAxisState(
        best: comfort,
        comfort: comfort,
        successRate: 1.0, // gain de ratchet maximal (0.35)
        lastSeenSession: 0,
      );
      final (target, next) = _playOneSuccessfulChallenge(state, 1);

      expect(target, 520); // round(400 × 1.30)
      expect(next.comfort, closeTo(comfort * 1.35, 0.001));
      expect(next.best, target.toDouble());
    });

    test('le BPM joué reste plafonné à 300 quoi qu\'affiche la bannière', () {
      // Miroir du clamp `beep_engine.dart:314` / `:324` — la rampe réelle
      // est plate à 300 alors que la bannière annonce 956.
      const int announced = 956;
      expect(announced.clamp(20, kBeepEngineMaxBpm), kBeepEngineMaxBpm);
    });
  });

  group('La cible fictive contamine aussi l\'humiliation carrière', () {
    // `_raiseHumiliationFloorFromRecord` (session_controller_challenge.dart:1178)
    // pose `raiseCareerFloor(HumiliationScale.requiredFor(bpm: ch.bpmEnd))`
    // sur tout succès non-exploratoire. `_bpmExtra` est **quadratique**
    // (humiliation_engine.dart:139-143).
    double floorForBpm(int bpm) => HumiliationScale.requiredFor(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: bpm,
          duration: 25,
        );

    test('956 BPM annoncés → plancher d\'humiliation à 4 chiffres', () {
      expect(floorForBpm(140), lessThan(20)); // séance carrière normale
      expect(floorForBpm(kBeepEngineMaxBpm), greaterThan(200)); // borne réelle
      expect(floorForBpm(956), greaterThan(4000)); // cible affichée
    });

    test('le plancher écrase le score carrière et ne redescend pas', () {
      final e = HumiliationEngine();
      e.seed(career: 40); // ordre de grandeur d'une carrière avancée
      e.raiseCareerFloor(floorForBpm(956));
      expect(e.careerScore, greaterThan(4000));
    });
  });

  group('Le succès du défi ne dépend pas du BPM atteint', () {
    test('la durée nominale shallow est une fenêtre de 25 s', () {
      const ch = Challenge(
        axis: _axis,
        kind: ChallengeAxisKind.bpm,
        targetThreshold: 956,
        mode: SessionMode.rhythm,
        bpm: 735,
        bpmEnd: 956,
      );
      // `RhythmBpmCeilShallowBuilder` émet un unique segment de cette
      // durée puis pose `thresholdReached` — le BPM n'entre nulle part
      // dans la condition de succès.
      expect(ch.nominalDurationSeconds, 25);
      expect(ch.targetCrossings, isNull);
    });
  });
}
