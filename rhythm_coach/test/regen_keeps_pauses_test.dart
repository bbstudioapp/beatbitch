import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> t) =>
    t.map((s) => PhraseEntry(text: s)).toList();

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

Session _gen({
  int seed = 1,
  int durationSeconds = 900,
  PostureScript carry = PostureScript.none,
}) =>
    CareerSessionGenerator(seed: seed)
        .generate(
          level: 12,
          bank: _bank(),
          durationSeconds: durationSeconds,
          unlockedKeys: UnlockKey.values.toSet(),
          carry: carry,
        )
        .session;

Session _shell({
  List<ScriptedBreak> breaks = const [],
  List<PostureChange> changes = const [],
}) =>
    Session(
      id: 's',
      name: 'n',
      description: '',
      durationSeconds: 600,
      defaultMode: SessionMode.rhythm,
      steps: const [],
      breaks: breaks,
      postureChanges: changes,
    );

void main() {
  const carry = PostureScript(
    breaks: [
      ScriptedBreak(time: 240, durationSeconds: 90, newPose: Posture.kneeling),
    ],
    changes: [PostureChange(time: 520, pose: Posture.allFours)],
  );

  group('PostureScript', () {
    test('shifted décale tout et ne descend jamais sous 0', () {
      final s = carry.shifted(-300);
      expect(s.breaks.single.time, 0);
      expect(s.breaks.single.durationSeconds, 90);
      expect(s.breaks.single.newPose, Posture.kneeling);
      expect(s.changes.single.time, 220);
      expect(s.changes.single.pose, Posture.allFours);
    });

    test('pauseSeconds somme les durées', () {
      const two = PostureScript(breaks: [
        ScriptedBreak(time: 10, durationSeconds: 60),
        ScriptedBreak(time: 400, durationSeconds: 120),
      ]);
      expect(two.pauseSeconds, 180);
      expect(PostureScript.none.pauseSeconds, 0);
    });
  });

  group('generate(carry:) — la suite rejoue pauses et changements', () {
    for (var seed = 1; seed <= 10; seed++) {
      test('graine $seed : durée, pose et ordre conservés', () {
        final s = _gen(seed: seed, carry: carry);
        final base = _gen(seed: seed);

        final b = s.breaks.single;
        expect(b.durationSeconds, 90);
        expect(b.newPose, Posture.kneeling);
        expect(b.time, greaterThanOrEqualTo(240));

        final c = s.postureChanges.single;
        expect(c.pose, Posture.allFours);
        expect(c.time, greaterThanOrEqualTo(520));

        expect(
          s.steps.where((x) => x.time >= b.time && x.time < b.endTime),
          isEmpty,
          reason: 'trou d\'effort dans la pause',
        );
        expect(
          ((s.durationSeconds - 90) - base.durationSeconds).abs(),
          lessThanOrEqualTo(90),
          reason: 'effort = durée choisie',
        );
      });
    }

    test('sans report : aucune pause ni changement', () {
      final s = _gen();
      expect(s.breaks, isEmpty);
      expect(s.postureChanges, isEmpty);
    });

    test('une pause qui ne tient plus avant la fin est abandonnée', () {
      final s = _gen(
        durationSeconds: 300,
        carry: const PostureScript(breaks: [
          ScriptedBreak(time: 290, durationSeconds: 120),
        ]),
      );
      expect(s.breaks, isEmpty);
    });
  });

  group('builders de régénération — pauses de la suite décalées', () {
    final upcoming = _shell(
      breaks: const [ScriptedBreak(time: 100, durationSeconds: 80)],
      changes: const [PostureChange(time: 300, pose: Posture.sitting)],
    );
    final previous = _shell();

    test('Supplier / retry : décalées de début + beg', () {
      final s = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: const SessionStep(
            time: 0, text: 'beg', mode: SessionMode.beg, duration: 6),
        start: 50,
      );
      expect(s.breaks.single.time, 156);
      expect(s.breaks.single.durationSeconds, 80);
      expect(s.postureChanges.single.time, 356);
      expect(s.postureChanges.single.pose, Posture.sitting);
    });

    test('post-défi : décalées de la fin du souffle', () {
      final s = SessionController.buildPostChallengeRegenSession(
        previous: previous,
        upcoming: upcoming,
        breathEnd: 70,
      );
      expect(s.breaks.single.time, 170);
      expect(s.postureChanges.single.time, 370);
    });
  });
}
