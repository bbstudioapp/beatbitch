import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/models/specialization.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Construit un `CapabilityProfile` minimal avec un comfort posé sur un
/// axe précis. Les autres axes restent vides → `pickOverloadAxis` les
/// ignore (pas de donnée prouvée).
///
/// Pose aussi par défaut `rhythmDepthMax.comfort = 4` (full) — sans ça, le
/// gating profondeur (cf. bug 5 v0.5.1) exclut tous les axes profonds du
/// tirage, masquant l'intention du test. Mettre `withDepthAccess: false`
/// pour simuler une joueuse qui n'a pas encore validé la profondeur en
/// session normale (rare — utilisé par les tests dédiés au gating).
CapabilityProfile _profileWithComfort(
  CapabilityAxis axis,
  double comfort, {
  bool withDepthAccess = true,
}) {
  final entries = <CapabilityAxis, CapabilityAxisState>{
    axis: CapabilityAxisState(
      best: comfort,
      comfort: comfort,
      successRate: 0.9,
      lastSeenSession: 1,
    ),
  };
  if (withDepthAccess && axis != CapabilityAxis.rhythmDepthMax) {
    // `lastSeenSession` volontairement plus récent que l'axe testé : la
    // staleness de rhythmDepthMax est ainsi nulle face à l'autre axe →
    // pickOverloadAxis préfère l'axe testé. Permet de poser la profondeur
    // requise par le gating bug 5 sans polluer le tirage des autres tests.
    entries[CapabilityAxis.rhythmDepthMax] = const CapabilityAxisState(
      best: 4.0,
      comfort: 4.0,
      successRate: 0.9,
      lastSeenSession: 100,
    );
  }
  return CapabilityProfile(entries);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChallengeService.buildForSession', () {
    test('tutoriel : axe robuste hold throat 5 s, isTutorial flag posé',
        () async {
      final svc = ChallengeService();
      final challenge = await svc.buildForSession(
        profile: null,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(42),
        isTutorial: true,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.isTutorial, isTrue);
      expect(challenge.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.kind, ChallengeAxisKind.duration);
      expect(challenge.targetThreshold, kChallengeTutorialDurationSeconds);
      expect(challenge.mode, SessionMode.hold);
      expect(challenge.from, Position.throat);
      expect(challenge.branch, SpecializationBranch.endurance);
    });

    test('non-tutoriel : pickOverloadAxis utilisé, seuil = comfort × 1.30',
        () async {
      final svc = ChallengeService();
      final profile = _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      // 10 × 1.30 = 13.
      expect(challenge.targetThreshold, 13);
      expect(challenge.comfortAtCalibration, 10.0);
    });

    test('axe BPM : rampe comfort → comfort × 1.30 (bpm/bpmEnd)', () async {
      final svc = ChallengeService();
      final profile =
          _profileWithComfort(CapabilityAxis.rhythmBpmCeilThroat, 100);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmBpmCeilThroat);
      expect(challenge.kind, ChallengeAxisKind.bpm);
      // 100 × 1.30 = 130.
      expect(challenge.targetThreshold, 130);
      // Rampe : démarre au comfort, monte au seuil cible.
      expect(challenge.bpm, 100);
      expect(challenge.bpmEnd, 130);
      expect(challenge.mode, SessionMode.rhythm);
      // Convention rhythm : from < to (amplitude obligatoire).
      expect(challenge.from, Position.head);
      expect(challenge.to, Position.throat);
    });

    test('axe profondeur : seuil = comfort + 1 cran', () async {
      final svc = ChallengeService();
      // rhythmDepthMax comfort = 2 (mid) → seuil = cran 3 (throat).
      final profile = _profileWithComfort(CapabilityAxis.rhythmDepthMax, 2);
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.kind, ChallengeAxisKind.depthCran);
      expect(challenge.targetThreshold, 3);
    });

    test(
        'axes exclus du pickOverloadAxis : fallback exploratoire sur axes vierges (Phase 2)',
        () async {
      final svc = ChallengeService();
      // Pas de rhythmDepthMax (`withDepthAccess: false`) : le gating bug 5
      // s'occupe d'exclure les autres axes profonds, le seul candidat
      // (holdThroatStreak) est aussi exclu manuellement → fallback
      // exploratoire actif.
      final profile = _profileWithComfort(
        CapabilityAxis.holdThroatStreak,
        10,
        withDepthAccess: false,
      );
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.holdThroatStreak},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      // Phase 2 : le seul axe avec donnée est exclu, mais d'autres axes
      // pilotants sont vierges → fallback exploratoire actif.
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isTrue);
      expect(challenge.axis, isNot(CapabilityAxis.holdThroatStreak));
    });

    test('profil vide → exploratoire valide (Phase 2)', () async {
      final svc = ChallengeService();
      final challenge = await svc.buildForSession(
        profile: const CapabilityProfile({}),
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      // Phase 2 : profil vide → fallback exploratoire (axe vierge tiré au
      // hasard parmi `CapabilityClamps.overloadableAxes`).
      expect(challenge, isNotNull);
      expect(challenge!.isExploratory, isTrue);
    });

    test(
      'axe franchissement gorge : targetCrossings posé selon attemptsCount',
      () async {
        final svc = ChallengeService();
        final profile =
            _profileWithComfort(CapabilityAxis.rhythmBpmCeilThroat, 100);
        // 1er essai (attemptsCount = 0) → 5 franchissements.
        final first = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(first?.axis, CapabilityAxis.rhythmBpmCeilThroat);
        expect(first?.targetCrossings, 5);

        // Incrémente le compteur — le 2e essai monte à 8.
        await svc.incrementAttempts(CapabilityAxis.rhythmBpmCeilThroat);
        final second = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(second?.targetCrossings, 8);

        // 3e essai → 12.
        await svc.incrementAttempts(CapabilityAxis.rhythmBpmCeilThroat);
        final third = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(third?.targetCrossings, 12);
      },
    );

    test(
      'axe non-franchissement : targetCrossings null',
      () async {
        final svc = ChallengeService();
        final profile =
            _profileWithComfort(CapabilityAxis.holdThroatStreak, 10);
        final challenge = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(challenge?.axis, CapabilityAxis.holdThroatStreak);
        expect(challenge?.targetCrossings, isNull);
      },
    );

    test(
      'axes franchissement gorge : from/to non-null (régression défi infini)',
      () async {
        // Régression : `_toOf`/`_fromOf` n'avaient pas de cas pour
        // gorgeCrossingsBpm{Throat,Full} → `ch.to == null` → le compteur
        // `_challengeCrossingsCount` (incrémenté sur `e.to == ch.to`) restait
        // figé à 0 → le défi ne basculait jamais en `atSeuil` → boucle infinie.
        final throatCh = await ChallengeService().buildForSession(
          profile:
              _profileWithComfort(CapabilityAxis.gorgeCrossingsBpmThroat, 100),
          ceilings: const {},
          excludeAxes: const {CapabilityAxis.rhythmDepthMax},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(throatCh?.axis, CapabilityAxis.gorgeCrossingsBpmThroat);
        expect(throatCh?.to, Position.throat,
            reason: 'to non-null sinon le compteur de franchissements fige');
        expect(throatCh?.from, isNotNull);
        expect(throatCh?.targetCrossings, isNotNull);

        final fullCh = await ChallengeService().buildForSession(
          profile:
              _profileWithComfort(CapabilityAxis.gorgeCrossingsBpmFull, 100),
          ceilings: const {},
          excludeAxes: const {CapabilityAxis.rhythmDepthMax},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(fullCh?.axis, CapabilityAxis.gorgeCrossingsBpmFull);
        expect(fullCh?.to, Position.full);
        expect(fullCh?.from, isNotNull);
        expect(fullCh?.targetCrossings, isNotNull);
      },
    );

    test(
      'tutoriel : targetCrossings null (le tuto est hold, pas franchissement)',
      () async {
        final svc = ChallengeService();
        final challenge = await svc.buildForSession(
          profile: null,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(42),
          isTutorial: true,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(challenge?.isTutorial, isTrue);
        expect(challenge?.targetCrossings, isNull);
      },
    );
  });

  group('ChallengeService — signature visuelle (mode, from, to)', () {
    // Plusieurs axes pilotants partagent la même signature visuelle
    // côté joueuse (même mode, même from, même to). Quand la session
    // contient plusieurs défis, exclure uniquement l'axe précédent ne
    // suffit pas : on peut tirer un 2ᵉ axe différent qui produira un
    // défi visuellement identique (deux « hold throat » successifs avec
    // des durées incohérentes parce que dérivées de comforts d'axes
    // différents). Cf. retour stefsub v0.5.0 (feedback_v0.5.1.md).
    test(
        '2 défis sur 3 axes hold throat synonymes — bug : 2 défis '
        'visuellement identiques', () async {
      final svc = ChallengeService();
      // Trois axes différents, tous mappés vers (hold, throat, throat).
      const profile = CapabilityProfile({
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 14,
          comfort: 14,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.gorgeApneeStreak: CapabilityAxisState(
          best: 8,
          comfort: 8,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.gorgeEngagementStreak: CapabilityAxisState(
          best: 20,
          comfort: 20,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      // Simule la boucle de génération de career_screen : on pioche un
      // défi, on ajoute son axe à excludeAxes, on recommence pour le
      // défi suivant.
      final excluded = <CapabilityAxis>{};
      final picks = <Challenge>[];
      for (var i = 0; i < 2; i++) {
        final ch = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: excluded,
          rng: Random(i),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        if (ch == null) break;
        picks.add(ch);
        excluded.add(ch.axis);
        // Fix attendu : exclure aussi tous les axes partageant la même
        // signature visuelle pour éviter le doublon perçu par la joueuse.
        excluded.addAll(ChallengeService.axesSharingVisualSignature(ch.axis));
      }
      expect(picks.length, 2,
          reason: '2 défis attendus parmi les axes hold throat');
      final signatures =
          picks.map((c) => '${c.mode}|${c.from}|${c.to}').toSet();
      expect(signatures.length, 2,
          reason: 'Les 2 défis doivent avoir des signatures (mode, from, to) '
              'distinctes — sinon la joueuse voit deux fois le même défi avec '
              'des durées incohérentes');
    });

    test(
        'axesSharingVisualSignature : holdThroatStreak ⇔ gorgeApneeStreak ⇔ '
        'gorgeEngagementStreak', () {
      final group = ChallengeService.axesSharingVisualSignature(
          CapabilityAxis.holdThroatStreak);
      expect(group, contains(CapabilityAxis.gorgeApneeStreak));
      expect(group, contains(CapabilityAxis.gorgeEngagementStreak));
      // L'axe lui-même n'est pas dans le retour (le caller l'a déjà
      // ajouté à excludeAxes via excluded.add(ch.axis)).
      expect(group, isNot(contains(CapabilityAxis.holdThroatStreak)));
    });

    test('axesSharingVisualSignature : holdFullStreak isolé', () {
      // hold full a sa propre signature (from/to = full), pas de doublon.
      final group = ChallengeService.axesSharingVisualSignature(
          CapabilityAxis.holdFullStreak);
      expect(group, isEmpty);
    });

    test('axesSharingVisualSignature : axes rhythm franchissement appariés',
        () {
      // rhythmBpmCeilThroat = (rhythm, head→throat, bpm) partage sa signature
      // avec gorgeCrossingsBpmThroat (même mode/from/to/kind) — les deux sont
      // des défis franchissement gorge identiques à l'œil ; les dédupliquer
      // ensemble évite d'enchaîner deux défis perçus comme le même. En
      // revanche pas de collision avec full (mid→full) ni shallow (head→mid).
      final throatGroup = ChallengeService.axesSharingVisualSignature(
          CapabilityAxis.rhythmBpmCeilThroat);
      expect(throatGroup, contains(CapabilityAxis.gorgeCrossingsBpmThroat));
      expect(throatGroup, isNot(contains(CapabilityAxis.rhythmBpmCeilFull)));
      expect(throatGroup, isNot(contains(CapabilityAxis.rhythmBpmCeilShallow)));

      final fullGroup = ChallengeService.axesSharingVisualSignature(
          CapabilityAxis.rhythmBpmCeilFull);
      expect(fullGroup, contains(CapabilityAxis.gorgeCrossingsBpmFull));
      expect(fullGroup, isNot(contains(CapabilityAxis.rhythmBpmCeilThroat)));
    });
  });

  group('ChallengeService — gating unlocks (modèle gorge)', () {
    test(
        'unlockGatedAxes : pas d\'unlocks → gorgeApnee et gorgeEngagement '
        'gatés', () {
      final gated = ChallengeService.unlockGatedAxes(const {});
      expect(gated, contains(CapabilityAxis.gorgeApneeStreak));
      expect(gated, contains(CapabilityAxis.gorgeEngagementStreak));
    });

    test(
        'unlockGatedAxes : seulement throatPulse → gorgeEngagement ouvert, '
        'gorgeApnee toujours gaté', () {
      final gated =
          ChallengeService.unlockGatedAxes(const {UnlockKey.throatPulse});
      expect(gated, isNot(contains(CapabilityAxis.gorgeEngagementStreak)));
      // gorgeApnee exige fullPulse + fullHold en plus.
      expect(gated, contains(CapabilityAxis.gorgeApneeStreak));
    });

    test('unlockGatedAxes : fullPulse + fullHold → gorgeApnee ouvert', () {
      final gated = ChallengeService.unlockGatedAxes(
          const {UnlockKey.fullPulse, UnlockKey.fullHold});
      expect(gated, isNot(contains(CapabilityAxis.gorgeApneeStreak)));
    });

    test(
        'unlockGatedAxes : fullPulse seul (fullHold manquant) → gorgeApnee '
        'gaté', () {
      final gated =
          ChallengeService.unlockGatedAxes(const {UnlockKey.fullPulse});
      expect(gated, contains(CapabilityAxis.gorgeApneeStreak));
    });

    test(
        'buildForSession : sans unlocks → gorgeApnee et gorgeEngagement '
        'ne sortent pas même si comfort prouvé', () async {
      final svc = ChallengeService();
      // Comfort prouvé sur gorgeApnee + gorgeEngagement + holdThroatStreak.
      // Sans unlocks, gorgeApnee et gorgeEngagement sont gatés ; seul
      // holdThroatStreak peut sortir (sous réserve du gating profondeur,
      // qu'on satisfait via rhythmDepthMax).
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 4.0,
          comfort: 4.0,
          successRate: 0.9,
          lastSeenSession: 100,
        ),
        CapabilityAxis.gorgeApneeStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.gorgeEngagementStreak: CapabilityAxisState(
          best: 20.0,
          comfort: 20.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      // unlocks vide ≠ mode hérité : le mode hérité utilise un set vide
      // pour signifier « pas de gating ». Ici, on simule un mode hérité.
      // On passe explicitement un set non-vide mais sans les keys requises
      // pour que le gating s'active.
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        unlocks: const {UnlockKey.basics},
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, isNot(CapabilityAxis.gorgeApneeStreak));
      expect(challenge.axis, isNot(CapabilityAxis.gorgeEngagementStreak));
    });

    test(
        'buildForSession : mode hérité (unlocks vide) → gating unlock '
        'désactivé', () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 4.0,
          comfort: 4.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.gorgeApneeStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
        // unlocks: default {} → mode hérité, pas de gating.
      );
      expect(challenge, isNotNull);
      // Sans gating, le seul axe candidat hors rhythmDepthMax est
      // gorgeApneeStreak (rhythmDepthMax est lastSeen=1 donc moins
      // attractif que les éventuels axes plus anciens).
      expect(
        challenge!.axis,
        anyOf(
          CapabilityAxis.gorgeApneeStreak,
          CapabilityAxis.rhythmDepthMax,
        ),
      );
    });
  });

  group('ChallengeService — gating profondeur (bug 5)', () {
    test('depthGatedAxes : profil neuf → tous les axes profonds gatés', () {
      final gated = ChallengeService.depthGatedAxes(null);
      // 5 axes throat + 3 axes full.
      expect(gated, contains(CapabilityAxis.holdThroatStreak));
      expect(gated, contains(CapabilityAxis.gorgeApneeStreak));
      expect(gated, contains(CapabilityAxis.gorgeEngagementStreak));
      expect(gated, contains(CapabilityAxis.rhythmBpmCeilThroat));
      expect(gated, contains(CapabilityAxis.gorgeCrossingsBpmThroat));
      expect(gated, contains(CapabilityAxis.holdFullStreak));
      expect(gated, contains(CapabilityAxis.rhythmBpmCeilFull));
      expect(gated, contains(CapabilityAxis.gorgeCrossingsBpmFull));
    });

    test('depthGatedAxes : rhythmDepthMax = mid → axes throat/full gatés', () {
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 2.0,
          comfort: 2.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final gated = ChallengeService.depthGatedAxes(profile);
      // mid (2) < throat (3) ⇒ tous les axes throat gatés.
      expect(gated, contains(CapabilityAxis.holdThroatStreak));
      expect(gated, contains(CapabilityAxis.rhythmBpmCeilThroat));
      expect(gated, contains(CapabilityAxis.holdFullStreak));
    });

    test('depthGatedAxes : rhythmDepthMax = throat → axes throat ouverts', () {
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 3.0,
          comfort: 3.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final gated = ChallengeService.depthGatedAxes(profile);
      // throat (3) ≥ throat (3) ⇒ axes throat ouverts.
      expect(gated, isNot(contains(CapabilityAxis.holdThroatStreak)));
      expect(gated, isNot(contains(CapabilityAxis.rhythmBpmCeilThroat)));
      // full (4) > throat (3) ⇒ axes full restent gatés.
      expect(gated, contains(CapabilityAxis.holdFullStreak));
      expect(gated, contains(CapabilityAxis.rhythmBpmCeilFull));
    });

    test('depthGatedAxes : rhythmDepthMax = full → aucun axe gaté', () {
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 4.0,
          comfort: 4.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      expect(ChallengeService.depthGatedAxes(profile), isEmpty);
    });

    test(
        'buildForSession : profil sans profondeur throat → pas de défi sur '
        'holdThroatStreak même si comfort posé', () async {
      final svc = ChallengeService();
      // holdThroatStreak prouvé (via tuto par exemple) mais rhythm.depth_max
      // reste à mid : on ne reverra plus de défi hold throat tant que
      // rhythm profondeur n'a pas monté.
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 2.0,
          comfort: 2.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 5.0,
          comfort: 5.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      // rhythmDepthMax reste candidat (son rôle est de pousser la
      // profondeur — pas gaté).
      expect(challenge, isNotNull);
      expect(challenge!.axis, isNot(CapabilityAxis.holdThroatStreak));
    });

    test('buildForSession : tutoriel reste exempté du gating', () async {
      final svc = ChallengeService();
      // Pas de profil → axes profonds gatés normalement, mais le tuto
      // est forcé sur holdThroatStreak.
      final challenge = await svc.buildForSession(
        profile: null,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(42),
        isTutorial: true,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.isTutorial, isTrue);
      expect(challenge.axis, CapabilityAxis.holdThroatStreak);
    });

    test(
        'buildForSession : rhythmDepthMax non gaté — son rôle est de pousser '
        'la profondeur d\'un cran', () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 2.0,
          comfort: 2.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmDepthMax);
      expect(challenge.targetThreshold, 3); // mid + 1 cran = throat
    });
  });

  group('ChallengeService — dégradation amplitude axes endurance (bug 5)', () {
    test(
        'rhythmMotionStreak avec rhythm.depth_max.comfort=mid → from/to '
        'dégradés à tip→mid', () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 2.0, // mid
          comfort: 2.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
        CapabilityAxis.rhythmMotionStreak: CapabilityAxisState(
          best: 70.0,
          comfort: 70.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      // Force le tirage de rhythmMotionStreak en excluant rhythmDepthMax.
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: {CapabilityAxis.rhythmDepthMax},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmMotionStreak);
      // Mapping standard = head→throat ; dégradé à profondeur mid →
      // (head→mid) ou (tip→mid) selon la convention from<to.
      expect(challenge.to, Position.mid);
      expect(challenge.from!.index, lessThan(Position.mid.index));
    });

    test(
        'rhythmMotionStreak avec rhythm.depth_max.comfort=throat → '
        'pas de dégradation (head→throat préservé)', () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 3.0, // throat
          comfort: 3.0,
          successRate: 0.9,
          lastSeenSession: 100,
        ),
        CapabilityAxis.rhythmMotionStreak: CapabilityAxisState(
          best: 70.0,
          comfort: 70.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.rhythmMotionStreak);
      expect(challenge.from, Position.head);
      expect(challenge.to, Position.throat);
    });

    test(
        'holdThroatStreak (axe profondeur) avec gating ouvert : pas de '
        'dégradation, throat préservé', () async {
      final svc = ChallengeService();
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
          best: 3.0, // throat (passe le gating)
          comfort: 3.0,
          successRate: 0.9,
          lastSeenSession: 100,
        ),
        CapabilityAxis.holdThroatStreak: CapabilityAxisState(
          best: 10.0,
          comfort: 10.0,
          successRate: 0.9,
          lastSeenSession: 1,
        ),
      });
      final challenge = await svc.buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(challenge, isNotNull);
      expect(challenge!.axis, CapabilityAxis.holdThroatStreak);
      expect(challenge.from, Position.throat);
      expect(challenge.to, Position.throat);
    });
  });

  group('ChallengeService — anti-répétition inter-sessions', () {
    test('lastSessionAxes : vide par défaut', () async {
      final svc = ChallengeService();
      expect(await svc.lastSessionAxes(), isEmpty);
    });

    test('recordSessionChallenges → lastSessionAxes : round-trip', () async {
      final svc = ChallengeService();
      await svc.recordSessionChallenges([
        CapabilityAxis.holdThroatStreak,
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.gorgeApneeStreak,
      ]);
      expect(
        await svc.lastSessionAxes(),
        {
          CapabilityAxis.holdThroatStreak,
          CapabilityAxis.rhythmBpmCeilThroat,
          CapabilityAxis.gorgeApneeStreak,
        },
      );
    });

    test('recordSessionChallenges : écrase l\'ancienne liste', () async {
      final svc = ChallengeService();
      await svc.recordSessionChallenges([CapabilityAxis.holdThroatStreak]);
      await svc.recordSessionChallenges([CapabilityAxis.rhythmBpmCeilShallow]);
      // Pas d'union — la liste de la session précédente seule est conservée.
      expect(
        await svc.lastSessionAxes(),
        {CapabilityAxis.rhythmBpmCeilShallow},
      );
    });

    test('recordSessionChallenges : liste vide → reset', () async {
      final svc = ChallengeService();
      await svc.recordSessionChallenges([CapabilityAxis.holdThroatStreak]);
      await svc.recordSessionChallenges(const []);
      expect(await svc.lastSessionAxes(), isEmpty);
    });

    test('resetAll : nettoie aussi lastSessionAxes', () async {
      final svc = ChallengeService();
      await svc.recordSessionChallenges([CapabilityAxis.holdThroatStreak]);
      await svc.resetAll();
      expect(await svc.lastSessionAxes(), isEmpty);
    });

    test(
      'session N+1 sur même profil restreint : exclure axes de la session N '
      '→ axes différents si pool suffisante',
      () async {
        final svc = ChallengeService();
        // Profil de stefsub-like : 3 axes prouvés (cf. retour v0.5.0).
        // Plus un 4ᵉ vierge dans la pool overloadable (pour qu'un axe
        // alternatif soit dispo après exclusion).
        const profile = CapabilityProfile({
          CapabilityAxis.holdThroatStreak: CapabilityAxisState(
            best: 14,
            comfort: 14,
            successRate: 0.9,
            lastSeenSession: 5,
          ),
          CapabilityAxis.rhythmBpmCeilThroat: CapabilityAxisState(
            best: 100,
            comfort: 100,
            successRate: 0.9,
            lastSeenSession: 5,
          ),
          CapabilityAxis.holdFullStreak: CapabilityAxisState(
            best: 8,
            comfort: 8,
            successRate: 0.9,
            lastSeenSession: 5,
          ),
        });
        // Session N : pick le 1ᵉʳ axe via tirage standard.
        final firstSession = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: const {},
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(firstSession, isNotNull);
        await svc.recordSessionChallenges([firstSession!.axis]);

        // Session N+1 : exclure les axes de la session N → tirage doit
        // tomber sur un autre axe prouvé.
        final lastAxes = await svc.lastSessionAxes();
        expect(lastAxes, contains(firstSession.axis));
        final secondSession = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: lastAxes,
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        expect(secondSession, isNotNull);
        expect(secondSession!.axis, isNot(firstSession.axis));
      },
    );

    test(
      'session N+1 avec pool totalement épuisée : exploratoire ou null '
      '(fallback du caller : retirer l\'exclusion)',
      () async {
        final svc = ChallengeService();
        const profile = CapabilityProfile({
          CapabilityAxis.holdThroatStreak: CapabilityAxisState(
            best: 14,
            comfort: 14,
            successRate: 0.9,
            lastSeenSession: 1,
          ),
        });
        await svc.recordSessionChallenges([CapabilityAxis.holdThroatStreak]);
        // Exclure le seul axe prouvé : on retombe sur l'exploratoire d'un
        // axe vierge — c'est le comportement attendu et c'est ok ici.
        final challenge = await svc.buildForSession(
          profile: profile,
          ceilings: const {},
          excludeAxes: await svc.lastSessionAxes(),
          rng: Random(0),
          isTutorial: false,
          maxChallengeDurationSeconds: _noTruncationCap,
        );
        // L'exploratoire reste activé tant qu'il existe au moins un axe
        // pilotant vierge non exclu (le cas ici).
        expect(challenge, isNotNull);
        expect(challenge!.isExploratory, isTrue);
        expect(challenge.axis, isNot(CapabilityAxis.holdThroatStreak));
      },
    );
  });

  group('crossingsTargetForAttempts', () {
    test('progression no-limit : 5, 8, 12, 17, 23, 30 …', () {
      expect(crossingsTargetForAttempts(0), 5);
      expect(crossingsTargetForAttempts(1), 8);
      expect(crossingsTargetForAttempts(2), 12);
      expect(crossingsTargetForAttempts(3), 17);
      expect(crossingsTargetForAttempts(4), 23);
      expect(crossingsTargetForAttempts(5), 30);
      // Pas de cap : à 10 défis, 80 franchissements.
      expect(crossingsTargetForAttempts(10), 80);
    });

    test('valeurs négatives → 5 (cas défensif)', () {
      expect(crossingsTargetForAttempts(-1), 5);
      expect(crossingsTargetForAttempts(-99), 5);
    });
  });

  group('ChallengeService.branchOf', () {
    test('mapping axes → branches connues', () async {
      expect(ChallengeService.branchOf(CapabilityAxis.holdThroatStreak),
          SpecializationBranch.endurance);
      expect(ChallengeService.branchOf(CapabilityAxis.rhythmDepthMax),
          SpecializationBranch.profondeur);
      expect(ChallengeService.branchOf(CapabilityAxis.biffleStreak),
          SpecializationBranch.rythmeBiffle);
      expect(ChallengeService.branchOf(CapabilityAxis.noswallowStreak),
          SpecializationBranch.sloppy);
    });

    test('axes non pilotants par branche → null', () async {
      expect(ChallengeService.branchOf(CapabilityAxis.handStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.lickStreak), isNull);
      expect(ChallengeService.branchOf(CapabilityAxis.breathMinDose), isNull);
    });
  });

  group('ChallengeService.thresholdFor', () {
    test('maximize duration : comfort × 1.30', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.duration,
          10,
          CapabilityAxis.holdThroatStreak,
          maxDurationSeconds: _noTruncationCap,
        ),
        13,
      );
    });

    test('maximize bpm : comfort × 1.30', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          100,
          CapabilityAxis.rhythmBpmCeilThroat,
          maxDurationSeconds: _noTruncationCap,
        ),
        130,
      );
    });

    test('minimize bpm : comfort / 1.30 (rampe descendante)', () async {
      // 60 / 1.30 ≈ 46.
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          60,
          CapabilityAxis.rhythmBpmFloorThroat,
          maxDurationSeconds: _noTruncationCap,
        ),
        46,
      );
    });

    test('minimize bpm : plancher à 18 si la division descend plus bas',
        () async {
      // 20 / 1.30 ≈ 15 → planché à 18.
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.bpm,
          20,
          CapabilityAxis.rhythmBpmFloorShallow,
          maxDurationSeconds: _noTruncationCap,
        ),
        18,
      );
    });

    test('maximize depthCran : +1 cran', () async {
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.depthCran,
          2, // mid
          CapabilityAxis.rhythmDepthMax,
          maxDurationSeconds: _noTruncationCap,
        ),
        3, // throat
      );
    });

    test('depthCran : clamp au dernier cran disponible', () async {
      // comfort = dernier cran → +1 sortirait de la plage, clampé.
      final lastCran = Position.values.length - 1;
      expect(
        ChallengeService.thresholdFor(
          ChallengeAxisKind.depthCran,
          lastCran.toDouble(),
          CapabilityAxis.rhythmDepthMax,
          maxDurationSeconds: _noTruncationCap,
        ),
        lastCran,
      );
    });
  });

  group('Challenge.nominalDurationSeconds', () {
    // Construit un Challenge minimal pour tester le getter selon (kind, axis).
    Challenge mk(CapabilityAxis axis, ChallengeAxisKind kind,
        {int threshold = 1}) {
      return Challenge(
        axis: axis,
        kind: kind,
        targetThreshold: threshold,
        mode: SessionMode.rhythm,
      );
    }

    test('axes durée : durée = targetThreshold', () async {
      expect(
        mk(CapabilityAxis.holdThroatStreak, ChallengeAxisKind.duration,
                threshold: 15)
            .nominalDurationSeconds,
        15,
      );
      expect(
        mk(CapabilityAxis.biffleStreak, ChallengeAxisKind.duration,
                threshold: 22)
            .nominalDurationSeconds,
        22,
      );
    });

    test('axes BPM : durée par axe — table de calibration', () async {
      final cases = <CapabilityAxis, int>{
        CapabilityAxis.rhythmBpmCeilShallow: 25,
        CapabilityAxis.rhythmBpmCeilThroat: 8,
        CapabilityAxis.rhythmBpmCeilFull: 7,
        CapabilityAxis.gorgeCrossingsBpmThroat: 8,
        CapabilityAxis.gorgeCrossingsBpmFull: 7,
        CapabilityAxis.biffleBpmMax: 20,
        CapabilityAxis.rhythmBpmFloorShallow: 20,
        CapabilityAxis.rhythmBpmFloorThroat: 12,
        CapabilityAxis.rhythmBpmFloorFull: 8,
      };
      for (final entry in cases.entries) {
        expect(
          mk(entry.key, ChallengeAxisKind.bpm).nominalDurationSeconds,
          entry.value,
          reason: '${entry.key} doit durer ${entry.value} s',
        );
      }
    });

    test('axe profondeur : rhythmDepthMax = 12 s', () async {
      expect(
        mk(CapabilityAxis.rhythmDepthMax, ChallengeAxisKind.depthCran)
            .nominalDurationSeconds,
        12,
      );
    });

    test('axe BPM non listé : fallback 30 s', () async {
      // breathMinDose est BPM-like (minimize) mais non câblé dans _modeOf —
      // sert ici de proxy d'un axe pilotant pas encore couvert par la table.
      expect(
        mk(CapabilityAxis.breathMinDose, ChallengeAxisKind.bpm)
            .nominalDurationSeconds,
        30,
      );
    });
  });

  group('Challenge.extensionSeconds', () {
    test('plancher à 10 s pour comfort bas', () async {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 15,
        mode: SessionMode.hold,
        comfortAtCalibration: 5.0,
      );
      // 5 × 0.30 = 1.5 → planché à 10.
      expect(ch.extensionSeconds, 10);
    });

    test('comfort × 0.30 pour comfort élevé', () async {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 75,
        mode: SessionMode.hold,
        comfortAtCalibration: 50.0,
      );
      // 50 × 0.30 = 15.
      expect(ch.extensionSeconds, 15);
    });
  });
}

/// Ces tests ne portent pas sur le plafond de durée par palier : celui du
/// plus long des formats ne tronque aucun de leurs seuils.
final _noTruncationCap = SessionLengthChoice.longue.maxChallengeDurationSeconds;
