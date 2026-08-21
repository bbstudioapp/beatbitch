import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

void main() {
  group('_scrollBeats (via scrollBeatsForTest)', () {
    test(
      'entre deux calculs, les points futurs gardent leur idx et glissent '
      'de exactement deltaT',
      () {
        final scrolled = scrollBeatsForTest(
          raw: const [
            (t: 0.0, idx: 2.0, isAnchor: true),
            (t: 0.2, idx: 0.0, isAnchor: false),
            (t: 0.5, idx: 2.0, isAnchor: false),
          ],
          deltaT: 0.1,
        );

        expect(scrolled, isNotNull);
        final future = scrolled!.where((b) => !b.isAnchor).toList();
        expect(future, hasLength(2));
        expect(future[0].t, closeTo(0.1, 1e-9));
        expect(future[0].idx, 0.0, reason: 'idx inchangé, seul t glisse');
        expect(future[1].t, closeTo(0.4, 1e-9));
        expect(future[1].idx, 2.0, reason: 'idx inchangé, seul t glisse');
      },
    );

    test(
      'un point sorti de la fenêtre par la gauche (t décalé <= 0) '
      'disparaît de la trajectoire affichée',
      () {
        final scrolled = scrollBeatsForTest(
          raw: const [
            (t: 0.0, idx: 1.0, isAnchor: true),
            (t: 0.15, idx: 3.0, isAnchor: false),
            (t: 0.35, idx: 1.0, isAnchor: false),
            (t: 0.6, idx: 4.0, isAnchor: false),
          ],
          deltaT: 0.5,
        );

        expect(scrolled, isNotNull);
        // Seul le dernier point (t=0.6 -> 0.1) reste devant t=0 ; les 3
        // premiers (glissés à -0.5, -0.35, -0.15) ont disparu.
        final future = scrolled!.where((b) => !b.isAnchor).toList();
        expect(future, hasLength(1));
        expect(future.single.t, closeTo(0.1, 1e-9));
        expect(future.single.idx, 4.0);
      },
    );

    test(
      'le nouvel ancrage à t=0 interpole entre les 2 points qui '
      'l\'encadrent avec la même easing que le pont synthétique '
      '(Curves.easeInOutCubic, pas une interpolation linéaire)',
      () {
        // prev à t=-0.1 (idx tip=0), next à t=0.1 (idx full=4) après
        // décalage -> frac = 0.5 au point t=0.
        final scrolled = scrollBeatsForTest(
          raw: const [
            (t: 0.1, idx: 0.0, isAnchor: false),
            (t: 0.3, idx: 4.0, isAnchor: false),
          ],
          deltaT: 0.2,
        );

        expect(scrolled, isNotNull);
        final anchor = scrolled!.first;
        expect(anchor.isAnchor, isTrue);
        expect(anchor.t, 0.0);

        final eased = Curves.easeInOutCubic.transform(0.5);
        final expectedIdx = 0.0 + (4.0 - 0.0) * eased;
        expect(anchor.idx, closeTo(expectedIdx, 1e-9));
      },
    );

    test(
      'interpolation à frac=0.25 : easeInOutCubic diverge nettement du '
      'linéaire, la valeur observée doit suivre la courbe',
      () {
        // prev à t=-0.1 (idx=0), next à t=0.3 (idx=4) -> frac = 0.25.
        final scrolled = scrollBeatsForTest(
          raw: const [
            (t: 0.0, idx: 0.0, isAnchor: false),
            (t: 0.4, idx: 4.0, isAnchor: false),
          ],
          deltaT: 0.1,
        );

        expect(scrolled, isNotNull);
        final anchor = scrolled!.first;
        final eased = Curves.easeInOutCubic.transform(0.25);
        final expectedIdx = 0.0 + (4.0 - 0.0) * eased;
        const linearIdx = 0.0 + (4.0 - 0.0) * 0.25;
        expect(anchor.idx, closeTo(expectedIdx, 1e-9));
        expect((anchor.idx - linearIdx).abs(), greaterThan(0.1),
            reason: 'la valeur eased doit nettement différer du linéaire '
                'sur ce cas, sinon le test ne discrimine rien');
      },
    );

    test(
      'plus aucun point ne dépasse t=0 après décalage : scroll renvoie '
      'null (mémoïsation caduque, il faut recalculer)',
      () {
        final scrolled = scrollBeatsForTest(
          raw: const [
            (t: 0.0, idx: 0.0, isAnchor: true),
            (t: 0.2, idx: 3.0, isAnchor: false),
          ],
          deltaT: 0.3,
        );

        expect(scrolled, isNull);
      },
    );
  });

  group('_sameGeometry (via sameGeometryForTest) — clé de recalcul', () {
    GeometryKeyForTest baseKey({
      DateTime? lastBeatAt,
      List<UpcomingMovementStep> upcomingSteps = const [],
    }) =>
        (
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          beatDuration: const Duration(milliseconds: 500),
          flipped: false,
          lastBeatAt: lastBeatAt,
          frozenIdx: null,
          frozenAt: null,
          rowCount: 5,
          upcomingSteps: upcomingSteps,
        );

    test(
      'deux jeux de paramètres identiques (seul pulseT changerait d\'une '
      'frame à l\'autre, hors de cette clé) ne déclenchent aucun recalcul',
      () {
        final beatAt = DateTime(2026, 1, 1, 12, 0, 0);
        expect(
          sameGeometryForTest(
              baseKey(lastBeatAt: beatAt), baseKey(lastBeatAt: beatAt)),
          isTrue,
        );
      },
    );

    test(
      'un lastBeatAt neuf (donc un BeatEvent réel) déclenche un recalcul',
      () {
        final a = baseKey(lastBeatAt: DateTime(2026, 1, 1, 12, 0, 0));
        final b = baseKey(lastBeatAt: DateTime(2026, 1, 1, 12, 0, 0, 500));
        expect(sameGeometryForTest(a, b), isFalse);
      },
    );

    test(
      'upcomingSteps de même contenu mais dans une nouvelle instance de '
      'liste (rebuild à chaque frame côté parent) ne déclenche pas de '
      'recalcul',
      () {
        UpcomingMovementStep freshStep() => const UpcomingMovementStep(
              mode: SessionMode.hold,
              from: Position.full,
              to: Position.full,
              bpm: 60,
              startSecond: 12,
            );
        final a = baseKey(upcomingSteps: [freshStep()]);
        final b = baseKey(upcomingSteps: [freshStep()]);
        expect(identical(a.upcomingSteps, b.upcomingSteps), isFalse);
        expect(sameGeometryForTest(a, b), isTrue);
      },
    );
  });
}
