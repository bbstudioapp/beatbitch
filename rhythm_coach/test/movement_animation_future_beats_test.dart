import 'package:beat_bitch/widgets/movement_animation.dart';
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
}
