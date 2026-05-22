import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/final_category.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

Session _baseSession({
  String id = 'src',
  int durationSeconds = 600,
  List<SessionStep> steps = const [],
  String? milestoneId,
  int? milestoneStartTime,
  int? milestoneDurationSeconds,
  String? secondMilestoneId,
  int? secondMilestoneStartTime,
  int? secondMilestoneDurationSeconds,
  String? finalMilestoneId,
  int? finalMilestoneStartTime,
  int? finalMilestoneDurationSeconds,
  int? finalStepTime,
  int? silentFinishStartTime,
  FinalCategory? finalCategory,
}) {
  return Session(
    id: id,
    name: 'n',
    description: 'd',
    durationSeconds: durationSeconds,
    defaultMode: SessionMode.rhythm,
    steps: steps,
    milestoneId: milestoneId,
    milestoneStartTime: milestoneStartTime,
    milestoneDurationSeconds: milestoneDurationSeconds,
    secondMilestoneId: secondMilestoneId,
    secondMilestoneStartTime: secondMilestoneStartTime,
    secondMilestoneDurationSeconds: secondMilestoneDurationSeconds,
    finalMilestoneId: finalMilestoneId,
    finalMilestoneStartTime: finalMilestoneStartTime,
    finalMilestoneDurationSeconds: finalMilestoneDurationSeconds,
    finalStepTime: finalStepTime,
    silentFinishStartTime: silentFinishStartTime,
    finalCategory: finalCategory,
  );
}

SessionStep _beg({int duration = 12}) => SessionStep(
      time: 0,
      text: 'supplie',
      mode: SessionMode.beg,
      from: Position.full,
      duration: duration,
    );

void main() {
  group('SessionController.buildUpgradedSession — propagation milestones', () {
    test(
        'milestone body PASSÉE de l\'ancienne session est conservée '
        '(acquittable à _finish)', () {
      final previous = _baseSession(
        milestoneId: 'intro_hold_mid',
        milestoneStartTime: 60,
        milestoneDurationSeconds: 90, // fenêtre [60, 150]
      );
      final upcoming = _baseSession(id: 'gen', durationSeconds: 300);

      // Supplier à t=400 → fenêtre [60,150] entièrement passée
      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(),
        start: 400,
      );

      expect(out.milestoneId, 'intro_hold_mid');
      expect(out.milestoneStartTime, 60);
      expect(out.milestoneDurationSeconds, 90);
    });

    test(
        'milestone body NON jouée (fenêtre coupée par Supplier) est ABANDONNÉE '
        '— sinon _finish acquitterait une milestone non jouée (bug stefsub)',
        () {
      final previous = _baseSession(
        milestoneId: 'intro_hold_mid',
        milestoneStartTime: 480, // 8 min, dans le futur
        milestoneDurationSeconds: 60,
      );
      final upcoming = _baseSession(id: 'gen', durationSeconds: 300);

      // Supplier cliqué à t=10s → milestone pas encore jouée
      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(),
        start: 10,
      );

      expect(out.milestoneId, isNull);
      expect(out.milestoneStartTime, isNull);
      expect(out.milestoneDurationSeconds, isNull);
    });

    test('fenêtre se terminant pile à l\'instant Supplier est conservée', () {
      final previous = _baseSession(
        milestoneId: 'intro_hold_mid',
        milestoneStartTime: 100,
        milestoneDurationSeconds: 50, // se termine à t=150
      );
      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: _baseSession(id: 'gen'),
        insistentBeg: _beg(),
        start: 150, // pile à la fin
      );
      expect(out.milestoneId, 'intro_hold_mid');
    });

    test(
        'milestone body de upcoming (cas retry milestone) est décalée '
        'par start+begDuration', () {
      final upcoming = _baseSession(
        id: 'retry',
        milestoneId: 'intro_hold_mid',
        milestoneStartTime: 30,
        milestoneDurationSeconds: 90,
      );
      final previous = _baseSession();

      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(duration: 6), // offset = 200 + 6 = 206
        start: 200,
      );

      expect(out.milestoneId, 'intro_hold_mid');
      expect(out.milestoneStartTime, 30 + 206);
      expect(out.milestoneDurationSeconds, 90);
    });

    test(
        'finalMilestoneId vient de upcoming, décalé (Supplier remplace le final)',
        () {
      final previous = _baseSession(
        finalMilestoneId: 'old_final', // ne doit PAS apparaître
        finalMilestoneStartTime: 540,
        finalMilestoneDurationSeconds: 30,
      );
      final upcoming = _baseSession(
        id: 'gen',
        durationSeconds: 300,
        finalMilestoneId: 'new_final',
        finalMilestoneStartTime: 270,
        finalMilestoneDurationSeconds: 30,
      );

      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(duration: 12),
        start: 100, // offset = 112
      );

      expect(out.finalMilestoneId, 'new_final');
      expect(out.finalMilestoneStartTime, 270 + 112);
      expect(out.finalMilestoneDurationSeconds, 30);
    });

    test(
        '2 body milestones passées de l\'ancienne + 1 nouvelle → '
        'on garde les 2 premières chronologiquement (3 ne tient pas en 2 slots)',
        () {
      final previous = _baseSession(
        milestoneId: 'old_a',
        milestoneStartTime: 30,
        milestoneDurationSeconds: 60, // ends 90
        secondMilestoneId: 'old_b',
        secondMilestoneStartTime: 120,
        secondMilestoneDurationSeconds: 60, // ends 180
      );
      final upcoming = _baseSession(
        id: 'gen',
        milestoneId: 'new_c',
        milestoneStartTime: 50,
        milestoneDurationSeconds: 60,
      );

      // Supplier à t=400 → les 2 olds sont passées
      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(duration: 12),
        start: 400,
      );

      // Tri chrono : old_a (30) < old_b (120) < new_c (50+412=462)
      expect(out.milestoneId, 'old_a');
      expect(out.secondMilestoneId, 'old_b');
      // new_c est jetée faute de slot — le scénario reste rare
    });

    test('1 ancienne passée + 1 nouvelle → mid1=ancienne, mid2=nouvelle', () {
      final previous = _baseSession(
        milestoneId: 'old_a',
        milestoneStartTime: 30,
        milestoneDurationSeconds: 60,
      );
      final upcoming = _baseSession(
        id: 'gen',
        milestoneId: 'new_b',
        milestoneStartTime: 50,
        milestoneDurationSeconds: 60,
      );

      final out = SessionController.buildUpgradedSession(
        previous: previous,
        upcoming: upcoming,
        insistentBeg: _beg(duration: 6),
        start: 200, // offset = 206
      );

      expect(out.milestoneId, 'old_a');
      expect(out.milestoneStartTime, 30);
      expect(out.secondMilestoneId, 'new_b');
      expect(out.secondMilestoneStartTime, 50 + 206);
    });

    test(
        'beg insistant en tête, steps de upcoming décalés, durée totale '
        'correcte', () {
      final upcoming = _baseSession(
        id: 'gen',
        durationSeconds: 300,
        steps: [
          const SessionStep(
              time: 0, text: 'a', mode: SessionMode.rhythm, bpm: 80),
          const SessionStep(
              time: 100, text: 'b', mode: SessionMode.lick, bpm: 60),
        ],
      );

      final out = SessionController.buildUpgradedSession(
        previous: _baseSession(),
        upcoming: upcoming,
        insistentBeg: _beg(duration: 10),
        start: 50,
      );

      expect(out.steps.length, 3); // beg + 2 steps
      expect(out.steps[0].time, 50);
      expect(out.steps[0].text, 'supplie');
      expect(out.steps[1].time, 0 + 60); // offset = 50+10
      expect(out.steps[2].time, 100 + 60);
      expect(out.durationSeconds, 60 + 300);
    });

    test(
        'champs additionnels du SessionStep (bpmEnd, chainAction, swallowMode, '
        'background) sont propagés', () {
      final upcoming = _baseSession(
        id: 'gen',
        steps: [
          const SessionStep(
            time: 0,
            text: 'rampé',
            mode: SessionMode.rhythm,
            bpm: 80,
            bpmEnd: 130,
            background: 'porngif-xxx',
          ),
        ],
      );

      final out = SessionController.buildUpgradedSession(
        previous: _baseSession(),
        upcoming: upcoming,
        insistentBeg: _beg(),
        start: 0,
      );

      expect(out.steps[1].bpmEnd, 130);
      expect(out.steps[1].background, 'porngif-xxx');
    });

    test(
        'finalStepTime, silentFinishStartTime, finalCategory propagés et décalés',
        () {
      final upcoming = _baseSession(
        id: 'gen',
        durationSeconds: 300,
        finalStepTime: 270,
        silentFinishStartTime: 250,
        finalCategory: FinalCategory.hard,
      );

      final out = SessionController.buildUpgradedSession(
        previous: _baseSession(),
        upcoming: upcoming,
        insistentBeg: _beg(duration: 12),
        start: 100,
      );

      expect(out.finalStepTime, 270 + 112);
      expect(out.silentFinishStartTime, 250 + 112);
      expect(out.finalCategory, FinalCategory.hard);
    });

    test('noStats préservé depuis previous', () {
      final previous = _baseSession();
      // noStats n'est pas exposé par _baseSession, on le pose direct
      final previousNoStats = Session(
        id: previous.id,
        name: previous.name,
        description: previous.description,
        durationSeconds: previous.durationSeconds,
        defaultMode: previous.defaultMode,
        steps: previous.steps,
        noStats: true,
      );
      final out = SessionController.buildUpgradedSession(
        previous: previousNoStats,
        upcoming: _baseSession(id: 'gen'),
        insistentBeg: _beg(),
        start: 0,
      );
      expect(out.noStats, isTrue);
    });

    test('id suffixé `:upgraded`', () {
      final out = SessionController.buildUpgradedSession(
        previous: _baseSession(id: 'session_lvl5'),
        upcoming: _baseSession(id: 'gen'),
        insistentBeg: _beg(),
        start: 0,
      );
      expect(out.id, 'session_lvl5:upgraded');
    });
  });
}
