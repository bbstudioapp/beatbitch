import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `_computeFutureBeats` (courbe de prévision pointillée) alterne
/// `beatDuration` et son complémentaire pour extrapoler un battement ancré
/// — cf. rapport chantier-aimant-étape-3. [complementaryBeatIntervalMs] est
/// la brique pure de ce calcul (le widget lui-même ne connaît pas `anchor`/
/// `ratio`, seulement l'intervalle réel déjà mesuré par le moteur).
void main() {
  test('cycle 2T moins l\'intervalle mesuré, ancré (200 bpm, ratio 3:1)', () {
    // T=300ms, 2T=600ms. Ancrage 3:1 (schéma de Manu) → long 450, court 150.
    expect(
      complementaryBeatIntervalMs(lastIntervalMs: 450, bpm: 200),
      150,
    );
    expect(
      complementaryBeatIntervalMs(lastIntervalMs: 150, bpm: 200),
      450,
    );
  });

  test(
      'sans ancrage : le complémentaire vaut l\'intervalle régulier '
      '(à 1ms d\'arrondi près)', () {
    // 90 bpm ne divise pas rond 60000 — cf. relecture adverse étapes 1-2 :
    // round(2T) peut différer de 2×round(T) d'1ms. Le complémentaire d'un
    // intervalle déjà régulier doit rester à 1ms de lui-même, pas exactement
    // égal à coup sûr.
    const bpm = 90;
    final regular = (60000 / bpm).round();
    final other =
        complementaryBeatIntervalMs(lastIntervalMs: regular, bpm: bpm);
    expect((other - regular).abs(), lessThanOrEqualTo(1));
  });

  test(
      'rampe + ancrage : BeatEvent porte le BPM interpolé du beat, dont '
      'complementaryBeatIntervalMs déduit 600 ms à 50 bpm — le BPM de '
      'départ (80) en déduisait −300 ms', () {
    final engine = BeepEngine();
    engine.configureBeatSourceForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      anchor: BeatAnchor.from,
      ratio: 3,
    );

    // `onBeat` livre synchrone (contrairement à `beatStream`, broadcast
    // asynchrone — cf. doc de `simulateBeatsForTest`).
    final events = <BeatEvent>[];
    engine.onBeat = events.add;
    // Rampe 80 → 50 bpm (ralentissement de 37,5 %, au-delà du quart qui
    // fait passer le complément sous zéro — cf. relecture) : un premier
    // beat tôt dans la rampe (bpm interpolé ≈ 80, le bpm de départ que le
    // widget affiche à son montage), un second en fin de rampe (bpm
    // interpolé tombé à 50).
    engine.emitOneBeatForTest(80);
    final secondInterval = engine.emitOneBeatForTest(50);

    final lastEvent = events.last;
    expect(lastEvent.bpm, 50.0,
        reason: 'BeatEvent doit porter le BPM interpolé de ce beat précis, '
            'pas le BPM de départ affiché au montage du widget');

    final paintedWithInterpolatedBpm = complementaryBeatIntervalMs(
      lastIntervalMs: secondInterval.inMilliseconds,
      bpm: lastEvent.bpm.round(),
    );
    expect(paintedWithInterpolatedBpm, 600,
        reason: 'doit correspondre exactement au court intervalle réel à '
            '50 bpm, pas à une valeur déduite du bpm de départ');

    final paintedWithMountBpm = complementaryBeatIntervalMs(
      lastIntervalMs: secondInterval.inMilliseconds,
      bpm: 80,
    );
    expect(paintedWithMountBpm, lessThan(0),
        reason: 'reproduit le défaut de la relecture §4 : sous le bpm de '
            'départ, le complément passe sous zéro et la courbe recule '
            'dans le temps');
  });

  test(
      'la courbe extrapolée alterne les deux intervalles du battement ancré '
      '— la brique pure était testée, son usage dans `_computeFutureBeats` '
      'ne l\'était pas', () {
    // Battement ancré à 200 bpm, ratio 3:1 : `T = 300 ms`, le moteur vient
    // de mesurer l'intervalle court (150 ms) et le suivant sera son
    // complémentaire dans le cycle `2T` (450 ms).
    final beats = computeFutureBeatsForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.mid,
      beatDuration: const Duration(milliseconds: 150),
      bpm: 200,
      flipped: false,
      lastBeatAt: DateTime.now(),
    );
    final gapsMs = [
      for (var i = 2; i < beats.length; i++)
        (beats[i].t - beats[i - 1].t) * 3000,
    ];
    expect(gapsMs.length, greaterThanOrEqualTo(4),
        reason: 'la fenêtre de 3 s doit contenir plusieurs battements');
    for (var i = 0; i < gapsMs.length; i++) {
      expect(gapsMs[i], closeTo(i.isEven ? 450 : 150, 2),
          reason: 'écart n°$i : la courbe doit alterner 450/150 ms, pas '
              'répéter l\'intervalle mesuré (150 ms)');
    }
  });

  testWidgets(
      'le widget monté retient bien le BPM interpolé du beat pour peindre '
      'sa courbe de prévision — round 3, réserve gênante : le fil '
      'BeatEvent.bpm → écran n\'était tenu par aucun test (en lui rendant '
      'son code d\'avant, `widget.bpm`, les 1039 tests restaient verts)',
      (tester) async {
    final engine = BeepEngine();
    engine.configureBeatSourceForTest(
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      anchor: BeatAnchor.from,
      ratio: 3,
    );

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MovementAnimation(
          mode: SessionMode.rhythm,
          from: Position.head,
          to: Position.throat,
          bpm:
              80, // BPM affiché au montage — ne doit plus servir après un beat.
          beepEngine: engine,
        ),
      ),
    ));
    await tester.pump();

    // Rampe 80 → 50 sur `beatStream` (broadcast asynchrone, contrairement à
    // `onBeat` synchrone) : chaque emit demande son `pump()` pour laisser
    // `_onBeatEvent` livrer et mettre à jour `_lastBeatBpm`.
    engine.emitOneBeatForTest(80);
    await tester.pump();
    engine.emitOneBeatForTest(50);
    await tester.pump();

    // `_PositionLadder` est privé au widget — accès par nom de champ public
    // (`bpm`) via `dynamic`, la seule voie pour lire l'état interne réel
    // plutôt que reconstruire la formule en parallèle du fix.
    final ladder = tester
        .widgetList(find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PositionLadder'))
        .single;
    expect((ladder as dynamic).bpm, 50,
        reason: 'doit porter le BPM interpolé du dernier BeatEvent (50), '
            'pas le BPM affiché au montage du widget (widget.bpm=80)');
  });
}
