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

/// Liste des modes effectivement émis dans les steps de config (text-only
/// exclu — ils n'ont pas de mode propre, ils continuent le loop en place).
List<SessionMode> _emittedModes(Session s) => s.steps
    .where((step) => !step.isTextOnly)
    .map((step) => step.mode ?? s.defaultMode)
    .toList();

/// Construit une dose qui passe à 0.0 pour le mode banni et à 1.0 partout
/// ailleurs (dose `normal`). Reproduit ce que fait
/// `CustomSessionConfig.resolveCoachModeWeights` pour ce mode-là.
Map<SessionMode, double> _doseExcluding(SessionMode banned) => {
      for (final m in SessionMode.values) m: m == banned ? 0.0 : 1.0,
    };

void main() {
  group('Custom mode — la dose `none` exclut le mode des steps émis', () {
    // Niveau virtuel 6 = mapping `CustomDifficulty.normal`. Mode hérité
    // (unlockedKeys vide) pour reproduire fidèlement ce que passe
    // `CustomModeScreen._generate` aux Custom sessions.
    for (final banned in const [
      SessionMode.rhythm,
      SessionMode.lick,
      SessionMode.hold,
      SessionMode.beg,
      SessionMode.biffle,
      SessionMode.hand,
      SessionMode.freestyle,
    ]) {
      test('dose=none sur ${banned.name} → aucun step n\'utilise ce mode', () {
        // Plusieurs seeds pour couvrir la part aléatoire du tirage.
        for (final seed in [1, 7, 42, 99, 314]) {
          final gen = CareerSessionGenerator(seed: seed);
          final result = gen.generate(
            level: 6,
            bank: _bank(),
            durationSeconds: 12 * 60,
            coachModeWeights: _doseExcluding(banned),
            humiliationCareer: 400.0, // proche de Custom (cap humil quasi-off)
            obedience: 100.0,
          );
          final emitted = _emittedModes(result.session);
          expect(emitted, isNotEmpty,
              reason: 'session vide pour banned=${banned.name} seed=$seed');
          expect(emitted, isNot(contains(banned)),
              reason: 'mode ${banned.name} émis malgré dose=none (seed=$seed)');
        }
      });
    }

    test('rhythm exclu : pas de mini-vague rhythm dans une session ≥ 12 min',
        () {
      final gen = CareerSessionGenerator(seed: 12);
      final result = gen.generate(
        level: 6,
        bank: _bank(),
        durationSeconds: 19 * 60, // assez long pour 2-3 mini-vagues
        coachModeWeights: _doseExcluding(SessionMode.rhythm),
        humiliationCareer: 400.0,
      );
      final emitted = _emittedModes(result.session);
      expect(emitted, isNot(contains(SessionMode.rhythm)),
          reason: 'rhythm émis (mini-vague non gardée par le filtre)');
    });

    test('hand + rhythm exclus : les boosts retombent sur lick', () {
      final doses = {
        for (final m in SessionMode.values)
          m: (m == SessionMode.hand || m == SessionMode.rhythm) ? 0.0 : 1.0,
      };
      // Plusieurs seeds : on veut être robuste à la randomisation.
      var foundLickBurst = false;
      for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 6,
          bank: _bank(),
          durationSeconds: 12 * 60,
          coachModeWeights: doses,
          humiliationCareer: 400.0,
        );
        final emitted = _emittedModes(result.session);
        expect(emitted, isNot(contains(SessionMode.hand)),
            reason: 'seed=$seed hand leaked');
        expect(emitted, isNot(contains(SessionMode.rhythm)),
            reason: 'seed=$seed rhythm leaked');
        // Lick burst à BPM ≥ 80 = signature d'un boost rabattu sur lick.
        for (final s in result.session.steps) {
          if (s.mode == SessionMode.lick && (s.bpm ?? 0) >= 80) {
            foundLickBurst = true;
            break;
          }
        }
      }
      expect(foundLickBurst, isTrue,
          reason:
              'aucun lick à BPM ≥ 80 trouvé : les boosts ne sont pas tombés '
              'sur lick comme attendu quand hand+rhythm sont exclus');
    });
  });
}
