import '../models/session.dart';
import '../models/session_step.dart';
import '../services/beep_engine.dart';
import '../services/step_resolution.dart';

/// Configuration effective d'un step à venir, résolue (mode/from/to/bpm
/// hérités des steps précédents quand `null` dans le JSON source, par
/// `resolveStepConfig` — la même règle que `BeepEngine.applyStep` applique
/// au son).
class UpcomingMovementStep {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  /// Départ du step, en secondes depuis le début de la session.
  final int startSecond;

  /// Pause que `BeepEngine.applyStep` insère avant de démarrer ce step,
  /// lue via `BeepEngine.transitionGap` — pas dupliquée. Défaut zéro pour
  /// les `UpcomingMovementStep` construits hors résolveur.
  final Duration transitionGap;

  const UpcomingMovementStep({
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    required this.startSecond,
    this.transitionGap = Duration.zero,
  });
}

/// Résout la suite des steps de bip (non text-only) qui commencent après
/// `afterSecond`, en héritant mode/from/bpm depuis la configuration courante
/// (`currentMode`..`currentBpm`) comme le ferait le moteur audio. `to` n'est
/// jamais hérité : chaque step porte le sien, ou aucun.
List<UpcomingMovementStep> resolveUpcomingMovementSteps({
  required List<SessionStep> steps,
  required SessionMode defaultMode,
  required int afterSecond,
  required SessionMode currentMode,
  required Position currentFrom,
  required int currentBpm,
}) {
  final result = <UpcomingMovementStep>[];
  var mode = currentMode;
  var from = currentFrom;
  var bpm = currentBpm;

  for (final step in steps) {
    if (step.isTextOnly) continue;
    if (step.time <= afterSecond) continue;

    final previousMode = mode;
    final resolved = resolveStepConfig(
      step: step,
      defaultMode: defaultMode,
      currentFrom: from,
      currentBpm: bpm,
    );
    mode = resolved.mode;
    from = resolved.from;
    bpm = resolved.bpm;
    final to = resolved.to;

    result.add(UpcomingMovementStep(
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      startSecond: step.time,
      transitionGap: BeepEngine.transitionGap(
        incoming: mode,
        previous: previousMode,
        incomingTo: to,
      ),
    ));
  }
  return result;
}
