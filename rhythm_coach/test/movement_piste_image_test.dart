import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

const _asset = 'assets/courbe/piste_penis.png';

// L'image vient de R2 et manque en CI : selon qu'elle est là ou non, ce test
// garde le calage de l'image ou le repli sur la piste dessinée.
void main() {
  testWidgets('piste : image calée sur bout et fond si présente, sinon repli',
      (tester) async {
    final available = await tester.runAsync(() => Future.sync(
          () => rootBundle.load(_asset),
        ).then((_) => true, onError: (_) => false));

    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 160,
          child: MovementAnimation(
            mode: SessionMode.hold,
            from: Position.mid,
            to: Position.mid,
            bpm: 60,
            positionRowCount: 6,
          ),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));

    expect(tester.takeException(), isNull);
    final image = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == _asset);
    final backdrop = find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_ShaftBackdrop');

    if (available != true) {
      expect(image, findsNothing);
      expect(backdrop, findsOneWidget);
      return;
    }
    expect(backdrop, findsNothing);
    final lineYs = [
      for (final e in find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.constraints == const BoxConstraints.tightFor(height: 1))
          .evaluate())
        tester.getCenter(find.byWidget(e.widget)).dy
    ]..sort();
    final rect = tester.getRect(image);
    final scale = rect.height / 201;
    expect(rect.top + 3 * scale, closeTo(lineYs[Position.tip.index], 0.5),
        reason: 'bout du gland sur le niveau bout');
    expect(rect.top + 149 * scale, closeTo(lineYs[Position.full.index], 0.5),
        reason: 'jonction sur le niveau fond');
  });
}
