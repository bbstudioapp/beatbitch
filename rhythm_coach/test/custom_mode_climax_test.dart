import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

/// Garde-fou issue #43 : en mode Custom (= `unlockedKeys` vide, convention
/// « mode hérité »), le `_pickFinal` du générateur doit promouvoir le final
/// le plus humiliant accessible — *pas* retomber sur la baseline `hand`
/// faute d'avoir débloqué les `UnlockKey.finalXxx`. Le bug d'origine :
/// `_finalUnlocked` n'honorait pas la convention héritée, filtrait tous les
/// finals gated, et Custom Extrême se terminait systématiquement par un
/// « branler ».
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

SessionStep _finalStep(Session s) {
  final t = s.finalStepTime;
  expect(t, isNotNull, reason: 'le générateur doit annoter `finalStepTime`');
  return s.steps.firstWhere((step) => !step.isTextOnly && step.time == t);
}

void main() {
  group('Custom Extrême — le final est le plus dur, pas un « branler »', () {
    // Reproduit fidèlement ce que `CustomModeScreen._generate` passe pour
    // un preset Extrême avec `maxDepthIndex = 4` (full).
    for (final seed in [1, 7, 42, 99, 314, 1234]) {
      test('seed=$seed : final = hold full long (≥ 30 s)', () {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 18, // CustomDifficulty.extreme
          bank: _bank(),
          durationSeconds: 12 * 60,
          unlockedKeys: const {}, // mode hérité Custom
          humiliationCareer: 400.0,
          humiliationSession: 0.0,
          obedience: 100.0,
          intensityFloorOverride: 0.45,
        );
        final f = _finalStep(result.session);
        expect(f.mode, SessionMode.hold,
            reason: 'final attendu = hold (full), reçu ${f.mode}');
        expect(f.to, Position.full,
            reason: 'final attendu en profondeur full, reçu to=${f.to?.name}');
        // L'apothéose Extrême doit être *longue* : avec humilCareer=400,
        // `_pickFinal` projette ~80 s (cap des holds full). On accepte
        // ≥ 30 s pour absorber d'éventuels ajustements futurs sur la
        // formule de durée, tout en restant indubitablement « long ».
        expect(f.duration ?? 0, greaterThanOrEqualTo(30),
            reason: 'hold full final trop court (${f.duration}s)');
      });
    }
  });

  group('Custom — le final scale avec maxDepthIndex', () {
    test('maxDepthIndex=throat → final hold throat (full bloqué)', () {
      final gen = CareerSessionGenerator(seed: 42);
      final result = gen.generate(
        level: 18,
        bank: _bank(),
        durationSeconds: 12 * 60,
        unlockedKeys: const {},
        humiliationCareer: 400.0,
        maxDepthIndexOverride: Position.throat.index,
      );
      final f = _finalStep(result.session);
      expect(f.mode, SessionMode.hold);
      expect(f.to, Position.throat,
          reason: 'avec maxDepth=throat, l\'apothéose est un hold throat, '
              'pas un hold full ; reçu to=${f.to?.name}');
    });

    test('dose `hold`=none + maxDepth=full → final non-hold (pas hand)', () {
      // Cas Custom où l'utilisateur a banni hold dans son dosage :
      // `_isModeForbidden(hold)` true ⇒ tous les hold candidates sont
      // écartés. Le candidat le plus humiliant restant doit gagner —
      // typiquement biffle (req 13) si la main est dispo, sinon lick.
      final doses = {
        for (final m in SessionMode.values)
          m: m == SessionMode.hold ? 0.0 : 1.0,
      };
      final gen = CareerSessionGenerator(seed: 7);
      final result = gen.generate(
        level: 18,
        bank: _bank(),
        durationSeconds: 12 * 60,
        unlockedKeys: const {},
        humiliationCareer: 400.0,
        coachModeWeights: doses,
      );
      final f = _finalStep(result.session);
      expect(f.mode, isNot(SessionMode.hold),
          reason: 'hold est banni, le final ne doit pas être un hold');
      // hand a été ajouté comme candidat normal seulement pour `_level < 4`
      // → à level 18, hand ne peut tomber qu'en fallback ultime. Avec biffle
      // et lick disponibles ici, on ne doit jamais y retomber.
      expect(f.mode, isNot(SessionMode.hand),
          reason: 'le fallback hand ne doit pas être atteint (biffle/lick '
              'sont valides) ; reçu ${f.mode}');
    });
  });

  group('Régression carrière — le gating final reste actif', () {
    // En carrière (`_unlockedKeys` non vide), un final dont la `finalXxx`
    // n'est pas dans le set ne doit pas être retenu — sinon l'invariant
    // « 1 milestone → 1 unlock → 1 action » de la chaîne intro_final_*
    // s'effondre.
    test('unlockedKeys = {basics} : final hold full INTERDIT (pas la clé)', () {
      final gen = CareerSessionGenerator(seed: 1);
      final result = gen.generate(
        level: 18,
        bank: _bank(),
        durationSeconds: 12 * 60,
        unlockedKeys: const {UnlockKey.basics},
        humiliationCareer: 400.0,
      );
      final f = _finalStep(result.session);
      final isHoldFull = f.mode == SessionMode.hold && f.to == Position.full;
      expect(isHoldFull, isFalse,
          reason: 'sans `finalHoldFull` dans unlockedKeys, l\'apothéose '
              'hold full doit rester bloquée ; reçu mode=${f.mode} '
              'to=${f.to?.name}');
    });
  });
}
