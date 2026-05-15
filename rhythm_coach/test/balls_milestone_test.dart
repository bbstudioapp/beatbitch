import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/career/services/milestone_service.dart';
import 'package:beat_bitch/models/anatomy_profile.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Tous les unlocks sauf ceux passés en `except`. Pratique pour tester
/// le gating d'une compétence donnée sans casser les fondations (lick_full,
/// holds, etc.).
Set<UnlockKey> _allExcept(Set<UnlockKey> except) =>
    UnlockKey.values.where((k) => !except.contains(k)).toSet();

LevelMilestone _ballsMilestone({String id = 'intro_balls_lick'}) {
  // Séquence avec un step lick balls — le filtre anatomy de
  // `MilestoneService.allPendingFor` scanne `sequence.from/to` et exclut
  // toute milestone qui touche Position.balls quand hasBalls=false.
  const ballsStep = SessionStep(
    time: 0,
    mode: SessionMode.lick,
    from: Position.throat,
    to: Position.balls,
    bpm: 55,
    duration: 14,
  );
  return LevelMilestone(
    id: id,
    minLevel: 9,
    humilRequired: 5,
    displayLabel: 'Balls',
    sequence: const [ballsStep],
    durationSeconds: 14,
    unlocks: const [UnlockKey.lickBalls],
  );
}

LevelMilestone _neutralMilestone(
    {String id = 'rhythm_basic', int minLevel = 9}) {
  // Step neutre, sans Position.balls — doit passer le filtre anatomy
  // dans tous les cas.
  const neutralStep = SessionStep(
    time: 0,
    mode: SessionMode.rhythm,
    from: Position.head,
    to: Position.mid,
    bpm: 90,
    duration: 12,
  );
  return LevelMilestone(
    id: id,
    minLevel: minLevel,
    humilRequired: 5,
    displayLabel: id,
    sequence: const [neutralStep],
    durationSeconds: 12,
    unlocks: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('MilestoneService — filtre anatomy balls', () {
    test(
        "hasBalls=true : intro_balls_lick est candidate au level 9 "
        '(rien ne la filtre)', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _ballsMilestone(),
        _neutralMilestone(),
      ]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 9,
        anatomy: const AnatomyProfile(hasBalls: true),
      );
      expect(pending.map((m) => m.id), contains('intro_balls_lick'),
          reason: 'hasBalls=true → la milestone balls reste dans le pool');
    });

    test(
        "hasBalls=false : intro_balls_lick est exclue, le pool reste non vide "
        'grâce à un candidat non-balls au même level', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [
        _ballsMilestone(),
        _neutralMilestone(),
      ]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 9,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      final ids = pending.map((m) => m.id).toList();
      expect(ids, isNot(contains('intro_balls_lick')),
          reason:
              'hasBalls=false → milestone qui touche Position.balls exclue');
      expect(ids, contains('rhythm_basic'),
          reason: 'La candidate non-balls doit rester pour ne pas bloquer la '
              'progression de la joueuse sans la zone');
    });

    test(
        'anatomy=null (mode hérité tests / debug) : pas de filtre, la '
        'milestone balls reste candidate', () {
      final svc = MilestoneService();
      svc.seedForTest(catalog: [_ballsMilestone()]);
      final pending = svc.allPendingFor(
        humiliationScore: 100,
        obedience: 0,
        playerLevel: 9,
        // anatomy: null implicite (mode hérité).
      );
      expect(pending.map((m) => m.id), contains('intro_balls_lick'));
    });
  });

  group('Générateur — gating step balls par unlocks', () {
    test(
        "lickBalls absent : aucun step `lick to/from balls` n'apparaît "
        'même avec humil élevée et anatomy=hasBalls', () {
      final gen = CareerSessionGenerator(seed: 9876);
      final result = gen.generate(
        level: 12,
        bank: _bank(),
        unlockedKeys: _allExcept(<UnlockKey>{
          UnlockKey.lickBalls,
          UnlockKey.holdBalls,
          UnlockKey.begBalls,
        }),
        humiliationCareer: 400.0,
        maxDepthIndexOverride: Position.balls.index,
        anatomy: const AnatomyProfile(hasBalls: true),
      );
      for (final s in result.session.steps) {
        if (s.mode != SessionMode.lick) continue;
        final touchesBalls = s.from == Position.balls || s.to == Position.balls;
        expect(touchesBalls, isFalse,
            reason:
                "lickBalls hors du set d'unlocks → aucun step lick balls ne "
                'doit être généré (cascade humil + filtre _isUnlocked).');
      }
    });
  });

  group('_pickFinal — lick full→balls candidat', () {
    test(
        "level≥10 + humil suffisante + lickBalls acquise + anatomy.hasBalls : "
        "`lick full→balls` est le step final (palette bornée à `mid` pour "
        "que hold throat/full soient hors palette — sinon ils dominent en "
        "req)", () {
      final gen = CareerSessionGenerator(seed: 13579);
      // maxDepthIndexOverride=mid → hold throat/full sortent de la palette
      // de `_pickFinal` (`if (maxDepth >= Position.throat.index)`). Reste :
      // hold tip(5), lick tip→head(8), hold mid(10), biffle(13), hold
      // head(14), lick full→balls(17). Le plus humiliant valide = lick
      // full→balls.
      final result = gen.generate(
        level: 10,
        bank: _bank(),
        unlockedKeys: UnlockKey.values.toSet(),
        humiliationCareer: 30.0,
        maxDepthIndexOverride: Position.mid.index,
        anatomy: const AnatomyProfile(hasBalls: true),
      );
      final lickBallsSteps = result.session.steps.where((s) =>
          s.mode == SessionMode.lick &&
          s.from == Position.full &&
          s.to == Position.balls);
      expect(lickBallsSteps, isNotEmpty,
          reason: 'lick full→balls doit pouvoir être pioché par _pickFinal '
              'quand humil cap≥17, lickBalls acquise, anatomy.hasBalls=true, '
              'palette restreinte sous throat');
    });

    test(
        'même contexte mais anatomy.hasBalls=false : aucun step balls dans la '
        'session — la palette finale retombe sur les holds <throat', () {
      final gen = CareerSessionGenerator(seed: 24680);
      final result = gen.generate(
        level: 10,
        bank: _bank(),
        unlockedKeys: UnlockKey.values.toSet(),
        humiliationCareer: 30.0,
        maxDepthIndexOverride: Position.mid.index,
        anatomy: const AnatomyProfile(hasBalls: false),
      );
      final touchesBalls = result.session.steps.any(
        (s) => s.from == Position.balls || s.to == Position.balls,
      );
      expect(touchesBalls, isFalse,
          reason: 'hasBalls=false → balls strictement banni de la session');
    });
  });
}
