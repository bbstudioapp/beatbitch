/// Fige la règle d'aiguillage de l'input des défis :
/// « statique (mode hold) → tenue du doigt ; dynamique → tap GO/STOP ».
///
/// `Challenge.inputMode` est dérivé du `mode` (pas stocké) ; ce test verrouille
/// à la fois le getter pur et la chaîne axe → mode → input via
/// `ChallengeService.buildForSession`, pour qu'un futur changement de `_modeOf`
/// ne fasse pas basculer silencieusement un hold en tap (ou l'inverse).
library;

import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profil minimal avec un comfort posé sur [axis] (+ accès profondeur pour ne
/// pas faire exclure les axes profonds par le gating). Mêmes conventions que
/// `challenge_service_test._profileWithComfort` : `lastSeenSession` de l'axe
/// testé volontairement ancien pour que `pickOverloadAxis` le préfère.
CapabilityProfile _profileWithComfort(CapabilityAxis axis, double comfort) {
  final entries = <CapabilityAxis, CapabilityAxisState>{
    axis: CapabilityAxisState(
      best: comfort,
      comfort: comfort,
      successRate: 0.9,
      lastSeenSession: 1,
    ),
  };
  if (axis != CapabilityAxis.rhythmDepthMax) {
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
  group('Challenge.inputMode (getter dérivé du mode)', () {
    test('mode hold → hold (tenue du doigt)', () {
      const ch = Challenge(
        axis: CapabilityAxis.holdThroatStreak,
        kind: ChallengeAxisKind.duration,
        targetThreshold: 10,
        mode: SessionMode.hold,
        from: Position.throat,
        to: Position.throat,
      );
      expect(ch.inputMode, ChallengeInputMode.hold);
    });

    test('modes dynamiques (rhythm / biffle) → tapToggle', () {
      for (final mode in [SessionMode.rhythm, SessionMode.biffle]) {
        final ch = Challenge(
          axis: CapabilityAxis.rhythmMotionStreak,
          kind: ChallengeAxisKind.duration,
          targetThreshold: 30,
          mode: mode,
        );
        expect(
          ch.inputMode,
          ChallengeInputMode.tapToggle,
          reason: 'mode=$mode doit être en tap',
        );
      }
    });
  });

  group('ChallengeService.buildForSession → inputMode', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('tutoriel hold throat → hold', () async {
      final ch = await ChallengeService().buildForSession(
        profile: null,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(42),
        isTutorial: true,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(ch, isNotNull);
      expect(ch!.mode, SessionMode.hold);
      expect(ch.inputMode, ChallengeInputMode.hold);
    });

    test('axe hold statique (apnée gorge) → hold', () async {
      final profile = _profileWithComfort(CapabilityAxis.gorgeApneeStreak, 8);
      final ch = await ChallengeService().buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(ch, isNotNull);
      expect(ch!.axis, CapabilityAxis.gorgeApneeStreak);
      expect(ch.inputMode, ChallengeInputMode.hold);
    });

    test('axe franchissement gorge (le défi du retour stefsub) → tapToggle',
        () async {
      final profile =
          _profileWithComfort(CapabilityAxis.gorgeCrossingsBpmThroat, 115);
      final ch = await ChallengeService().buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(ch, isNotNull);
      expect(ch!.axis, CapabilityAxis.gorgeCrossingsBpmThroat);
      expect(ch.inputMode, ChallengeInputMode.tapToggle);
    });

    test('axe endurance rythme (motion streak, long) → tapToggle', () async {
      final profile =
          _profileWithComfort(CapabilityAxis.rhythmMotionStreak, 60);
      final ch = await ChallengeService().buildForSession(
        profile: profile,
        ceilings: const {},
        excludeAxes: const {},
        rng: Random(0),
        isTutorial: false,
        maxChallengeDurationSeconds: _noTruncationCap,
      );
      expect(ch, isNotNull);
      expect(ch!.axis, CapabilityAxis.rhythmMotionStreak);
      expect(ch.inputMode, ChallengeInputMode.tapToggle);
    });
  });
}

/// Ces tests ne portent pas sur le plafond de durée par palier : celui du
/// plus long des formats ne tronque aucun de leurs seuils.
final _noTruncationCap = SessionLengthChoice.longue.maxChallengeDurationSeconds;
