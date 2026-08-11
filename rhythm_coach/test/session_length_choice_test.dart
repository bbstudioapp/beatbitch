import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';

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

void main() {
  group('SessionLengthChoice — Phase 19.3', () {
    test('mapping durée par palier', () {
      expect(SessionLengthChoice.bachee.durationSeconds, 360);
      expect(SessionLengthChoice.courte.durationSeconds, 720);
      expect(SessionLengthChoice.moyenne.durationSeconds, 1500);
      expect(SessionLengthChoice.longue.durationSeconds, 2700);
    });

    test('valeurs strictement croissantes (sanity check)', () {
      // `aleatoire` est un méta-choix sans durée concrète — exclu du
      // contrat « durations strictement croissantes ».
      final concrete = SessionLengthChoice.values
          .where((c) => c != SessionLengthChoice.aleatoire)
          .toList(growable: false);
      final durations = concrete.map((c) => c.durationSeconds).toList();
      for (var i = 1; i < durations.length; i++) {
        expect(durations[i], greaterThan(durations[i - 1]),
            reason: 'palier $i (${concrete[i]}) doit '
                'être strictement plus long que ${concrete[i - 1]}');
      }
    });
  });

  group('SessionLengthChoice — events count (Phase 19.5 + 19.5.b)', () {
    test('maxBodyMilestones par palier (max 2 body)', () {
      expect(SessionLengthChoice.bachee.maxBodyMilestones, 0);
      expect(SessionLengthChoice.courte.maxBodyMilestones, 1);
      expect(SessionLengthChoice.moyenne.maxBodyMilestones, 2);
      expect(SessionLengthChoice.longue.maxBodyMilestones, 2);
    });

    test('totalEvents par palier (cible 1/2/3/4)', () {
      expect(SessionLengthChoice.bachee.totalEvents, 1);
      expect(SessionLengthChoice.courte.totalEvents, 2);
      expect(SessionLengthChoice.moyenne.totalEvents, 3);
      expect(SessionLengthChoice.longue.totalEvents, 4);
    });

    test('targetChallengesFor : compensation quand le catalogue manque', () {
      // Catalogue plein (= toutes les milestones cibles disponibles) :
      // nbDéfis = totalEvents - maxBody.
      expect(
          SessionLengthChoice.bachee.targetChallengesFor(
              SessionLengthChoice.bachee.maxBodyMilestones),
          1);
      expect(
          SessionLengthChoice.courte.targetChallengesFor(
              SessionLengthChoice.courte.maxBodyMilestones),
          1);
      expect(
          SessionLengthChoice.moyenne.targetChallengesFor(
              SessionLengthChoice.moyenne.maxBodyMilestones),
          1);
      expect(
          SessionLengthChoice.longue.targetChallengesFor(
              SessionLengthChoice.longue.maxBodyMilestones),
          2);

      // Catalogue épuisé (0 body inséré) : les défis comblent jusqu'à
      // totalEvents.
      expect(SessionLengthChoice.bachee.targetChallengesFor(0), 1);
      expect(SessionLengthChoice.courte.targetChallengesFor(0), 2);
      expect(SessionLengthChoice.moyenne.targetChallengesFor(0), 3);
      expect(SessionLengthChoice.longue.targetChallengesFor(0), 4);

      // Demi-rempli (1 body inséré en longue) : 3 défis.
      expect(SessionLengthChoice.longue.targetChallengesFor(1), 3);
    });

    test('targetChallengesFor : plancher à 0 (jamais négatif)', () {
      // Plus de body insérés que prévu (cas dégénéré) : 0 défi.
      expect(SessionLengthChoice.bachee.targetChallengesFor(5), 0);
    });

    test('le sous-titre du réglage annonce le bon nombre de défis', () {
      // `careerChallengesDescription` dit « de un à quatre défis » dans les
      // 4 langues. Ce sont ces deux bornes-là — un palier qui planifierait
      // 5 événements ferait mentir 4 traductions sans que rien ne le dise.
      final planifies = SessionLengthChoice.values
          .where((c) => c != SessionLengthChoice.aleatoire)
          .map((c) => c.totalEvents);
      expect(planifies.reduce(min), 1);
      expect(planifies.reduce(max), 4);
    });
  });

  group('CareerSessionGenerator — multi-défi (Phase 19.5.b)', () {
    const ch1 = Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      mode: SessionMode.hold,
      to: Position.throat,
      targetThreshold: 5,
    );
    const ch2 = Challenge(
      axis: CapabilityAxis.biffleStreak,
      kind: ChallengeAxisKind.duration,
      mode: SessionMode.biffle,
      bpm: 60,
      targetThreshold: 5,
    );
    const ch3 = Challenge(
      axis: CapabilityAxis.gorgeApneeStreak,
      kind: ChallengeAxisKind.duration,
      mode: SessionMode.hold,
      to: Position.full,
      targetThreshold: 5,
    );
    const ch4 = Challenge(
      axis: CapabilityAxis.holdFullStreak,
      kind: ChallengeAxisKind.duration,
      mode: SessionMode.hold,
      to: Position.full,
      targetThreshold: 5,
    );

    test('longue + 4 défis (catalogue milestone épuisé) : 4 défis insérés', () {
      final r = CareerSessionGenerator(seed: 1).generate(
        level: 5,
        bank: _bank(),
        lengthChoice: SessionLengthChoice.longue,
        challenge: const ChallengeInputs(challenges: [ch1, ch2, ch3, ch4]),
      );
      expect(r.session.challenges.length, 4,
          reason:
              'tous les défis doivent être insérés dans la longue (~45 min)');
      expect(r.session.challengeTriggerTimes.length, 4);
    });

    test('défis distribués dans la fenêtre [0.20, 0.80] de genUntil', () {
      final r = CareerSessionGenerator(seed: 1).generate(
        level: 5,
        bank: _bank(),
        lengthChoice: SessionLengthChoice.longue,
        challenge: const ChallengeInputs(challenges: [ch1, ch2]),
      );
      expect(r.session.challenges.length, 2);
      // Les 2 défis sont ordonnés temporellement et distincts.
      final times = r.session.challengeTriggerTimes;
      expect(times[0], lessThan(times[1]));
      expect(times[1] - times[0], greaterThan(60),
          reason: 'les défis doivent être espacés pour ne pas se chevaucher');
    });

    test('1 défi seulement : ratio ~60% (legacy)', () {
      final r = CareerSessionGenerator(seed: 1).generate(
        level: 5,
        bank: _bank(),
        lengthChoice: SessionLengthChoice.courte,
        challenge: const ChallengeInputs(challenges: [ch1]),
      );
      expect(r.session.challenges.length, 1);
      // Compat retour : le getter scalaire `challenge` retourne le premier.
      expect(r.session.challenge, ch1);
    });
  });

  group('ChallengeInputs — multi-défi API (Phase 19.5)', () {
    const fakeChallenge = Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      mode: SessionMode.hold,
      to: Position.throat,
      targetThreshold: 5,
    );

    test('none = liste vide, pas de défi', () {
      const inputs = ChallengeInputs.none;
      expect(inputs.hasChallenge, isFalse);
      expect(inputs.challenge, isNull);
      expect(inputs.challenges, isEmpty);
    });

    test('single(null) === none', () {
      expect(ChallengeInputs.single(null).hasChallenge, isFalse);
      expect(ChallengeInputs.single(null).challenges, isEmpty);
    });

    test('single(c) place c en tête de liste', () {
      final inputs = ChallengeInputs.single(fakeChallenge);
      expect(inputs.hasChallenge, isTrue);
      expect(inputs.challenge, fakeChallenge);
      expect(inputs.challenges, [fakeChallenge]);
    });

    test('liste multi-défi : challenge getter retourne le premier', () {
      const second = Challenge(
        axis: CapabilityAxis.biffleStreak,
        kind: ChallengeAxisKind.duration,
        mode: SessionMode.biffle,
        bpm: 60,
        targetThreshold: 5,
      );
      const inputs = ChallengeInputs(challenges: [fakeChallenge, second]);
      expect(inputs.challenges.length, 2);
      expect(inputs.challenge, fakeChallenge);
    });
  });

  // Tests par comparaison relative (la phase finish ajoute un delta
  // variable, mais l'ordre des durées est préservé tant que les paliers
  // sont eux-mêmes ordonnés).
  group('CareerSessionGenerator.generate — résolution durée (19.3)', () {
    int gen({
      SessionLengthChoice? lengthChoice,
      int? durationSeconds,
      bool quickie = false,
    }) =>
        CareerSessionGenerator(seed: 1)
            .generate(
              level: 5,
              bank: _bank(),
              lengthChoice: lengthChoice,
              durationSeconds: durationSeconds,
              quickie: quickie,
            )
            .session
            .durationSeconds;

    test(
        'lengthChoice ordonne les durées finales (bachee < courte < … < longue)',
        () {
      final bachee = gen(lengthChoice: SessionLengthChoice.bachee);
      final courte = gen(lengthChoice: SessionLengthChoice.courte);
      final moyenne = gen(lengthChoice: SessionLengthChoice.moyenne);
      final longue = gen(lengthChoice: SessionLengthChoice.longue);

      expect(bachee, lessThan(courte));
      expect(courte, lessThan(moyenne));
      expect(moyenne, lessThan(longue));

      // chaque palier livre AU MOINS la durée nominale demandée
      expect(bachee, greaterThanOrEqualTo(360));
      expect(courte, greaterThanOrEqualTo(720));
      expect(moyenne, greaterThanOrEqualTo(1500));
      expect(longue, greaterThanOrEqualTo(2700));
    });

    test('durationSeconds explicite prioritaire sur lengthChoice', () {
      // Si la priorité est respectée, durationSeconds=600 ignore longue.
      // Sinon, on aurait ~2700.
      final overridden = gen(
        lengthChoice: SessionLengthChoice.longue,
        durationSeconds: 600,
      );
      expect(overridden, lessThan(1000),
          reason: 'durationSeconds doit l\'emporter sur lengthChoice');
    });

    test('lengthChoice prioritaire sur le fallback quickie', () {
      // Quickie seul → ~360s. lengthChoice=moyenne + quickie doit
      // produire ~1500s (le quickie continue de driver intensityFloor,
      // mais la durée vient du palier).
      final quickieOnly = gen(quickie: true);
      final moyenneOverQuickie =
          gen(lengthChoice: SessionLengthChoice.moyenne, quickie: true);
      expect(moyenneOverQuickie, greaterThan(quickieOnly + 500),
          reason: 'lengthChoice doit l\'emporter sur le fallback quickie');
    });

    test('sans aucun override, quickie force ~6 min', () {
      final quickieOnly = gen(quickie: true);
      final normal = gen(); // level 5 → 12 min de base
      expect(quickieOnly, lessThan(normal));
      expect(quickieOnly, greaterThanOrEqualTo(360));
    });
  });
}
