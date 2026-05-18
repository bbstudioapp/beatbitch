// Library autonome — orchestration de la phase **finish** d'une
// séance carrière (pré-finisher → boosts → final → post-final →
// assemble result).
//
// Sortie du fichier principal en D.PR9 du plan de refacto
// (`~/beatbitch_refacto_phase_d.md`), même approche que D.PR8 :
// callbacks au constructor pour les helpers d'instance qui ne
// peuvent pas être externalisés (mutation `_state`, appel à
// `_emitStep`, etc.). Les méthodes de cette classe muent `ctx.time`
// / `ctx.stamina` au même titre que les méthodes du main loop.

import 'dart:math';

import '../../../models/session.dart';
import 'final_picker.dart';
import 'mode_rules.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';

/// Helpers d'orchestration de la phase finish. Instancié une fois par
/// `generate()` après que `_state` / `_config` / `_facade` /
/// `_finalPicker` sont posés ; consommé pour le pré-finisher, les
/// boosts, le step final, et le post-final.
class FinishPhase {
  FinishPhase({
    required this.config,
    required this.state,
    required this.rng,
    required this.rules,
    required this.finalPicker,
  })  : _staticHeldMode = _resolveRole(rules, ModeSemanticRole.staticHeld),
        _burstHumiliatingMode =
            _resolveRole(rules, ModeSemanticRole.burstHumiliating),
        _burstNeutralMode = _resolveRole(rules, ModeSemanticRole.burstNeutral),
        _burstFallbackMode =
            _resolveRole(rules, ModeSemanticRole.burstFallback);

  final SessionConfig config;
  final SessionRuntimeState state;
  final Random rng;
  final Map<SessionMode, ModeRules> rules;
  final FinalPicker finalPicker;

  /// Modes résolus une fois à la construction.
  final SessionMode _staticHeldMode;
  final SessionMode _burstHumiliatingMode;
  final SessionMode _burstNeutralMode;
  final SessionMode _burstFallbackMode;

  /// Résolution de rôle — duplication minimale depuis les autres
  /// libraries autonomes (`DifficultyDispatch`, `StepBuilders`).
  static SessionMode _resolveRole(
    Map<SessionMode, ModeRules> rules,
    ModeSemanticRole role,
  ) {
    for (final entry in rules.entries) {
      if (entry.value.roles.contains(role)) return entry.key;
    }
    throw StateError(
      'ModeSemanticRole.$role : aucun mode du registry ne le déclare',
    );
  }

  /// Choix du mode pour la phase de boosts (`burstNeutral` non
  /// humiliant vs `burstHumiliating` humiliant). Gère :
  ///  - le biais dramaturgique 70/30 vs 25/75 selon humil + niveau ;
  ///  - les exclusions Custom (`config.isModeForbidden`) avec repli
  ///    `burstFallback` quand neutre ET humiliant sont bannis ;
  ///  - le ratio de poids brut quand les doses neutre/humiliant sont
  ///    asymétriques (cf. issue #68).
  ///
  /// `useHandBurst` reste le nom historique du flag (les call sites
  /// en aval — caps BPM, pondération dramaturgique — distinguent
  /// encore l'axe humiliant vs neutre via ce booléen, le renommer
  /// est hors scope).
  ///
  /// Consomme un tirage RNG quand les deux modes sont autorisés.
  ({bool useHandBurst, SessionMode burstMode}) pickBurstMode() {
    final handForbidden = config.isModeForbidden(_burstNeutralMode);
    final rhythmForbidden = config.isModeForbidden(_burstHumiliatingMode);
    final preferHandBase =
        config.humiliationCareer < 5 && config.level <= 3 ? 0.70 : 0.25;
    if (handForbidden && rhythmForbidden) {
      // chemin "rhythm-like" : BPM cap/floor rhythm
      return (useHandBurst: false, burstMode: _burstFallbackMode);
    }
    if (handForbidden) {
      return (useHandBurst: false, burstMode: _burstHumiliatingMode);
    }
    if (rhythmForbidden) {
      return (useHandBurst: true, burstMode: _burstNeutralMode);
    }
    final handWeight = config.coachModeWeights[_burstNeutralMode] ?? 1.0;
    final rhythmWeight = config.coachModeWeights[_burstHumiliatingMode] ?? 1.0;
    final dosesAreSymmetric = (handWeight - rhythmWeight).abs() < 0.01;
    final preferHand = dosesAreSymmetric
        ? preferHandBase
        : handWeight / (handWeight + rhythmWeight);
    final useHandBurst = rng.nextDouble() < preferHand;
    return (
      useHandBurst: useHandBurst,
      burstMode: useHandBurst ? _burstNeutralMode : _burstHumiliatingMode,
    );
  }

  /// Construit le draft du **post-final** (aftercare ~12 s après
  /// l'orgasme). Wrap autour de `FinalPicker.buildPostFinalDraft`
  /// qui calcule le `holdCeilingIdx` depuis `state.unlockedKeys` +
  /// `config.maxDepthIndex`. Threaded en helper séparé pour symétrie
  /// avec le post-final dans la chaîne d'émission.
  StepDraft buildPostFinalDraft({
    required SessionMode finalMode,
    required double humilCap,
    required int holdCeilingIdx,
  }) {
    return finalPicker.buildPostFinalDraft(
      finalMode: finalMode,
      humilCap: humilCap,
      holdCeilingIdx: holdCeilingIdx,
    );
  }

  /// Mode résolu une fois pour le rôle `staticHeld` (hold), exposé
  /// aux callers pour le check `holdPosition` côté `_emitFinalStep`.
  SessionMode get staticHeldMode => _staticHeldMode;
}
