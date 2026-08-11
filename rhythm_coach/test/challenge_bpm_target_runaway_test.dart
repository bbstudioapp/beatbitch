/// Non-régression du retour utilisateur 0.6.0 « ramp up to 956 BPM » : la
/// cible d'un défi BPM divergeait d'un défi à l'autre parce que la valeur
/// créditée au profil de capacités était la cible *demandée*
/// (`Challenge.bpmEnd`), jamais bornée, et non le BPM réellement jouable
/// (le `BeepEngine` clampe à [BeepEngine.kMaxBpm]).
///
/// Trois bornes couvertes ici :
///   1. le **crédit** ([challengeReachedValue]) ne dépasse pas la borne
///      moteur ;
///   2. la **cible** ([ChallengeService.thresholdFor]) non plus ;
///   3. le **plancher d'humiliation** ([challengeHumiliationFloor]) reste
///      dans une plage défendable.
///
/// Le rattrapage des profils déjà dérivés est couvert par
/// `profile_reconciliation_test.dart`.
///
/// Cf. `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md`.
library;

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const CapabilityAxis _axis = CapabilityAxis.rhythmBpmCeilShallow;

/// Tous les axes BPM `maximize` — ils partagent exactement le même chemin
/// de code que l'axe rapporté par l'utilisateur, donc la même boucle.
const List<CapabilityAxis> _bpmMaximizeAxes = [
  CapabilityAxis.rhythmBpmCeilShallow,
  CapabilityAxis.rhythmBpmCeilThroat,
  CapabilityAxis.rhythmBpmCeilFull,
  CapabilityAxis.gorgeCrossingsBpmThroat,
  CapabilityAxis.gorgeCrossingsBpmFull,
  CapabilityAxis.biffleBpmMax,
];

Challenge _bpmChallenge(CapabilityAxis axis, {required int target}) =>
    Challenge(
      axis: axis,
      kind: ChallengeAxisKind.bpm,
      targetThreshold: target,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      bpm: (target / 1.3).round(),
      bpmEnd: target,
    );

/// Rejoue un défi BPM réussi (`netSuccess`, aucune extension) et renvoie
/// `(cible affichée, état du profil après commit)`.
///
/// Réplique fidèlement la chaîne réelle :
/// - `ChallengeService._buildChallenge` → `bpmEnd = thresholdFor(comfort)` ;
/// - `SessionController._completeChallenge` → `recordChallengeReached(axis,
///   challengeReachedValue(ch))` ;
/// - `CapabilityService.commit` → `CapabilityRegulator.regulate`.
(int, CapabilityAxisState) _playOneSuccessfulChallenge(
  CapabilityAxis axis,
  CapabilityAxisState prev,
  int sessionIndex,
) {
  final target = ChallengeService.thresholdFor(
    ChallengeAxisKind.bpm,
    prev.comfort!,
    axis,
    maxDurationSeconds: _noTruncationCap,
  );
  final credited = challengeReachedValue(
    _bpmChallenge(axis, target: target),
    extensionsCount: 0,
  );
  final next = CapabilityRegulator.regulate(
    axis: axis,
    prev: prev,
    reached: credited,
    sessionIndex: sessionIndex,
  );
  return (target, next);
}

CapabilityAxisState _seed(double comfort, {double? successRate}) =>
    CapabilityAxisState(
      best: comfort,
      comfort: comfort,
      successRate: successRate ?? CapabilityService.defaultSuccessRate,
      lastSeenSession: 0,
    );

void main() {
  group('Défi BPM — la cible reste dans le jouable sur des succès répétés', () {
    test('40 succès d\'affilée ne sortent jamais de la borne moteur', () {
      for (final axis in _bpmMaximizeAxes) {
        var state = _seed(120);
        final targets = <int>[];
        for (var i = 1; i <= 40; i++) {
          final (target, next) = _playOneSuccessfulChallenge(axis, state, i);
          targets.add(target);
          state = next;
        }

        expect(
          targets.every((t) => t <= BeepEngine.kMaxBpm),
          isTrue,
          reason: '${axis.storageKey} annonce un BPM injouable — $targets',
        );
        // La bannière du bug affichait 956 après ~10 succès ; ici la suite
        // sature au lieu de diverger.
        expect(targets.last, BeepEngine.kMaxBpm,
            reason: '${axis.storageKey} : la cible sature à la borne moteur');
      }
    });

    test('le `comfort` converge au lieu de croître géométriquement', () {
      var state = _seed(120);
      for (var i = 1; i <= 40; i++) {
        final (_, next) = _playOneSuccessfulChallenge(_axis, state, i);
        state = next;
      }
      // Borne du régulateur : `reached × kRatchetAnchorHeadroom`, avec
      // `reached ≤ kMaxBpm` désormais garanti.
      expect(
        state.comfort!,
        lessThanOrEqualTo(
            BeepEngine.kMaxBpm * CapabilityRegulator.kRatchetAnchorHeadroom),
      );
      expect(state.best!, lessThanOrEqualTo(BeepEngine.kMaxBpm.toDouble()));
    });

    test('un `comfort` déjà corrompu en base ne produit pas de cible absurde',
        () {
      // Profil dérivé avant correctif (le 735 déduit de la capture « 956 »).
      final target = ChallengeService.thresholdFor(
        ChallengeAxisKind.bpm,
        735.0,
        _axis,
        maxDurationSeconds: _noTruncationCap,
      );
      expect(target, BeepEngine.kMaxBpm);
    });

    test('le plancher 18 des axes `minimize` reste intact', () {
      // La borne haute ajoutée pour `maximize` ne doit pas déborder sur la
      // branche symétrique.
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          20.0,
          CapabilityAxis.rhythmBpmFloorShallow,
          maxDurationSeconds: _noTruncationCap,
        ),
        18,
      );
    });

    test('la progression normale sous la borne est inchangée', () {
      // Garde-fou anti-sur-correction : tant qu'on reste dans le jouable,
      // le défi doit continuer de surcharger à × 1.30.
      expect(
        ChallengeService.thresholdFor(ChallengeAxisKind.bpm, 120.0, _axis,
            maxDurationSeconds: _noTruncationCap),
        156,
      );
      expect(
        ChallengeService.thresholdFor(ChallengeAxisKind.bpm, 100.0, _axis,
            maxDurationSeconds: _noTruncationCap),
        130,
      );
    });
  });

  group('Le crédit au profil ne dépasse jamais la borne moteur', () {
    test('une cible injouable est créditée à la borne', () {
      final credited = challengeReachedValue(
        _bpmChallenge(_axis, target: 956),
        extensionsCount: 0,
      );
      expect(credited, BeepEngine.kMaxBpm.toDouble());
    });

    test('une cible jouable est créditée telle quelle', () {
      final credited = challengeReachedValue(
        _bpmChallenge(_axis, target: 156),
        extensionsCount: 0,
      );
      expect(credited, 156.0);
    });

    test('les axes durée et profondeur ne sont pas touchés par la borne', () {
      const durationChallenge = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 12,
        mode: SessionMode.hold,
        to: Position.throat,
      );
      // 12 s + 2 extensions au plancher de 10 s : la borne est une borne
      // *de BPM*, elle ne doit rien tronquer sur les autres axes.
      expect(
        challengeReachedValue(durationChallenge, extensionsCount: 2),
        32.0,
      );

      const depthChallenge = Challenge(
        axis: CapabilityAxis.rhythmDepthMax,
        kind: ChallengeAxisKind.depthCran,
        targetThreshold: 3,
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
      );
      expect(challengeReachedValue(depthChallenge, extensionsCount: 0), 3.0);
    });
  });

  group('Le plancher d\'humiliation reste dans une plage défendable', () {
    test('une cible à 4 chiffres ne pose plus un plancher à 4 chiffres', () {
      final floor = challengeHumiliationFloor(
        _bpmChallenge(_axis, target: 956),
        extensionsCount: 0,
      );
      // Avant correctif : ≈ 4 166, soit ~80 × le repère « ~50 pour une
      // session menée à terme par une débutante ».
      expect(floor, lessThan(300));
      // Le plancher du BPM maximum jouable, ni plus ni moins.
      expect(
        floor,
        challengeHumiliationFloor(
          _bpmChallenge(_axis, target: BeepEngine.kMaxBpm),
          extensionsCount: 0,
        ),
      );
    });

    test('un défi à vitesse normale garde son plancher d\'origine', () {
      final floor = challengeHumiliationFloor(
        _bpmChallenge(_axis, target: 140),
        extensionsCount: 0,
      );
      expect(floor, closeTo(13.9, 0.1));
    });

    test('le plancher n\'écrase plus un score carrière plausible', () {
      final e = HumiliationEngine();
      e.seed(career: 40);
      e.raiseCareerFloor(challengeHumiliationFloor(
        _bpmChallenge(_axis, target: 956),
        extensionsCount: 0,
      ));
      expect(e.careerScore, lessThan(300));
    });
  });

  group('Le succès du défi ne dépend pas du BPM atteint', () {
    // Constat inchangé par le correctif — le défi se gagne au temps, ce qui
    // est ce qui alimentait la boucle. Choix de design non tranché, laissé
    // au backlog : borner rend le symptôme invisible sans traiter la
    // question « faut-il créditer un succès obtenu en attendant 25 s ? ».
    test('la durée nominale shallow est une fenêtre de 25 s', () {
      final ch = _bpmChallenge(_axis, target: 300);
      // `RhythmBpmCeilShallowBuilder` émet un unique segment de cette
      // durée puis pose `thresholdReached` — le BPM n'entre nulle part
      // dans la condition de succès.
      expect(ch.nominalDurationSeconds, 25);
      expect(ch.targetCrossings, isNull);
    });
  });
}

/// Ces tests ne portent pas sur le plafond de durée par palier : celui du
/// plus long des formats ne tronque aucun de leurs seuils.
final _noTruncationCap = SessionLengthChoice.longue.maxChallengeDurationSeconds;
