import 'package:flutter_test/flutter_test.dart';

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
      final durations =
          SessionLengthChoice.values.map((c) => c.durationSeconds).toList();
      for (var i = 1; i < durations.length; i++) {
        expect(durations[i], greaterThan(durations[i - 1]),
            reason: 'palier $i (${SessionLengthChoice.values[i]}) doit '
                'être strictement plus long que ${SessionLengthChoice.values[i - 1]}');
      }
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
