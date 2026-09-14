import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/music/tempo_tracker.dart';

/// Génère des onsets réguliers (BPM/phase donnés) avec un jitter optionnel.
List<int> _clicks({
  required double bpm,
  required int phaseMs,
  required int count,
  int jitterMs = 0,
  Random? rng,
}) {
  final t = 60000.0 / bpm;
  return [
    for (var i = 0; i < count; i++)
      (phaseMs + i * t).round() +
          (jitterMs == 0 ? 0 : (rng!.nextInt(2 * jitterMs + 1) - jitterMs)),
  ];
}

void main() {
  group('TempoTracker', () {
    test('train propre 120 BPM → bpm ~120, phase ~100, confiance haute', () {
      final tr = TempoTracker();
      for (final o in _clicks(bpm: 120, phaseMs: 100, count: 16)) {
        tr.addOnset(o);
      }
      final e = tr.estimate()!;
      expect(e.bpm, closeTo(120, 1.0));
      expect(e.confidence, greaterThan(0.95));
      // phase modulo la période (500 ms)
      expect(e.anchorMs % 500, closeTo(100, 8));
    });

    test('train propre 90 BPM détecté', () {
      final tr = TempoTracker();
      for (final o in _clicks(bpm: 90, phaseMs: 0, count: 16)) {
        tr.addOnset(o);
      }
      expect(tr.estimate()!.bpm, closeTo(90, 1.0));
    });

    test('robuste à un jitter modéré (±15 ms)', () {
      final tr = TempoTracker();
      final rng = Random(7);
      for (final o in _clicks(
          bpm: 128, phaseMs: 50, count: 24, jitterMs: 15, rng: rng)) {
        tr.addOnset(o);
      }
      final e = tr.estimate()!;
      expect(e.bpm, closeTo(128, 2.0));
      expect(e.confidence, greaterThan(0.7));
    });

    test('pas assez d’onsets → null', () {
      final tr = TempoTracker(minOnsets: 6);
      tr.addOnset(0);
      tr.addOnset(500);
      expect(tr.estimate(), isNull);
    });

    test('onsets aléatoires → confiance basse', () {
      final tr = TempoTracker();
      final rng = Random(3);
      var t = 0;
      for (var i = 0; i < 30; i++) {
        t += 80 + rng.nextInt(400); // intervalles très irréguliers
        tr.addOnset(t);
      }
      final e = tr.estimate();
      // Une estimation existe mais ne doit pas atteindre la confiance d'un
      // train propre.
      expect(e!.confidence, lessThan(0.85));
    });

    test('fenêtre glissante : oublie les vieux onsets', () {
      final tr = TempoTracker(); // fenêtre par défaut (6 s)
      // Vieux onsets à 100 BPM, puis récents à 140 BPM bien après (> fenêtre).
      for (final o in _clicks(bpm: 100, phaseMs: 0, count: 8)) {
        tr.addOnset(o);
      }
      for (final o in _clicks(bpm: 140, phaseMs: 20000, count: 16)) {
        tr.addOnset(o);
      }
      expect(tr.estimate()!.bpm, closeTo(140, 2.0));
    });
  });
}
