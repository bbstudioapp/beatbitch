import 'dart:async';

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

class _Engine extends BeepEngine {
  final StreamController<BeatEvent> beats =
      StreamController<BeatEvent>.broadcast();
  @override
  Stream<BeatEvent> get beatStream => beats.stream;
}

const _start = 10;
const _gap = Duration(milliseconds: 600);
const _bpm = 90;
const _beatMs = 60000 ~/ _bpm;

/// Une séance qui passe d'un step courant à [next] à `_start` s : la courbe
/// quitte le step courant pour la première fois quand [leaves] est vrai.
class _Case {
  final SessionMode mode;
  final Position from;
  final Position to;
  final UpcomingMovementStep next;
  final bool Function(double idx) leaves;
  const _Case(this.mode, this.from, this.to, this.next, this.leaves);
}

final _holdThenRhythm = _Case(
  SessionMode.hold,
  Position.full,
  Position.full,
  const UpcomingMovementStep(
    mode: SessionMode.rhythm,
    from: Position.throat,
    to: Position.head,
    bpm: _bpm,
    startSecond: _start,
    transitionGap: _gap,
  ),
  (idx) => (idx - Position.full.index).abs() > 0.01,
);

final _rhythmThenHold = _Case(
  SessionMode.rhythm,
  Position.head,
  Position.tip,
  const UpcomingMovementStep(
    mode: SessionMode.hold,
    from: Position.full,
    to: Position.full,
    bpm: 60,
    startSecond: _start,
    transitionGap: _gap,
  ),
  (idx) => idx > Position.mid.index,
);

Widget _host(_Case k, _Engine engine,
        {required Duration elapsed, required bool paused}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 200,
          child: MovementAnimation(
            mode: k.mode,
            from: k.from,
            to: k.to,
            bpm: _bpm,
            beepEngine: engine,
            stepSerial: 1,
            elapsed: elapsed,
            paused: paused,
            upcomingSteps: [k.next],
          ),
        ),
      ),
    );

/// Séance à 8 s, mise en pause 1 s plus tard pendant [pauseMs] de temps
/// mural, puis 800 ms de reprise. Comme le moteur, un rythme émet son premier
/// bip de reprise avant que l'écran ne lève la pause. Rend l'instant de séance
/// où la courbe quitte le step courant juste avant la pause et, pendant et
/// après la pause, les images où elle le quitte à plus de 150 ms de cet
/// instant.
Future<(int?, Map<String, List<String>>)> _replay(
    WidgetTester tester, _Case k, int pauseMs) async {
  const startElapsed = Duration(milliseconds: 8000);
  const pauseAtMs = 1000;
  final resumeAtMs = pauseAtMs + pauseMs;
  final endMs = resumeAtMs + 800;
  final engine = _Engine();
  final wall = Stopwatch();
  Duration sessionNow() {
    final ms = wall.elapsedMilliseconds;
    final played = ms < pauseAtMs
        ? ms
        : ms < resumeAtMs
            ? pauseAtMs
            : ms - (resumeAtMs - pauseAtMs);
    return startElapsed + Duration(milliseconds: played);
  }

  var beatsSent = 0;
  var beatOrigin = startElapsed;
  var beatsBeforeOrigin = 0;
  Future<void> sendDueBeats() async {
    final since = (sessionNow() - beatOrigin).inMilliseconds;
    final due = beatsBeforeOrigin + since ~/ _beatMs + 1;
    var sent = false;
    while (k.mode == SessionMode.rhythm && beatsSent < due) {
      engine.beats.add(BeatEvent(
        mode: SessionMode.rhythm,
        position: beatsSent.isEven ? k.to : k.from,
        from: k.from,
        to: k.to,
        nextInterval: const Duration(milliseconds: _beatMs),
        bpm: _bpm.toDouble(),
      ));
      beatsSent++;
      sent = true;
    }
    if (sent) {
      await tester.pump();
      await tester.pump();
    }
  }

  await tester
      .pumpWidget(_host(k, engine, elapsed: startElapsed, paused: false));
  wall.start();

  int? referenceMs;
  final drifts = {'pause': <String>[], 'après': <String>[]};
  var lastTickMs = -1000;
  var tickPaused = false;
  while (wall.elapsedMilliseconds < endMs) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 16)));
    final ms = wall.elapsedMilliseconds;
    final paused = ms >= pauseAtMs && ms < resumeAtMs;
    if (tickPaused && !paused) {
      beatOrigin = sessionNow();
      beatsBeforeOrigin = beatsSent;
    }
    if (!paused) await sendDueBeats();
    if (ms - lastTickMs >= 200 || paused != tickPaused) {
      lastTickMs = ms;
      tickPaused = paused;
      await tester
          .pumpWidget(_host(k, engine, elapsed: sessionNow(), paused: paused));
    } else {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final session = sessionNow().inMilliseconds;
    final c = _curve(tester);
    // Le curseur quitte le step dès la frontière franchie : seuls les points
    // de la trajectoire situent la frontière.
    final leave = c.skip(1).where((p) => k.leaves(p.$2)).firstOrNull;
    if (leave == null) continue;
    final leaveMs = session + (leave.$1 * 3000).round();
    if (ms < pauseAtMs) {
      referenceMs = leaveMs;
      continue;
    }
    final drift = leaveMs - referenceMs!;
    if (drift.abs() > 150) {
      drifts[ms < resumeAtMs ? 'pause' : 'après']!
          .add('${ms}ms (séance ${session}ms) : la courbe quitte le step à '
              '${leaveMs}ms au lieu de ${referenceMs}ms '
              '(${drift > 0 ? '+' : ''}${drift}ms)');
    }
  }
  await engine.beats.close();
  return (referenceMs, drifts);
}

void main() {
  for (final (name, k, pauseMs) in [
    ('tenue → rythme, pause longue', _holdThenRhythm, 3000),
    ('rythme → tenue, pause longue', _rhythmThenHold, 3000),
    ('tenue → rythme, pause courte', _holdThenRhythm, 400),
  ]) {
    testWidgets(
        '$name puis reprise : la courbe situe le step suivant au même instant '
        'de séance qu\'avant la pause', (tester) async {
      final (referenceMs, d) = await _replay(tester, k, pauseMs);
      // Le scénario est valide : avant la pause, la courbe quitte le step
      // courant vers l'instant où le moteur jouera le suivant.
      expect(referenceMs, closeTo(_start * 1000 + _gap.inMilliseconds, 400));
      expect(d['après'], isEmpty, reason: d['après']!.join('\n'));
      expect(d['pause'], isEmpty, reason: d['pause']!.join('\n'));
    });
  }
}
