import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/music/beat_clock.dart';
import 'package:beat_bitch/music/mic_tempo_source.dart';

const _sr = 44100;

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

void _feedInChunks(MicTempoSource src, List<double> sig, {int chunk = 2048}) {
  for (var i = 0; i < sig.length; i += chunk) {
    src.feedPcm(sig.sublist(i, (i + chunk).clamp(0, sig.length)));
  }
}

void main() {
  group('MicTempoSource.feedPcm', () {
    test('intro → verrouille le tempo et émet des battements', () async {
      final src = MicTempoSource();
      final ticks = <BeatTick>[];
      src.ticks.listen(ticks.add);

      expect(src.isCalibrating, isTrue);
      _feedInChunks(src, _clickTrack(bpm: 120, durationMs: 6000));
      await pumpEventQueue();

      expect(src.isCalibrating, isFalse, reason: 'aurait dû verrouiller');
      expect(src.isRunning, isTrue);
      expect(src.bpm, closeTo(120, 2.0));
      expect(ticks, isNotEmpty);
      // Les battements émis sont monotones et bien formés.
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i].beatIndex, greaterThan(ticks[i - 1].beatIndex));
      }
      src.dispose();
    });

    test('silence : reste en calibration, aucun battement', () async {
      final src = MicTempoSource();
      final ticks = <BeatTick>[];
      src.ticks.listen(ticks.add);

      _feedInChunks(src, List<double>.filled(_sr * 4, 0));
      await pumpEventQueue();

      expect(src.isCalibrating, isTrue);
      expect(ticks, isEmpty);
      src.dispose();
    });

    test('gate : ignore les onsets pendant la fenêtre', () {
      final src = MicTempoSource();
      // Gate tout de suite une grande fenêtre, puis pousse un burst : l'onset
      // tombant dans la fenêtre ne doit pas alimenter le tracker (reste calé).
      src.gate(100000);
      _feedInChunks(src, _clickTrack(bpm: 120, durationMs: 6000));
      expect(src.isCalibrating, isTrue, reason: 'onsets gatés → pas de verrou');
      src.dispose();
    });

    test('suit un changement de tempo (re-cale)', () async {
      final src = MicTempoSource();
      src.ticks.listen((_) {});
      _feedInChunks(src, _clickTrack(bpm: 100, durationMs: 6000));
      await pumpEventQueue();
      expect(src.bpm, closeTo(100, 2.0));

      _feedInChunks(src, _clickTrack(bpm: 140, durationMs: 8000));
      await pumpEventQueue();
      expect(src.bpm, closeTo(140, 2.0));
      src.dispose();
    });
  });
}
