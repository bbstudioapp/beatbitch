import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/hold_move.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

double? _cursorY(WidgetTester tester) {
  final aligns = tester.widgetList<Align>(find.byType(Align)).toList();
  for (final a in aligns.reversed) {
    final al = a.alignment;
    if (al is Alignment && al.x != 0 && (al.x - 0.92).abs() > 0.001) {
      return al.y;
    }
  }
  return null;
}

Widget _host(Duration elapsed,
        {Position hold = Position.throat,
        int rows = 5,
        List<HoldMove> moves = const [
          HoldMove(kind: HoldMoveKind.excursion, at: 0.4, to: Position.tip),
        ]}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: MovementAnimation(
            mode: SessionMode.hold,
            from: hold,
            to: hold,
            bpm: 60,
            elapsed: elapsed,
            moves: moves,
            positionRowCount: rows,
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'pendant une tenue gorge, le curseur fait l\'aller-retour au bout aux '
      'instants du moteur', (tester) async {
    const start = Duration(seconds: 10);
    await tester.pumpWidget(_host(start));
    final clock = Stopwatch()..start();
    final samples = <(int, double)>[];
    while (clock.elapsedMilliseconds < 2200) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pumpWidget(_host(start + clock.elapsed));
      samples.add((clock.elapsedMilliseconds, _cursorY(tester)!));
    }
    final leg = excursionLeg(Position.throat, Position.tip).inMilliseconds;
    double at(int ms) => samples
        .reduce((a, b) => (a.$1 - ms).abs() < (b.$1 - ms).abs() ? a : b)
        .$2;

    // 5 rangées : gorge = +0,5, bout = -1.
    expect(at(200), closeTo(0.5, 0.05), reason: 'immobile avant le départ');
    expect(at(400 + leg), closeTo(-1, 0.15),
        reason: 'au bout au moment du bip d\'arrivée');
    expect(at(400 + 2 * leg + 300), closeTo(0.5, 0.05),
        reason: 'revenu en gorge après le bip de retour');
    final minY = samples.map((s) => s.$2).reduce((a, b) => a < b ? a : b);
    expect(minY, lessThan(-0.85), reason: 'monte vraiment jusqu\'au bout');
  });

  test('la courbe annonce l\'aller-retour d\'une tenue à venir', () {
    // Rythme en cours, tenue gorge dans 0,4 s : départ de l'aller-retour à
    // 0,4 + 0,6 (gap) + 0,3 = 1,3 s, arrivée au bout à 1,3 s + trajet.
    final leg = excursionLeg(Position.throat, Position.tip).inMilliseconds;
    final beats = computeFutureBeatsForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      beatDuration: const Duration(milliseconds: 500),
      flipped: false,
      lastBeatAt: DateTime.now(),
      elapsed: const Duration(milliseconds: 9600),
      upcomingSteps: const [
        UpcomingMovementStep(
          mode: SessionMode.hold,
          from: Position.throat,
          to: Position.throat,
          bpm: 60,
          startSecond: 10,
          transitionGap: Duration(milliseconds: 600),
          moves: [
            HoldMove(kind: HoldMoveKind.excursion, at: 0.3, to: Position.tip),
          ],
        ),
      ],
    );
    final tip = beats.where((b) => b.idx == Position.tip.index.toDouble());
    expect(tip, hasLength(1), reason: 'un seul point au bout');
    expect(tip.single.t * 3000, closeTo(1300 + leg, 30));
    final afterTip = beats.where((b) => b.t > tip.single.t).first;
    expect(afterTip.idx, Position.throat.index.toDouble());
    expect(afterTip.t * 3000, closeTo(1300 + 2 * leg, 30));
  });

  testWidgets('pendant une rafale, le curseur vibre autour de la gorge',
      (tester) async {
    const start = Duration(seconds: 10);
    const micro = [HoldMove(kind: HoldMoveKind.micro, at: 0.3, duration: 1.5)];
    await tester.pumpWidget(_host(start, moves: micro));
    final clock = Stopwatch()..start();
    final ys = <(int, double)>[];
    while (clock.elapsedMilliseconds < 2400) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpWidget(_host(start + clock.elapsed, moves: micro));
      ys.add((clock.elapsedMilliseconds, _cursorY(tester)!));
    }
    // 5 rangées : un cran = 0,5 en Align ; sommet = gorge − 0,4 cran.
    final during = ys.where((e) => e.$1 > 350 && e.$1 < 1750).map((e) => e.$2);
    final lows = during.where((y) => y < 0.5 - 0.15).length;
    final highs = during.where((y) => y > 0.5 - 0.05).length;
    expect(lows, greaterThan(5), reason: 'monte plusieurs fois');
    expect(highs, greaterThan(5), reason: 'et revient entre deux');
    expect(during.reduce((a, b) => a < b ? a : b), greaterThan(0.5 - 0.25),
        reason: 'reste un petit mouvement, pas un aller-retour');
    final after = ys.where((e) => e.$1 > 2100).map((e) => e.$2);
    expect(after.every((y) => (y - 0.5).abs() < 0.03), isTrue,
        reason: 'immobile après la rafale');
  });

  testWidgets(
      'pendant un lick balls, une langue bleue fait full ↔ balls, le curseur '
      'reste à full', (tester) async {
    const start = Duration(seconds: 10);
    const lick = [
      HoldMove(kind: HoldMoveKind.lickBalls, at: 0.4, duration: 1.2),
    ];
    final tongue = find.byKey(const ValueKey('cursor-tongue'));
    final curve = find.byKey(const ValueKey('tongue-curve'));
    Widget host(Duration e) =>
        _host(e, hold: Position.full, rows: 6, moves: lick);
    await tester.pumpWidget(host(start));
    final clock = Stopwatch()..start();
    final seen = <(int, double?, bool, double)>[];
    while (clock.elapsedMilliseconds < 2200) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpWidget(host(start + clock.elapsed));
      final t = tongue.evaluate();
      seen.add((
        clock.elapsedMilliseconds,
        t.isEmpty
            ? null
            : ((t.single.widget as Align).alignment as Alignment).y,
        curve.evaluate().isNotEmpty,
        _cursorY(tester)!,
      ));
    }
    // 6 rangées : full = 0,6, balls = 1.
    Iterable<(int, double?, bool, double)> at(bool Function(int) w) =>
        seen.where((e) => w(e.$1));
    expect(at((ms) => ms < 350).every((e) => e.$2 == null), isTrue,
        reason: 'pas de langue avant');
    expect(at((ms) => ms < 350).every((e) => e.$3), isTrue,
        reason: 'mais sa courbe est annoncée');
    final during = at((ms) => ms > 450 && ms < 1550).map((e) => e.$2);
    expect(during.every((y) => y != null), isTrue, reason: 'langue pendant');
    final ys = during.cast<double>();
    expect(ys.where((y) => y > 0.9).length, greaterThan(3),
        reason: 'descend jusqu\'à balls');
    expect(ys.where((y) => y < 0.7).length, greaterThan(3),
        reason: 'et remonte à full entre deux coups');
    expect(ys.every((y) => y >= 0.59 && y <= 1.01), isTrue,
        reason: 'entre full et balls seulement');
    expect(at((ms) => ms > 1700).every((e) => e.$2 == null && !e.$3), isTrue,
        reason: 'plus rien après');
    expect(seen.every((e) => (e.$4 - 0.6).abs() < 0.01), isTrue,
        reason: 'la langue ne déplace pas le curseur de la tenue');
  });
}
