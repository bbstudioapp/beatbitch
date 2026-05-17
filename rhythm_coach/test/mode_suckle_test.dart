import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';

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

Set<UnlockKey> _allExcept(Set<UnlockKey> except) =>
    UnlockKey.values.where((k) => !except.contains(k)).toSet();

LevelMilestone _suckleBallsMilestone() {
  // Séquence avec un step suckle balls — le filtre anatomy de
  // `MilestoneService.allPendingFor` doit l'exclure quand hasBalls=false.
  const ballsStep = SessionStep(
    time: 0,
    mode: SessionMode.suckle,
    to: Position.balls,
    duration: 10,
  );
  return const LevelMilestone(
    id: 'intro_suckle_balls',
    minLevel: 11,
    humilRequired: 5,
    displayLabel: 'Suckle balls',
    sequence: [ballsStep],
    durationSeconds: 10,
    unlocks: [UnlockKey.suckleBalls],
  );
}

LevelMilestone _suckleHeadMilestone() {
  // Séquence neutre (head, pas balls) — doit toujours passer le filtre
  // anatomy, indépendamment de hasBalls.
  const headStep = SessionStep(
    time: 0,
    mode: SessionMode.suckle,
    to: Position.head,
    duration: 10,
  );
  return const LevelMilestone(
    id: 'intro_suckle_head',
    minLevel: 4,
    humilRequired: 0,
    displayLabel: 'Suckle head',
    sequence: [headStep],
    durationSeconds: 10,
    unlocks: [UnlockKey.suckleHead],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('HumiliationScale.requiredFor(suckle, …)', () {
    test('suckle head — base 5 + 0.3/s au-delà de la 1ʳᵉ seconde', () {
      // duration=1 → base seul.
      final base = HumiliationScale.requiredFor(
        mode: SessionMode.suckle,
        to: Position.head,
        duration: 1,
      );
      expect(base, closeTo(5.0, 1e-9));
      // duration=11 → base + 0.3 × 10 = 8.0
      final long = HumiliationScale.requiredFor(
        mode: SessionMode.suckle,
        to: Position.head,
        duration: 11,
      );
      expect(long, closeTo(8.0, 1e-9));
    });

    test('suckle balls — base 12 + 0.6/s (humil pure, plus exigeante)', () {
      final base = HumiliationScale.requiredFor(
        mode: SessionMode.suckle,
        to: Position.balls,
        duration: 1,
      );
      expect(base, closeTo(12.0, 1e-9));
      final long = HumiliationScale.requiredFor(
        mode: SessionMode.suckle,
        to: Position.balls,
        duration: 11,
      );
      expect(long, closeTo(18.0, 1e-9));
    });

    test(
        'suckle hors {head, balls} : requiredFor renvoie 0 (le filtre '
        "`_isUnlocked` du générateur empêche le step d'arriver ici, mais on "
        'reste safe par défaut)', () {
      for (final p in [
        Position.tip,
        Position.mid,
        Position.throat,
        Position.full,
      ]) {
        final r = HumiliationScale.requiredFor(
          mode: SessionMode.suckle,
          to: p,
          duration: 8,
        );
        expect(r, equals(0.0),
            reason: 'requiredFor doit retourner 0 pour suckle to=$p');
      }
    });
  });

  group('Générateur — filtre suckle positions valides', () {
    test(
        'aucun step suckle ne touche tip/mid/throat/full, quelles que '
        "soient l'humil et l'allocation", () {
      for (var seed = 0; seed < 20; seed++) {
        final gen = CareerSessionGenerator(seed: seed);
        final r = gen.generate(
          level: 18,
          bank: _bank(),
          unlockedKeys: UnlockKey.values.toSet(),
          humiliationCareer: 400.0,
          anatomy: const AnatomyProfile(hasBalls: true),
        );
        for (final s in r.session.steps) {
          if (s.mode != SessionMode.suckle) continue;
          final target = s.to ?? s.from;
          expect(target == Position.head || target == Position.balls, isTrue,
              reason: 'suckle to=$target hors {head, balls} (seed=$seed)');
        }
      }
    });

    test(
        'suckleHead acquise mais suckleBalls absent : aucun step suckle '
        'balls ne sort du générateur (filtre `_isUnlocked` + cascade humil)',
        () {
      for (var seed = 0; seed < 10; seed++) {
        final gen = CareerSessionGenerator(seed: seed);
        final r = gen.generate(
          level: 12,
          bank: _bank(),
          unlockedKeys: _allExcept(<UnlockKey>{UnlockKey.suckleBalls}),
          humiliationCareer: 400.0,
          anatomy: const AnatomyProfile(hasBalls: true),
        );
        for (final s in r.session.steps) {
          if (s.mode != SessionMode.suckle) continue;
          final touchesBalls =
              s.from == Position.balls || s.to == Position.balls;
          expect(touchesBalls, isFalse,
              reason:
                  'suckleBalls absent → aucun step suckle balls (seed=$seed)');
        }
      }
    });

    test(
        'anatomy.hasBalls=false : aucun step suckle balls même avec '
        'suckleBalls dans le set d\'unlocks (anatomy gate primaire)', () {
      final gen = CareerSessionGenerator(seed: 4242);
      final r = gen.generate(
        level: 18,
        bank: _bank(),
        unlockedKeys: UnlockKey.values.toSet(),
        humiliationCareer: 400.0,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      for (final s in r.session.steps) {
        if (s.mode != SessionMode.suckle) continue;
        final touchesBalls = s.from == Position.balls || s.to == Position.balls;
        expect(touchesBalls, isFalse,
            reason:
                'hasBalls=false → aucun step suckle balls ne doit être généré');
      }
    });
  });

  group('MilestoneService — gating anatomy + level pour suckle', () {
    test(
        'hasBalls=true + level 11 : intro_suckle_balls candidate (pool a '
        'la milestone)', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _suckleBallsMilestone(),
        _suckleHeadMilestone(),
      ]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 11,
        anatomy: const AnatomyProfile(hasBalls: true),
      );
      expect(pending.map((m) => m.id), contains('intro_suckle_balls'),
          reason: 'hasBalls=true → suckle balls reste dans le pool');
    });

    test(
        'hasBalls=false + level 11 : intro_suckle_balls exclu (séquence '
        'touche Position.balls), intro_suckle_head reste candidate', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _suckleBallsMilestone(),
        _suckleHeadMilestone(),
      ]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 11,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      final ids = pending.map((m) => m.id).toList();
      expect(ids, isNot(contains('intro_suckle_balls')),
          reason: 'hasBalls=false → suckle balls strictement filtré');
      expect(ids, contains('intro_suckle_head'),
          reason: 'suckle head n\'utilise pas Position.balls, doit passer');
    });

    test(
        'anatomy=null (mode hérité) : pas de filtre anatomy, la milestone '
        'balls reste candidate', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [_suckleBallsMilestone()]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 11,
        // anatomy: null implicite (mode hérité).
      );
      expect(pending.map((m) => m.id), contains('intro_suckle_balls'));
    });
  });
}
