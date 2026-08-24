import '../models/session.dart';
import '../models/session_step.dart';
import 'beep_engine.dart';

/// Configuration de mouvement d'un step, une fois les champs absents
/// hérités de la configuration courante.
class ResolvedStepConfig {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  const ResolvedStepConfig({
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
  });
}

/// Seule implémentation de « quelle configuration ce step demande, sachant
/// celle en cours » : `BeepEngine.applyStep` l'applique au son,
/// `resolveUpcomingMovementSteps` la lit pour dessiner la trajectoire.
///
/// Pour hold/beg/suckle, la cible tenue est rangée dans `from` : les
/// consommateurs UI lisent `from` pour placer le curseur des modes statiques.
///
/// Ne couvre pas le relèvement aléatoire de `from` quand `from == to` en
/// rhythm/lick : ce tirage vit dans le moteur, l'affichage ne peut pas le
/// deviner.
ResolvedStepConfig resolveStepConfig({
  required SessionStep step,
  required SessionMode defaultMode,
  required Position currentFrom,
  required int currentBpm,
}) {
  final mode = step.mode ?? defaultMode;

  var bpm = currentBpm;
  if (step.bpm != null) {
    bpm = step.bpm!.clamp(BeepEngine.kMinBpm, BeepEngine.kMaxBpm);
  }

  var from = currentFrom;
  if (mode == SessionMode.hold ||
      mode == SessionMode.beg ||
      mode == SessionMode.suckle) {
    if (step.to != null) from = step.to!;
  } else if (step.from != null) {
    from = step.from!;
  }

  return ResolvedStepConfig(mode: mode, from: from, to: step.to, bpm: bpm);
}
