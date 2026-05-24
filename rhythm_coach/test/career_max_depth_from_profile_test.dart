import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/services/career_level_gates.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

CapabilityProfile _profileWithDepth(double comfort) {
  return CapabilityProfile({
    CapabilityAxis.rhythmDepthMax: CapabilityAxisState(
      best: comfort,
      comfort: comfort,
    ),
  });
}

void main() {
  group('CareerLevelGates.maxDepthIndexForProfile — Phase 19.7', () {
    test('profil null → full ouvert (rétrocompat Custom/debug)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(null),
        Position.full.index,
      );
    });

    test('profil vide → full ouvert (joueuse neuve, axe sans donnée)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(const CapabilityProfile({})),
        Position.full.index,
      );
    });

    test('comfort 0.5 → arrondi à tip mais plancher mid (idx 2)', () {
      // 0.5 arrondit à 0 = tip, mais le plancher pédagogique est mid
      // (les basics couvrent déjà la profondeur mid).
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(0.5)),
        Position.mid.index,
      );
    });

    test('comfort 1.4 → head arrondi, mais plancher mid (idx 2)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(1.4)),
        Position.mid.index,
      );
    });

    test('comfort 2.5 → throat (idx 3, round half-away-from-zero)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(2.5)),
        Position.throat.index,
      );
    });

    test('comfort 3 → throat (idx 3)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(3.0)),
        Position.throat.index,
      );
    });

    test('comfort 4 → full (idx 4)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(4.0)),
        Position.full.index,
      );
    });

    test('comfort 5 (> full) → clampé à full (jamais balls)', () {
      expect(
        CareerLevelGates.maxDepthIndexForProfile(_profileWithDepth(5.0)),
        Position.full.index,
      );
    });
  });
}
