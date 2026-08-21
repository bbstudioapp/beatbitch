import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

/// Canvas espion : ne retient que ce que le peintre de trajectoire dessine
/// réellement — le tracé de la courbe et les pastilles par beat.
class RecordingCanvas implements Canvas {
  final List<Offset> circles = [];
  final List<Path> paths = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 400, height: 200, child: child)),
    );

/// Peint le peintre de trajectoire réellement monté par le widget (donc en
/// passant par le câblage complet) sur un canvas espion.
RecordingCanvas paintTrajectory(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((c) => c.painter)
      .whereType<CustomPainter>()
      .where((p) => p.runtimeType.toString().contains('TrajectoryPainter'))
      .toList();
  expect(painters, hasLength(1), reason: 'un seul peintre de trajectoire');
  final canvas = RecordingCanvas();
  painters.single.paint(canvas, const Size(400, 200));
  return canvas;
}

Future<RecordingCanvas> pumpAndPaint(
  WidgetTester tester, {
  required bool showTrajectoryDots,
}) async {
  await tester.pumpWidget(wrap(MovementAnimation(
    mode: SessionMode.rhythm,
    from: Position.head,
    to: Position.throat,
    bpm: 60,
    elapsed: const Duration(seconds: 12),
    showTrajectoryDots: showTrajectoryDots,
  )));
  await tester.pump(const Duration(milliseconds: 16));
  return paintTrajectory(tester);
}

void main() {
  testWidgets('debug : une pastille par beat à venir, en plus de la courbe',
      (tester) async {
    final canvas = await pumpAndPaint(tester, showTrajectoryDots: true);

    expect(canvas.paths, hasLength(1), reason: 'la courbe lissée est tracée');
    expect(canvas.circles.length, greaterThan(1),
        reason: 'plusieurs beats à venir portent une pastille');
  });

  testWidgets('séance : aucune pastille, la courbe reste tracée entière',
      (tester) async {
    final canvas = await pumpAndPaint(tester, showTrajectoryDots: false);

    expect(canvas.circles, isEmpty, reason: 'aucune pastille en séance');
    expect(canvas.paths, hasLength(1), reason: 'la courbe lissée est tracée');
    final bounds = canvas.paths.single.getBounds();
    expect(bounds.width, greaterThan(100),
        reason: 'la courbe court sur la fenêtre, elle n\'est pas tronquée');
    expect(bounds.height, greaterThan(0), reason: 'la courbe monte et descend');
  });

  testWidgets('séance : le curseur reste visible', (tester) async {
    await pumpAndPaint(tester, showTrajectoryDots: false);

    final cursors = tester
        .widgetList<Align>(find.byType(Align))
        .where((a) => a.alignment is Alignment)
        .where((a) => (a.alignment as Alignment).x != 0)
        .where((a) => ((a.alignment as Alignment).x - 0.92).abs() > 0.001);
    expect(cursors, isNotEmpty, reason: 'le curseur est toujours monté');
  });
}
