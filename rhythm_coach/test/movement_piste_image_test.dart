import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';

const _asset = 'assets/courbe/piste_penis.png';
const _size = Size(400, 160);

final _png = ByteData.sublistView(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg=='));

/// Seule la piste est fournie par le test ; le reste (manifeste) vient du
/// bundle de flutter_test.
class _PisteBundle extends CachingAssetBundle {
  final Future<ByteData> Function() piste;

  _PisteBundle(this.piste);

  factory _PisteBundle.async(Completer<ByteData> gate) =>
      _PisteBundle(() => gate.future);

  factory _PisteBundle.presente() => _PisteBundle(() async => _png);

  /// Comme `PlatformAssetBundle` sous flutter_test quand le fichier manque.
  factory _PisteBundle.absenteLeveeSynchrone() =>
      _PisteBundle(() => throw FlutterError('Unable to load asset: $_asset'));

  /// Comme sur appareil : l'erreur passe par le Future.
  factory _PisteBundle.absenteLeveeAsynchrone() => _PisteBundle(
      () => Future<ByteData>.error(FlutterError('Unable to load asset')));

  @override
  Future<ByteData> load(String key) =>
      key == _asset ? piste() : rootBundle.load(key);
}

Widget host(AssetBundle bundle,
        {int rows = 6, SessionMode mode = SessionMode.hold}) =>
    DefaultAssetBundle(
      bundle: bundle,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: _size.width,
            height: _size.height,
            child: MovementAnimation(
              mode: mode,
              from: Position.mid,
              to: Position.mid,
              bpm: 60,
              positionRowCount: rows,
            ),
          ),
        ),
      ),
    );

final image = find.byWidgetPredicate((w) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == _asset);
final backdrop =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ShaftBackdrop');

List<double> levelLineYs(WidgetTester tester) => [
      for (final e in find
          .byWidgetPredicate((w) =>
              w is Container &&
              w.constraints == const BoxConstraints.tightFor(height: 1))
          .evaluate())
        tester.getCenter(find.byWidget(e.widget)).dy
    ]..sort();

/// Les niveaux occupent toujours les six places, affichés ou non.
double levelY(WidgetTester tester, Position p) {
  final top = tester.getTopLeft(find.byType(MovementAnimation)).dy;
  const box = 28.0;
  return top +
      box / 2 +
      p.index / (Position.values.length - 1) * (_size.height - box);
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets(
      'image présente : ni silhouette ni image avant la réponse, puis '
      'l\'image sans silhouette', (tester) async {
    final gate = Completer<ByteData>();
    await tester.pumpWidget(host(_PisteBundle.async(gate)));

    expect(backdrop, findsNothing, reason: 'premier frame, réponse attendue');
    expect(image, findsNothing);

    gate.complete(_png);
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(image, findsOneWidget);
    expect(backdrop, findsNothing);
  });

  testWidgets('image présente : au remontage, l\'image dès le premier frame',
      (tester) async {
    final gate = Completer<ByteData>();
    final bundle = _PisteBundle.async(gate);
    await tester.pumpWidget(host(bundle));
    gate.complete(_png);
    await settle(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host(bundle));

    expect(image, findsOneWidget, reason: 'premier frame du remontage');
    expect(backdrop, findsNothing);
  });

  for (final (nom, fabrique) in [
    ('levée synchrone', _PisteBundle.absenteLeveeSynchrone),
    ('levée asynchrone', _PisteBundle.absenteLeveeAsynchrone),
  ]) {
    testWidgets(
        'image absente ($nom) : repli sur la piste dessinée, dès le '
        'remontage', (tester) async {
      final bundle = fabrique();
      await tester.pumpWidget(host(bundle));
      expect(image, findsNothing);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(image, findsNothing);
      expect(backdrop, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(host(bundle));
      expect(backdrop, findsOneWidget, reason: 'premier frame du remontage');
    });
  }

  testWidgets(
      'image présente : calée sur bout et fond, centrée sur le curseur, '
      'à 0,85', (tester) async {
    await tester.pumpWidget(host(_PisteBundle.presente()));
    await settle(tester);

    final lineYs = levelLineYs(tester);
    expect(lineYs, hasLength(6));
    for (final p in Position.values) {
      expect(lineYs[p.index], closeTo(levelY(tester, p), 0.5),
          reason: 'ligne ${p.name} à sa place sur six');
    }

    final rect = tester.getRect(image);
    final scale = rect.height / 201;
    expect(rect.top + 3 * scale, closeTo(levelY(tester, Position.tip), 0.5),
        reason: 'bout du gland sur le niveau bout');
    expect(rect.top + 149 * scale, closeTo(levelY(tester, Position.full), 0.5),
        reason: 'jonction sur le niveau fond');

    final left = tester.getTopLeft(find.byType(MovementAnimation)).dx;
    expect(rect.center.dx, closeTo(left + 0.45 * _size.width, 0.5),
        reason: 'centrée sur la colonne du curseur');

    final opacity = tester.widget<Opacity>(find.byWidgetPredicate(
        (w) => w is Opacity && w.child is Image,
        description: 'Opacity de l\'image'));
    expect(opacity.opacity, 0.85);
  });

  for (final (mode, forme) in [
    (SessionMode.hold, '_OrbShape'),
    (SessionMode.hand, '_RingShape'),
    (SessionMode.lick, '_TongueShape'),
  ]) {
    testWidgets('curseur $forme : jamais écrasé par la boîte de niveau',
        (tester) async {
      await tester.pumpWidget(host(_PisteBundle.presente(), mode: mode));
      await settle(tester);

      final shape =
          find.byWidgetPredicate((w) => w.runtimeType.toString() == forme);
      final declared = tester
          .widget<Container>(
              find.descendant(of: shape, matching: find.byType(Container)))
          .constraints!;
      expect(
          tester.getSize(shape), Size(declared.maxWidth, declared.maxHeight));
    });
  }
}
