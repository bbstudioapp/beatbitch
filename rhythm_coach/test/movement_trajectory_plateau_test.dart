import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

const _windowMs = 3000.0;

List<({double t, double idx, bool isAnchor})> _plateau({
  required SessionMode mode,
  required Duration beatDuration,
  required int ageMs,
}) =>
    computeFutureBeatsForTest(
      mode: mode,
      from: Position.full,
      to: Position.full,
      beatDuration: beatDuration,
      flipped: false,
      frozenIdx: Position.tip.index.toDouble(),
      frozenAt: DateTime.now().subtract(Duration(milliseconds: ageMs)),
      bridgeGap: const Duration(milliseconds: 600),
    );

class RecordingCanvas implements Canvas {
  final List<Offset> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<List<double>> _dotXs(WidgetTester tester, SessionMode mode) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 200,
        child: MovementAnimation(
          mode: mode,
          from: Position.full,
          to: Position.full,
          bpm: 60,
          showTrajectoryDots: true,
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 16));
  final painter = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<CustomPainter>()
      .singleWhere(
          (p) => p.runtimeType.toString().contains('TrajectoryPainter'));
  final canvas = RecordingCanvas();
  painter.paint(canvas, const Size(400, 200));
  return canvas.circles.map((c) => c.dx).toList()..sort();
}

void main() {
  group(
      'plateau (hold/beg/suckle/breath/biffle) : une série, pas un point figé',
      () {
    for (final (mode, beatMs) in const [
      (SessionMode.hold, 1800),
      (SessionMode.suckle, 1200),
      (SessionMode.biffle, 1000),
      (SessionMode.breath, 3200),
    ]) {
      test('$mode : des points à intervalle régulier sur la position tenue',
          () {
        final beats = _plateau(
          mode: mode,
          beatDuration: Duration(milliseconds: beatMs),
          ageMs: 25000,
        );
        final points = beats.where((b) => !b.isAnchor).toList();

        expect(points.length, greaterThanOrEqualTo(2),
            reason: 'une tenue longue porte une série de points, pas un seul');
        expect(points.last.t * _windowMs, greaterThanOrEqualTo(_windowMs),
            reason: 'la série court jusqu\'au bout de la fenêtre : la courbe '
                'ne s\'arrête pas sur un point figé');
        expect(
          points.every((p) => p.idx == Position.full.index.toDouble()),
          isTrue,
          reason: 'la tenue ne bouge pas de sa position',
        );
        for (var i = 1; i < points.length; i++) {
          expect(
            (points[i].t - points[i - 1].t) * _windowMs,
            closeTo(beatMs.toDouble(), 40),
            reason: 'aucun trou plus large que le battement du mode',
          );
        }
      });
    }

    test(
      'deux recalculs successifs posent les points aux mêmes instants : '
      'un plateau ne se recrée pas ailleurs',
      () {
        const beatMs = 1800;
        const shiftMs = 400;
        final early = _plateau(
          mode: SessionMode.hold,
          beatDuration: const Duration(milliseconds: beatMs),
          ageMs: 25000,
        );
        final late = _plateau(
          mode: SessionMode.hold,
          beatDuration: const Duration(milliseconds: beatMs),
          ageMs: 25000 + shiftMs,
        );

        // Instants ramenés sur l'horloge du premier calcul : `late` est
        // calculé `shiftMs` plus tard, ses `t` sont donc décalés d'autant.
        List<double> absMs(
                List<({double t, double idx, bool isAnchor})> b, double at) =>
            [for (final p in b.where((p) => !p.isAnchor)) p.t * _windowMs + at];

        final earlyAbs = absMs(early, 0);
        final lateAbs = absMs(late, shiftMs.toDouble())
            .where((ms) => ms <= earlyAbs.last)
            .toList();

        expect(lateAbs, isNotEmpty,
            reason: 'les deux calculs doivent avoir des points comparables');
        for (final ms in lateAbs) {
          expect(
            earlyAbs.any((e) => (e - ms).abs() <= 50),
            isTrue,
            reason: 'point du recalcul à ${ms.round()} ms absent du calcul '
                'initial ($earlyAbs) : la grille du plateau a bougé',
          );
        }
      },
    );
  });

  testWidgets(
    'câblage : le mode pilote l\'intervalle des pastilles (suckle plus '
    'serré que hold, dans le rapport de leurs battements)',
    (tester) async {
      // Le dernier écart seulement : le premier point d'un plateau est
      // l'arrivée du pont, dont la distance au précédent dépend de l'instant
      // du rendu.
      double lastGap(List<double> xs) {
        expect(xs.length, greaterThanOrEqualTo(2),
            reason: 'plusieurs pastilles sur un plateau');
        return xs.last - xs[xs.length - 2];
      }

      final holdGap = lastGap(await _dotXs(tester, SessionMode.hold));
      final suckleGap = lastGap(await _dotXs(tester, SessionMode.suckle));

      expect(holdGap / suckleGap, closeTo(1800 / 1200, 0.15),
          reason: 'les pastilles suivent `_durationFor(mode, bpm)` du step '
              'monté, pas un intervalle indépendant du mode');
    },
  );
}
