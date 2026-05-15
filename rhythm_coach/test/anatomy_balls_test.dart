import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/anatomy_profile.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

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

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

void main() {
  group('AnatomyProfile', () {
    test('défaut = hasBalls true (rétrocompat tests / mode hérité)', () {
      expect(AnatomyProfile.defaults.hasBalls, isTrue);
      expect(const AnatomyProfile().hasBalls, isTrue);
    });

    test('copyWith change seulement le champ demandé', () {
      const base = AnatomyProfile(hasBalls: true);
      expect(base.copyWith().hasBalls, isTrue);
      expect(base.copyWith(hasBalls: false).hasBalls, isFalse);
    });

    test('équivalence value-based (operator ==)', () {
      expect(const AnatomyProfile(hasBalls: true),
          equals(const AnatomyProfile(hasBalls: true)));
      expect(const AnatomyProfile(hasBalls: false),
          isNot(equals(const AnatomyProfile(hasBalls: true))));
    });
  });

  group('Générateur — filtre anatomy balls', () {
    test(
        'hasBalls=false : aucun step ne touche Position.balls, même quand '
        'maxDepth=balls et humil très élevée', () {
      final gen = CareerSessionGenerator(seed: 1234);
      final result = gen.generate(
        level: 18,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
        maxDepthIndexOverride: Position.balls.index,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      final touchesBalls = result.session.steps.any(
        (s) => s.from == Position.balls || s.to == Position.balls,
      );
      expect(touchesBalls, isFalse,
          reason: 'Anatomy hasBalls=false → aucun step balls.');
    });

    test(
        'hasBalls=true + humil élevée + maxDepth=balls : balls peut '
        'apparaître mais seulement sur lick / hold / beg (pas rhythm / hand '
        '/ biffle)', () {
      final gen = CareerSessionGenerator(seed: 4321);
      final result = gen.generate(
        level: 18,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 400.0,
        maxDepthIndexOverride: Position.balls.index,
        anatomy: const AnatomyProfile(hasBalls: true),
      );
      for (final s in result.session.steps) {
        final touchesBalls =
            s.from == Position.balls || s.to == Position.balls;
        if (!touchesBalls) continue;
        // Modes-incompatibles : balls n'est pertinent que pour
        // lick/hold/beg (zone à lécher / aspirer / supplier-en-tenant).
        expect(
          s.mode == SessionMode.rhythm ||
              s.mode == SessionMode.hand ||
              s.mode == SessionMode.biffle,
          isFalse,
          reason: 'Modes-incompatibles sur balls : ${s.mode} interdit.',
        );
      }
    });
  });
}
