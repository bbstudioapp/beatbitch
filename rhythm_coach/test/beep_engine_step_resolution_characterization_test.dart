import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fige la résolution mode/from/to/bpm de `BeepEngine.applyStep` telle
/// qu'elle est aujourd'hui, avant toute extraction : c'est la référence que
/// le son ne doit pas cesser de respecter.
///
/// `applyStep` n'attend rien une fois le moteur initialisé — la résolution
/// est posée avant le `Future.delayed` du gap de transition, donc lisible
/// juste après l'appel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<BeepEngine> engine() async {
    final beep = BeepEngine();
    await beep.init();
    addTearDown(beep.dispose);
    return beep;
  }

  void apply(
    BeepEngine beep,
    SessionStep step, {
    SessionMode sessionMode = SessionMode.rhythm,
  }) {
    beep.applyStep(step, sessionMode).ignore();
  }

  group('BeepEngine.applyStep — résolution du mode', () {
    test('le mode du step gagne sur le mode de séance', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(time: 0, mode: SessionMode.hold, to: Position.mid),
        sessionMode: SessionMode.rhythm,
      );
      expect(beep.currentMode, SessionMode.hold);
    });

    test('sans mode explicite, le mode de séance s\'applique', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(time: 0, from: Position.head, to: Position.throat),
        sessionMode: SessionMode.lick,
      );
      expect(beep.currentMode, SessionMode.lick);
    });

    test('un step text-only ne touche à rien', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          bpm: 90,
          from: Position.head,
          to: Position.throat,
        ),
      );
      apply(beep, const SessionStep(time: 10, text: 'juste une phrase'));

      expect(beep.currentMode, SessionMode.rhythm);
      expect(beep.currentFrom, Position.head);
      expect(beep.currentTo, Position.throat);
      expect(beep.currentBpm, 90);
    });
  });

  group('BeepEngine.applyStep — résolution from/to', () {
    test('rhythm : from vient de step.from, to de step.to', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
        ),
      );
      expect(beep.currentFrom, Position.head);
      expect(beep.currentTo, Position.throat);
    });

    test('rhythm sans from : la position courante est conservée', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.mid,
          to: Position.full,
        ),
      );
      apply(
        beep,
        const SessionStep(
            time: 10, mode: SessionMode.rhythm, to: Position.balls),
      );
      expect(beep.currentFrom, Position.mid);
      expect(beep.currentTo, Position.balls);
    });

    test('to n\'est jamais hérité : un step sans to remet to à null', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
        ),
      );
      apply(
        beep,
        const SessionStep(
            time: 10, mode: SessionMode.rhythm, from: Position.mid),
      );
      expect(beep.currentTo, isNull);
      expect(beep.currentFrom, Position.mid);
    });

    for (final mode in const [
      SessionMode.hold,
      SessionMode.beg,
      SessionMode.suckle,
    ]) {
      test('${mode.name} : from vient de step.to, step.from est ignoré',
          () async {
        final beep = await engine();
        apply(
          beep,
          SessionStep(
            time: 0,
            mode: mode,
            from: Position.tip,
            to: Position.full,
          ),
        );
        expect(beep.currentFrom, Position.full);
        expect(beep.currentTo, Position.full);
      });

      test('${mode.name} sans to : from garde la position courante', () async {
        final beep = await engine();
        apply(
          beep,
          const SessionStep(
            time: 0,
            mode: SessionMode.rhythm,
            from: Position.mid,
            to: Position.full,
          ),
        );
        apply(beep, SessionStep(time: 10, mode: mode, from: Position.tip));
        expect(beep.currentFrom, Position.mid);
        expect(beep.currentTo, isNull);
      });
    }

    for (final mode in const [
      SessionMode.hand,
      SessionMode.biffle,
      SessionMode.breath,
      SessionMode.freestyle,
    ]) {
      test('${mode.name} : from vient de step.from, comme rhythm', () async {
        final beep = await engine();
        apply(
          beep,
          SessionStep(
            time: 0,
            mode: mode,
            from: Position.head,
            to: Position.throat,
          ),
        );
        expect(beep.currentFrom, Position.head);
        expect(beep.currentTo, Position.throat);
      });
    }
  });

  group('BeepEngine.applyStep — résolution du BPM', () {
    test('sans bpm, le bpm courant est conservé', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 110),
      );
      apply(
        beep,
        const SessionStep(time: 10, mode: SessionMode.rhythm, to: Position.mid),
      );
      expect(beep.currentBpm, 110);
    });

    test('un bpm au-dessus de kMaxBpm est ramené au plafond', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 600),
      );
      expect(beep.currentBpm, BeepEngine.kMaxBpm);
    });

    test('un bpm sous kMinBpm est remonté au plancher', () async {
      final beep = await engine();
      apply(beep, const SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 5));
      expect(beep.currentBpm, BeepEngine.kMinBpm);
    });
  });

  group('BeepEngine.applyStep — from == to', () {
    test('lick head/head : from remonte à tip, seule position plus aiguë',
        () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.lick,
          from: Position.head,
          to: Position.head,
        ),
      );
      expect(beep.currentFrom, Position.tip);
      expect(beep.currentTo, Position.head);
    });

    test('rhythm throat/throat : from remonte au-dessus de throat', () async {
      for (var i = 0; i < 20; i++) {
        final beep = await engine();
        apply(
          beep,
          const SessionStep(
            time: 0,
            mode: SessionMode.rhythm,
            from: Position.throat,
            to: Position.throat,
          ),
        );
        expect(beep.currentTo, Position.throat);
        expect(
          beep.currentFrom.index,
          lessThan(Position.throat.index),
          reason: 'tirage $i',
        );
      }
    });

    test('rhythm tip/tip : rien au-dessus de tip, le plateau reste', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.tip,
          to: Position.tip,
        ),
      );
      expect(beep.currentFrom, Position.tip);
      expect(beep.currentTo, Position.tip);
    });

    test('l\'égalité peut venir d\'un from hérité, pas seulement écrit',
        () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.rhythm,
          from: Position.mid,
          to: Position.full,
        ),
      );
      apply(
        beep,
        const SessionStep(time: 10, mode: SessionMode.rhythm, to: Position.mid),
      );
      expect(beep.currentFrom.index, lessThan(Position.mid.index));
      expect(beep.currentTo, Position.mid);
    });

    test('hand full/full : le relèvement ne concerne pas ce mode', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.hand,
          from: Position.full,
          to: Position.full,
        ),
      );
      expect(beep.currentFrom, Position.full);
      expect(beep.currentTo, Position.full);
    });

    test('hold full/full : le relèvement ne concerne pas ce mode', () async {
      final beep = await engine();
      apply(
        beep,
        const SessionStep(
          time: 0,
          mode: SessionMode.hold,
          from: Position.full,
          to: Position.full,
        ),
      );
      expect(beep.currentFrom, Position.full);
      expect(beep.currentTo, Position.full);
    });
  });
}
