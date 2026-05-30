import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Posture', () {
    test('free n\'a pas de unlockKey, les autres oui', () {
      expect(Posture.free.unlockKey, isNull);
      for (final p in Posture.values.where((p) => p != Posture.free)) {
        expect(p.unlockKey, isNotNull, reason: '$p doit avoir une unlockKey');
      }
    });

    test('unlockKeys uniques entre postures', () {
      final keys =
          Posture.values.map((p) => p.unlockKey).whereType<String>().toList();
      expect(keys.toSet().length, keys.length);
    });

    test('serialized round-trip via fromString', () {
      for (final p in Posture.values) {
        expect(Posture.fromString(p.serialized), p);
      }
    });

    test('fromString tolère null, casse et alias', () {
      expect(Posture.fromString(null), Posture.free);
      expect(Posture.fromString('inconnu'), Posture.free);
      expect(Posture.fromString('KNEELING'), Posture.kneeling);
      expect(Posture.fromString('allfours'), Posture.allFours);
      expect(Posture.fromString('all_fours'), Posture.allFours);
      expect(Posture.fromString('onback'), Posture.onBack);
      expect(Posture.fromString('on_back'), Posture.onBack);
    });

    test('serialized des postures composées est snake_case', () {
      expect(Posture.allFours.serialized, 'all_fours');
      expect(Posture.onBack.serialized, 'on_back');
      expect(Posture.kneeling.serialized, 'kneeling');
    });
  });

  group('ScriptedBreak', () {
    test('endTime = time + durationSeconds', () {
      const b = ScriptedBreak(time: 600, durationSeconds: 90);
      expect(b.endTime, 690);
    });

    test('défauts : pas de newPose, orders vide', () {
      const b = ScriptedBreak(time: 0, durationSeconds: 60);
      expect(b.newPose, isNull);
      expect(b.orders, isEmpty);
    });
  });

  group('Session — champs posture', () {
    Session make({Posture? pose, List<ScriptedBreak>? breaks}) => Session(
          id: 's',
          name: 'n',
          description: '',
          durationSeconds: 60,
          defaultMode: SessionMode.rhythm,
          steps: const [SessionStep(time: 0, from: Position.tip, bpm: 80)],
          initialPose: pose ?? Posture.free,
          breaks: breaks ?? const [],
        );

    test('défauts : free + pas de breaks', () {
      final s = make();
      expect(s.initialPose, Posture.free);
      expect(s.breaks, isEmpty);
    });

    test('porte la posture initiale et les breaks fournis', () {
      final s = make(
        pose: Posture.kneeling,
        breaks: const [
          ScriptedBreak(
              time: 300, durationSeconds: 90, newPose: Posture.allFours),
        ],
      );
      expect(s.initialPose, Posture.kneeling);
      expect(s.breaks, hasLength(1));
      expect(s.breaks.first.newPose, Posture.allFours);
    });

    test('breaks/posture sont transients : absents de toJson', () {
      final s = make(
        pose: Posture.kneeling,
        breaks: const [ScriptedBreak(time: 300, durationSeconds: 90)],
      );
      final json = s.toJson();
      expect(json.containsKey('breaks'), isFalse);
      expect(json.containsKey('initial_pose'), isFalse);
    });
  });
}
