import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bpm = 600.0; // T = 100ms, rond — évite tout artefact d'arrondi.
  const halfCycleMs = 100;
  const fullCycleMs = 200;

  List<int> intervalsFor({
    required BeatAnchor anchor,
    required int ratio,
    required int count,
  }) {
    final engine = BeepEngine();
    final events = engine.simulateBeatsForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      bpm: bpm,
      anchor: anchor,
      ratio: ratio,
      count: count,
    );
    return [for (final e in events) e.nextInterval.inMilliseconds];
  }

  test('ratio=1 : suite d\'intervalles constante, identique à aujourd\'hui',
      () {
    final intervals = intervalsFor(anchor: BeatAnchor.none, ratio: 1, count: 5);
    expect(intervals, List.filled(5, halfCycleMs));
  });

  test('ratio=3 ancre from : alternance 1,5T / 0,5T', () {
    final intervals = intervalsFor(anchor: BeatAnchor.from, ratio: 3, count: 4);
    // Premier bip émis = `to` (alternateToggle démarre à true) → l'intervalle
    // qui suit est celui après `to` (court), puis après `from` (long).
    expect(intervals, [50, 150, 50, 150]);
  });

  test('ratio=3 ancre to : alternance 0,5T / 1,5T', () {
    final intervals = intervalsFor(anchor: BeatAnchor.to, ratio: 3, count: 4);
    expect(intervals, [150, 50, 150, 50]);
  });

  test('la somme sur un cycle vaut 2T, régulier et ancré', () {
    for (final config in [
      (anchor: BeatAnchor.none, ratio: 1),
      (anchor: BeatAnchor.from, ratio: 3),
      (anchor: BeatAnchor.to, ratio: 3),
    ]) {
      final intervals =
          intervalsFor(anchor: config.anchor, ratio: config.ratio, count: 6);
      for (var i = 0; i + 1 < intervals.length; i += 2) {
        expect(
          intervals[i] + intervals[i + 1],
          fullCycleMs,
          reason: 'anchor=${config.anchor} ratio=${config.ratio} i=$i',
        );
      }
    }
  });
}
