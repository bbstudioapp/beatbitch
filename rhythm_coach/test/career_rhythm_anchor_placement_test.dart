import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/session_step.dart' show BeatAnchor;
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
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

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

/// Chantier aimant, étape 3 : `RhythmRules`/`CareerLevelGates.rhythmAnchorFor`
/// posent l'ancre selon l'interprétation de la consigne de Manu (rapport
/// chantier-aimant-étape-3) — sous le plancher de niveau, toujours `from` ;
/// au-dessus, elle alterne selon le bpm (proxy de la difficulté du moment)
/// du step. Vérifié sur des séances de carrière réellement générées, pas en
/// théorie.
void main() {
  group('placement de l\'ancre rythmée (générateur réel)', () {
    test('sous le plancher de niveau : toujours from', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: CareerLevelGates.rhythmAnchorToFloorLevel - 1,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 200.0,
      );
      final rhythmSteps = result.session.steps
          .where((s) =>
              (s.mode ?? result.session.defaultMode) == SessionMode.rhythm)
          .toList();
      expect(rhythmSteps, isNotEmpty);
      for (final s in rhythmSteps) {
        expect(s.anchor, BeatAnchor.from,
            reason: 'step t=${s.time} bpm=${s.bpm}');
      }
    });

    test('au-dessus du plancher : alterne from/to selon le bpm du step', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 25,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
      );
      final rhythmSteps = result.session.steps
          .where((s) =>
              (s.mode ?? result.session.defaultMode) == SessionMode.rhythm)
          .toList();
      expect(rhythmSteps, isNotEmpty);
      for (final s in rhythmSteps) {
        final expected =
            (s.bpm ?? 0) >= CareerLevelGates.rhythmAnchorHarderBpmThreshold
                ? BeatAnchor.to
                : BeatAnchor.from;
        expect(s.anchor, expected, reason: 'step t=${s.time} bpm=${s.bpm}');
      }
      // Alterne vraiment au sein de la séance — pas figé sur une seule
      // valeur (ce qui trahirait un bpm constant ou un seuil mal câblé).
      expect(rhythmSteps.map((s) => s.anchor).toSet(),
          containsAll(<BeatAnchor>[BeatAnchor.from, BeatAnchor.to]));
    });

    test('ratio par défaut de l\'aimant pour tout step rythmé généré', () {
      final gen = CareerSessionGenerator(seed: 7);
      final result = gen.generate(
        level: 15,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 300.0,
      );
      final rhythmSteps = result.session.steps.where(
          (s) => (s.mode ?? result.session.defaultMode) == SessionMode.rhythm);
      expect(rhythmSteps, isNotEmpty);
      for (final s in rhythmSteps) {
        expect(s.ratio, CareerLevelGates.rhythmAnchorDefaultRatio);
      }
    });

    test(
        'un aller-retour complet dure toujours 2T, ancré ou non — steps '
        'rythmés générés, rejoués via le vrai BeepEngine', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 25,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
      );
      final rhythmSteps = result.session.steps.where((s) =>
          (s.mode ?? result.session.defaultMode) == SessionMode.rhythm &&
          s.bpm != null &&
          s.from != null &&
          s.to != null);
      expect(rhythmSteps, isNotEmpty);
      for (final s in rhythmSteps) {
        final engine = BeepEngine();
        final events = engine.simulateBeatsForTest(
          mode: SessionMode.rhythm,
          from: s.from!,
          to: s.to!,
          bpm: s.bpm!.toDouble(),
          anchor: s.anchor,
          ratio: s.ratio,
          count: 4,
        );
        final intervals = [
          for (final e in events) e.nextInterval.inMilliseconds
        ];
        final expectedFullCycle = (120000 / s.bpm!).round();
        for (var i = 0; i + 1 < intervals.length; i += 2) {
          expect(intervals[i] + intervals[i + 1], expectedFullCycle,
              reason: 'step t=${s.time} bpm=${s.bpm} anchor=${s.anchor} '
                  'ratio=${s.ratio} i=$i');
        }
      }
    });

    test('modes non-rythmés : jamais ancrés (none / ratio 1)', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 25,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
      );
      final nonRhythm = result.session.steps.where(
          (s) => (s.mode ?? result.session.defaultMode) != SessionMode.rhythm);
      expect(nonRhythm, isNotEmpty);
      for (final s in nonRhythm) {
        expect(s.anchor, BeatAnchor.none, reason: '${s.mode} t=${s.time}');
        expect(s.ratio, 1, reason: '${s.mode} t=${s.time}');
      }
    });
  });
}
