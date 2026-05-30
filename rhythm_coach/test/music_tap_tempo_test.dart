import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/music/beat_grid.dart';
import 'package:beat_bitch/music/tap_tempo.dart';

void main() {
  group('TapTempoEstimator', () {
    test('4 taps à 600 ms → ~100 BPM, ancre = 1er tap', () {
      final e = TapTempoEstimator();
      for (final t in [1000, 1600, 2200, 2800]) {
        e.tap(t);
      }
      expect(e.tapCount, 4);
      expect(e.isStable, isTrue);
      expect(e.bpm, closeTo(100, 0.001));
      expect(e.anchorMs, 1000);
    });

    test('médiane robuste à un intervalle aberrant', () {
      final e = TapTempoEstimator();
      // intervalles : 600, 600, 1500 (un raté), 600 → médiane 600 → 100 BPM
      for (final t in [0, 600, 1200, 2700, 3300]) {
        e.tap(t);
      }
      expect(e.bpm, closeTo(100, 0.001));
    });

    test('un long silence réinitialise la série', () {
      final e = TapTempoEstimator(resetGapMs: 2000);
      e.tap(0);
      e.tap(600);
      e.tap(1200); // 100 BPM établi
      e.tap(10000); // gap > 2000 → reset, ce tap devient le 1er
      expect(e.tapCount, 1);
      expect(e.hasTempo, isFalse);
      expect(e.anchorMs, 10000);
    });

    test('BPM clampé dans [minBpm, maxBpm]', () {
      final e = TapTempoEstimator(minBpm: 40, maxBpm: 240);
      e.tap(0);
      e.tap(100); // 600 BPM théorique → clampé 240
      expect(e.bpm, 240);
      // resetGapMs élevé pour ne pas réinitialiser sur l'intervalle long.
      final slow =
          TapTempoEstimator(minBpm: 40, maxBpm: 240, resetGapMs: 100000);
      slow.tap(0);
      slow.tap(5000); // 12 BPM théorique → clampé 40
      expect(slow.bpm, 40);
    });
  });

  group('BeatGrid', () {
    const grid = BeatGrid(bpm: 120, anchorMs: 1000); // 500 ms/beat, 4/4, 4 bars
    test('beatIndexAt', () {
      expect(grid.beatIndexAt(1000), 0);
      expect(grid.beatIndexAt(1499), 0);
      expect(grid.beatIndexAt(1500), 1);
      expect(grid.beatIndexAt(3000), 4); // 4 beats plus tard
      expect(grid.beatIndexAt(500), lessThan(0)); // avant l'ancre
    });

    test('drapeaux mesure / phrase', () {
      expect(grid.tickFor(0).isBarStart, isTrue);
      expect(grid.tickFor(0).isPhraseStart, isTrue);
      expect(grid.tickFor(1).isBarStart, isFalse);
      expect(grid.tickFor(4).isBarStart, isTrue); // mesure 1
      expect(grid.tickFor(4).isPhraseStart, isFalse);
      expect(grid.tickFor(16).isPhraseStart, isTrue); // 4 mesures = 1 phrase
      expect(grid.tickFor(16).phraseIndex, 1);
      expect(grid.tickFor(6).beatInBar, 2);
      expect(grid.tickFor(6).barIndex, 1);
    });
  });

  group('BeatScheduler', () {
    test('émet chaque battement une seule fois, dans l’ordre', () {
      final sched = BeatScheduler(const BeatGrid(bpm: 120, anchorMs: 0));
      // 500 ms/beat
      expect(sched.poll(0).map((t) => t.beatIndex), [0]);
      expect(sched.poll(400), isEmpty); // toujours sur le beat 0
      expect(sched.poll(500).map((t) => t.beatIndex), [1]);
      expect(sched.poll(510), isEmpty);
      expect(sched.poll(1000).map((t) => t.beatIndex), [2]);
    });

    test('rattrape plusieurs battements si le poll est en retard', () {
      final sched = BeatScheduler(const BeatGrid(bpm: 120, anchorMs: 0));
      final ticks = sched.poll(1600); // beats 0,1,2,3 (0,500,1000,1500)
      expect(ticks.map((t) => t.beatIndex), [0, 1, 2, 3]);
    });

    test('retune ne rejoue pas les battements passés', () {
      final sched = BeatScheduler(const BeatGrid(bpm: 120, anchorMs: 0));
      sched.poll(1000); // jusqu'au beat 2
      sched.retune(const BeatGrid(bpm: 120, anchorMs: 0), 1000);
      expect(sched.poll(1000), isEmpty);
      expect(sched.poll(1500).map((t) => t.beatIndex), [3]);
    });
  });

  group('TapTempoSource (intégration légère)', () {
    test('tap établit un tempo ; start/stop sans crash', () {
      var t = 0;
      final src = TapTempoSource(nowMs: () => t);
      expect(src.bpm, isNull);
      expect(src.isRunning, isFalse);
      src.tap(); // t=0
      t = 600;
      src.tap();
      t = 1200;
      src.tap(); // 100 BPM
      expect(src.tapCount, 3);
      expect(src.bpm, closeTo(100, 0.001));
      src.start();
      expect(src.isRunning, isTrue);
      src.stop();
      expect(src.isRunning, isFalse);
      src.dispose();
    });
  });
}
