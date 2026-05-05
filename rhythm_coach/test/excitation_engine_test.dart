import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm_coach/models/session.dart';
import 'package:rhythm_coach/models/session_step.dart';
import 'package:rhythm_coach/services/excitation_engine.dart';

void main() {
  group('ExcitationEngine — décroissance naturelle', () {
    test('V=40 perd ≈ 2/s après 1 tick', () {
      final e = ExcitationEngine()..seed(40);
      e.setCurrentMode(mode: SessionMode.freestyle, from: null, to: null);
      e.onTickSecond();
      // 40²/800 = 2.0
      expect(e.value, closeTo(38.0, 0.01));
    });

    test('V=10 perd peu (~0.125/s)', () {
      final e = ExcitationEngine()..seed(10);
      e.setCurrentMode(mode: SessionMode.freestyle, from: null, to: null);
      e.onTickSecond();
      expect(e.value, closeTo(9.875, 0.01));
    });

    test('V=90 perd beaucoup (~10/s)', () {
      final e = ExcitationEngine()..seed(90);
      e.setCurrentMode(mode: SessionMode.freestyle, from: null, to: null);
      e.onTickSecond();
      expect(e.value, closeTo(79.875, 0.05));
    });
  });

  group('ExcitationEngine — spike full atténué', () {
    test('coup full à V=10 ≈ +25', () {
      final e = ExcitationEngine()..seed(10);
      final before = e.value;
      e.onBeat(mode: SessionMode.rhythm, to: Position.full, from: Position.full);
      // base 25, cap 78, atténuation = 1-(10/78)² ≈ 0.984
      expect(e.value - before, closeTo(24.6, 0.5));
    });

    test('coup full à V=70 → spike modeste (cap=78)', () {
      final e = ExcitationEngine()..seed(70);
      final before = e.value;
      e.onBeat(mode: SessionMode.rhythm, to: Position.full, from: Position.full);
      // 25 × (1 - (70/78)²) ≈ 4.86
      expect(e.value - before, closeTo(4.9, 0.5));
    });

    test('coup full à V=78 → quasi nul (au plafond)', () {
      final e = ExcitationEngine()..seed(78);
      final before = e.value;
      e.onBeat(mode: SessionMode.rhythm, to: Position.full, from: Position.full);
      expect(e.value - before, closeTo(0.0, 0.1));
    });

    test('amplitude head→full augmente le V_plafond (+15)', () {
      final e = ExcitationEngine()..seed(78);
      final before = e.value;
      e.onBeat(mode: SessionMode.rhythm, to: Position.full, from: Position.head);
      // cap = 78 + 5×3 = 93. 25 × (1-(78/93)²) = 25 × 0.297 ≈ 7.4
      expect(e.value - before, greaterThan(5.0));
    });
  });

  group('ExcitationEngine — résistance', () {
    test('R=1 divise les apports par 2', () {
      final e = ExcitationEngine()..setResistance(1.0);
      final before = e.value;
      e.onBeat(mode: SessionMode.rhythm, to: Position.full, from: Position.full);
      // base 25 × atténuation 1.0 (V=0) × 1/(1+1) = 12.5
      expect(e.value - before, closeTo(12.5, 0.5));
    });
  });

  group('ExcitationEngine — fail', () {
    test('reset 30%', () {
      final e = ExcitationEngine()..seed(80);
      e.onFail();
      expect(e.value, closeTo(56.0, 0.01));
    });
  });

  group('ExcitationEngine — plateau lick', () {
    test('lick head → plateau 30, dampen au-dessus', () {
      final e = ExcitationEngine()..seed(60);
      e.setCurrentMode(mode: SessionMode.lick, from: Position.tip, to: Position.head);
      final before = e.value;
      e.onTickSecond();
      // Décroissance naturelle V²/800 = 4.5 freinée × 0.5 → -2.25
      expect(before - e.value, closeTo(2.25, 0.1));
    });

    test('lick tip → plateau 50, monte légèrement en-dessous', () {
      final e = ExcitationEngine()..seed(20);
      // Plusieurs coups doivent pousser doucement vers le plateau
      for (var i = 0; i < 10; i++) {
        e.onBeat(mode: SessionMode.lick, to: Position.head, from: Position.tip);
      }
      // 10 coups × 0.5 = +5 → 25
      expect(e.value, closeTo(25.0, 0.5));
    });
  });

  group('ExcitationEngine — hold spike + maintien', () {
    test('hold full à V=20 spike +25 (atténué) puis maintien freine descente', () {
      final e = ExcitationEngine()..seed(20);
      e.setCurrentMode(mode: SessionMode.hold, from: Position.full, to: null);
      // Le spike s'applique au setCurrentMode (hold). Donc immédiatement une
      // remontée est attendue.
      final afterSpike = e.value;
      expect(afterSpike, greaterThan(20));
      // Tick → décroissance freinée + maintien +0.67
      e.onTickSecond();
      // Acceptable que ça monte légèrement ou descende doucement.
      expect((afterSpike - e.value).abs(), lessThan(2.0));
    });

    test('hold ne réapplique pas le spike au tick suivant', () {
      final e = ExcitationEngine()..seed(20);
      e.setCurrentMode(mode: SessionMode.hold, from: Position.full, to: null);
      final v1 = e.value;
      // Re-call setCurrentMode avec même config : pas de re-spike
      e.setCurrentMode(mode: SessionMode.hold, from: Position.full, to: null);
      expect(e.value, equals(v1));
    });
  });
}
