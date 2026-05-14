import 'package:beat_bitch/services/obedience_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ObedienceEngine.onFail(milestoneOpportunityMissed:)` : même doctrine
/// que HumiliationEngine — ×2 cumulable avec le ×2 de dernière minute.
void main() {
  ObedienceEngine fresh(double seed) => ObedienceEngine()..seed(seed);

  test('onFail() standard → -2 obed', () {
    final e = fresh(100);
    e.onFail();
    expect(e.score, closeTo(98.0, 1e-9));
  });

  test('onFail(milestoneOpportunityMissed: true) → -4 obed', () {
    final e = fresh(100);
    e.onFail(milestoneOpportunityMissed: true);
    expect(e.score, closeTo(96.0, 1e-9));
  });

  test('cumul dernière minute + opportunité ratée → -8 obed (×4)', () {
    final e = fresh(100);
    e.onFail(multiplier: 2.0, milestoneOpportunityMissed: true);
    expect(e.score, closeTo(92.0, 1e-9));
  });

  test('plancher 0 : un gros malus ne descend pas sous 0', () {
    final e = fresh(3);
    e.onFail(multiplier: 2.0, milestoneOpportunityMissed: true);
    expect(e.score, 0.0);
  });
}
