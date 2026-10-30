import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

/// Points de la courbe peinte : (t ∈ [0,1] de la fenêtre de 3 s, idx).
List<(double, double)> _curve(WidgetTester tester) {
  for (final cp in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    final p = cp.painter;
    if (p != null && p.runtimeType.toString() == '_TrajectoryPainter') {
      return [
        for (final b in (p as dynamic).beats as List)
          ((b as dynamic).t as double, b.idx as double),
      ];
    }
  }
  return const [];
}

const _gap = Duration(milliseconds: 600);

const _rhythm = UpcomingMovementStep(
  mode: SessionMode.rhythm,
  from: Position.throat,
  to: Position.head,
  bpm: 90,
  startSecond: 10,
  transitionGap: _gap,
);

const _later = UpcomingMovementStep(
  mode: SessionMode.rhythm,
  from: Position.tip,
  to: Position.mid,
  bpm: 60,
  startSecond: 40,
  transitionGap: _gap,
);

Widget _host(List<UpcomingMovementStep> upcoming) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: MovementAnimation(
            mode: SessionMode.hold,
            from: Position.full,
            to: Position.full,
            bpm: 60,
            beepEngine: BeepEngine(),
            stepSerial: 1,
            elapsed: const Duration(seconds: 8),
            paused: false,
            upcomingSteps: upcoming,
          ),
        ),
      ),
    );

/// Instant, en ms devant le curseur, où la courbe quitte la tenue.
int? _leavesHoldMs(WidgetTester tester) {
  final leave = _curve(tester)
      .skip(1)
      .where((p) => (p.$2 - Position.full.index).abs() > 0.01)
      .firstOrNull;
  return leave == null ? null : (leave.$1 * 3000).round();
}

void main() {
  testWidgets(
      'une frontière qui sort de la liste annoncée est oubliée même si la '
      'liste n\'est pas vide', (tester) async {
    // L'horloge de séance est figée : l'instant mural de la frontière recule
    // sans cesse, et seule une épingle survivante la garderait en avance.
    await tester.pumpWidget(_host([_rhythm, _later]));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_leavesHoldMs(tester), closeTo(2600, 300),
        reason: 'le scénario doit annoncer la frontière à 2 s + le gap');

    await tester.pumpWidget(_host([_later]));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1000)));

    await tester.pumpWidget(_host([_rhythm, _later]));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_leavesHoldMs(tester), closeTo(2600, 300),
        reason: 'la frontière revenue dans la liste repart de l\'horloge '
            'courante, pas de l\'épingle posée avant son retrait');
  });
}
