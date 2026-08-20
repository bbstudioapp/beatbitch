import '../models/session.dart';
import '../models/session_step.dart';

/// Configuration effective d'un step à venir, résolue (mode/from/to/bpm
/// hérités des steps précédents quand `null` dans le JSON source — même
/// règle de résolution que `BeepEngine.applyStep`, dupliquée ici en lecture
/// seule pour l'affichage : `movement_animation.dart` n'a pas accès à l'état
/// interne du moteur audio).
class UpcomingMovementStep {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  /// Départ du step, en secondes depuis le début de la session.
  final int startSecond;

  const UpcomingMovementStep({
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
    required this.startSecond,
  });
}

/// Résout la suite des steps de bip (non text-only) qui commencent après
/// `afterSecond`, en héritant mode/from/to/bpm depuis la configuration
/// courante (`currentMode`..`currentBpm`) comme le ferait le moteur audio.
List<UpcomingMovementStep> resolveUpcomingMovementSteps({
  required List<SessionStep> steps,
  required SessionMode defaultMode,
  required int afterSecond,
  required SessionMode currentMode,
  required Position currentFrom,
  required Position? currentTo,
  required int currentBpm,
}) {
  final result = <UpcomingMovementStep>[];
  var mode = currentMode;
  var from = currentFrom;
  Position? to = currentTo;
  var bpm = currentBpm;

  for (final step in steps) {
    if (step.isTextOnly) continue;
    if (step.time <= afterSecond) continue;

    mode = step.mode ?? defaultMode;
    if (step.bpm != null) bpm = step.bpm!;
    if (mode == SessionMode.hold ||
        mode == SessionMode.beg ||
        mode == SessionMode.suckle) {
      if (step.to != null) from = step.to!;
    } else if (step.from != null) {
      from = step.from!;
    }
    to = step.to;

    result.add(UpcomingMovementStep(
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      startSecond: step.time,
    ));
  }
  return result;
}
