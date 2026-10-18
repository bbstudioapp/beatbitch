import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_leaderboard.dart';
import 'package:beat_bitch/services/capability_service.dart';

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
  bool quickie = false,
}) =>
    CapabilityRegulator.regulate(
      axis: axis,
      prev: prev,
      reached: reached,
      sessionCeiling: sessionCeiling,
      hardNegative: hardNegative,
      sessionIndex: sessionIndex,
      quickie: quickie,
    );

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'boost': _p(['b']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

void main() {
  group('quickie — comfort gelé (CapabilityRegulator.regulate)', () {
    test('ratchet ↑ neutralisé : best monte, comfort et successRate figés', () {
      final prev = _st(best: 30, comfort: 30, sr: 0.9, seen: 4);
      final normal = _reg(CapabilityAxis.holdFullStreak, prev,
          reached: 33, sessionIndex: 5);
      final quick = _reg(CapabilityAxis.holdFullStreak, prev,
          reached: 33, sessionIndex: 5, quickie: true);
      expect(normal.comfort, greaterThan(30.0));
      expect(quick.best, 33.0);
      expect(quick.comfort, 30.0);
      expect(quick.successRate, 0.9);
      expect(quick.lastSeenSession, 5);
    });

    test('ratchet ↓ imputé neutralisé : comfort lifetime intact', () {
      final prev = _st(best: 30, comfort: 30, sr: 0.5, seen: 4);
      final normal = _reg(CapabilityAxis.gorgeApneeStreak, prev,
          sessionCeiling: 20, hardNegative: true, sessionIndex: 5);
      final quick = _reg(CapabilityAxis.gorgeApneeStreak, prev,
          sessionCeiling: 20,
          hardNegative: true,
          sessionIndex: 5,
          quickie: true);
      expect(normal.comfort, lessThan(30.0));
      expect(quick.comfort, 30.0);
      expect(quick.best, 30.0);
      expect(quick.successRate, 0.5);
    });

    test('signal non imputé neutralisé en quickie', () {
      final prev = _st(best: 30, comfort: 30);
      final normal = _reg(CapabilityAxis.holdFullStreak, prev,
          sessionCeiling: 22, sessionIndex: 5);
      final quick = _reg(CapabilityAxis.holdFullStreak, prev,
          sessionCeiling: 22, sessionIndex: 5, quickie: true);
      expect(normal.comfort, 30.0);
      expect(normal.successRate, lessThan(prev.successRate));
      expect(quick.comfort, 30.0);
      expect(quick.successRate, prev.successRate);
    });

    test('le decay des axes non sollicités est indépendant du quickie', () {
      final prev = _st(best: 30, comfort: 25, seen: 0);
      final normal =
          _reg(CapabilityAxis.holdFullStreak, prev, sessionIndex: 10);
      final quick = _reg(CapabilityAxis.holdFullStreak, prev,
          sessionIndex: 10, quickie: true);
      expect(normal.comfort, isNot(25.0));
      expect(quick.comfort, normal.comfort);
    });

    test('1ʳᵉ donnée en quickie → comfort quand même seedé à best', () {
      final next = _reg(CapabilityAxis.gorgeApneeStreak, _st(),
          reached: 18, sessionIndex: 1, quickie: true);
      expect(next.best, 18.0);
      expect(next.comfort, 18.0);
      expect(next.lastSeenSession, 1);
    });

    test('axe accumulate (lifetime) inchangé en quickie', () {
      final next = _reg(
          CapabilityAxis.gorgeCrossingsLifetime, _st(best: 100, comfort: 100),
          reached: 30, sessionIndex: 5, quickie: true);
      expect(next.best, 130.0);
      expect(next.comfort, 130.0);
    });
  });

  group('quickie — propagation via CapabilityService.commit', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('commit(quickie: true) enregistre best mais ne ratchet pas comfort',
        () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.gorgeApneeStreak: 18},
            sessionCeilings: {}),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.gorgeApneeStreak: 22},
            sessionCeilings: {}),
        sessionIndex: 2,
        quickie: true,
      );
      final p = await svc.snapshotProfile();
      expect(p.bestOf(CapabilityAxis.gorgeApneeStreak), 22.0);
      expect(p.comfortOf(CapabilityAxis.gorgeApneeStreak), 18.0);
    });

    test('commit(quickie: false) ratchet bien le comfort (contrôle)', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.gorgeApneeStreak: 18},
            sessionCeilings: {}),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.gorgeApneeStreak: 22},
            sessionCeilings: {}),
        sessionIndex: 2,
      );
      final p = await svc.snapshotProfile();
      expect(p.bestOf(CapabilityAxis.gorgeApneeStreak), 22.0);
      expect(p.comfortOf(CapabilityAxis.gorgeApneeStreak), greaterThan(18.0));
    });
  });

  group('garde Custom — generate sans capabilityProfile n\'est pas gaté', () {
    test('session identique avec capabilityProfile null vs absent', () {
      List<SessionStep> steps({bool passProfile = false}) =>
          CareerSessionGenerator(seed: 7)
              .generate(
                level: 14,
                bank: _bank(),
                humiliationCareer: 400.0,
                unlockedKeys: const {},
                custom: const CustomOverrides(noStats: true),
                capability: CapabilityInputs(
                  profile: passProfile ? const CapabilityProfile({}) : null,
                ),
              )
              .session
              .steps;
      final withoutArg = steps();
      final withNull = steps(passProfile: false);
      expect(withNull.length, withoutArg.length);
      for (var i = 0; i < withoutArg.length; i++) {
        final a = withoutArg[i];
        final b = withNull[i];
        expect(
          [b.time, b.mode, b.from, b.to, b.bpm, b.bpmEnd, b.duration],
          [a.time, a.mode, a.from, a.to, a.bpm, a.bpmEnd, a.duration],
        );
      }
    });
  });

  group('CapabilityLeaderboardPayload', () {
    test('fromProfile : une entrée par axe avec données, comfort exclu', () {
      const profile = CapabilityProfile({
        CapabilityAxis.gorgeApneeStreak:
            CapabilityAxisState(best: 41, comfort: 38),
        CapabilityAxis.biffleBpmMax:
            CapabilityAxisState(best: 168, comfort: 150),
        CapabilityAxis.holdFullStreak: CapabilityAxisState(),
      });
      final now = DateTime.utc(2026, 5, 12, 10, 0, 0);
      final payload = CapabilityLeaderboardPayload.fromProfile(
        profile,
        careerLevel: 14,
        now: now,
      );
      expect(payload.schemaVersion,
          CapabilityLeaderboardPayload.currentSchemaVersion);
      expect(payload.careerLevel, 14);
      expect(payload.generatedAtMs, now.millisecondsSinceEpoch);
      expect(payload.axes.length, 2);
      expect(payload.isEmpty, isFalse);

      final apnee = payload.axes.firstWhere(
          (e) => e.key == CapabilityAxis.gorgeApneeStreak.storageKey);
      expect(apnee.best, 41.0);
      expect(apnee.kind, CapabilityRecordKind.maximize);
      expect(apnee.unit, CapabilityUnit.seconds);
      expect(apnee.pilotant, isTrue);

      final json = payload.toJson();
      final axesJson = json['axes'] as List<dynamic>;
      for (final e in axesJson) {
        final m = e as Map<String, dynamic>;
        expect(m.containsKey('comfort'), isFalse);
        expect(m.keys.toSet(), {'key', 'best', 'kind', 'unit', 'pilotant'});
      }
      expect(json['schema_version'], 1);
      expect(json['career_level'], 14);
      expect(json['generated_at_ms'], now.millisecondsSinceEpoch);
    });

    test('fromProfile sur profil vide → payload vide', () {
      final payload = CapabilityLeaderboardPayload.fromProfile(
        const CapabilityProfile({}),
        careerLevel: 1,
      );
      expect(payload.isEmpty, isTrue);
      expect(payload.axes, isEmpty);
      expect((payload.toJson()['axes'] as List).isEmpty, isTrue);
    });

    test('kind/unit sérialisés via .name', () {
      const profile = CapabilityProfile({
        CapabilityAxis.rhythmBpmFloorThroat:
            CapabilityAxisState(best: 22, comfort: 24),
        CapabilityAxis.rhythmDepthMax: CapabilityAxisState(best: 3, comfort: 3),
        CapabilityAxis.gorgeCrossingsLifetime:
            CapabilityAxisState(best: 1200, comfort: 1200),
      });
      final payload =
          CapabilityLeaderboardPayload.fromProfile(profile, careerLevel: 9);
      final byKey = {for (final e in payload.axes) e.key: e};
      expect(byKey[CapabilityAxis.rhythmBpmFloorThroat.storageKey]!.kind,
          CapabilityRecordKind.minimize);
      expect(byKey[CapabilityAxis.rhythmDepthMax.storageKey]!.unit,
          CapabilityUnit.depthCran);
      expect(byKey[CapabilityAxis.gorgeCrossingsLifetime.storageKey]!.kind,
          CapabilityRecordKind.accumulate);
      final json =
          byKey[CapabilityAxis.rhythmBpmFloorThroat.storageKey]!.toJson();
      expect(json['kind'], 'minimize');
      expect(json['unit'], 'bpm');
    });
  });
}
