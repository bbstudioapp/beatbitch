import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:rhythm_coach/career/models/coach.dart';
import 'package:rhythm_coach/career/models/coach_catalog.dart';
import 'package:rhythm_coach/career/models/phrase_bank.dart';
import 'package:rhythm_coach/models/session.dart';

void main() {
  group('CoachPhrasePack.fromJson', () {
    test('parse une structure complète', () {
      final pack = CoachPhrasePack.fromJson({
        'phrases': {
          'rhythm': {
            'soft': ['rs1', 'rs2'],
            'hard': ['rh1'],
          },
          'hold': {
            'finale': ['hf1'],
          },
        },
        'intros': ['hello'],
        'congrats': ['merci'],
        'encore': ['encore'],
        'progress': {
          '50': ['mid'],
          '90': ['peak'],
        },
      });
      expect(pack.byMode[SessionMode.rhythm]!['soft'], ['rs1', 'rs2']);
      expect(pack.byMode[SessionMode.rhythm]!['hard'], ['rh1']);
      expect(pack.byMode[SessionMode.hold]!['finale'], ['hf1']);
      expect(pack.intros, ['hello']);
      expect(pack.congrats, ['merci']);
      expect(pack.encore, ['encore']);
      expect(pack.progress[50], ['mid']);
      expect(pack.progress[90], ['peak']);
    });

    test('ignore les clés inconnues et listes vides', () {
      final pack = CoachPhrasePack.fromJson({
        'phrases': {
          'unknownMode': {'soft': ['x']},
          'rhythm': {'soft': []},
        },
        'progress': {'notANumber': ['x']},
        'intros': ['  ', 'real'],
      });
      expect(pack.byMode.containsKey(SessionMode.rhythm), isFalse,
          reason: 'liste vide → tier non créé');
      expect(pack.progress, isEmpty);
      expect(pack.intros, ['real'], reason: 'whitespace-only filtré');
    });

    test('JSON vide → pack vide non null', () {
      final pack = CoachPhrasePack.fromJson({});
      expect(pack.isEmpty, isTrue);
    });
  });

  group('Coach.toPhraseBank — fallback sur banque globale', () {
    PhraseBank globalBank() => const PhraseBank(
          byMode: {
            SessionMode.rhythm: {
              'soft': ['G_rhythm_soft'],
              'medium': ['G_rhythm_medium'],
              'hard': ['G_rhythm_hard'],
            },
            SessionMode.hold: {
              'soft': ['G_hold_soft'],
            },
          },
          congrats: ['G_congrats'],
          intros: ['G_intro'],
          progress: {
            50: ['G_excit50'],
          },
          encore: ['G_encore'],
        );

    Coach coachWith(CoachPhrasePack pack) {
      return CoachCatalog.defaults.first.withPhrases(pack);
    }

    final rng = Random(42);

    test('phrase coach présente → coach a priorité', () {
      final coach = coachWith(const CoachPhrasePack(
        byMode: {
          SessionMode.rhythm: {
            'soft': ['C_rhythm_soft'],
          },
        },
      ));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.rhythm, 'soft', rng), 'C_rhythm_soft');
    });

    test('phrase coach absente sur ce tier → fallback global', () {
      final coach = coachWith(const CoachPhrasePack(
        byMode: {
          SessionMode.rhythm: {
            'soft': ['C_rhythm_soft'],
          },
        },
      ));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.rhythm, 'medium', rng),
          'G_rhythm_medium',
          reason: 'medium absent côté coach → fallback');
    });

    test('phrase coach absente sur ce mode entier → fallback global', () {
      final coach = coachWith(const CoachPhrasePack(byMode: {}));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.hold, 'soft', rng), 'G_hold_soft');
    });

    test('intros / congrats / encore : coach prioritaire, fallback sinon', () {
      final coachAvecIntro = coachWith(const CoachPhrasePack(intros: ['C_intro']));
      expect(coachAvecIntro.toPhraseBank(fallback: globalBank()).pickIntro(rng),
          'C_intro');

      final coachSansIntro = coachWith(const CoachPhrasePack());
      expect(coachSansIntro.toPhraseBank(fallback: globalBank()).pickIntro(rng),
          'G_intro');

      final coachAvecCongrats = coachWith(const CoachPhrasePack(
        congrats: ['C_congrats'],
      ));
      expect(
          coachAvecCongrats.toPhraseBank(fallback: globalBank()).pickCongrats(rng),
          'C_congrats');
      expect(coachWith(const CoachPhrasePack())
          .toPhraseBank(fallback: globalBank())
          .pickCongrats(rng), 'G_congrats');

      final coachAvecEncore = coachWith(const CoachPhrasePack(encore: ['C_e']));
      expect(coachAvecEncore.toPhraseBank(fallback: globalBank()).pickEncore(rng),
          'C_e');
      expect(coachWith(const CoachPhrasePack())
          .toPhraseBank(fallback: globalBank())
          .pickEncore(rng), 'G_encore');
    });

    test('progress : coach prioritaire au seuil, fallback sinon', () {
      final coach = coachWith(const CoachPhrasePack(progress: {
        50: ['C_50'],
      }));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickProgress(50, rng), 'C_50');
      expect(bank.pickProgress(90, rng), isNull,
          reason: 'global n\'a pas de phrase 90 → null');
    });

    test('coach pack vide → 100 % fallback', () {
      final bank = coachWith(CoachPhrasePack.empty)
          .toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.rhythm, 'soft', rng), 'G_rhythm_soft');
      expect(bank.pickIntro(rng), 'G_intro');
      expect(bank.pickCongrats(rng), 'G_congrats');
      expect(bank.pickEncore(rng), 'G_encore');
      expect(bank.pickProgress(50, rng), 'G_excit50');
    });
  });
}
