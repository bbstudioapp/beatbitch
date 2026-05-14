import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// `HumiliationEngine.onFail(milestoneOpportunityMissed:)` : double le
/// malus session quand une milestone candidate au level courant a été
/// ratée. Cumulable avec le ×2 de dernière minute (×4 au pire).
void main() {
  HumiliationEngine fresh(double seed) {
    final e = HumiliationEngine()..seed(career: 0, session: seed);
    return e;
  }

  test('onFail() standard → -5 humil session', () {
    final e = fresh(40);
    e.onFail();
    expect(e.sessionScore, closeTo(35.0, 1e-9));
  });

  test('onFail(milestoneOpportunityMissed: true) → -10 humil session', () {
    final e = fresh(40);
    e.onFail(milestoneOpportunityMissed: true);
    expect(e.sessionScore, closeTo(30.0, 1e-9));
  });

  test('cumul dernière minute + opportunité ratée → -20 humil session (×4)',
      () {
    final e = fresh(40);
    e.onFail(multiplier: 2.0, milestoneOpportunityMissed: true);
    expect(e.sessionScore, closeTo(20.0, 1e-9));
  });

  test('plancher 0 : un gros malus ne descend pas sous 0', () {
    final e = fresh(3);
    e.onFail(multiplier: 2.0, milestoneOpportunityMissed: true);
    expect(e.sessionScore, 0.0);
  });
}
