import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

extension _PhraseTexts on List<PhraseEntry> {
  List<String> get texts => map((e) => e.text).toList();
}

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
      expect(pack.byMode[SessionMode.rhythm]!['soft']!.texts, ['rs1', 'rs2']);
      expect(pack.byMode[SessionMode.rhythm]!['hard']!.texts, ['rh1']);
      expect(pack.byMode[SessionMode.hold]!['finale']!.texts, ['hf1']);
      expect(pack.intros.texts, ['hello']);
      expect(pack.congrats.texts, ['merci']);
      expect(pack.encore.texts, ['encore']);
      expect(pack.progress[50]!.texts, ['mid']);
      expect(pack.progress[90]!.texts, ['peak']);
    });

    test('ignore les clés inconnues et listes vides', () {
      final pack = CoachPhrasePack.fromJson({
        'phrases': {
          'unknownMode': {
            'soft': ['x']
          },
          'rhythm': {'soft': []},
        },
        'progress': {
          'notANumber': ['x']
        },
        'intros': ['  ', 'real'],
      });
      expect(pack.byMode.containsKey(SessionMode.rhythm), isFalse,
          reason: 'liste vide → tier non créé');
      expect(pack.progress, isEmpty);
      expect(pack.intros.texts, ['real'], reason: 'whitespace-only filtré');
    });

    test('JSON vide → pack vide non null', () {
      final pack = CoachPhrasePack.fromJson({});
      expect(pack.isEmpty, isTrue);
    });

    test('parse progressPhrases (clés = storageKeys d\'axes, 3 tiers)', () {
      final pack = CoachPhrasePack.fromJson({
        'progressPhrases': {
          'gorge.apnee_streak': {
            'attempt': ['a1', 'a2'],
            'record': ['r1'],
            'tapout': ['t1'],
          },
          'rhythm.depth_max': {
            'attempt': ['da1'],
          },
          'cle.bidon.inconnue': {
            'attempt': ['conservée telle quelle'],
          },
          'vide.partout': {
            'attempt': [],
          },
          '   ': {
            'attempt': ['clé blanche → ignorée'],
          },
        },
      });
      expect(pack.progressPhrases['gorge.apnee_streak']!['attempt']!.texts,
          ['a1', 'a2']);
      expect(
          pack.progressPhrases['gorge.apnee_streak']!['record']!.texts, ['r1']);
      expect(
          pack.progressPhrases['gorge.apnee_streak']!['tapout']!.texts, ['t1']);
      expect(
          pack.progressPhrases['rhythm.depth_max']!['attempt']!.texts, ['da1']);
      // Clé inconnue : conservée (jamais validée contre l'enum CapabilityAxis).
      expect(pack.progressPhrases.containsKey('cle.bidon.inconnue'), isTrue);
      // Axe sans aucun tier non vide → absent.
      expect(pack.progressPhrases.containsKey('vide.partout'), isFalse);
      // Clé blanche → ignorée.
      expect(pack.progressPhrases.containsKey('   '), isFalse);
    });

    test('progressPhrases absent → map vide', () {
      expect(CoachPhrasePack.fromJson({}).progressPhrases, isEmpty);
      expect(CoachPhrasePack.empty.progressPhrases, isEmpty);
    });

    test('parse un objet contraint avec min_depth/max_depth', () {
      final pack = CoachPhrasePack.fromJson({
        'phrases': {
          'hold': {
            'medium': [
              'simple',
              {'text': 'respire par le nez', 'max_depth': 'mid'},
            ],
          },
        },
      });
      final entries = pack.byMode[SessionMode.hold]!['medium']!;
      expect(entries.length, 2);
      expect(entries[0].text, 'simple');
      expect(entries[0].hasNoConstraints, isTrue);
      expect(entries[1].text, 'respire par le nez');
      expect(entries[1].maxDepth, isNotNull);
    });
  });

  group('Coach.toPhraseBank — fallback sur banque globale', () {
    PhraseBank globalBank() => const PhraseBank(
          byMode: {
            SessionMode.rhythm: {
              'soft': [PhraseEntry(text: 'G_rhythm_soft')],
              'medium': [PhraseEntry(text: 'G_rhythm_medium')],
              'hard': [PhraseEntry(text: 'G_rhythm_hard')],
            },
            SessionMode.hold: {
              'soft': [PhraseEntry(text: 'G_hold_soft')],
            },
          },
          congrats: [PhraseEntry(text: 'G_congrats')],
          intros: [PhraseEntry(text: 'G_intro')],
          progress: {
            50: [PhraseEntry(text: 'G_excit50')],
          },
          encore: [PhraseEntry(text: 'G_encore')],
        );

    Coach coachWith(CoachPhrasePack pack) {
      return CoachCatalog.defaults.first.withPhrases(pack);
    }

    final rng = Random(42);

    test('phrase coach présente → coach a priorité', () {
      final coach = coachWith(const CoachPhrasePack(
        byMode: {
          SessionMode.rhythm: {
            'soft': [PhraseEntry(text: 'C_rhythm_soft')],
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
            'soft': [PhraseEntry(text: 'C_rhythm_soft')],
          },
        },
      ));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.rhythm, 'medium', rng), 'G_rhythm_medium',
          reason: 'medium absent côté coach → fallback');
    });

    test('phrase coach absente sur ce mode entier → fallback global', () {
      final coach = coachWith(const CoachPhrasePack(byMode: {}));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.hold, 'soft', rng), 'G_hold_soft');
    });

    test('intros / congrats / encore : coach prioritaire, fallback sinon', () {
      final coachAvecIntro = coachWith(const CoachPhrasePack(
        intros: [PhraseEntry(text: 'C_intro')],
      ));
      expect(coachAvecIntro.toPhraseBank(fallback: globalBank()).pickIntro(rng),
          'C_intro');

      final coachSansIntro = coachWith(const CoachPhrasePack());
      expect(coachSansIntro.toPhraseBank(fallback: globalBank()).pickIntro(rng),
          'G_intro');

      final coachAvecCongrats = coachWith(const CoachPhrasePack(
        congrats: [PhraseEntry(text: 'C_congrats')],
      ));
      expect(
          coachAvecCongrats
              .toPhraseBank(fallback: globalBank())
              .pickCongrats(rng),
          'C_congrats');
      expect(
          coachWith(const CoachPhrasePack())
              .toPhraseBank(fallback: globalBank())
              .pickCongrats(rng),
          'G_congrats');

      final coachAvecEncore = coachWith(const CoachPhrasePack(
        encore: [PhraseEntry(text: 'C_e')],
      ));
      expect(
          coachAvecEncore.toPhraseBank(fallback: globalBank()).pickEncore(rng),
          'C_e');
      expect(
          coachWith(const CoachPhrasePack())
              .toPhraseBank(fallback: globalBank())
              .pickEncore(rng),
          'G_encore');
    });

    test('progress : coach prioritaire au seuil, fallback sinon', () {
      final coach = coachWith(const CoachPhrasePack(progress: {
        50: [PhraseEntry(text: 'C_50')],
      }));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickProgress(50, rng), 'C_50');
      expect(bank.pickProgress(90, rng), isNull,
          reason: 'global n\'a pas de phrase 90 → null');
    });

    test('coach pack vide → 100 % fallback', () {
      final bank =
          coachWith(CoachPhrasePack.empty).toPhraseBank(fallback: globalBank());
      expect(bank.pickFor(SessionMode.rhythm, 'soft', rng), 'G_rhythm_soft');
      expect(bank.pickIntro(rng), 'G_intro');
      expect(bank.pickCongrats(rng), 'G_congrats');
      expect(bank.pickEncore(rng), 'G_encore');
      expect(bank.pickProgress(50, rng), 'G_excit50');
    });

    test('pickProgressPhrase : coach prioritaire, null si axe/tier absent', () {
      final coach = coachWith(const CoachPhrasePack(progressPhrases: {
        'gorge.apnee_streak': {
          'attempt': [PhraseEntry(text: 'C_apnee_attempt')],
          'tapout': [PhraseEntry(text: 'C_apnee_tapout')],
        },
      }));
      final bank = coach.toPhraseBank(fallback: globalBank());
      expect(bank.pickProgressPhrase('gorge.apnee_streak', 'attempt', rng),
          'C_apnee_attempt');
      expect(bank.pickProgressPhrase('gorge.apnee_streak', 'tapout', rng),
          'C_apnee_tapout');
      // Tier absent pour cet axe → null (l'appelant reste silencieux).
      expect(
          bank.pickProgressPhrase('gorge.apnee_streak', 'record', rng), isNull);
      // Axe absent → null.
      expect(
          bank.pickProgressPhrase('hold.full.streak', 'attempt', rng), isNull);
    });

    test('pickProgressPhrase : banque globale nue / coach sans section → null',
        () {
      expect(
          globalBank().pickProgressPhrase('gorge.apnee_streak', 'attempt', rng),
          isNull);
      expect(
          coachWith(CoachPhrasePack.empty)
              .toPhraseBank(fallback: globalBank())
              .pickProgressPhrase('gorge.apnee_streak', 'attempt', rng),
          isNull);
    });
  });

  group('PhraseBank.pickFor — filtrage par contexte', () {
    final rng = Random(0);

    test('max_depth filtre les phrases pour les profondeurs au-delà', () {
      const bank = PhraseBank(
        byMode: {
          SessionMode.hold: {
            'medium': [
              PhraseEntry(
                text: 'respire par le nez',
                maxDepth: Position.mid,
              ),
              PhraseEntry(text: 'générique'),
            ],
          },
        },
        congrats: [],
        intros: [],
      );
      // Hold full → la phrase max_depth=mid doit être exclue. Reste
      // « générique » qui passe (sans contraintes).
      for (var i = 0; i < 10; i++) {
        final picked = bank.pickFor(
          SessionMode.hold,
          'medium',
          rng,
          context: const PhraseContext(depth: Position.full),
        );
        expect(picked, 'générique');
      }
      // Hold mid → la phrase max_depth=mid passe, plus la générique. On
      // accepte les deux dans le tirage.
      final results = <String>{};
      for (var i = 0; i < 50; i++) {
        results.add(bank.pickFor(
          SessionMode.hold,
          'medium',
          rng,
          context: const PhraseContext(depth: Position.mid),
        ));
      }
      expect(results, contains('respire par le nez'));
      expect(results, contains('générique'));
    });

    test('min_depth filtre les phrases pour les profondeurs en-dessous', () {
      const bank = PhraseBank(
        byMode: {
          SessionMode.rhythm: {
            'hard': [
              PhraseEntry(
                text: 'nez contre les couilles',
                minDepth: Position.full,
              ),
              PhraseEntry(text: 'plus dur'),
            ],
          },
        },
        congrats: [],
        intros: [],
      );
      // Rhythm head→mid → minDepth=full ne match pas. Fallback sur
      // « plus dur ».
      for (var i = 0; i < 10; i++) {
        final picked = bank.pickFor(
          SessionMode.rhythm,
          'hard',
          rng,
          context: const PhraseContext(depth: Position.mid),
        );
        expect(picked, 'plus dur');
      }
    });

    test('sans contexte → tirage uniforme, pas de filtre', () {
      const bank = PhraseBank(
        byMode: {
          SessionMode.hold: {
            'medium': [
              PhraseEntry(
                text: 'contrainte',
                maxDepth: Position.mid,
              ),
            ],
          },
        },
        congrats: [],
        intros: [],
      );
      // Sans contexte, la phrase contrainte sort quand même (compat
      // historique).
      expect(bank.pickFor(SessionMode.hold, 'medium', rng), 'contrainte');
    });
  });
}
