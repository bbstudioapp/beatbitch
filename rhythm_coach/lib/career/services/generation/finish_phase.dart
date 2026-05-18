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
import 'position_pickers.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'stamina_model.dart';
import 'step_builders.dart' show ClampToCapability, EnforceHumiliationRequired;
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

/// Callback de tracking post-emission. Pointe sur
/// `_trackPushedStep` côté générateur (qui notifie
/// `_rhythmChain` + `_state.recordContinuity` + `_patternBuffer`).
typedef TrackPushedStep = void Function(
  SessionMode mode,
  Position? to, {
  Position? from,
  int? bpm,
  int? duration,
});

/// Callback d'avancement de la simulation salive. Pointe sur
/// `_advanceSalivaSim(draft)` côté générateur (qui mute
/// `_state.salivaSim`).
typedef AdvanceSalivaSim = void Function(StepDraft draft);

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
    required this.positionPickers,
    required this.emitStep,
    required this.pickPhraseForDraft,
    required this.clampToCapability,
    required this.enforceHumiliationRequired,
    required this.trackPushedStep,
    required this.advanceSalivaSim,
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
  final PositionPickers positionPickers;
  final EmitStep emitStep;
  final PickPhraseForDraft pickPhraseForDraft;
  final ClampToCapability clampToCapability;
  final EnforceHumiliationRequired enforceHumiliationRequired;
  final TrackPushedStep trackPushedStep;
  final AdvanceSalivaSim advanceSalivaSim;

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

  /// Boucle des boosts de la phase finish — sprint déterministe de
  /// `ctx.boostsCount` steps qui ramp BPM et profondeur de manière
  /// monotone croissante. Renvoie l'index du dernier step ajouté à
  /// `ctx.steps` (pour que l'annonce du final puisse y faire
  /// référence si besoin).
  ///
  /// Les listes `ctx.steps` et `ctx.profile` sont mutées en place
  /// (sans passer par [emitStep] — la séquence boost garde sa propre
  /// comptabilité stamina pour préserver l'isomorphie historique).
  /// `state.lastMode/lastText/lastBpm` mis à jour à chaque boost via
  /// [trackPushedStep].
  int? emitBoosts(
    GenerationContext ctx, {
    required bool useHandBurst,
    required SessionMode burstMode,
  }) {
    // Plafond humiliation pour les bursts. Hand n'est pas gating par
    // humiliation (cap inutile), mais on laisse
    // [enforceHumiliationRequired] tourner — il rejettera juste si la
    // profondeur du draft demande trop. Cap assoupli pour les boosts :
    // projection au temps courant du début de la phase finish, +8 de
    // tolérance pour permettre des bursts un poil au-dessus du cap
    // mécanique strict (tradition du finish).
    final boostHumilCap = config.humilCapAt(ctx.time) + 8.0;
    // Nombre total de boosts : table par niveau + bonus encore (fixé
    // en amont via `boostsCount`). Plus de boucle conditionnelle sur
    // la jauge — le sprint est entièrement déterministe.
    final totalBoosts = max(1, ctx.boostsCount);
    // **BPM cap qui scale par niveau ET par chaîne d'encore** : niveau
    // 1 plafonne à ~110 BPM (hand) / 130 (rhythm), +4 BPM/niveau
    // jusqu'à un plafond de garde-fou à 300 (très haut — c'est le
    // `comfort` du profil de capacités qui borne en pratique, via
    // [clampToCapability]). Le mode encore ajoute +8 BPM par cran de
    // chaîne pour intensifier le sprint sans changer le nombre de
    // boosts.
    final levelBpmBoost =
        ((config.level - 1) * 4 + max(0, ctx.encoreChainIndex) * 8)
            .clamp(0, 70);
    final bpmCap = useHandBurst
        ? (110 + levelBpmBoost).clamp(110, 300)
        : (130 + levelBpmBoost).clamp(130, 300);
    final bpmFloor = useHandBurst ? 80 : 100;
    // Cap de profondeur des boosts gaté par les milestones
    // effectivement acquittées : throat ouvert si `throatPulse`
    // débloqué (intro_throat_pulse), full si `fullPulse`
    // (intro_full_pulse). Indépendant du niveau seul — sauter des
    // milestones ne donne pas accès aux profondeurs. Borné par
    // `config.maxDepthIndex` en sécurité, et par mid (idx 2) au
    // minimum (un boost ne descend jamais sous mid pour rester
    // reconnaissable comme un sprint).
    final boostMaxToIdx = max(2, positionPickers.milestoneRhythmCeilingIdx());
    int? lastBoostIndex;
    // Monotonie ascendante : la phase finish ne doit JAMAIS ralentir.
    // Chaque boost démarre sur un BPM ≥ au précédent (idem pour la
    // profondeur `to`).
    int prevBoostBpm = 0;
    int prevBoostToIdx = 0;
    final plannedBoosts = totalBoosts;
    for (var boostsAdded = 0; boostsAdded < totalBoosts; boostsAdded++) {
      // Durée variable : 12 à 16 s par défaut, +1s par cran de chaîne
      // encore pour allonger un peu chaque sprint.
      final boostDur =
          12 + rng.nextInt(5) + max(0, ctx.encoreChainIndex).clamp(0, 4);
      // Progression linéaire 0→1 sur les `plannedBoosts`. Plancher
      // 0.4 : pas de démarrage mou.
      final progress = plannedBoosts <= 1
          ? 1.0
          : ((boostsAdded + 1) / plannedBoosts).clamp(0.4, 1.0);
      final targetBpm = (bpmFloor + progress * (bpmCap - bpmFloor)).round();
      // Jitter ±5 BPM autour de la cible pour ne pas répéter
      // exactement le même tempo deux boosts d'affilée. Capé par
      // bpmCap.
      final shift = rng.nextInt(11) - 5;
      final bpmRaw = (targetBpm + shift).clamp(bpmFloor, bpmCap);
      // Plancher monotone : on ne descend jamais sous le BPM du boost
      // précédent.
      final bpm =
          bpmRaw <= prevBoostBpm ? min(prevBoostBpm + 4, bpmCap) : bpmRaw;
      // Profondeur : ramp aussi sur la progression. Plancher
      // `prevBoostToIdx` garantit la monotonie.
      final rampDenom = plannedBoosts <= 1 ? 1 : (plannedBoosts - 1);
      final progressionToIdx =
          (boostMaxToIdx - 2 + 2 * (boostsAdded / rampDenom).clamp(0.0, 1.0))
              .round()
              .clamp(2, boostMaxToIdx);
      final toIdx = max(prevBoostToIdx, progressionToIdx);
      final boostTo = Position.values[toIdx];
      // `from` : 2 crans au-dessus si possible (amplitude max), sinon
      // 1 cran.
      final boostFromIdx =
          rng.nextBool() && toIdx >= 2 ? max(0, toIdx - 2) : max(0, toIdx - 1);
      final boostFrom = Position.values[boostFromIdx];
      final boostDraftRaw = StepDraft(
        mode: burstMode,
        bpm: bpm,
        from: boostFrom,
        to: boostTo,
        duration: boostDur,
      );
      // Hand : pas de gating humil → on garde amplitude max. Rhythm :
      // cap normal du finish. Dans les deux cas,
      // [clampToCapability] (qui applique aussi les bornes Custom).
      final boostDraft = useHandBurst
          ? clampToCapability(boostDraftRaw)
          : enforceHumiliationRequired(boostDraftRaw, boostHumilCap);
      // Tier dédié `boost` ; fallback `hard` si la bank n'a rien.
      var boostText = pickPhraseForDraft(ctx.bank, boostDraft, 'boost');
      if (boostText.isEmpty) {
        boostText = pickPhraseForDraft(ctx.bank, boostDraft, 'hard');
      }
      ctx.steps.add(_draftToStep(boostDraft, time: ctx.time, text: boostText));
      lastBoostIndex = ctx.steps.length - 1;
      state.recordLastTransit(boostDraft.mode, boostText);
      state.lastBpm = boostDraft.bpm ?? state.lastBpm;
      trackPushedStep(boostDraft.mode, boostDraft.to,
          from: boostDraft.from,
          bpm: boostDraft.bpm,
          duration: boostDraft.duration);
      final staminaBeforeBoost = ctx.stamina;
      ctx.stamina = StaminaModel.apply(ctx.stamina, boostDraft, 1.0, ctx.cfg,
          rules: rules);
      advanceSalivaSim(boostDraft);
      StaminaModel.fillProfile(ctx.profile, ctx.time, boostDur, ctx.stamina,
          valueStart: staminaBeforeBoost);
      ctx.time += boostDur;
      // Mémorise BPM/profondeur retenus (post-dégradation humil) pour
      // que le boost suivant ne puisse pas redescendre sous ce palier.
      prevBoostBpm = boostDraft.bpm ?? prevBoostBpm;
      if (boostDraft.to != null) {
        prevBoostToIdx = max(prevBoostToIdx, boostDraft.to!.index);
      }
    }
    return lastBoostIndex;
  }

  /// Helper local — convertit un `StepDraft` interne en `SessionStep`
  /// sérialisable. Convention uniforme hold/beg : la position tenue
  /// est dans `to`. Dupliqué depuis `_draftToStep` du générateur
  /// (helper pur, 8 lignes — pas le coût d'une dépendance threadée).
  SessionStep _draftToStep(StepDraft draft,
      {required int time, String text = ''}) {
    return SessionStep(
      time: time,
      text: text,
      mode: draft.mode,
      bpm: draft.bpm,
      bpmEnd: draft.bpmEnd,
      from: draft.from,
      to: draft.to,
      duration: draft.duration,
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
