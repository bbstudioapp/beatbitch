import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/models/session_step.dart' show Position;
import 'package:beat_bitch/music/beat_clock.dart';
import 'package:beat_bitch/music/beat_grid.dart';
import 'package:beat_bitch/music/music_pattern_generator.dart';
import 'package:beat_bitch/music/music_session_engine.dart';
import 'package:beat_bitch/music/slot_action.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

CapabilityProfile _profile(Map<CapabilityAxis, double> comforts) =>
    CapabilityProfile({
      for (final e in comforts.entries)
        e.key: CapabilityAxisState(best: e.value, comfort: e.value),
    });

final _fullCaps = _profile({
  CapabilityAxis.rhythmDepthMax: Position.full.index.toDouble(),
  CapabilityAxis.rhythmBpmCeilShallow: 200,
  CapabilityAxis.rhythmBpmCeilThroat: 200,
  CapabilityAxis.rhythmBpmCeilFull: 200,
  CapabilityAxis.holdThroatStreak: 30,
  CapabilityAxis.holdFullStreak: 30,
});

MusicSessionEngine _engine(CapabilityProfile p, int seed) => MusicSessionEngine(
      generator: MusicPatternGenerator(profile: p, rng: Random(seed)),
    );

class _FakeClock implements BeatClock {
  final StreamController<BeatTick> _c = StreamController<BeatTick>.broadcast();
  @override
  Stream<BeatTick> get ticks => _c.stream;
  void emit(BeatTick t) => _c.add(t);
  @override
  double? get bpm => null;
  @override
  bool get isRunning => true;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void dispose() => _c.close();
}

void main() {
  group('MusicSessionEngine.onBeat', () {
    test('1× : une action par battement, profondeurs dans les bornes', () {
      final eng = _engine(_fullCaps, 1);
      const grid = BeatGrid(bpm: 120, anchorMs: 0);
      var emitted = 0;
      for (var i = 0; i < 16; i++) {
        final a = eng.onBeat(grid.tickFor(i));
        if (a == null) continue;
        emitted++;
        expect(a.depth.index, lessThanOrEqualTo(Position.full.index));
        if (a.kind == SlotActionKind.release) {
          expect(a.depth, Position.head); // ancre PR1
        } else {
          expect(a.depth.index, greaterThan(Position.head.index));
        }
      }
      expect(emitted, 16); // 1 slot = 1 battement
    });

    test('½× : un slot tous les 2 battements quand la soupape ralentit', () {
      // depthMax throat + plafond throat 90 : à 150 BPM, throat passe en ½×.
      final p = _profile({
        CapabilityAxis.rhythmDepthMax: Position.throat.index.toDouble(),
        CapabilityAxis.rhythmBpmCeilShallow: 200,
        CapabilityAxis.rhythmBpmCeilThroat: 90,
      });
      final eng = _engine(p, 2);
      const grid = BeatGrid(bpm: 150, anchorMs: 0);
      // Phrase 4 (beats 64..79) → profondeur visée throat → bpm 75 → 2 b/slot.
      var emitted = 0;
      for (var i = 64; i < 80; i++) {
        if (eng.onBeat(grid.tickFor(i)) != null) emitted++;
      }
      expect(emitted, 8); // 64,66,68,70,72,74,76,78
      expect(eng.currentPattern!.bpm, 75);
    });

    test('hold porte la dernière frappe, release porte l’ancre', () {
      final eng = _engine(_fullCaps, 5);
      const grid = BeatGrid(bpm: 120, anchorMs: 0);
      Position? lastStrike;
      for (var i = 0; i < 64; i++) {
        final a = eng.onBeat(grid.tickFor(i));
        if (a == null) continue;
        switch (a.kind) {
          case SlotActionKind.strike:
            lastStrike = a.depth;
            expect(a.depth.index, greaterThan(Position.head.index));
          case SlotActionKind.hold:
            expect(a.depth, lastStrike); // tient la frappe précédente
          case SlotActionKind.release:
            expect(a.depth, Position.head);
        }
      }
    });

    test('régénère seulement en fin de boucle (jamais au milieu d\'un pattern)',
        () {
      final eng = MusicSessionEngine(
        generator: MusicPatternGenerator(profile: _fullCaps, rng: Random(9)),
        repeatLoops: 2,
      );
      const grid = BeatGrid(bpm: 120, anchorMs: 0);
      var prev = (eng..onBeat(grid.tickFor(0))).currentPattern;
      var changes = 0;
      for (var i = 1; i < 300; i++) {
        eng.onBeat(grid.tickFor(i));
        if (!identical(eng.currentPattern, prev)) {
          // Tout changement de figure tombe en début de pattern (curseur 0).
          expect(eng.cursor, 0,
              reason: 'figure changée au milieu (slot ${eng.cursor})');
          prev = eng.currentPattern;
          changes++;
        }
      }
      expect(changes, greaterThan(0)); // ça régénère bien au fil du temps
    });

    test('robustesse : aucune action hors bornes sur un long run', () {
      final eng = _engine(_fullCaps, 13);
      const grid = BeatGrid(bpm: 100, anchorMs: 0);
      for (var i = 0; i < 256; i++) {
        final a = eng.onBeat(grid.tickFor(i));
        if (a == null) continue;
        expect(a.depth.index,
            inInclusiveRange(Position.head.index, Position.full.index));
      }
    });
  });

  group('MusicSessionEngine.peek', () {
    test('prédit ce que onBeat émettra (en milieu de phrase, 1×)', () {
      final eng = _engine(_fullCaps, 17);
      const grid = BeatGrid(bpm: 120, anchorMs: 0);
      for (var i = 0; i < 8; i++) {
        eng.onBeat(grid.tickFor(i)); // milieu de phrase (16 beats)
      }
      final pk = eng.peek(3);
      expect(pk.length, 3);
      for (var k = 0; k < 3; k++) {
        final a = eng.onBeat(grid.tickFor(8 + k))!;
        expect(pk[k].kind, a.kind, reason: 'kind divergent au slot $k');
        expect(pk[k].depth, a.depth, reason: 'depth divergent au slot $k');
      }
    });

    test('peek sans figure encore générée renvoie vide', () {
      final eng = _engine(_fullCaps, 1);
      expect(eng.peek(4), isEmpty);
    });
  });

  group('MusicSessionEngine.attach', () {
    test('pousse les actions du flux d’horloge dans actions', () async {
      final eng = _engine(_fullCaps, 21);
      final clock = _FakeClock();
      final got = <SlotAction>[];
      eng.actions.listen(got.add);
      eng.attach(clock);

      const grid = BeatGrid(bpm: 120, anchorMs: 0);
      for (var i = 0; i < 8; i++) {
        clock.emit(grid.tickFor(i));
      }
      await pumpEventQueue();

      expect(got.length, 8); // 1× → 8 battements, 8 actions
      eng.dispose();
      clock.dispose();
    });
  });
}
