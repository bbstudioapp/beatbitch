import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

/// Passage tenue gorge → rythme head/throat rejoué à la cadence de l'app :
/// ticks de 200 ms, step appliqué au tick qui suit son instant, premier bip
/// réel du rythme sur `to` à la fin du gap de 600 ms, puis bips réguliers.
class _Engine extends BeepEngine {
  final StreamController<BeatEvent> beats =
      StreamController<BeatEvent>.broadcast();
  @override
  Stream<BeatEvent> get beatStream => beats.stream;
}

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

const _bpm = 90;
const _start = 10;
const _rythme = UpcomingMovementStep(
  mode: SessionMode.rhythm,
  from: Position.head,
  to: Position.throat,
  bpm: _bpm,
  startSecond: _start,
  transitionGap: Duration(milliseconds: 600),
);

Widget _host({
  required _Engine engine,
  required bool applied,
  required Duration elapsed,
}) {
  // Comme l'écran : steps strictement après la seconde entière courante.
  final upcoming = applied || elapsed.inSeconds >= _start
      ? const <UpcomingMovementStep>[]
      : const [_rythme];
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 200,
        child: MovementAnimation(
          mode: applied ? SessionMode.rhythm : SessionMode.hold,
          from: applied ? Position.head : Position.throat,
          to: Position.throat,
          bpm: applied ? _bpm : 60,
          beepEngine: engine,
          stepSerial: applied ? 2 : 1,
          elapsed: elapsed,
          upcomingSteps: upcoming,
        ),
      ),
    ),
  );
}

/// Rejoue le passage. [deferTicks] : nombre de ticks pendant lesquels le
/// contrôleur reporte le step parce que la voix parle encore — il recule
/// alors l'horloge logique d'un tick à chaque report
/// (`SessionController._checkSteps`, `_timelineOffset -= _tickInterval`).
Future<List<String>> _replay(WidgetTester tester,
    {required int deferTicks}) async {
  {
    final engine = _Engine();
    const startElapsed = Duration(milliseconds: 8800);
    final wall = Stopwatch()..start();
    var offset = Duration.zero;
    var deferred = 0;
    Duration sessionNow() => startElapsed + wall.elapsed + offset;

    var applied = false;
    var tickElapsed = startElapsed;
    DateTime? appliedAt;
    var beatsSent = 0;
    await tester.pumpWidget(
        _host(engine: engine, applied: false, elapsed: tickElapsed));

    final trace = StringBuffer();
    var lastTickMs = 0;
    final frames = <(int, double, List<(double, double)>)>[];
    while (wall.elapsedMilliseconds < 3600) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 16)));
      final ms = wall.elapsedMilliseconds;
      var rebuild = false;
      if (ms - lastTickMs >= 200) {
        lastTickMs = ms;
        tickElapsed = sessionNow();
        rebuild = true;
        if (!applied && tickElapsed.inMilliseconds >= _start * 1000) {
          if (deferred < deferTicks) {
            deferred++;
            offset -= const Duration(milliseconds: 200);
            tickElapsed = sessionNow();
          } else {
            applied = true;
            appliedAt = DateTime.now();
          }
        }
      }
      if (applied && appliedAt != null) {
        final since = DateTime.now().difference(appliedAt).inMilliseconds;
        final due = since >= 600 ? 1 + (since - 600) * _bpm ~/ 60000 : 0;
        while (beatsSent < due) {
          engine.beats.add(BeatEvent(
            mode: SessionMode.rhythm,
            position: beatsSent.isEven ? Position.throat : Position.head,
            from: Position.head,
            to: Position.throat,
            nextInterval: const Duration(milliseconds: 60000 ~/ _bpm),
            bpm: _bpm.toDouble(),
          ));
          beatsSent++;
        }
      }
      if (rebuild) {
        await tester.pumpWidget(
            _host(engine: engine, applied: applied, elapsed: tickElapsed));
      } else {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final y = _cursorY(tester)!;
      final c = _curve(tester);
      frames.add((ms, y, c));
      trace.writeln('$ms ${applied ? 'R' : 'H'} b=$beatsSent '
          'y=${y.toStringAsFixed(3)} '
          '${c.take(6).map((p) => '${(p.$1 * 3000).round()}:'
              '${p.$2.toStringAsFixed(2)}').join(' ')}');
    }
    final tracePath = Platform.environment['TRACE'];
    if (tracePath != null) File(tracePath).writeAsStringSync('$trace');

    // Une géométrie stable fait glisser chaque point futur vers la gauche au
    // rythme de l'horloge : son instant absolu (ms + t·3000) ne bouge pas.
    // Un « rembobinage » : le premier point futur change d'instant absolu.
    final events = <String>[];
    for (var i = 1; i < frames.length; i++) {
      final (ms0, _, c0) = frames[i - 1];
      final (ms1, _, c1) = frames[i];
      final f0 = c0.where((p) => p.$1 > 0.02).toList();
      final f1 = c1.where((p) => p.$1 > 0.02).toList();
      if (f0.isEmpty || f1.isEmpty) continue;
      final abs0 = f0.map((p) => ms0 + p.$1 * 3000).toList();
      final abs1 = f1.first.$1 * 3000 + ms1;
      final nearest =
          abs0.reduce((a, b) => (a - abs1).abs() < (b - abs1).abs() ? a : b);
      final shift = abs1 - nearest;
      if (shift.abs() > 60) {
        events.add('${ms1}ms point décalé de ${shift.round()}ms');
      }
    }
    for (var i = 2; i < frames.length; i++) {
      final d1 = frames[i - 1].$2 - frames[i - 2].$2;
      final d2 = frames[i].$2 - frames[i - 1].$2;
      if (d1.abs() > 0.08 && d2.abs() > 0.08 && d1.sign != d2.sign) {
        events.add('${frames[i].$1}ms curseur ${d1.toStringAsFixed(2)} '
            'puis ${d2.toStringAsFixed(2)}');
      }
    }
    await engine.beats.close();
    return events;
  }
}

void main() {
  testWidgets('tenue gorge → rythme head/throat : la courbe ne rembobine pas',
      (tester) async {
    final events = await _replay(tester, deferTicks: 0);
    expect(events.length, lessThanOrEqualTo(1), reason: events.join('\n'));
  });

  testWidgets(
      'step reporté pendant que la voix parle : la courbe ne rembobine pas '
      'à chaque tick', (tester) async {
    final events = await _replay(tester, deferTicks: 4);
    expect(events.length, lessThanOrEqualTo(1), reason: events.join('\n'));
  });
}
