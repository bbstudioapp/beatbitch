// Library autonome — interface de la 2ᵉ enveloppe de difficulté
// (`CapabilityClamps`) telle que vue par les `ModeRules`. Découple les
// rules de l'implémentation concrète : la rule reçoit cette interface,
// pas la classe `CapabilityClamps` (qui vit toujours en `part of` du
// générateur). Casse le cycle `ModeRules ↔ CapabilityClamps` en
// préparation de l'extraction de `mode_rules.dart` en library autonome
// (A.PR2).
//
// Surface volontairement minimale : seules les méthodes que les rules
// consomment réellement. Le helper `CapabilityClamps.minNullable` reste
// statique et n'est **pas** dans l'interface — les rules l'appellent
// directement par nom de classe (visibilité préservée via les re-exports
// de `career_session_generator.dart`).

import '../../../services/capability_axis.dart';
import 'step_draft.dart';

/// Surface de `CapabilityClamps` exposée aux `ModeRules`.
abstract class CapabilityClampSurface {
  /// Plafond effectif d'un axe de capacité pour la génération en cours
  /// (= `min(comfort éventuellement surchargé, ceiling figé sur fail)`),
  /// ou `null` si aucune donnée (joueuse neuve / axe jamais sollicité).
  double? capabilityCapFor(CapabilityAxis axis);

  /// Facteur de surcharge applicable à [axis] (1.0 hors surcharge).
  /// Pour `rhythmDepthMax` la surcharge est un cran, pas un facteur —
  /// utiliser [capabilityCapFor] directement.
  double overloadFactorFor(CapabilityAxis axis);

  /// Borne un draft à l'enveloppe « profil de capacités » (profondeur /
  /// BPM / durée). Orchestre la récursion sur `chainNext` et la
  /// composition avec les bornes utilisateur Custom.
  StepDraft clampToCapability(StepDraft d);
}
