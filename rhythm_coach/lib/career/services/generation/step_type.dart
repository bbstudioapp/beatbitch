// Library autonome — enum `StepType` : cluster sémantique d'un step.
//
// Extrait de `career_session_generator_mode_rules.dart` : référencé
// par `SessionRuntimeState.recordContinuity`, `ModeRules.classify`,
// `ModeContinuityState.lastType` et le `_ModePicker`. Sa sortie en
// library autonome est préalable à l'extraction de
// `gen_facade.dart` et de `session_runtime_state.dart` en libraries
// indépendantes.

/// Cluster sémantique d'un step, utilisé pour assurer la cohérence de
/// la séance : on doit rester plusieurs steps consécutifs sur le même
/// type avant d'en changer (sauf `transit` qui est une parenthèse
/// transparente : breath de récup, freestyle).
///
/// - `bouche` (rhythm, hold, beg-non-libre, suckle) : cœur de l'app, on
///   y passe la majorité du temps.
/// - `langue` (lick) : variante douce, intros et transitions.
/// - `libreMain` (hand, biffle, beg-libre) : la bouche est libre, la
///   stim vient de la main / d'un coup / d'une supplique vocale pure.
/// - `transit` (breath, freestyle) : pause neutre, ne casse pas la
///   continuité du type courant.
enum StepType { bouche, langue, libreMain, transit }
