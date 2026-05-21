import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/models/session_step.dart';

void main() {
  group('CareerLevelGates — Phase 19.2 (no-op)', () {
    group('isLowLevelIntro', () {
      test('level 1-2 hors quickie/intense → true', () {
        expect(
          CareerLevelGates.isLowLevelIntro(
              level: 1, quickie: false, intense: false),
          isTrue,
        );
        expect(
          CareerLevelGates.isLowLevelIntro(
              level: 2, quickie: false, intense: false),
          isTrue,
        );
      });
      test('level 3+ → false', () {
        expect(
          CareerLevelGates.isLowLevelIntro(
              level: 3, quickie: false, intense: false),
          isFalse,
        );
      });
      test('quickie ou intense désactivent même en level 1', () {
        expect(
          CareerLevelGates.isLowLevelIntro(
              level: 1, quickie: true, intense: false),
          isFalse,
        );
        expect(
          CareerLevelGates.isLowLevelIntro(
              level: 1, quickie: false, intense: true),
          isFalse,
        );
      });
    });

    test('isMiniWaveEligible : seuil à level 5', () {
      expect(CareerLevelGates.isMiniWaveEligible(4), isFalse);
      expect(CareerLevelGates.isMiniWaveEligible(5), isTrue);
      expect(CareerLevelGates.isMiniWaveEligible(20), isTrue);
    });

    test('canColorFinalBySpec : seuil à level 7', () {
      expect(CareerLevelGates.canColorFinalBySpec(6), isFalse);
      expect(CareerLevelGates.canColorFinalBySpec(7), isTrue);
    });

    test('usesShortHandFinalBaseline : level < 4', () {
      expect(CareerLevelGates.usesShortHandFinalBaseline(3), isTrue);
      expect(CareerLevelGates.usesShortHandFinalBaseline(4), isFalse);
    });

    group('burstHandPreference', () {
      test('humil bas + level bas → 0.70', () {
        expect(
          CareerLevelGates.burstHandPreference(level: 1, humiliationCareer: 0),
          0.70,
        );
        expect(
          CareerLevelGates.burstHandPreference(
              level: 3, humiliationCareer: 4.9),
          0.70,
        );
      });
      test('humil >= 5 ou level > 3 → 0.25', () {
        expect(
          CareerLevelGates.burstHandPreference(level: 1, humiliationCareer: 5),
          0.25,
        );
        expect(
          CareerLevelGates.burstHandPreference(level: 4, humiliationCareer: 0),
          0.25,
        );
      });
    });

    group('finishBpmBoostBpm', () {
      test('level 1, no encore → 0', () {
        expect(
          CareerLevelGates.finishBpmBoostBpm(level: 1, encoreChainIndex: 0),
          0,
        );
      });
      test('level 10, no encore → (10-1)*4 = 36', () {
        expect(
          CareerLevelGates.finishBpmBoostBpm(level: 10, encoreChainIndex: 0),
          36,
        );
      });
      test('level 5, encore 2 → (5-1)*4 + 2*8 = 32', () {
        expect(
          CareerLevelGates.finishBpmBoostBpm(level: 5, encoreChainIndex: 2),
          32,
        );
      });
      test('cap à 70', () {
        expect(
          CareerLevelGates.finishBpmBoostBpm(level: 30, encoreChainIndex: 5),
          70,
        );
      });
      test('encoreChainIndex négatif clampé à 0', () {
        expect(
          CareerLevelGates.finishBpmBoostBpm(level: 1, encoreChainIndex: -3),
          0,
        );
      });
    });

    test('defaultMaxDepthIndex : full', () {
      expect(CareerLevelGates.defaultMaxDepthIndex(), Position.full.index);
    });
  });
}
