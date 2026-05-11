import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/capability_tracker.dart';
import 'package:beat_bitch/services/saliva_engine.dart';

/// Avance le tracker de [n] secondes avec un `swallowMode` constant.
void _tick(CapabilityTracker t, int n,
    {SwallowMode swallow = SwallowMode.allowed}) {
  for (var i = 0; i < n; i++) {
    t.onTickSecond(swallowMode: swallow);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CapabilityTracker', () {
    test('rhythm head→throat alimente engagement mais pas apnée', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.head,
        to: Position.throat,
        bpm: 90,
        duration: 20,
      );
      _tick(t, 10);
      final report = t.finalizeReport();
      expect(report.reached[CapabilityAxis.gorgeEngagementStreak], 10.0);
      expect(
          report.reached.containsKey(CapabilityAxis.gorgeApneeStreak), isFalse);
      // ≥ 3 s à throat → record de profondeur + fenêtre BPM gorge.
      expect(report.reached[CapabilityAxis.rhythmDepthMax],
          Position.throat.index.toDouble());
      expect(report.reached[CapabilityAxis.rhythmBpmCeilThroat], 90.0);
      expect(report.reached[CapabilityAxis.gorgeCrossingsBpmThroat], 90.0);
    });

    test('hold full : apnée + engagement + hold.full cumulent', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(mode: SessionMode.hold, to: Position.full, duration: 30);
      _tick(t, 12);
      // Un beg full enchaîné cumule avec le hold.
      t.onStepApplied(mode: SessionMode.beg, to: Position.full, duration: 6);
      _tick(t, 6);
      final report = t.finalizeReport();
      expect(report.reached[CapabilityAxis.holdFullStreak], 18.0);
      expect(report.reached[CapabilityAxis.gorgeApneeStreak], 18.0);
      expect(report.reached[CapabilityAxis.gorgeEngagementStreak], 18.0);
    });

    test(
        'un breath casse l\'apnée et l\'engagement, pas un hold throat ↔ '
        'rhythm throat→full', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(
          mode: SessionMode.hold, to: Position.throat, duration: 10);
      _tick(t, 8);
      t.onStepApplied(
        mode: SessionMode.rhythm,
        from: Position.throat,
        to: Position.full,
        bpm: 60,
        duration: 12,
      );
      _tick(t, 6);
      // Le rhythm throat→full reste airless (from = throat) → apnée cumule.
      // Mais hold.throat se casse (le rhythm n'est pas un hold/beg à throat).
      t.onStepApplied(mode: SessionMode.breath, duration: 8);
      _tick(t, 8);
      final report = t.finalizeReport();
      expect(report.reached[CapabilityAxis.gorgeApneeStreak], 14.0);
      expect(report.reached[CapabilityAxis.holdThroatStreak], 8.0);
      // Le breath a aussi clos l'effort-sans-pause des 14 s d'avant.
      expect(report.reached[CapabilityAxis.effortNoBreathStreak], 14.0);
      // … et a posé une dose mini de souffle de 8 s à la reprise.
      // (la reprise = finalizeReport ici, donc pas de step suivant — la dose
      // n'est posée que sur un step non-breath suivant. On vérifie l'absence.)
      expect(report.reached.containsKey(CapabilityAxis.breathMinDose), isFalse);
    });

    test('breath.min_dose enregistrée quand un step d\'effort suit le breath',
        () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: 80,
          duration: 20);
      _tick(t, 12);
      t.onStepApplied(mode: SessionMode.breath, duration: 9);
      _tick(t, 9);
      t.onStepApplied(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: 80,
          duration: 20);
      _tick(t, 5);
      final report = t.finalizeReport();
      expect(report.reached[CapabilityAxis.breathMinDose], 9.0);
    });

    test('un fail vide les streaks actifs sans produire de record', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(mode: SessionMode.hold, to: Position.full, duration: 30);
      _tick(t, 15);
      t.onFail();
      // Reprise post-fail sur une section anodine.
      t.onStepApplied(
          mode: SessionMode.hand,
          from: Position.head,
          to: Position.mid,
          bpm: 50,
          duration: 14);
      _tick(t, 14);
      final report = t.finalizeReport();
      // Le hold full de 15 s a été figé en plafond de session, pas en record.
      expect(
          report.reached.containsKey(CapabilityAxis.holdFullStreak), isFalse);
      expect(report.sessionCeilings[CapabilityAxis.holdFullStreak], 15.0);
      // Hand a bien produit son streak (hors difficulté mais enregistré).
      expect(report.reached[CapabilityAxis.handStreak], 14.0);
    });

    test('un fail fige aussi les params « config » du step courant (§6)', () {
      final t = CapabilityTracker()..onSessionStart();
      // Fail pendant un rhythm mid→full rapide : profondeur, BPM de bande et
      // BPM de franchissement sont figés (même si le step n'a pas tenu 3 s).
      t.onStepApplied(
          mode: SessionMode.rhythm,
          from: Position.mid,
          to: Position.full,
          bpm: 140,
          duration: 16);
      _tick(t, 2);
      t.onFail();
      // Reprise anodine pour clore proprement.
      t.onStepApplied(
          mode: SessionMode.hand,
          from: Position.head,
          to: Position.mid,
          bpm: 50,
          duration: 14);
      _tick(t, 14);
      final report = t.finalizeReport();
      expect(report.sessionCeilings[CapabilityAxis.rhythmDepthMax],
          Position.full.index.toDouble());
      expect(report.sessionCeilings[CapabilityAxis.rhythmBpmCeilFull], 140.0);
      expect(
          report.sessionCeilings[CapabilityAxis.gorgeCrossingsBpmFull], 140.0);
      // Pas de record propre pour ces axes (le step a été interrompu).
      expect(
          report.reached.containsKey(CapabilityAxis.rhythmDepthMax), isFalse);
      expect(report.reached.containsKey(CapabilityAxis.rhythmBpmCeilFull),
          isFalse);
    });

    test('un fail pendant un biffle rapide fige biffle.bpm_max (§6)', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(mode: SessionMode.biffle, bpm: 150, duration: 12);
      _tick(t, 1);
      t.onFail();
      t.onStepApplied(
          mode: SessionMode.hand,
          from: Position.head,
          to: Position.mid,
          bpm: 50,
          duration: 14);
      _tick(t, 14);
      final report = t.finalizeReport();
      expect(report.sessionCeilings[CapabilityAxis.biffleBpmMax], 150.0);
      expect(report.reached.containsKey(CapabilityAxis.biffleBpmMax), isFalse);
    });

    test('noswallow : streak enregistré, mais voidé par un débordement', () {
      final t = CapabilityTracker()..onSessionStart();
      t.onStepApplied(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.mid,
          bpm: 80,
          duration: 60);
      _tick(t, 20, swallow: SwallowMode.forbidden);
      _tick(t, 1, swallow: SwallowMode.allowed); // fenêtre autorisée → flush
      _tick(t, 10, swallow: SwallowMode.forbidden);
      t.onSalivaOverflow();
      _tick(t, 5, swallow: SwallowMode.forbidden);
      _tick(t, 1, swallow: SwallowMode.allowed); // ce streak-ci est voidé
      final report = t.finalizeReport();
      expect(report.reached[CapabilityAxis.noswallowStreak], 20.0);
      // Le débordement fige aussi un plafond de session sur noswallow (= signal
      // négatif imputé de plein droit, §5.3).
      expect(report.sessionCeilings[CapabilityAxis.noswallowStreak], 10.0);
    });
  });

  group('CapabilityService', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('commit puis snapshot : best/comfort round-trip + max', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.gorgeApneeStreak: 20.0},
          sessionCeilings: {},
        ),
        sessionIndex: 1,
      );
      var profile = await svc.snapshotProfile();
      expect(profile.bestOf(CapabilityAxis.gorgeApneeStreak), 20.0);
      expect(profile.comfortOf(CapabilityAxis.gorgeApneeStreak), 20.0);
      expect(profile.hasAnyData, isTrue);

      // Une session plus faible ne fait pas reculer le best.
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.gorgeApneeStreak: 12.0},
          sessionCeilings: {},
        ),
        sessionIndex: 2,
      );
      profile = await svc.snapshotProfile();
      expect(profile.bestOf(CapabilityAxis.gorgeApneeStreak), 20.0);
    });

    test('axe minimize : best descend', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.breathMinDose: 10.0},
          sessionCeilings: {},
        ),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.breathMinDose: 6.0},
          sessionCeilings: {},
        ),
        sessionIndex: 2,
      );
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.breathMinDose: 8.0},
          sessionCeilings: {},
        ),
        sessionIndex: 3,
      );
      final profile = await svc.snapshotProfile();
      expect(profile.bestOf(CapabilityAxis.breathMinDose), 6.0);
    });

    test('axe accumulate : best somme les sessions', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.gorgeCrossingsLifetime: 30.0},
          sessionCeilings: {},
        ),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.gorgeCrossingsLifetime: 25.0},
          sessionCeilings: {},
        ),
        sessionIndex: 2,
      );
      final profile = await svc.snapshotProfile();
      expect(profile.bestOf(CapabilityAxis.gorgeCrossingsLifetime), 55.0);
    });

    test('migration legacy : maxHoldFullAtomic seedé dans holdFullStreak',
        () async {
      SharedPreferences.setMockInitialValues(
          {'stats.max_hold_full_atomic': 42});
      final svc = CapabilityService();
      final profile = await svc.snapshotProfile();
      expect(profile.bestOf(CapabilityAxis.holdFullStreak), 42.0);
      expect(profile.comfortOf(CapabilityAxis.holdFullStreak), 42.0);
    });

    test('resetAll efface le profil', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
          reached: {CapabilityAxis.holdThroatStreak: 18.0},
          sessionCeilings: {},
        ),
        sessionIndex: 1,
      );
      await svc.resetAll();
      final profile = await svc.snapshotProfile();
      expect(profile.hasAnyData, isFalse);
    });
  });
}
