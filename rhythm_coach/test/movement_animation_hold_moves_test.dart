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

Widget _host(Duration elapsed) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: MovementAnimation(
            mode: SessionMode.hold,
            from: Position.throat,
            to: Position.throat,
            bpm: 60,
            elapsed: elapsed,
            moves: const [
              HoldMove(kind: HoldMoveKind.excursion, at: 0.4, to: Position.tip),
            ],
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
}
