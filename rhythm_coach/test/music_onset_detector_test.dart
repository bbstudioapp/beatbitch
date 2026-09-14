import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/music/onset_detector.dart';

const _sr = 44100;

/// Construit un signal PCM : un burst (amplitude 0.6, `burstSamples`) à chaque
/// battement, silence entre. `bpm` battements/min, `durationMs` total.
List<double> _clickTrack({
  required double bpm,
  required int durationMs,
  int burstSamples = 1500,
}) {
  final n = (_sr * durationMs / 1000).round();
  final sig = List<double>.filled(n, 0);
  final periodSamples = (60.0 / bpm * _sr).round();
  for (var start = 0; start < n; start += periodSamples) {
    for (var i = 0; i < burstSamples && start + i < n; i++) {
      sig[start + i] = 0.6;
    }
  }
  return sig;
}

void main() {
  group('OnsetDetector', () {
    test('click-track 120 BPM → un onset par battement, bien placé', () {
      final det = OnsetDetector();
      final onsets = det.process(_clickTrack(bpm: 120, durationMs: 4000));
      // 4 s à 120 BPM = 8 battements (à ±1 selon les bords).
      expect(onsets.length, inInclusiveRange(7, 9));
      // Chaque onset proche d'un multiple de 500 ms (résolution ~ 1 trame).
      for (final o in onsets) {
        final nearest = (o / 500).round() * 500;
        expect((o - nearest).abs(), lessThan(35),
            reason: 'onset $o loin du battement $nearest');
      }
    });

    test('silence → aucun onset', () {
      final det = OnsetDetector();
      final onsets = det.process(List<double>.filled(_sr * 2, 0));
      expect(onsets, isEmpty);
    });

    test('streaming par petits blocs = même résultat qu’en un coup', () {
      final sig = _clickTrack(bpm: 100, durationMs: 3000);

      final whole = OnsetDetector().process(sig);

      final det = OnsetDetector();
      final streamed = <int>[];
      const block = 777; // taille non alignée sur la trame
      for (var i = 0; i < sig.length; i += block) {
        streamed.addAll(
          det.process(sig.sublist(i, (i + block).clamp(0, sig.length))),
        );
      }
      expect(streamed, whole);
    });

    test('alimente le tempo : intervalles ~ réguliers à 140 BPM', () {
      final det = OnsetDetector();
      final onsets = det.process(_clickTrack(bpm: 140, durationMs: 4000));
      expect(onsets.length, greaterThanOrEqualTo(8));
      const period = 60000 / 140; // ~428 ms
      for (var i = 1; i < onsets.length; i++) {
        expect((onsets[i] - onsets[i - 1] - period).abs(), lessThan(35));
      }
    });
  });
}
