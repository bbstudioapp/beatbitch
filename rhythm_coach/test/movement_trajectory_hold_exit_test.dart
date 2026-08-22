import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/widgets/movement_animation.dart';
import 'package:beat_bitch/widgets/movement_trajectory_forecast.dart';

/// Sortie d'une tenue `full` vers un rythme `head`/`throat` à 120 BPM.
/// `elapsed` est l'horloge de séance extrapolée (`extrapolatedElapsed`) :
/// entre deux ticks du contrôleur elle dépasse la frontière annoncée alors
/// que `upcomingSteps`, figé avec les props du dernier tick, la contient
/// encore.
const _rythmeApresTenue = UpcomingMovementStep(
  mode: SessionMode.rhythm,
  from: Position.head,
  to: Position.throat,
  bpm: 120,
  startSecond: 10,
  transitionGap: Duration(milliseconds: 600),
);

double? _curseur({
  required Duration ageDeLaTenue,
  required Duration elapsed,
  required Duration depuisLeCalcul,
}) =>
    anchorAfterScrollForTest(
      mode: SessionMode.hold,
      from: Position.full,
      to: Position.full,
      beatDuration: const Duration(milliseconds: 1800),
      flipped: false,
      elapsedSinceCompute: depuisLeCalcul,
      frozenIdx: 2.5,
      frozenAt: DateTime.now().subtract(ageDeLaTenue),
      bridgeGap: const Duration(milliseconds: 600),
      elapsed: elapsed,
      upcomingSteps: const [_rythmeApresTenue],
    );

void main() {
  test(
      'un recalcul tombé après la frontière ne déplace pas le curseur en '
      'sortie de tenue', () {
    // Géométrie calculée 200 ms plus tôt, quand la frontière était encore
    // 50 ms dans le futur, puis défilée jusqu'à l'instant d'observation.
    final memoise = _curseur(
      ageDeLaTenue: const Duration(milliseconds: 1800),
      elapsed: const Duration(milliseconds: 9950),
      depuisLeCalcul: const Duration(milliseconds: 200),
    )!;

    // Même instant, mais la courbe vient d'être recalculée : la frontière est
    // désormais 150 ms dans le passé et le step n'est pas encore appliqué.
    final recalcule = _curseur(
      ageDeLaTenue: const Duration(milliseconds: 2000),
      elapsed: const Duration(milliseconds: 10150),
      depuisLeCalcul: Duration.zero,
    )!;

    expect(recalcule, closeTo(memoise, 0.05),
        reason: 'le recalcul repose le curseur ailleurs que là où la '
            'géométrie précédente l\'affichait');
  });
}
