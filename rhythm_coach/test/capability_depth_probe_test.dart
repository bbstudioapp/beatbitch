import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Sonde vers le `best` (direction #1) : la profondeur rythme peut viser **un
/// cran** au-dessus du `comfort`, borné par la profondeur déjà prouvée (`best`).
/// Objectif : une compétence rabaissée (best > comfort après tap-out / decay)
/// se re-propose un cran plus profond en séance normale — throat réapparaît, et
/// l'overshoot redevient possible → le `comfort` peut ratcheter. Quand
/// `best == comfort` (axe consolidé), la sonde est un no-op (comportement
/// Phase 19.7 inchangé).

CapabilityProfile _depth({required double best, required double comfort}) =>
    CapabilityProfile({
      CapabilityAxis.rhythmDepthMax:
          CapabilityAxisState(best: best, comfort: comfort),
    });

List<PhraseEntry> _p(List<String> t) =>
    t.map((s) => PhraseEntry(text: s)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'boost': _p(['b']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

CareerGenerationResult _gen(int seed, CapabilityProfile profile) =>
    CareerSessionGenerator(seed: seed).generate(
      level: 14,
      bank: _bank(),
      includeHand: true,
      humiliationCareer: 100.0,
      unlockedKeys: UnlockKey.values.toSet(),
      capability: CapabilityInputs(profile: profile),
    );

void main() {
  group('maxDepthIndexForProfile — sonde vers le best', () {
    test('best throat > comfort mid → throat (sonde +1 cran)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(
            _depth(best: 3.0, comfort: 2.0)),
        Position.throat.index,
      );
    });

    test('best full > comfort mid → throat (un seul cran, pas full)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(
            _depth(best: 4.0, comfort: 2.0)),
        Position.throat.index,
      );
    });

    test('best full, comfort throat → full', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(
            _depth(best: 4.0, comfort: 3.0)),
        Position.full.index,
      );
    });

    test('best == comfort mid → mid (no-op, sonde inactive)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(
            _depth(best: 2.0, comfort: 2.0)),
        Position.mid.index,
      );
    });

    test('best throat, comfort head → mid (sonde +1 = mid, planché mid)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(
            _depth(best: 3.0, comfort: 1.0)),
        Position.mid.index,
      );
    });
  });

  group('générateur — la sonde débloque throat sans dépasser le best', () {
    test('best throat > comfort mid → au moins un rhythm throat, jamais > best',
        () {
      final profile = _depth(best: 3.0, comfort: 2.0);
      var sawThroat = false;
      for (final seed in [1, 7, 13, 42, 256]) {
        for (final s in _gen(seed, profile).session.steps) {
          if (s.mode != SessionMode.rhythm || s.to == null) continue;
          expect(s.to!.index, lessThanOrEqualTo(Position.throat.index),
              reason: 'seed=$seed rhythm to=${s.to!.name} (t=${s.time}) '
                  'dépasse le best prouvé (throat)');
          if (s.to!.index == Position.throat.index) sawThroat = true;
        }
      }
      expect(sawThroat, isTrue,
          reason:
              'best=throat, comfort=mid : la sonde doit re-proposer du throat');
    });

    test('best == comfort mid → aucun rhythm au-delà de mid (no-op préservé)',
        () {
      final profile = _depth(best: 2.0, comfort: 2.0);
      for (final seed in [1, 7, 13, 42, 256]) {
        for (final s in _gen(seed, profile).session.steps) {
          if (s.mode != SessionMode.rhythm || s.to == null) continue;
          expect(s.to!.index, lessThanOrEqualTo(Position.mid.index),
              reason: 'seed=$seed rhythm to=${s.to!.name} (t=${s.time}) '
                  'dépasse mid alors que best == comfort == mid');
        }
      }
    });
  });
}
