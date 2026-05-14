import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';

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
          'boost': _p(['b']),
          'finale': _p(['f']),
          'fake_breath': _p(['ssh']),
        },
    },
    congrats: _p(['bravo']),
    intros: _p(['intro']),
  );
}

bool _isRhythmic(SessionMode m) =>
    m == SessionMode.rhythm ||
    m == SessionMode.lick ||
    m == SessionMode.biffle ||
    m == SessionMode.hand;

void main() {
  group('Custom mode — bornes BPM/hold imposées par l\'utilisateur', () {
    test('bpmRange borne le BPM de tous les steps rythmés émis', () {
      const lo = 70;
      const hi = 110;
      for (final seed in [1, 7, 42, 99, 314, 1234]) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 6,
          bank: _bank(),
          durationSeconds: 12 * 60,
          humiliationCareer: 400.0,
          obedience: 100.0,
          bpmRange: (lo, hi),
        );
        for (final step in result.session.steps) {
          if (step.isTextOnly) continue;
          final mode = step.mode ?? result.session.defaultMode;
          if (!_isRhythmic(mode)) continue;
          if (step.bpm == null) continue;
          expect(step.bpm, greaterThanOrEqualTo(lo),
              reason:
                  'BPM=${step.bpm} < lo=$lo pour mode=$mode seed=$seed time=${step.time}');
          expect(step.bpm, lessThanOrEqualTo(hi),
              reason:
                  'BPM=${step.bpm} > hi=$hi pour mode=$mode seed=$seed time=${step.time}');
        }
      }
    });

    test('holdDurationRange borne la durée des holds émis', () {
      const lo = 6;
      const hi = 20;
      for (final seed in [1, 7, 42, 99, 314, 1234]) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 6,
          bank: _bank(),
          durationSeconds: 12 * 60,
          humiliationCareer: 400.0,
          obedience: 100.0,
          holdDurationRange: (lo, hi),
        );
        for (final step in result.session.steps) {
          if (step.isTextOnly) continue;
          final mode = step.mode ?? result.session.defaultMode;
          if (mode != SessionMode.hold) continue;
          final dur = step.duration;
          if (dur == null) continue;
          expect(dur, greaterThanOrEqualTo(lo),
              reason: 'hold dur=$dur < lo=$lo (seed=$seed time=${step.time})');
          expect(dur, lessThanOrEqualTo(hi),
              reason: 'hold dur=$dur > hi=$hi (seed=$seed time=${step.time})');
        }
      }
    });

    test('range inversé (max < min) est silencieusement réordonné', () {
      // L'utilisateur a tiré le min au-dessus du max : le générateur trie
      // pour ne pas générer un clamp vide qui crasherait.
      final gen = CareerSessionGenerator(seed: 1);
      final result = gen.generate(
        level: 6,
        bank: _bank(),
        durationSeconds: 8 * 60,
        humiliationCareer: 400.0,
        bpmRange: (140, 80),
      );
      // Aucun crash + BPM dans [80, 140] sur les rythmés.
      for (final step in result.session.steps) {
        if (step.isTextOnly) continue;
        final mode = step.mode ?? result.session.defaultMode;
        if (!_isRhythmic(mode) || step.bpm == null) continue;
        expect(step.bpm, inInclusiveRange(80, 140));
      }
    });

    test('sans bornage (paramètres null) → comportement inchangé', () {
      // Garde-fou : un Custom à valeurs par défaut a bpmRange/holdRange null
      // (le mode Custom les passe systématiquement, mais carrière/scénario
      // les laissent à null). Pas de régression sur les autres call sites.
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 6,
        bank: _bank(),
        durationSeconds: 8 * 60,
        humiliationCareer: 400.0,
      );
      expect(result.session.steps, isNotEmpty);
    });
  });
}
