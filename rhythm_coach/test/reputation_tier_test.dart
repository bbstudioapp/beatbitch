import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/services/reputation_service.dart';
import 'package:beat_bitch/services/stats_service.dart';

void main() {
  group('ReputationTier.tierFor — Phase 19.11', () {
    test('score 0 → bonneEleve (palier de démarrage)', () {
      expect(ReputationTier.tierFor(0), ReputationTier.bonneEleve);
    });

    test('score à la borne basse de chaque palier déclenche le palier', () {
      expect(ReputationTier.tierFor(150), ReputationTier.petiteSuceuse);
      expect(ReputationTier.tierFor(400), ReputationTier.suceuseConfirmee);
      expect(ReputationTier.tierFor(900), ReputationTier.puteReconnue);
      expect(ReputationTier.tierFor(1800), ReputationTier.puteConsacree);
      expect(ReputationTier.tierFor(3500), ReputationTier.reineDesSuceuses);
      expect(ReputationTier.tierFor(6000), ReputationTier.reineDesPutes);
    });

    test('score juste sous le seuil reste au palier précédent', () {
      expect(ReputationTier.tierFor(149), ReputationTier.bonneEleve);
      expect(ReputationTier.tierFor(399), ReputationTier.petiteSuceuse);
      expect(ReputationTier.tierFor(899), ReputationTier.suceuseConfirmee);
      expect(ReputationTier.tierFor(1799), ReputationTier.puteReconnue);
      expect(ReputationTier.tierFor(3499), ReputationTier.puteConsacree);
      expect(ReputationTier.tierFor(5999), ReputationTier.reineDesSuceuses);
    });

    test('score très élevé → reineDesPutes (palier terminal)', () {
      expect(ReputationTier.tierFor(50000), ReputationTier.reineDesPutes);
    });

    test('monotonie : score ↗ ⇒ tier ≥', () {
      ReputationTier? previous;
      for (var s = 0; s <= 10000; s += 100) {
        final t = ReputationTier.tierFor(s);
        if (previous != null) {
          expect(t.index, greaterThanOrEqualTo(previous.index),
              reason: 'régression de palier détectée à score=$s');
        }
        previous = t;
      }
    });

    test('snapshot expose le tier (intégration)', () {
      const snap = ReputationSnapshot(
        score: 1000,
        maxLevel: 5,
        stats: StatsSnapshot(
          totalSeconds: 7200,
          throatfucks: 0,
          biffles: 0,
          holdThroatSeconds: 0,
          holdFullSeconds: 0,
          sessionsCompleted: 20,
          sessionsNoFailStreak: 5,
          modesUsedMask: 0,
          maxHoldFullAtomic: 0,
          dailyStreak: 0,
          encoresAsked: 0,
          quickiesCompleted: 0,
          humiliationLevel: 0.0,
          obedienceLevel: 0.0,
        ),
        respecCount: 0,
        tier: ReputationTier.puteReconnue,
      );
      expect(snap.tier, ReputationTier.puteReconnue);
    });
  });
}
