import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/services/coach_service.dart';

Coach get _lilith =>
    CoachCatalog.defaults.firstWhere((c) => c.id == CoachCatalog.lilithId);

List<Coach> get _permanent =>
    CoachCatalog.defaults.where((c) => c.availability == null).toList();

final _before = DateTime(2026, 10, 26, 23, 59, 59);
final _firstDay = DateTime(2026, 10, 27);
final _lastDay = DateTime(2026, 11, 8, 23, 59, 59);
final _after = DateTime(2026, 11, 9);
final _nextYearFirstDay = DateTime(2027, 10, 27);
final _nextYearAfter = DateTime(2027, 11, 9);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('CoachAvailability — fenêtre annuelle du 27/10 au 08/11', () {
    final window = _lilith.availability!;

    final cases = <DateTime, bool>{
      _before: false,
      _firstDay: true,
      DateTime(2026, 11, 1, 12): true,
      _lastDay: true,
      _after: false,
      DateTime(2027, 10, 26, 23, 59, 59): false,
      _nextYearFirstDay: true,
      DateTime(2027, 11, 8, 23, 59, 59): true,
      _nextYearAfter: false,
    };
    cases.forEach((now, expected) {
      test('$now → ${expected ? 'proposée' : 'absente'}', () {
        expect(window.includes(now), expected);
      });
    });

    test('le dernier jour suit l\'année de l\'horloge', () {
      expect(window.lastDayOf(_firstDay), DateTime(2026, 11, 8));
      expect(window.lastDayOf(_nextYearFirstDay), DateTime(2027, 11, 8));
    });
  });

  group('CoachService — Lilith selon la date', () {
    for (final now in [_before, _after, _nextYearAfter]) {
      test('hors fenêtre ($now) : absente, non sélectionnable', () async {
        final s = CoachService(clock: () => now);
        await s.load();
        expect(s.coaches.map((c) => c.id),
            orderedEquals(_permanent.map((c) => c.id)));
        expect(s.isUnlocked(_lilith), isFalse);
        expect(
          s.evaluate(_lilith, playerTotalSeconds: 0),
          CoachSelectionStatus.lockedTier,
        );
      });
    }

    for (final now in [_firstDay, _lastDay, _nextYearFirstDay]) {
      test('dans la fenêtre ($now) : proposée en dernier, pour toutes',
          () async {
        final s = CoachService(clock: () => now);
        await s.load();
        expect(s.coaches.map((c) => c.id), [
          ..._permanent.map((c) => c.id),
          CoachCatalog.lilithId,
        ]);
        expect(s.currentTier, 1);
        expect(s.isUnlocked(_lilith), isTrue);
        expect(
          s.evaluate(_lilith, playerTotalSeconds: 0),
          CoachSelectionStatus.selectedLimitedTime,
        );
        expect(s.offeredUntil(_lilith), DateTime(now.year, 11, 8));
      });
    }

    test('sa sélection retombe sur rien le lendemain de la fenêtre', () async {
      var now = _lastDay;
      final s = CoachService(clock: () => now);
      await s.load();
      await s.selectCoach(_lilith);
      expect(s.selectedCoach?.id, CoachCatalog.lilithId);

      now = _after;
      expect(s.selectedCoach, isNull);

      now = _nextYearFirstDay;
      expect(s.selectedCoach?.id, CoachCatalog.lilithId);
    });

    test('une sélection persistée expirée est oubliée au chargement', () async {
      SharedPreferences.setMockInitialValues(
          {'coach.selected_id': CoachCatalog.lilithId});
      final s = CoachService(clock: () => _after);
      await s.load();
      expect(s.selectedCoachId, isNull);
      expect(s.selectedCoach, isNull);
    });

    test('ne débloque ni ne fait avancer aucun palier', () async {
      final s = CoachService(clock: () => _firstDay);
      await s.load();
      final unlocked = await s.syncFromTotalSeconds(1 << 30);
      expect(unlocked.map((c) => c.id), isNot(contains(CoachCatalog.lilithId)));
      expect(s.advancesTier(_lilith), isFalse);
      expect(s.currentTier, 7);
    });
  });

  group('Les coachs permanents sont inchangés', () {
    test('catalogue : les 7 entrées, champ à champ', () {
      final expected = <String, (String, int, bool, int)>{
        'coach_01_lina': ('Lina', 1, true, 0),
        'coach_02_helene': ('Hélène', 2, true, 3600),
        'coach_07_marc': ('Marc', 3, true, 5400),
        'coach_03_jade': ('Jade', 4, true, 10800),
        'coach_04_morgan': ('Morgan', 5, true, 25200),
        'coach_05_victoria': ('Victoria', 6, true, 54000),
        'coach_06_nyx': ('Nyx', 7, true, 90000),
      };
      expect(_permanent.map((c) => c.id), orderedEquals(expected.keys));
      for (final c in _permanent) {
        final (name, tier, principal, minSeconds) = expected[c.id]!;
        expect(c.name, name, reason: c.id);
        expect(c.tier, tier, reason: c.id);
        expect(c.isPrincipal, principal, reason: c.id);
        expect(c.requirements.minPlayerSeconds, minSeconds, reason: c.id);
        expect(c.portraitAsset, 'assets/career/coaches/portraits/${c.id}.png',
            reason: c.id);
      }
      expect(CoachCatalog.defaults.first.id, 'coach_01_lina');
    });

    for (final now in [_before, _firstDay, _lastDay, _after]) {
      for (final total in [0, 4000, 30000, 100000]) {
        test(
            'à $now, $total s joués : même service qu\'un catalogue sans Lilith',
            () async {
          SharedPreferences.setMockInitialValues({});
          final withLilith = CoachService(clock: () => now);
          await withLilith.load();
          final unlockedWith = await withLilith.syncFromTotalSeconds(total);

          SharedPreferences.setMockInitialValues({});
          final reference = CoachService(coaches: _permanent);
          await reference.load();
          final unlockedRef = await reference.syncFromTotalSeconds(total);

          expect(unlockedWith.map((c) => c.id),
              orderedEquals(unlockedRef.map((c) => c.id)));
          expect(withLilith.currentTier, reference.currentTier);
          expect(withLilith.currentTierPrincipal?.id,
              reference.currentTierPrincipal?.id);
          for (final c in _permanent) {
            expect(withLilith.isUnlocked(c), reference.isUnlocked(c),
                reason: c.id);
            expect(withLilith.advancesTier(c), reference.advancesTier(c),
                reason: c.id);
            expect(
              withLilith.evaluate(c, playerTotalSeconds: total),
              reference.evaluate(c, playerTotalSeconds: total),
              reason: c.id,
            );
            expect(withLilith.offeredUntil(c), isNull, reason: c.id);
          }
        });
      }
    }
  });

  group('CoachCatalogValidator', () {
    test('le catalogue livré est valide', () {
      expect(CoachCatalogValidator.validate(CoachCatalog.defaults), isEmpty);
    });

    test('un coach éphémère Principal est refusé', () {
      final principal = _lilith.withMeta(const CoachMeta(
        isPrincipal: true,
        tier: 8,
        requirements: CoachRequirement(minPlayerSeconds: 200000),
      ));
      final issues = CoachCatalogValidator.validate([..._permanent, principal]);
      expect(issues, hasLength(1));
      expect(issues.single, contains(CoachCatalog.lilithId));
    });
  });
}
