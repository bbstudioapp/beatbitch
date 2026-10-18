import 'dart:convert';

import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_history.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:beat_bitch/services/diagnostic_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

CapabilityHistoryEntry _entry(int i, {double best = 10}) =>
    CapabilityHistoryEntry(
      at: DateTime.utc(2026, 10, 18).add(Duration(minutes: i)),
      sessionIndex: i,
      axes: {
        'hold.full.streak': CapabilityHistoryAxis(
            best: best, comfort: best - 1, successRate: 0.6),
      },
    );

Future<DiagnosticExportService> _exporter(SharedPreferences prefs) async =>
    DiagnosticExportService(
      prefs: prefs,
      packageInfo: PackageInfo(
        appName: 'BeatBitch',
        packageName: 'x',
        version: '0.0.0',
        buildNumber: '0',
      ),
      platform: 'android',
      locale: 'fr',
      exportedAt: DateTime.utc(2026, 10, 18),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<CapabilityHistoryEntry>> stored() async =>
      CapabilityHistory.read(await SharedPreferences.getInstance());

  group('CapabilityService.commit — une entrée par séance', () {
    test('une séance → une entrée : date, index, confort/record/taux par axe',
        () async {
      final at = DateTime.utc(2026, 10, 18, 9, 30);
      final svc = CapabilityService(clock: () => at);
      await svc.commit(
        const SessionCapabilityReport(reached: {
          CapabilityAxis.holdFullStreak: 20,
          CapabilityAxis.gorgeApneeStreak: 12,
        }, sessionCeilings: {}),
        sessionIndex: 7,
      );

      final h = await stored();
      expect(h, hasLength(1));
      expect(h.single.at, at);
      expect(h.single.sessionIndex, 7);

      final profile = await svc.snapshotProfile();
      expect(h.single.axes.keys.toSet(),
          {'hold.full.streak', 'gorge.apnee_streak'});
      for (final a in [
        CapabilityAxis.holdFullStreak,
        CapabilityAxis.gorgeApneeStreak
      ]) {
        final e = h.single.axes[a.storageKey]!;
        expect(e.best, profile.bestOf(a));
        expect(e.comfort, profile.comfortOf(a));
        expect(e.successRate, profile.stateOf(a).successRate);
      }
      expect(h.single.axes['hold.full.streak']!.best, 20);
    });

    test('deux séances → deux entrées, la 2ᵉ reflète le profil mis à jour',
        () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 20}, sessionCeilings: {}),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 30}, sessionCeilings: {}),
        sessionIndex: 2,
      );
      final h = await stored();
      expect(h.map((e) => e.sessionIndex), [1, 2]);
      expect(h[0].axes['hold.full.streak']!.best, 20);
      expect(h[1].axes['hold.full.streak']!.best, 30);
    });

    test('rapport vide (séance qui n\'écrit pas le profil) → aucune entrée',
        () async {
      await CapabilityService().commit(
        const SessionCapabilityReport(reached: {}, sessionCeilings: {}),
        sessionIndex: 3,
      );
      expect(await stored(), isEmpty);
      expect((await SharedPreferences.getInstance()).containsKey('cap.history'),
          isFalse);
    });
  });

  group('CapabilityHistory — borne', () {
    test('au-delà de maxEntries les plus anciennes sortent', () async {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < CapabilityHistory.maxEntries + 5; i++) {
        await CapabilityHistory.append(prefs, _entry(i));
      }
      final h = CapabilityHistory.read(prefs);
      expect(h, hasLength(CapabilityHistory.maxEntries));
      expect(h.first.sessionIndex, 5);
      expect(h.last.sessionIndex, CapabilityHistory.maxEntries + 4);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('CapabilityHistory — tolérance', () {
    for (final raw in <Object>[
      '{pas du json',
      '[1,2,3]',
      '{"v":1,"entries":"non"}',
      '{"v":99,"entries":[{"t":1,"i":1,"a":{}}]}',
      42,
    ]) {
      test(
          'illisible ($raw) : séance intacte, profil écrit, historique relancé',
          () async {
        SharedPreferences.setMockInitialValues({'cap.history': raw});
        final svc = CapabilityService();
        expect(await svc.snapshotProfile(), isNotNull);
        await svc.commit(
          const SessionCapabilityReport(
              reached: {CapabilityAxis.holdFullStreak: 20},
              sessionCeilings: {}),
          sessionIndex: 4,
        );
        expect(
            (await svc.snapshotProfile()).bestOf(CapabilityAxis.holdFullStreak),
            20);
        final h = await stored();
        expect(h, hasLength(1));
        expect(h.single.sessionIndex, 4);
      });
    }

    test('une entrée abîmée est ignorée, les autres sont gardées', () async {
      SharedPreferences.setMockInitialValues({
        'cap.history': json.encode({
          'v': 1,
          'entries': [
            {
              't': 1000,
              'i': 1,
              'a': {
                'hold.full.streak': [10.0, 9.0, 0.5]
              }
            },
            {'t': 'x', 'i': 2, 'a': {}},
            {
              't': 3000,
              'i': 3,
              'a': {
                'hold.full.streak': [11.0, 9.5, 0.6],
                'cassé': [1]
              }
            },
          ],
        }),
      });
      final h = await stored();
      expect(h.map((e) => e.sessionIndex), [1, 3]);
      expect(h.last.axes.keys, ['hold.full.streak']);
    });
  });

  group('Export / import', () {
    test('aller-retour : l\'historique exporté est restitué à l\'identique',
        () async {
      final src = await SharedPreferences.getInstance();
      await CapabilityHistory.append(src, _entry(1, best: 10));
      await CapabilityHistory.append(src, _entry(2, best: 12.5));

      final payload =
          (await _exporter(src)).buildPayload(const DiagnosticExportOptions());
      // Passage par du vrai JSON, comme le fichier.
      final decoded = json.decode(json.encode(payload)) as Map<String, dynamic>;

      SharedPreferences.setMockInitialValues({});
      final dst = await SharedPreferences.getInstance();
      await DiagnosticImportService(dst).apply(decoded);

      final a = CapabilityHistory.read(src);
      final b = CapabilityHistory.read(dst);
      expect(b, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(b[i].at, a[i].at);
        expect(b[i].sessionIndex, a[i].sessionIndex);
        expect(b[i].axes['hold.full.streak']!.best,
            a[i].axes['hold.full.streak']!.best);
        expect(b[i].axes['hold.full.streak']!.comfort,
            a[i].axes['hold.full.streak']!.comfort);
        expect(b[i].axes['hold.full.streak']!.successRate,
            a[i].axes['hold.full.streak']!.successRate);
      }
    });

    test('export sans historique : section présente et vide', () async {
      final payload = (await _exporter(await SharedPreferences.getInstance()))
          .buildPayload(const DiagnosticExportOptions());
      expect(payload['capabilityHistory'], isNotNull);
      expect((payload['capabilityHistory'] as Map)['entries'], isEmpty);
    });

    test(
        'import d\'un export sans historique : l\'historique résiduel est effacé',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await CapabilityHistory.append(prefs, _entry(1));
      await DiagnosticImportService(prefs).apply(<String, dynamic>{});
      expect(CapabilityHistory.read(prefs), isEmpty);
      expect(prefs.containsKey('cap.history'), isFalse);
    });

    test('import d\'une section illisible : ni crash ni historique', () async {
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs)
          .apply(<String, dynamic>{'capabilityHistory': 'n\'importe quoi'});
      expect(CapabilityHistory.read(prefs), isEmpty);
    });
  });

  group('Remise à zéro', () {
    test('CapabilityService.resetAll vide l\'historique', () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 20}, sessionCeilings: {}),
        sessionIndex: 1,
      );
      expect(await stored(), hasLength(1));
      await svc.resetAll();
      expect(await stored(), isEmpty);
      expect((await SharedPreferences.getInstance()).containsKey('cap.history'),
          isFalse);
    });
  });
}
