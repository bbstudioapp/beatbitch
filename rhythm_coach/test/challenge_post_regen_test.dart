/// Tests de la régénération de session post-défi.
///
/// La logique de bout en bout (callback `onPostChallengeRegen` câblé sur
/// `_finalizeChallengeAcquittals` → `_handlePostChallengeRegen` du
/// `CareerScreen`) tient en deux briques unitaires couvertes ici :
///
/// 1. **Décision** : un défi acquitte au moins une milestone via
///    `markCompletedViaChallenge` → `acquiredUnlockKeys()` s'élargit (déjà
///    couvert par `challenge_silent_milestone_test`, on ajoute juste un cas
///    de **cascade** transitive pour s'assurer que le set final reflète
///    bien la chaîne d'unlocks et déclenche donc la régen).
/// 2. **Rebase** : `SessionController.buildPostChallengeRegenSession`
///    remplace la suite en repositionnant `time`, `finalStepTime` et
///    `silentFinishStartTime` sur `breathEnd`. C'est le seul calcul nouveau
///    qui mérite un test ciblé (le reste = orchestration).
library;

import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/final_category.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/saliva_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LevelMilestone _milestone({
  required String id,
  required List<CapabilityRequirement> requiresCapability,
  List<UnlockKey> unlocks = const [],
  List<UnlockKey> requires = const [],
}) {
  return LevelMilestone(
    id: id,
    humilRequired: 0,
    displayLabel: id,
    sequence: const [],
    durationSeconds: 1,
    unlocks: unlocks,
    requires: requires,
    requiresCapability: requiresCapability,
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('Décision de régen — cascade d\'acquittements', () {
    test(
      'un défi qui acquitte head → débloque mid → débloque throat en cascade',
      () async {
        // Catalogue : 3 milestones liées par dépendances d'unlock + un seul
        // axe pilotant le défi (`holdThroatStreak`). On simule un défi qui
        // pousse l'axe au seuil de la milestone la plus haute — la cascade
        // doit acquitter toute la chaîne.
        final svc = MilestoneService();
        final head = _milestone(
          id: 'm_head',
          requiresCapability: [
            const CapabilityRequirement(
                axis: CapabilityAxis.holdThroatStreak, min: 5.0),
          ],
          unlocks: [UnlockKey.holdHead],
        );
        final mid = _milestone(
          id: 'm_mid',
          requiresCapability: [
            const CapabilityRequirement(
                axis: CapabilityAxis.holdThroatStreak, min: 8.0),
          ],
          requires: [UnlockKey.holdHead],
          unlocks: [UnlockKey.holdMid],
        );
        final throat = _milestone(
          id: 'm_throat',
          requiresCapability: [
            const CapabilityRequirement(
                axis: CapabilityAxis.holdThroatStreak, min: 12.0),
          ],
          requires: [UnlockKey.holdMid],
          unlocks: [UnlockKey.throatHold],
        );
        svc.seedForTest(catalog: [head, mid, throat]);

        // Avant : aucun unlock acquittement-par-défi.
        expect(svc.acquiredUnlockKeys(), isEmpty);

        // Défi : axe holdThroatStreak, atteint 12 s (= seuil de m_throat).
        // Sans cascade, seule m_head serait acquittée (m_mid/m_throat ont
        // des prérequis d'unlock non encore satisfaits côté `acquiredUnlocks`).
        // Avec cascade (fixed point), les trois doivent passer.
        final acquittable = svc.milestonesAcquittableByChallenge(
          axis: CapabilityAxis.holdThroatStreak,
          reached: 12.0,
          profile: const CapabilityProfile({}),
          acquiredUnlocks: svc.acquiredUnlockKeys(),
        );
        // Cascade transitive (cf. PR #195) : on doit récupérer les 3
        // milestones, pas seulement la 1ère.
        expect(acquittable.map((m) => m.id),
            containsAll(['m_head', 'm_mid', 'm_throat']));

        // Acquitte-les toutes et vérifie l'expansion finale.
        for (final m in acquittable) {
          await svc.markCompletedViaChallenge(m.id);
        }
        expect(
          svc.acquiredUnlockKeys(),
          containsAll([
            UnlockKey.holdHead,
            UnlockKey.holdMid,
            UnlockKey.throatHold,
          ]),
        );
      },
    );

    test('défi qui n\'acquitte rien → acquiredUnlockKeys inchangé', () async {
      final svc = MilestoneService();
      final m = _milestone(
        id: 'm_high',
        requiresCapability: [
          const CapabilityRequirement(
              axis: CapabilityAxis.holdThroatStreak, min: 20.0),
        ],
        unlocks: [UnlockKey.throatHold],
      );
      svc.seedForTest(catalog: [m]);
      final before = Set<UnlockKey>.from(svc.acquiredUnlockKeys());
      // Défi qui n'atteint pas le seuil (12 < 20).
      final acquittable = svc.milestonesAcquittableByChallenge(
        axis: CapabilityAxis.holdThroatStreak,
        reached: 12.0,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: svc.acquiredUnlockKeys(),
      );
      expect(acquittable, isEmpty);
      // Le caller (career_screen) skip la regen dans ce cas — modélisé
      // par l'invariant : acquiredUnlockKeys ne bouge pas.
      expect(svc.acquiredUnlockKeys(), before);
    });
  });

  group('buildPostChallengeRegenSession — rebase des steps', () {
    Session makePrevious({
      int? finalStepTime,
      int? silentFinishStartTime,
      Challenge? challenge,
      int? challengeStepTime,
      int? challengeBreathStartTime,
    }) {
      return Session(
        id: 'prev',
        name: 'prev-name',
        description: 'prev-desc',
        durationSeconds: 600,
        defaultMode: SessionMode.rhythm,
        steps: const [],
        finalStepTime: finalStepTime,
        silentFinishStartTime: silentFinishStartTime,
        challenges: challenge == null ? const [] : [challenge],
        challengeStepTimes:
            challengeStepTime == null ? const [] : [challengeStepTime],
        challengeBreathStartTimes: challengeBreathStartTime == null
            ? const []
            : [challengeBreathStartTime],
        noStats: false,
      );
    }

    Session makeUpcoming({
      List<SessionStep> steps = const [],
      int durationSeconds = 240,
      int? finalStepTime,
      int? silentFinishStartTime,
      FinalCategory? finalCategory,
    }) {
      return Session(
        id: 'gen',
        name: 'gen-name',
        description: 'gen-desc',
        durationSeconds: durationSeconds,
        defaultMode: SessionMode.rhythm,
        steps: steps,
        finalStepTime: finalStepTime,
        silentFinishStartTime: silentFinishStartTime,
        finalCategory: finalCategory,
      );
    }

    test('chaque step.time est décalé de breathEnd', () {
      final upcoming = makeUpcoming(
        steps: const [
          SessionStep(
              time: 0,
              mode: SessionMode.rhythm,
              from: Position.head,
              to: Position.mid,
              bpm: 100),
          SessionStep(
              time: 30,
              mode: SessionMode.hold,
              from: Position.throat,
              to: Position.throat,
              duration: 5),
          SessionStep(time: 90, mode: SessionMode.breath, duration: 6),
        ],
      );
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: makePrevious(),
        upcoming: upcoming,
        breathEnd: 360,
      );
      expect(
          rebased.steps.map((s) => s.time).toList(), equals([360, 390, 450]));
    });

    test('finalStepTime et silentFinishStartTime décalés', () {
      final upcoming = makeUpcoming(
        durationSeconds: 240,
        finalStepTime: 220,
        silentFinishStartTime: 210,
        finalCategory: FinalCategory.hard,
      );
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: makePrevious(),
        upcoming: upcoming,
        breathEnd: 360,
      );
      expect(rebased.finalStepTime, 220 + 360);
      expect(rebased.silentFinishStartTime, 210 + 360);
      expect(rebased.finalCategory, FinalCategory.hard);
      expect(rebased.durationSeconds, 360 + 240);
    });

    test('finalStepTime null reste null', () {
      final upcoming =
          makeUpcoming(finalStepTime: null, silentFinishStartTime: null);
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: makePrevious(),
        upcoming: upcoming,
        breathEnd: 100,
      );
      expect(rebased.finalStepTime, isNull);
      expect(rebased.silentFinishStartTime, isNull);
    });

    test('conserve challenge + timestamps du previous (pas de re-défi)', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 10,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
        comfortAtCalibration: 6.0,
      );
      final previous = makePrevious(
        challenge: ch,
        challengeStepTime: 340,
        challengeBreathStartTime: 327,
      );
      final upcoming = makeUpcoming();
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: previous,
        upcoming: upcoming,
        breathEnd: 360,
      );
      // Les timestamps du défi déjà joué ne sont PAS rebaseés : ils
      // restent dans le passé. Combinés à `_challengePhase == ended`,
      // ils n'ont aucun effet → robuste.
      expect(rebased.challenge, ch);
      expect(rebased.challengeStepTime, 340);
      expect(rebased.challengeBreathStartTime, 327);
    });

    test('noStats hérite du previous (pas de bascule sandbox)', () {
      const previous = Session(
        id: 'prev',
        name: 'prev',
        description: 'd',
        durationSeconds: 600,
        defaultMode: SessionMode.rhythm,
        steps: [],
        noStats: true,
      );
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: previous,
        upcoming: makeUpcoming(),
        breathEnd: 100,
      );
      expect(rebased.noStats, isTrue);
    });

    test('id de la session porte le suffix :postchallenge', () {
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: makePrevious(),
        upcoming: makeUpcoming(),
        breathEnd: 100,
      );
      expect(rebased.id, 'prev:postchallenge');
    });

    test('propage les overrides de step (bpmEnd / swallowMode / background)',
        () {
      final upcoming = makeUpcoming(
        steps: const [
          SessionStep(
            time: 10,
            mode: SessionMode.rhythm,
            from: Position.head,
            to: Position.throat,
            bpm: 90,
            bpmEnd: 120,
            duration: 20,
            swallowMode: SwallowMode.forbidden,
            background: 'bg_porn_42',
          ),
        ],
      );
      final rebased = SessionController.buildPostChallengeRegenSession(
        previous: makePrevious(),
        upcoming: upcoming,
        breathEnd: 50,
      );
      final s = rebased.steps.single;
      expect(s.time, 60);
      expect(s.bpm, 90);
      expect(s.bpmEnd, 120);
      expect(s.duration, 20);
      expect(s.swallowMode, SwallowMode.forbidden);
      expect(s.background, 'bg_porn_42');
    });
  });
}
