// Library autonome — value object `StepDraft` : brouillon de step
// interne au générateur, avant matérialisation en `SessionStep`.
//
// Extrait de `career_session_generator.dart` : type partagé entre le
// générateur, ses sous-systèmes (rules, pickers, dispatcher, …) et la
// facade exposée aux `ModeRules`. Sa sortie en library autonome est
// préalable à l'extraction de `gen_facade.dart` (les rules consomment
// `StepDraft` dans toutes leurs signatures).

import '../../../models/session.dart' show SessionMode;
import '../../../models/session_step.dart' show Position, SessionStep;

/// Brouillon de step interne au générateur, avant matérialisation en
/// `SessionStep` (il manque `time` et `text` qui sont décidés au push).
class StepDraft {
  final SessionMode mode;
  final int? bpm;

  /// BPM cible en fin de step pour les rampes intra-step (cf. doc de
  /// `SessionStep.bpmEnd`). Null = pas de rampe (BPM constant).
  final int? bpmEnd;
  final Position? from;
  final Position? to;
  final int? duration;

  /// Action enchaînée optionnelle. Émise comme step indépendant juste
  /// après le step parent par le générateur. Sert aux beg « guidés »
  /// (« dis X et continue à me sucer »). Le combo n'est jouable que si
  /// les deux composants passent `_isUnlocked` ET `humilCap`.
  final StepDraft? chainNext;

  const StepDraft({
    required this.mode,
    required this.bpm,
    required this.from,
    required this.to,
    required this.duration,
    this.bpmEnd,
    this.chainNext,
  });

  SessionStep copyWithTime(int t) => SessionStep(
        time: t,
        mode: mode,
        bpm: bpm,
        bpmEnd: bpmEnd,
        from: from,
        to: to,
        duration: duration,
      );
}
