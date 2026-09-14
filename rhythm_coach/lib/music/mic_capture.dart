import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Couche de capture micro (la **seule** qui dépend du natif `record`).
/// Diffuse des samples PCM mono `−1..1` vers un callback ; le reste de la
/// chaîne (`OnsetDetector` → `TempoTracker` → `MicTempoSource`) est pur.
///
/// Hors ligne : capture locale du micro, aucun réseau. `echoCancel` +
/// `noiseSuppress` demandent à l'OS d'atténuer nos propres bips dans l'entrée.
class MicCapture {
  final int sampleRate;
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  MicCapture({this.sampleRate = 44100});

  Future<bool> hasPermission() => _rec.hasPermission();

  /// Démarre la capture et appelle [onPcm] à chaque bloc (samples mono −1..1).
  /// Retourne `false` si la permission micro est refusée.
  Future<bool> start(void Function(List<double> samples) onPcm) async {
    if (!await _rec.hasPermission()) return false;
    final stream = await _rec.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _sub = stream.listen((bytes) => onPcm(decodePcm16(bytes)));
    return true;
  }

  /// Décode du PCM 16 bits little-endian en samples `double` (−1..1). Pur.
  static List<double> decodePcm16(Uint8List bytes) {
    final n = bytes.length ~/ 2;
    final out = List<double>.filled(n, 0);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    if (await _rec.isRecording()) await _rec.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _rec.dispose();
  }
}
