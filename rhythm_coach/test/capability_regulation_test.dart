import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

/// Tests de la **boucle d'autorégulation** (Phase 3) : `CapabilityRegulator`
/// (fonction pure) + l'orchestration `CapabilityService.commit` (round-trip
/// `shared_preferences` + attribution du tap-out).

CapabilityAxisState _st({
  double? best,
  double? comfort,
  double sr = CapabilityService.defaultSuccessRate,
  int seen = -1,
}) =>
    CapabilityAxisState(
        best: best, comfort: comfort, successRate: sr, lastSeenSession: seen);

CapabilityAxisState _reg(
  CapabilityAxis axis,
  CapabilityAxisState prev, {
  double? reached,
  double? sessionCeiling,
  bool hardNegative = false,
  required int sessionIndex,
}) =>
    CapabilityRegulator.regulate(
      axis: axis,
      prev: prev,
      reached: reached,
      sessionCeiling: sessionCeiling,
      hardNegative: hardNegative,
      sessionIndex: sessionIndex,
    );

void main() {
  group('CapabilityRegulator.regulate', () {
    test('1ʳᵉ donnée → comfort seedé à best', () {
      final next = _reg(CapabilityAxis.gorgeApneeStreak, _st(),
          reached: 18, sessionIndex: 1);
      expect(next.best, 18.0);
      expect(next.comfort, 18.0);
      expect(next.lastSeenSession, 1);
    });

    test(
        'réussite au-dessus de comfort → ratchet ↑, gain modulé par successRate',
        () {
      final hi = _reg(CapabilityAxis.holdFullStreak,
          _st(best: 30, comfort: 30, sr: 0.9, seen: 4),
          reached: 33, sessionIndex: 5);
      final lo = _reg(CapabilityAxis.holdFullStreak,
          _st(best: 30, comfort: 30, sr: 0.1, seen: 4),
          reached: 33, sessionIndex: 5);
      expect(hi.comfort, greaterThan(30.0));
      expect(lo.comfort, greaterThan(30.0));
      // confiance haute → gain plus gros que confiance basse.
      expect(lo.comfort! - 30.0, lessThan(hi.comfort! - 30.0));
      // ancré : jamais plus que `reached × headroom`.
      expect(
          hi.comfort,
          lessThanOrEqualTo(
              33.0 * CapabilityRegulator.kRatchetAnchorHeadroom + 1e-9));
      // best suit le record propre, successRate dérive vers 1.
      expect(hi.best, 33.0);
      expect(lo.best, 33.0);
      expect(hi.successRate, greaterThan(0.9 - 1e-9));
      expect(lo.successRate, greaterThan(0.1));
    });

    test(
        'ratchet ↑ : l\'ancrage sur `reached` borne le gain si elle a à peine '
        'dépassé', () {
      // reached à peine au-dessus du comfort → l\'ancrage (reached × 1.05)
      // borne le ratchet, même avec une confiance maxi.
      final next = _reg(CapabilityAxis.gorgeApneeStreak,
          _st(best: 20, comfort: 20, sr: 1.0, seen: 4),
          reached: 21, sessionIndex: 5);
      expect(next.comfort,
          closeTo(21.0 * CapabilityRegulator.kRatchetAnchorHeadroom, 1e-9));
      expect(next.comfort,
          lessThan(20.0 * (1.0 + CapabilityRegulator.kRatchetUpGainMax)));
      expect(next.comfort, greaterThan(20.0));
    });

    test(
        'record propre sans dépassement → rien ne bouge (axe clampé au comfort)',
        () {
      final next = _reg(CapabilityAxis.holdFullStreak,
          _st(best: 30, comfort: 30, sr: 0.5, seen: 4),
          reached: 30, sessionIndex: 5);
      expect(next.comfort, 30.0);
      expect(next.successRate, 0.5);
      expect(next.lastSeenSession, 5);
    });

    test('signal négatif imputé → ratchet ↓ ×0.85, best inchangé', () {
      final next = _reg(CapabilityAxis.gorgeApneeStreak,
          _st(best: 40, comfort: 24, sr: 0.7, seen: 4),
          sessionCeiling: 22, hardNegative: true, sessionIndex: 5);
      expect(next.comfort,
          closeTo(22.0 * CapabilityRegulator.kRatchetDownFactor, 1e-9));
      expect(next.best, 40.0); // l\'exploit ne baisse jamais
      expect(next.successRate, lessThan(0.7));
    });

    test('signal négatif subi mais non imputé → simple soft-cap (pas ×0.85)',
        () {
      final next = _reg(CapabilityAxis.gorgeEngagementStreak,
          _st(best: 40, comfort: 30, sr: 0.6, seen: 4),
          sessionCeiling: 26, hardNegative: false, sessionIndex: 5);
      expect(next.comfort, 26.0);
      expect(next.successRate, lessThan(0.6));
      // soft-cap n\'augmente jamais le comfort (plafond figé plus haut → no-op).
      final higher = _reg(CapabilityAxis.gorgeEngagementStreak,
          _st(best: 40, comfort: 22, sr: 0.6, seen: 4),
          sessionCeiling: 30, hardNegative: false, sessionIndex: 5);
      expect(higher.comfort, 22.0);
    });

    test(
        'decay : axe inactif depuis ≥ kDecayAfterSessions → glisse vers '
        '0.7×best, lastSeen figé', () {
      final prev = _st(best: 40, comfort: 40, sr: 0.8, seen: 2);
      final decayed = _reg(CapabilityAxis.holdFullStreak, prev,
          sessionIndex: 2 + CapabilityRegulator.kDecayAfterSessions);
      expect(decayed.comfort, lessThan(40.0));
      expect(
          decayed.comfort,
          greaterThan(
              40.0 * CapabilityRegulator.kDecayTargetFracOfBest - 1e-9));
      expect(decayed.best, 40.0);
      expect(
          decayed.lastSeenSession, 2); // ne bouge pas → continue de décroître
      // un cran avant le seuil → rien ne bouge.
      final notYet = _reg(CapabilityAxis.holdFullStreak, prev,
          sessionIndex: 2 + CapabilityRegulator.kDecayAfterSessions - 1);
      expect(notYet.comfort, 40.0);
    });

    test('decay répété converge vers 0.7×best sans le franchir', () {
      var s = _st(best: 40, comfort: 40, sr: 0.8, seen: 0);
      for (var i = 0; i < 25; i++) {
        s = _reg(CapabilityAxis.holdFullStreak, s,
            sessionIndex: CapabilityRegulator.kDecayAfterSessions + i);
      }
      expect(s.comfort,
          closeTo(40.0 * CapabilityRegulator.kDecayTargetFracOfBest, 0.2));
      expect(
          s.comfort,
          greaterThanOrEqualTo(
              40.0 * CapabilityRegulator.kDecayTargetFracOfBest - 1e-9));
    });

    test('profondeur : +1 cran au plus, gaté par successRate', () {
      // confiance suffisante : throat(3) → full(4)
      final ok = _reg(CapabilityAxis.rhythmDepthMax,
          _st(best: 3, comfort: 3, sr: 0.7, seen: 4),
          reached: 4, sessionIndex: 5);
      expect(ok.comfort, 4.0);
      // jamais 2 crans d\'un coup : mid(2) + reached full(4) → throat(3)
      final two = _reg(CapabilityAxis.rhythmDepthMax,
          _st(best: 2, comfort: 2, sr: 0.9, seen: 4),
          reached: 4, sessionIndex: 5);
      expect(two.comfort, 3.0);
      // confiance insuffisante : comfort ne bouge pas, mais successRate monte.
      final low = _reg(CapabilityAxis.rhythmDepthMax,
          _st(best: 3, comfort: 3, sr: 0.5, seen: 4),
          reached: 4, sessionIndex: 5);
      expect(low.comfort, 3.0);
      expect(low.successRate, greaterThan(0.5));
      // tap-out imputé sur la profondeur → −1 cran.
      final down = _reg(CapabilityAxis.rhythmDepthMax,
          _st(best: 4, comfort: 4, sr: 0.7, seen: 4),
          sessionCeiling: 4, hardNegative: true, sessionIndex: 5);
      expect(down.comfort, 3.0);
      expect(down.best, 4.0);
    });

    test('best `maximize` ne baisse jamais, même après une série de fails', () {
      var s = _st(best: 30, comfort: 28, sr: 0.7, seen: 1);
      for (var i = 0; i < 6; i++) {
        s = _reg(CapabilityAxis.gorgeApneeStreak, s,
            sessionCeiling: 8, hardNegative: true, sessionIndex: 2 + i);
      }
      expect(s.best, 30.0);
      expect(s.comfort, greaterThan(0.0));
    });

    test('compteur lifetime : comfort suit best, pas de ratchet', () {
      final s1 = _reg(CapabilityAxis.gorgeCrossingsLifetime, _st(),
          reached: 30, sessionIndex: 1);
      expect(s1.best, 30.0);
      expect(s1.comfort, 30.0);
      final s2 = _reg(CapabilityAxis.gorgeCrossingsLifetime, s1,
          reached: 25, sessionIndex: 2);
      expect(s2.best, 55.0);
      expect(s2.comfort, 55.0);
    });

    test(
        'BPM floor : ratchet vers le bas (creep), planché à kBpmFloorPractical',
        () {
      final next = _reg(CapabilityAxis.rhythmBpmFloorShallow,
          _st(best: 25, comfort: 25, sr: 0.7, seen: 4),
          reached: 10, sessionIndex: 5);
      expect(next.comfort, lessThan(25.0));
      expect(next.comfort,
          greaterThanOrEqualTo(CapabilityRegulator.kBpmFloorPractical));
      expect(next.best, 10.0); // l\'exploit (le tempo le plus lent) lui descend
      // creep limité : pas plus de kRatchetUpGainMax de baisse en une session.
      expect(
          next.comfort,
          greaterThanOrEqualTo(
              25.0 * (1.0 - CapabilityRegulator.kRatchetUpGainMax) - 1e-9));
    });
  });

  group('CapabilityService.commit — round-trip + attribution', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> seed(
            CapabilityService svc, Map<CapabilityAxis, double> reached,
            {int sessionIndex = 1}) =>
        svc.commit(
            SessionCapabilityReport(
                reached: reached, sessionCeilings: const {}),
            sessionIndex: sessionIndex);

    test('attribution : l\'axe le plus surchargé relativement à son comfort',
        () async {
      final svc = CapabilityService();
      await seed(svc, {
        CapabilityAxis.gorgeApneeStreak: 24,
        CapabilityAxis.holdFullStreak: 40,
      });
      // Fail figeant apnée à 30 (ratio 30/24 = 1.25) et holdFull à 41 (≈ 1.03).
      final attributed = await svc.commit(
        const SessionCapabilityReport(reached: {}, sessionCeilings: {
          CapabilityAxis.gorgeApneeStreak: 30,
          CapabilityAxis.holdFullStreak: 41,
        }),
        sessionIndex: 2,
      );
      expect(attributed, CapabilityAxis.gorgeApneeStreak);
      final p = await svc.snapshotProfile();
      // apnée : ratchet dur ×0.85 sur min(comfort 24, figé 30) = 24.
      expect(p.comfortOf(CapabilityAxis.gorgeApneeStreak),
          closeTo(24.0 * CapabilityRegulator.kRatchetDownFactor, 1e-6));
      // holdFull : juste un soft-cap (figé 41 > comfort 40 → no-op).
      expect(p.comfortOf(CapabilityAxis.holdFullStreak), 40.0);
    });

    test('aucun axe au-dessus de son comfort → pas d\'attribution dure',
        () async {
      final svc = CapabilityService();
      await seed(svc, {CapabilityAxis.gorgeApneeStreak: 24});
      final attributed = await svc.commit(
        const SessionCapabilityReport(
            reached: {},
            sessionCeilings: {CapabilityAxis.gorgeApneeStreak: 18}),
        sessionIndex: 2,
      );
      expect(attributed, isNull);
      final p = await svc.snapshotProfile();
      expect(p.comfortOf(CapabilityAxis.gorgeApneeStreak), 18.0); // soft-cap
    });

    test('débordement de salive → ratchet dur sur noswallow même si ratio < 1',
        () async {
      final svc = CapabilityService();
      await seed(svc, {CapabilityAxis.noswallowStreak: 120});
      final attributed = await svc.commit(
        const SessionCapabilityReport(
            reached: {}, sessionCeilings: {CapabilityAxis.noswallowStreak: 60}),
        sessionIndex: 2,
      );
      // L\'attribution « coach » reste nulle (ratio 60/120 = 0.5 < 1)…
      expect(attributed, isNull);
      // …mais le comfort noswallow encaisse le ×0.85.
      final p = await svc.snapshotProfile();
      expect(p.comfortOf(CapabilityAxis.noswallowStreak),
          closeTo(60.0 * CapabilityRegulator.kRatchetDownFactor, 1e-6));
    });

    test('ratchet ↑ consolide la progression sur plusieurs sessions', () async {
      final svc = CapabilityService();
      await seed(svc, {CapabilityAxis.holdFullStreak: 30});
      var prev = (await svc.snapshotProfile())
          .comfortOf(CapabilityAxis.holdFullStreak)!;
      expect(prev, 30.0);
      for (var i = 2; i <= 5; i++) {
        // Le générateur surcharge à ~comfort × 1.1 et elle tient.
        await svc.commit(
          SessionCapabilityReport(
              reached: {CapabilityAxis.holdFullStreak: prev * 1.1},
              sessionCeilings: const {}),
          sessionIndex: i,
        );
        final now = (await svc.snapshotProfile())
            .comfortOf(CapabilityAxis.holdFullStreak)!;
        expect(now, greaterThan(prev));
        prev = now;
      }
      expect(prev, greaterThan(39.0)); // a bien grimpé en 4 sessions
    });

    test('decay appliqué via commit aux axes non sollicités', () async {
      final svc = CapabilityService();
      await seed(
          svc,
          {
            CapabilityAxis.holdFullStreak: 40,
            CapabilityAxis.gorgeApneeStreak: 24,
          },
          sessionIndex: 1);
      // 4 sessions plus tard, seule l\'apnée est sollicitée → holdFull decaye.
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.gorgeApneeStreak: 24},
            sessionCeilings: {}),
        sessionIndex: 1 + CapabilityRegulator.kDecayAfterSessions,
      );
      final p = await svc.snapshotProfile();
      expect(p.comfortOf(CapabilityAxis.holdFullStreak), lessThan(40.0));
      expect(
          p.comfortOf(CapabilityAxis.holdFullStreak),
          greaterThan(
              40.0 * CapabilityRegulator.kDecayTargetFracOfBest - 1e-9));
      expect(p.bestOf(CapabilityAxis.holdFullStreak), 40.0);
      // l\'apnée, elle, ne decaye pas (vue cette session).
      expect(p.comfortOf(CapabilityAxis.gorgeApneeStreak), 24.0);
    });
  });
}
