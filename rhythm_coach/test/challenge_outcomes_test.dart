import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:beat_bitch/services/obedience_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HumiliationEngine challenge outcomes', () {
    test('netSuccess : +2 sur careerScore', () {
      final e = HumiliationEngine();
      e.seed(career: 10);
      e.onChallengeNetSuccess();
      expect(e.careerScore, 12.0);
      expect(e.sessionScore, 0.0);
    });

    test('extension : +1 sur careerScore par extension acquise', () {
      final e = HumiliationEngine();
      e.seed(career: 10);
      e.onChallengeNetSuccess();
      e.onChallengeExtension();
      e.onChallengeExtension();
      expect(e.careerScore, 14.0); // 10 + 2 (net) + 1 + 1 (ext).
    });
  });

  group('ObedienceEngine challenge outcomes', () {
    test('netSuccess : +2', () {
      final e = ObedienceEngine();
      e.seed(50);
      e.onChallengeNetSuccess();
      expect(e.score, 52.0);
    });

    test('extension : +1 par extension', () {
      final e = ObedienceEngine();
      e.seed(50);
      e.onChallengeNetSuccess();
      e.onChallengeExtension();
      e.onChallengeExtension();
      expect(e.score, 54.0); // 50 + 2 + 1 + 1.
    });

    test('skip : -3 (plancher 0)', () {
      final e = ObedienceEngine();
      e.seed(10);
      e.onChallengeSkip();
      expect(e.score, 7.0);
    });

    test('skip avec score initial 1 : planché à 0, pas en négatif', () {
      final e = ObedienceEngine();
      e.seed(1);
      e.onChallengeSkip();
      expect(e.score, 0.0);
    });
  });
}
