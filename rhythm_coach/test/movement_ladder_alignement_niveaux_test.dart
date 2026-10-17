import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/l10n/enum_labels.dart';
import 'package:beat_bitch/models/hold_move.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

class _CircleCanvas implements Canvas {
  final List<Offset> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<double> levelLineYs(WidgetTester tester) => [
      for (final e in find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.constraints == const BoxConstraints.tightFor(height: 1))
          .evaluate())
        tester.getCenter(find.byWidget(e.widget)).dy
    ]..sort();

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(body: SizedBox(width: 400, height: 160, child: child)),
    );

void main() {
  for (final rows in [5, 6]) {
    for (final p in Position.values.take(rows)) {
      testWidgets(
          'tenue sur ${p.name} ($rows niveaux) : curseur, libellé et ligne '
          'à la même hauteur', (tester) async {
        await tester.pumpWidget(wrap(MovementAnimation(
          mode: SessionMode.hold,
          from: p,
          to: p,
          bpm: 60,
          positionRowCount: rows,
        )));
        await tester.pump(const Duration(milliseconds: 16));

        final context = tester.element(find.byType(MovementAnimation));
        final labelY =
            tester.getCenter(find.text(p.localizedLabel(context))).dy;
        final cursorY = tester
            .getCenter(find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_OrbShape'))
            .dy;
        final lineYs = levelLineYs(tester);

        expect(lineYs, hasLength(rows));
        expect(labelY, closeTo(cursorY, 0.5));
        expect(lineYs[p.index], closeTo(cursorY, 0.5));
      });
    }
  }

  for (final rows in [5, 6]) {
    testWidgets(
        'rythme bout ↔ fond ($rows niveaux) : chaque pastille de la '
        'trajectoire tombe sur une ligne de niveau', (tester) async {
      await tester.pumpWidget(wrap(MovementAnimation(
        mode: SessionMode.rhythm,
        from: Position.tip,
        to: Position.full,
        bpm: 60,
        elapsed: const Duration(seconds: 12),
        showTrajectoryDots: true,
        positionRowCount: rows,
      )));
      await tester.pump(const Duration(milliseconds: 16));

      final trajectory = find.byWidgetPredicate((w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_TrajectoryPainter');
      final canvas = _CircleCanvas();
      tester
          .widget<CustomPaint>(trajectory)
          .painter!
          .paint(canvas, tester.getSize(trajectory));
      final top = tester.getTopLeft(trajectory).dy;
      final lineYs = levelLineYs(tester);

      expect(canvas.circles.map((c) => c.dy).toSet(), hasLength(2),
          reason: 'des pastilles au bout et au fond');
      for (final c in canvas.circles) {
        final y = top + c.dy;
        final nearest =
            lineYs.map((l) => (l - y).abs()).reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(0.5),
            reason: 'pastille à y=$y, lignes $lineYs');
      }
    });
  }

  testWidgets(
      'lick balls : la langue reste sur les ordonnées des lignes entre full '
      'et balls', (tester) async {
    const start = Duration(seconds: 10);
    Widget host(Duration e) => wrap(MovementAnimation(
          mode: SessionMode.hold,
          from: Position.full,
          to: Position.full,
          bpm: 60,
          elapsed: e,
          moves: const [
            HoldMove(kind: HoldMoveKind.lickBalls, at: 0.4, duration: 1.2),
          ],
          positionRowCount: 6,
        ));
    final tongue = find.byKey(const ValueKey('cursor-tongue'));
    await tester.pumpWidget(host(start));
    final clock = Stopwatch()..start();
    final gaps = <double>[];
    while (clock.elapsedMilliseconds < 1500) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpWidget(host(start + clock.elapsed));
      if (tongue.evaluate().isEmpty) continue;
      final lineYs = levelLineYs(tester);
      final a = (tester.widget<Align>(tongue).alignment as Alignment).y;
      final idx = (a + 1) / 2 * (lineYs.length - 1);
      final expected = lineYs.first + idx * (lineYs[1] - lineYs.first);
      final shape = find.descendant(
          of: tongue,
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_TongueShape'));
      gaps.add((tester.getCenter(shape).dy - expected).abs());
    }

    expect(gaps.length, greaterThan(10), reason: 'la langue a été vue');
    expect(gaps.every((g) => g < 0.5), isTrue, reason: 'écarts $gaps');
  });
}
