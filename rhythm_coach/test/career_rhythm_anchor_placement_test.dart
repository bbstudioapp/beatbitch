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

/// Chantier aimant, étape 3-bis : le métronome (boucle main + recovery) est
/// le standard, jamais ancré ; l'ancre est une variation posée uniquement
/// sur les moments intenses (mini-vague, pré-finisher, boosts de la phase
/// finish) — cf. rapport chantier-aimant-étape-3-bis. `RhythmRules`/
/// `CareerLevelGates.rhythmAnchorFor` décident *quelle* position (from/to)
/// parmi les steps que le générateur a choisi d'ancrer ; sous le plancher de
/// niveau, toujours `from`, au-dessus elle alterne selon le bpm (proxy de la
/// difficulté du moment). Vérifié sur des séances de carrière réellement
/// générées, pas en théorie.
void main() {
  group('placement de l\'ancre rythmée (générateur réel)', () {
    test(
        'le métronome (boucle main + recovery) reste très majoritairement '
        'non ancré, à tout niveau', () {
      for (final level in [5, CareerLevelGates.rhythmAnchorToFloorLevel, 25]) {
        final gen = CareerSessionGenerator(seed: 42);
        final result = gen.generate(
          level: level,
          bank: _bank(),
          unlockedKeys: _allUnlocks,
          humiliationCareer: 400.0,
        );
        final rhythmSteps = result.session.steps
            .where((s) =>
                (s.mode ?? result.session.defaultMode) == SessionMode.rhythm)
            .toList();
        expect(rhythmSteps, isNotEmpty, reason: 'level=$level');
        final anchored =
            rhythmSteps.where((s) => s.anchor != BeatAnchor.none).length;
        // Aux niveaux balayés ici (mini-vague éligible dès 5), la vague ou
        // les boosts rythmés posent au moins une ancre. Aux niveaux 3-4 —
        // ni pré-finisher (≤ 2) ni mini-vague (≥ 5) — une séance entière
        // peut n'en porter aucune quand les boosts sortent en hand.
        expect(anchored, greaterThan(0), reason: 'level=$level');
        // Minoritaire : la mini-vague (2-3 steps) + le pré-finisher (0-1) +
        // les boosts (quelques-uns) ne pèsent jamais la moitié d'une séance
        // rythmée complète.
        expect(anchored, lessThan(rhythmSteps.length ~/ 2),
            reason: 'level=$level : ${rhythmSteps.length} steps rythmés, '
                '$anchored ancrés');
      }
    });

    test(
        'au-dessus du plancher, l\'ancre posée alterne from/to selon le '
        'bpm du step', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 25,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
      );
      final anchored = result.session.steps
          .where((s) =>
              (s.mode ?? result.session.defaultMode) == SessionMode.rhythm &&
              s.anchor != BeatAnchor.none)
          .toList();
      expect(anchored, isNotEmpty);
      for (final s in anchored) {
        final expected =
            (s.bpm ?? 0) >= CareerLevelGates.rhythmAnchorHarderBpmThreshold
                ? BeatAnchor.to
                : BeatAnchor.from;
        expect(s.anchor, expected, reason: 'step t=${s.time} bpm=${s.bpm}');
      }
      // Pas de `containsAll([from, to])` ici : en génération carrière
      // au-dessus du plancher, les deux seules sources ancrées (mini-vague,
      // boosts) plafonnent leur bpm à ≥100 — la branche `from` de la règle
      // n'y est plus atteinte. Elle l'est encore hors carrière : le mode
      // Custom passe des bornes BPM utilisateur au même générateur. Couverte
      // à part par le test unitaire de `rhythmAnchorFor` ci-dessous.
    });

    test(
        'rhythmAnchorFor (unitaire) : couvre la branche from que la '
        'génération réelle au-dessus du plancher n\'atteint plus', () {
      expect(
          CareerLevelGates.rhythmAnchorFor(
              level: CareerLevelGates.rhythmAnchorToFloorLevel, bpm: 60),
          BeatAnchor.from);
      expect(
          CareerLevelGates.rhythmAnchorFor(
              level: CareerLevelGates.rhythmAnchorToFloorLevel, bpm: 140),
          BeatAnchor.to);
    });

    test(
        'ratio par défaut de l\'aimant sur tout step rythmé effectivement '
        'ancré ; 1 sinon', () {
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
        expect(
            s.ratio,
            s.anchor != BeatAnchor.none
                ? CareerLevelGates.rhythmAnchorDefaultRatio
                : 1,
            reason: 'step t=${s.time} anchor=${s.anchor}');
      }
      expect(rhythmSteps.any((s) => s.anchor != BeatAnchor.none), isTrue,
          reason: 'la sonde ratio doit couvrir au moins un step ancré');
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
        // Sans ancrage, le court et le long sont chacun arrondis
        // indépendamment (`_regularInterval` deux fois) au lieu que le court
        // se déduise du long par soustraction — tolérance ±1 ms documentée
        // dans `movement_animation.dart` (`complementaryBeatIntervalMs`).
        // Avec ancrage, l'invariant reste exact par construction.
        final tolerance = s.anchor == BeatAnchor.none ? 1 : 0;
        for (var i = 0; i + 1 < intervals.length; i += 2) {
          expect((intervals[i] + intervals[i + 1] - expectedFullCycle).abs(),
              lessThanOrEqualTo(tolerance),
              reason: 'step t=${s.time} bpm=${s.bpm} anchor=${s.anchor} '
                  'ratio=${s.ratio} i=$i');
        }
      }
    });

    test(
        'modes non-rythmés : jamais ancrés (none / ratio 1), sauf le '
        'final hold (chantier aimant étape 4)', () {
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
      final finalTime = result.session.finalStepTime;
      for (final s in nonRhythm) {
        final isEligibleFinalHold = s.time == finalTime &&
            (s.mode ?? result.session.defaultMode) == SessionMode.hold &&
            s.to != null &&
            s.to!.index > 0;
        if (isEligibleFinalHold) {
          // Seul cas légitime : le final lui-même, quand c'est un hold
          // qui n'est pas déjà sur `tip`. Vérifié en détail par
          // `career_hold_final_anchor_placement_test.dart`.
          continue;
        }
        expect(s.anchor, BeatAnchor.none, reason: '${s.mode} t=${s.time}');
        expect(s.ratio, 1, reason: '${s.mode} t=${s.time}');
      }
    });
  });
}
