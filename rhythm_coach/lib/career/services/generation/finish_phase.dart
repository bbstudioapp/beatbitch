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
import '../../../models/session_step.dart';
import '../../models/phrase_bank.dart';
import 'final_picker.dart';
import 'generation_context.dart';
import 'mode_rules.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_builders.dart' show ClampToCapability;
import 'step_draft.dart';

/// Callback d'émission d'un step. Pointe sur `_emitStep` côté
/// générateur (qui mute `ctx.time` / `ctx.stamina`, ajoute le step à
/// `ctx.steps`, met à jour stamina/saliva/tracking).
typedef EmitStep = void Function(
  GenerationContext ctx, {
  required StepDraft draft,
  required String text,
  required double progress,
  required bool asTransit,
  bool updateLastBpm,
});

/// Callback de tirage de phrase contextualisée. Pointe sur
/// `_pickPhraseForDraft(bank, draft, tier)` côté générateur (qui
/// applique auto-bump par obédiance + filtre par contraintes
/// profondeur/BPM via `PhraseContext`).
typedef PickPhraseForDraft = String Function(
    PhraseBank bank, StepDraft draft, String tier);

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
    required this.emitStep,
    required this.pickPhraseForDraft,
    required this.clampToCapability,
  })  : _staticHeldMode = _resolveRole(rules, ModeSemanticRole.staticHeld),
        _burstHumiliatingMode =
            _resolveRole(rules, ModeSemanticRole.burstHumiliating),
        _burstNeutralMode = _resolveRole(rules, ModeSemanticRole.burstNeutral),
        _burstFallbackMode =
            _resolveRole(rules, ModeSemanticRole.burstFallback),
        _preFinisherCoreMode =
            _resolveRole(rules, ModeSemanticRole.preFinisherCore);

  final SessionConfig config;
  final SessionRuntimeState state;
  final Random rng;
  final Map<SessionMode, ModeRules> rules;
  final FinalPicker finalPicker;
  final EmitStep emitStep;
  final PickPhraseForDraft pickPhraseForDraft;
  final ClampToCapability clampToCapability;

  /// Modes résolus une fois à la construction.
  final SessionMode _staticHeldMode;
  final SessionMode _burstHumiliatingMode;
  final SessionMode _burstNeutralMode;
  final SessionMode _burstFallbackMode;
  final SessionMode _preFinisherCoreMode;

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

  /// Émet le step de **pré-finisher** : courte accélération
  /// `head → preFinisherTarget` qui prépare la phase boosts. Utilisé
  /// uniquement pour les bas niveaux — le caller garde la guard
  /// `isLowLevel && !isModeForbidden(preFinisherCore)` autour de
  /// l'appel pour ne pas changer la séquence RNG (la position est
  /// pickée avant l'appel).
  ///
  /// La construction du draft (BPM 62-70, dur 22-30 s) est déléguée
  /// au mode qui porte le rôle `preFinisherCore` (cf. B.PR8). Le
  /// clamp capacité, le pick de phrase et l'émission du step
  /// consomment les callbacks threadés ([clampToCapability],
  /// [pickPhraseForDraft], [emitStep]).
  void emitPreFinisher(
    GenerationContext ctx, {
    required Position preFinisherTarget,
  }) {
    final preDraft =
        clampToCapability(rules[_preFinisherCoreMode]!.buildPreFinisher(
      PreFinisherCtx(rng: rng, preFinisherTarget: preFinisherTarget),
    )!);
    final preText = pickPhraseForDraft(ctx.bank, preDraft, 'medium');
    emitStep(
      ctx,
      draft: preDraft,
      text: preText,
      progress: ctx.progress,
      asTransit: true,
    );
  }

  /// Émet le step **post-final** (aftercare ~12 s après l'orgasme).
  /// Mode contrastant choisi par [buildPostFinalDraft] selon le mode
  /// final + l'humil. Phrase : cascade `post_final_<mode>` (rules) /
  /// `post_final` / `congrats`. Mute `ctx.time` / `ctx.stamina`.
  void emitPostFinal(
    GenerationContext ctx, {
    required SessionMode finalMode,
    required int holdCeilingIdx,
  }) {
    final postFinalDraft = clampToCapability(buildPostFinalDraft(
      finalMode: finalMode,
      humilCap: config.humilCapAt(ctx.time),
      holdCeilingIdx: holdCeilingIdx,
    ));
    // Phrase : pool mode-spécifique (beg = CONSIGNE de supplique ;
    // lick = consigne d'aftercare humiliant) puis cascade sur le pool
    // générique. Default `pickPostFinalText` retourne `null` → on
    // saute direct à la cascade générique. Garantit un text non-vide
    // via le fallback final `pickCongrats`.
    final modeSpecific =
        rules[postFinalDraft.mode]!.pickPostFinalText(ctx.bank, rng);
    final postFinalText = modeSpecific ??
        ctx.bank.pickPostFinal(rng) ??
        ctx.bank.pickCongrats(rng);
    emitStep(
      ctx,
      draft: postFinalDraft,
      text: postFinalText,
      progress: 1.0,
      asTransit: true,
    );
  }
}
