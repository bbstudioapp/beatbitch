import 'dart:convert';
import 'dart:math';

import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_history.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:beat_bitch/services/diagnostic_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

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

    test('confort et record distincts : chacun sa valeur, le taux aussi',
        () async {
      SharedPreferences.setMockInitialValues({
        'cap.legacy_migrated': true,
        'cap.use_me_held_migrated': true,
        'cap.hold.full.streak.best': 40.0,
        'cap.hold.full.streak.comfort': 25.0,
        'cap.hold.full.streak.sr': 0.8,
        'cap.hold.full.streak.seen': 3,
      });
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 10}, sessionCeilings: {}),
        sessionIndex: 4,
      );
      final profile = await svc.snapshotProfile();
      final e = (await stored()).single.axes['hold.full.streak']!;
      expect(e.best, 40.0);
      expect(e.comfort, profile.comfortOf(CapabilityAxis.holdFullStreak));
      expect(e.comfort, isNot(e.best));
      expect(e.successRate, isNot(CapabilityService.defaultSuccessRate));
      expect(e.successRate,
          profile.stateOf(CapabilityAxis.holdFullStreak).successRate);
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

    test(
        'rapport vide (séance qui n\'écrit pas le profil) : pas de nouvelle entrée',
        () async {
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 20}, sessionCeilings: {}),
        sessionIndex: 1,
      );
      await svc.commit(
        const SessionCapabilityReport(reached: {}, sessionCeilings: {}),
        sessionIndex: 2,
      );
      expect((await stored()).map((e) => e.sessionIndex), [1]);
    });
  });

  group('CapabilityHistory — borne', () {
    test('au-delà de maxEntries les plus anciennes sortent', () async {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < CapabilityHistory.maxEntries + 5; i++) {
        await CapabilityHistory.append(prefs, _entry(i));
      }
      final h = CapabilityHistory.read(prefs);
      expect(CapabilityHistory.maxEntries, 300);
      expect(h, hasLength(CapabilityHistory.maxEntries));
      expect(h.first.sessionIndex, 5);
      expect(h.last.sessionIndex, CapabilityHistory.maxEntries + 4);
      final raw = json.decode(prefs.getString('cap.history')!) as Map;
      expect(raw['entries'], hasLength(CapabilityHistory.maxEntries),
          reason: 'le stockage lui-même est borné, pas seulement la lecture');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('valeurs arrondies à 2 décimales à l\'écriture', () async {
      final prefs = await SharedPreferences.getInstance();
      await CapabilityHistory.append(
        prefs,
        CapabilityHistoryEntry(
          at: DateTime.utc(2026, 10, 18),
          sessionIndex: 1,
          axes: {
            'hold.full.streak': const CapabilityHistoryAxis(
                best: 12.3456789,
                comfort: 0.30000000000000004,
                successRate: 0.5714285),
          },
        ),
      );
      final raw = json.decode(prefs.getString('cap.history')!) as Map;
      final axes = (raw['entries'] as List).single['a'] as Map;
      expect(axes['hold.full.streak'], [12.35, 0.3, 0.57]);
    });

    test('historique plein sur tous les axes : poids borné', () async {
      final rng = Random(7);
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < CapabilityHistory.maxEntries + 10; i++) {
        await CapabilityHistory.append(
          prefs,
          CapabilityHistoryEntry(
            at: DateTime.utc(2026, 10, 18).add(Duration(minutes: i)),
            sessionIndex: i,
            axes: {
              for (final axis in CapabilityAxis.values)
                axis.storageKey: CapabilityHistoryAxis(
                  best: rng.nextDouble() * 150,
                  comfort: rng.nextDouble() * 150,
                  successRate: rng.nextDouble(),
                ),
            },
          ),
        );
      }
      final size = prefs.getString('cap.history')!.length;
      // ignore: avoid_print
      print('poids plein (${CapabilityAxis.values.length} axes) : $size');
      expect(size, lessThan(350000));
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('un import plus long que la borne est tronqué au stockage', () async {
      final prefs = await SharedPreferences.getInstance();
      final longHistory = CapabilityHistory.toJson([
        for (var i = 0; i < CapabilityHistory.maxEntries + 5; i++) _entry(i),
      ]);
      await DiagnosticImportService(prefs)
          .apply(<String, dynamic>{'capabilityHistory': longHistory});
      final raw = json.decode(prefs.getString('cap.history')!) as Map;
      expect(raw['entries'], hasLength(CapabilityHistory.maxEntries));
      expect(CapabilityHistory.read(prefs).first.sessionIndex, 5);
    });
  });

  group('CapabilityHistory — tolérance', () {
    test('écriture de l\'historique en échec : le profil est quand même écrit',
        () async {
      final store = _FailingHistoryStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final svc = CapabilityService();
      await svc.commit(
        const SessionCapabilityReport(
            reached: {CapabilityAxis.holdFullStreak: 20}, sessionCeilings: {}),
        sessionIndex: 1,
      );
      expect(store.historyWrites, 1,
          reason: 'sonde non vide : on a bien tenté');
      expect(
          (await svc.snapshotProfile()).bestOf(CapabilityAxis.holdFullStreak),
          20);
    });

    for (final raw in <Object>[
      '{pas du json',
      '[1,2,3]',
      '{"v":1,"entries":"non"}',
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

    for (final raw in <String>[
      '{"v":99,"entries":[{"t":1,"i":1,"a":{}}]}',
      '{"v":2,"entries":"autre forme"}',
    ]) {
      test('version inconnue ($raw) : gardée telle quelle, rien n\'est ajouté',
          () async {
        SharedPreferences.setMockInitialValues({'cap.history': raw});
        final svc = CapabilityService();
        await svc.commit(
          const SessionCapabilityReport(
              reached: {CapabilityAxis.holdFullStreak: 20},
              sessionCeilings: {}),
          sessionIndex: 4,
        );
        expect(
            (await svc.snapshotProfile()).bestOf(CapabilityAxis.holdFullStreak),
            20,
            reason: 'le profil est écrit malgré tout');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('cap.history'), raw);
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
    test('aller-retour : l\'historique exporté garde le jour et le reste',
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
        final local = a[i].at.toLocal();
        expect(b[i].at, DateTime.utc(local.year, local.month, local.day));
        expect(b[i].sessionIndex, a[i].sessionIndex);
        expect(b[i].axes['hold.full.streak']!.best,
            a[i].axes['hold.full.streak']!.best);
        expect(b[i].axes['hold.full.streak']!.comfort,
            a[i].axes['hold.full.streak']!.comfort);
        expect(b[i].axes['hold.full.streak']!.successRate,
            a[i].axes['hold.full.streak']!.successRate);
      }
    });

    test(
        'l\'export ne garde que le jour local : aucune heure, même pour un '
        'historique déjà enregistré avec l\'heure', () async {
      final src = await SharedPreferences.getInstance();
      final instants = [
        DateTime.utc(2026, 10, 18, 9, 30, 12, 345),
        DateTime.utc(2026, 10, 18, 23, 59, 59),
      ];
      for (var i = 0; i < instants.length; i++) {
        await CapabilityHistory.append(
          src,
          CapabilityHistoryEntry(
            at: instants[i],
            sessionIndex: i + 1,
            axes: _entry(1).axes,
          ),
        );
      }

      final payload =
          (await _exporter(src)).buildPayload(const DiagnosticExportOptions());
      final decoded = json.decode(json.encode(payload)) as Map<String, dynamic>;
      final entries = (decoded['capabilityHistory'] as Map)['entries'] as List;

      expect(entries, hasLength(2));
      for (var i = 0; i < 2; i++) {
        final local = instants[i].toLocal();
        expect(
            (entries[i] as Map)['t'],
            DateTime.utc(local.year, local.month, local.day)
                .millisecondsSinceEpoch);
        expect((entries[i] as Map)['t'] % Duration.millisecondsPerDay, 0);
      }

      // L'import relit un export « jour seul » sans erreur.
      SharedPreferences.setMockInitialValues({});
      final dst = await SharedPreferences.getInstance();
      await DiagnosticImportService(dst).apply(decoded);
      final b = CapabilityHistory.read(dst);
      expect(b, hasLength(2));
      expect(b.map((e) => e.sessionIndex), [1, 2]);
    });

    group('jour local de la joueuse, quel que soit le fuseau de la machine',
        () {
      // Fuseau injecté : le résultat ne dépend pas de TZ.
      DateTime Function(DateTime) offset(int hours) =>
          (d) => d.add(Duration(hours: hours));

      int tOf(DateTime at, DateTime Function(DateTime) toLocal) {
        final json = CapabilityHistory.toJson(
          [
            CapabilityHistoryEntry(
                at: at, sessionIndex: 1, axes: _entry(1).axes),
          ],
          dayOnly: true,
          toLocal: toLocal,
        );
        return ((json['entries'] as List).single as Map)['t'] as int;
      }

      test('Paris : 18/10 23:30 UTC est le 19/10 local', () {
        expect(tOf(DateTime.utc(2026, 10, 18, 23, 30), offset(2)),
            DateTime.utc(2026, 10, 19).millisecondsSinceEpoch);
      });

      test('New York : 19/10 01:30 UTC est le 18/10 local', () {
        expect(tOf(DateTime.utc(2026, 10, 19, 1, 30), offset(-4)),
            DateTime.utc(2026, 10, 18).millisecondsSinceEpoch);
      });
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

class _FailingHistoryStore extends InMemorySharedPreferencesStore {
  int historyWrites = 0;

  _FailingHistoryStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key.endsWith('cap.history')) {
      historyWrites++;
      throw StateError('disque plein');
    }
    return super.setValue(valueType, key, value);
  }
}
