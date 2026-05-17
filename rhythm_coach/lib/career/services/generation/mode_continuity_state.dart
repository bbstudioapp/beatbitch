// Library autonome — value object `ModeContinuityState` : snapshot du
// tracking de continuité au moment d'un pick.
//
// Extrait de `career_session_generator_mode_picker.dart` : consommé par
// `_ModePicker.pickWeighted` et reconstruit par
// `SessionRuntimeState.continuitySnapshot()` à chaque pick. Sa sortie
// en library autonome est préalable à l'extraction de
// `session_runtime_state.dart` (cette dernière doit pouvoir importer
// `ModeContinuityState` sans passer par le `part of` du générateur).

import '../../../models/session.dart' show SessionMode;
import 'step_type.dart';

/// Snapshot du tracking de continuité au moment d'un pick.
///
/// Reconstruit à chaque appel au picker depuis les fields d'instance
/// mutables (`_state.lastType`, `_stepsInLastType`, `_state.stepsOutsideBouche`,
/// `_state.lastMode`). Le picker reste pur en consommant ce snapshot.
class ModeContinuityState {
  /// Type du dernier step poussé (cluster sémantique bouche / langue /
  /// libreMain / transit). `null` au premier step de la séance.
  final StepType? lastType;

  /// Nombre de steps consécutifs sur [lastType]. 0 si [lastType] est null.
  final int stepsInLastType;

  /// Nombre de steps consécutifs **hors bouche** depuis la dernière
  /// excursion. Sert à forcer le retour à bouche après 2+ excursions.
  final int stepsOutsideBouche;

  /// Dernier mode poussé. Permet le filtre anti-répétition de
  /// `_ModePicker.filterRepeated` pour les modes ponctuels
  /// (breath / beg / biffle / hold / freestyle).
  final SessionMode? lastMode;

  const ModeContinuityState({
    required this.lastType,
    required this.stepsInLastType,
    required this.stepsOutsideBouche,
    required this.lastMode,
  });
}
