import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/session_step.dart' show BeatAnchor;
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

/// Chantier aimant, étape 4 : le final `hold` reçoit l'aimant « très dur »
/// (ancre sur `to`, ratio 9, bpm dédié 60) au-dessus du plancher de niveau
/// réutilisé de l'étape 3 ([CareerLevelGates.rhythmAnchorToFloorLevel]), et
/// jamais sinon — que ce soit par niveau trop bas ou parce que la position
/// tenue est `tip` (pas de position plus aiguë pour l'aller-retour). Vérifié
/// sur des séances de carrière réellement générées, pas en théorie.
void main() {
  group('ancrage du final hold (générateur réel)', () {
    test(
        'le final hold suit exactement '
        'CareerLevelGates.holdFinalAnchorEligible, quel que soit le niveau/'
        'seed — et le balayage couvre les deux issues', () {
      var sawAnchored = false;
      var sawNotAnchored = false;
      for (final level in [
        3,
        8,
        CareerLevelGates.rhythmAnchorToFloorLevel,
        15,
        25,
        35,
      ]) {
        for (final seed in [1, 7, 42, 99, 123]) {
          final gen = CareerSessionGenerator(seed: seed);
          final result = gen.generate(
            level: level,
            bank: _bank(),
            unlockedKeys: _allUnlocks,
            humiliationCareer: 400.0,
          );
          final finalTime = result.session.finalStepTime;
          if (finalTime == null) continue;
          final finalStep =
              result.session.steps.firstWhere((s) => s.time == finalTime);
          final mode = finalStep.mode ?? result.session.defaultMode;
          if (mode != SessionMode.hold) continue;
          final eligible = CareerLevelGates.holdFinalAnchorEligible(
              level: level, to: finalStep.to);
          final reason = 'level=$level seed=$seed to=${finalStep.to}';
          if (eligible) {
            sawAnchored = true;
            expect(finalStep.anchor, BeatAnchor.to, reason: reason);
            expect(finalStep.ratio, CareerLevelGates.holdFinalAnchorRatio,
                reason: reason);
            expect(finalStep.bpm, CareerLevelGates.holdFinalAnchorBpm,
                reason: reason);
          } else {
            sawNotAnchored = true;
            expect(finalStep.anchor, BeatAnchor.none, reason: reason);
            expect(finalStep.ratio, 1, reason: reason);
          }
        }
      }
      expect(sawAnchored, isTrue,
          reason: 'le balayage doit atteindre au moins un final hold '
              'éligible');
      expect(sawNotAnchored, isTrue,
          reason: 'le balayage doit atteindre au moins un final hold non '
              'éligible (niveau bas ou tip)');
    });

    test(
        'les autres steps hold de la séance (pas le final) ne sont jamais '
        'ancrés, y compris au-dessus du plancher', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 25,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
      );
      final finalTime = result.session.finalStepTime;
      final otherHolds = result.session.steps.where((s) =>
          s.time != finalTime &&
          (s.mode ?? result.session.defaultMode) == SessionMode.hold);
      expect(otherHolds, isNotEmpty);
      for (final s in otherHolds) {
        expect(s.anchor, BeatAnchor.none, reason: 't=${s.time} to=${s.to}');
        expect(s.ratio, 1, reason: 't=${s.time}');
      }
    });

    test(
        'holdFinalAnchorEligible (unitaire) : plancher de niveau ET '
        'position au-dessus de tip, cumulatifs', () {
      const floor = CareerLevelGates.rhythmAnchorToFloorLevel;
      expect(
          CareerLevelGates.holdFinalAnchorEligible(
              level: floor - 1, to: Position.full),
          isFalse,
          reason: 'sous le plancher, même profond');
      expect(
          CareerLevelGates.holdFinalAnchorEligible(
              level: floor, to: Position.tip),
          isFalse,
          reason: 'au plancher mais sur tip : pas de position plus aiguë');
      expect(
          CareerLevelGates.holdFinalAnchorEligible(
              level: floor, to: Position.head),
          isTrue,
          reason: 'au plancher et au-dessus de tip');
      expect(CareerLevelGates.holdFinalAnchorEligible(level: floor, to: null),
          isFalse,
          reason: 'pas de position tenue : rien à ancrer');
    });
  });
}
