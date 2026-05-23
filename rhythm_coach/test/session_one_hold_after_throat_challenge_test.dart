/// Reproduit le scénario rapporté par l'utilisatrice :
///
///   « En session 1 je passe le défi hold throat avec 2 s de plus.
///     Pourquoi le 1er hold qui suit le défi est encore un hold head ? »
///
/// Le test démarre d'une carrière neuve (profil capacités vide, aucun
/// unlock acquitté, level 1), génère la session 1 avec le défi tutoriel
/// (`holdThroatStreak`, 5 s, mode hold throat→throat), simule un
/// `extendedSuccess` qui pousse `reached = 5 + 2 = 7 s`, applique la
/// cascade transitive d'acquittements, puis régénère la suite via
/// `CareerSessionGenerator.generate(...)` avec le nouveau set d'unlocks
/// — comme le fait `career_screen._handlePostChallengeRegen`.
///
/// Attendu : la cascade `_impliedHoldUnlocksByAxis[holdThroatStreak]`
/// débloque `holdHead`, `holdMid`, `throatHold`. Le générateur post-défi
/// doit en tirer parti via `milestoneHoldCeilingIdx` → tous les holds
/// produits ensuite sont **mid ou throat**, jamais head.
library;

import 'package:beat_bitch/career/models/capability_requirement.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() {
  return PhraseBank(
    byMode: {
      for (final m in SessionMode.values)
        m: {
          'soft': _p(['s']),
          'medium': _p(['m']),
          'hard': _p(['h']),
          'finale': _p(['f']),
        },
    },
    congrats: _p(['bravo']),
    intros: _p(['intro']),
  );
}

/// Catalogue minimal qui reproduit la chaîne hold de la carrière réelle :
/// `intro_basics` (socle) → `intro_hold_mid` → `intro_hold_throat_short`.
/// Chaque milestone unlock une étape, les requires forment la chaîne.
/// Seule la milestone hold-throat porte un `requiresCapability` — c'est
/// celle dont le défi tuto valide la condition. Les deux précédentes sont
/// acquittées via la passe transitive (`_impliedHoldUnlocksByAxis`).
List<LevelMilestone> _holdChainCatalog() {
  return const [
    LevelMilestone(
      id: 'intro_basics',
      humilRequired: 0,
      displayLabel: 'Basics',
      sequence: [],
      durationSeconds: 1,
      unlocks: [UnlockKey.basics, UnlockKey.holdHead],
    ),
    LevelMilestone(
      id: 'intro_hold_mid',
      humilRequired: 0,
      displayLabel: 'Hold mid',
      sequence: [],
      durationSeconds: 1,
      unlocks: [UnlockKey.holdMid],
      requires: [UnlockKey.holdHead],
    ),
    LevelMilestone(
      id: 'intro_hold_throat_short',
      humilRequired: 0,
      displayLabel: 'Hold throat',
      sequence: [],
      durationSeconds: 1,
      unlocks: [UnlockKey.throatHold],
      requires: [UnlockKey.holdMid],
      requiresCapability: [
        CapabilityRequirement(axis: CapabilityAxis.holdThroatStreak, min: 3.0),
      ],
    ),
  ];
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

  test(
    'session 1 + défi hold throat tuto +2 s → tous les holds qui suivent sont ≥ mid',
    () async {
      // ─── Carrière neuve ─────────────────────────────────────────────
      final milestones = MilestoneService();
      milestones.seedForTest(catalog: _holdChainCatalog());
      // Aucun unlock acquitté au démarrage.
      expect(milestones.acquiredUnlockKeys(), isEmpty);

      // Défi tuto verbatim (cf. `ChallengeService._buildTutorialChallenge`).
      const tutorial = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 5,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
        comfortAtCalibration: 5.0,
        isTutorial: true,
      );

      // ─── Génération session 1 ───────────────────────────────────────
      // Profil vide (joueuse neuve), level 1, durée tendre 5 min.
      final initialUnlocks = milestones.acquiredUnlockKeys();
      final session1 = CareerSessionGenerator(seed: 42).generate(
        level: 1,
        bank: _bank(),
        durationSeconds: 300,
        unlockedKeys: initialUnlocks,
        humiliationCareer: 0.0,
        humiliationSession: 0.0,
        obedience: 0.0,
        challenge: ChallengeInputs.single(tutorial),
        capability: const CapabilityInputs(profile: CapabilityProfile({})),
      );
      expect(session1.session.challenges, contains(tutorial),
          reason: 'le défi tuto doit être inséré en session 1');

      // ─── Simule l'outcome « +2 s au-delà du seuil » ────────────────
      // Sémantique user : elle tient 2 s de plus → reached = 5 + 2.
      // (Le bumping discret par extension complète n'est pas l'objet du
      // test : on injecte directement le `reached` qui résulterait de
      // `recordChallengeReached`.)
      const reached = 7.0;

      final acquittable = milestones.milestonesAcquittableByChallenge(
        axis: tutorial.axis,
        reached: reached,
        profile: const CapabilityProfile({}),
        acquiredUnlocks: milestones.acquiredUnlockKeys(),
      );
      // Toute la chaîne hold doit être acquittée d'un coup, via la
      // transitivité `_impliedHoldUnlocksByAxis[holdThroatStreak]` =
      // {holdHead, holdMid, throatHold, finalHold*}.
      expect(
        acquittable.map((m) => m.id),
        containsAll(
            ['intro_basics', 'intro_hold_mid', 'intro_hold_throat_short']),
        reason:
            'cascade transitive holds : tenir gorge 7 s prouve qu\'on tient '
            'mid/head à la même durée, donc toutes les milestones de la chaîne '
            'sont acquittables',
      );
      for (final m in acquittable) {
        await milestones.markCompletedViaChallenge(m.id);
      }
      final newUnlocks = milestones.acquiredUnlockKeys();
      expect(
        newUnlocks,
        containsAll([
          UnlockKey.holdHead,
          UnlockKey.holdMid,
          UnlockKey.throatHold,
        ]),
      );

      // ─── Régénération post-défi ─────────────────────────────────────
      // Reproduit `career_screen._handlePostChallengeRegen` : nouvelle
      // génération avec le set d'unlocks élargi, même profil/level.
      // (`humiliationSession` un peu plus chaud pour matcher l'effet du
      // défi sur la chauffe — non discriminant ici.)
      final regen = CareerSessionGenerator(seed: 43).generate(
        level: 1,
        bank: _bank(),
        durationSeconds: 200,
        unlockedKeys: newUnlocks,
        humiliationCareer: 0.0,
        humiliationSession: 5.0,
        obedience: 0.0,
        capability: const CapabilityInputs(profile: CapabilityProfile({})),
      );

      // ─── Assert principal ───────────────────────────────────────────
      final holds = regen.session.steps
          .where((s) => s.mode == SessionMode.hold && !s.isTextOnly)
          .toList();
      expect(holds, isNotEmpty,
          reason:
              'la régen post-défi devrait contenir des holds (le défi vient '
              'de prouver la capacité throat — les holds sont la mise en '
              'pratique attendue)');
      final offending = holds.where((h) {
        final pos = h.from ?? h.to ?? Position.tip;
        return pos.index < Position.mid.index;
      }).toList();
      expect(
        offending,
        isEmpty,
        reason: 'défi hold throat acquitté → throatHold + holdMid unlocked, '
            'donc `milestoneHoldCeilingIdx = throat` → les holds doivent '
            'sortir mid ou throat ; ${offending.length} hold(s) ${offending.map((h) => (h.from ?? h.to).toString()).join(", ")} apparaissent à un palier inférieur',
      );
    },
  );
}
