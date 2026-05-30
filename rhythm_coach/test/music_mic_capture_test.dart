import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/music/mic_capture.dart';

void main() {
  group('MicCapture.decodePcm16', () {
    test('décode du PCM16 little-endian en −1..1', () {
      // 0 → 0.0 ; 32767 → ~+1 ; -32768 → -1.0
      final bytes = Uint8List.fromList([
        0x00, 0x00, // 0
        0xFF, 0x7F, // 32767
        0x00, 0x80, // -32768
      ]);
      final s = MicCapture.decodePcm16(bytes);
      expect(s.length, 3);
      expect(s[0], 0.0);
      expect(s[1], closeTo(1.0, 0.001));
      expect(s[2], -1.0);
    });

    test('octet impair en trop ignoré (tronque au sample complet)', () {
      final bytes = Uint8List.fromList([0x10, 0x20, 0x05]);
      expect(MicCapture.decodePcm16(bytes).length, 1);
    });
  });
}
