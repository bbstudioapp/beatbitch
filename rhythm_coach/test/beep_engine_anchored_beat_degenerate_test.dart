import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// L'ancrage ne doit jamais déformer le tempo moyen : la somme de deux
/// battements consécutifs vaut `2T`. Deux entrées le cassaient — un step sans
/// amplitude (`to` absent ou égal à `from`), où l'alternance n'existe pas et
/// où *tous* les intervalles devenaient longs ; et un `ratio` ≤ 1, qui
/// produisait un intervalle nul, négatif ou NaN.
void main() {
  const bpm = 60.0; // T = 1000 ms
  const regularMs = 1000;

  List<int> intervals({
    required BeatAnchor anchor,
    required int ratio,
    Position from = Position.head,
    Position? to = Position.mid,
    SessionMode mode = SessionMode.rhythm,
    int count = 6,
  }) =>
      [
        for (final e in BeepEngine().simulateBeatsForTest(
          mode: mode,
          from: from,
          to: to,
          bpm: bpm,
          anchor: anchor,
          ratio: ratio,
          count: count,
        ))
          e.nextInterval.inMilliseconds
      ];

  test('sans amplitude, l\'ancrage retombe sur l\'intervalle régulier', () {
    for (final anchor in [BeatAnchor.from, BeatAnchor.to]) {
      expect(intervals(anchor: anchor, ratio: 3, to: null),
          List.filled(6, regularMs),
          reason: 'to absent, ancre $anchor');
      expect(
          intervals(
              anchor: anchor, ratio: 3, from: Position.mid, to: Position.mid),
          List.filled(6, regularMs),
          reason: 'to == from, ancre $anchor');
      expect(
          intervals(anchor: anchor, ratio: 3, to: null, mode: SessionMode.hand),
          List.filled(6, regularMs),
          reason: 'hand sans amplitude, ancre $anchor');
    }
  });

  test('un ratio hors domaine retombe sur l\'intervalle régulier', () {
    for (final ratio in [1, 0, -1, -3]) {
      expect(intervals(anchor: BeatAnchor.from, ratio: ratio),
          List.filled(6, regularMs),
          reason: 'ratio $ratio');
    }
  });
}
