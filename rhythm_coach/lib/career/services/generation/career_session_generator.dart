import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../models/anatomy_profile.dart';
import '../../../models/final_category.dart';
import '../../../models/punishment.dart';
import '../../../models/session.dart';
import '../../../models/session_step.dart';
import '../../../services/capability_axis.dart';
import '../../../services/capability_service.dart';
import '../../models/career_generation_inputs.dart';
import '../../models/career_level.dart';
import '../../models/level_milestone.dart';
import '../../models/phrase_bank.dart';
import '../../models/specialization.dart';
import '../../models/unlock_key.dart';

// Re-exports : les rules (libraries autonomes dans `rules/`) importent
// uniquement `career_session_generator.dart`. Pour leur épargner une
// dizaine d'imports models/services chacune, on re-exporte ici les
// types qu'elles consomment.
export '../../../models/anatomy_profile.dart' show AnatomyProfile;
export '../../../models/final_category.dart' show FinalCategory;
export '../../../models/session.dart' show SessionMode;
export '../../../models/session_step.dart' show Position, SessionStep;
export '../../../services/capability_axis.dart' show CapabilityAxis;
export '../../models/career_level.dart' show CareerLevel;
export '../../models/phrase_bank.dart' show PhraseBank;
export '../../models/specialization.dart'
    show SpecializationAllocation, SpecializationBranch;
export '../../models/unlock_key.dart' show UnlockKey;

// Les 9 rules sont des libraries autonomes (cf. `rules/`) qui importent
// cette library pour le contrat `ModeRules` + les types support. Les
// importer ici permet à `modeRulesRegistry` (cf. `mode_rules.dart`) de
// les instancier en const. Le cycle d'import est résolu lexicalement
// par Dart (toutes les déclarations sont visibles avant l'évaluation
// des const top-level).
import 'rules/career_session_generator_rules_beg.dart';
import 'rules/career_session_generator_rules_biffle.dart';
import 'rules/career_session_generator_rules_breath.dart';
import 'rules/career_session_generator_rules_freestyle.dart';
import 'rules/career_session_generator_rules_hand.dart';
import 'rules/career_session_generator_rules_hold.dart';
import 'rules/career_session_generator_rules_lick.dart';
import 'rules/career_session_generator_rules_rhythm.dart';
import 'rules/career_session_generator_rules_suckle.dart';
import 'bpm_pacing.dart';
import 'capability_clamps.dart';
import 'final_picker.dart';
import 'humiliation_gates.dart';
import 'mode_continuity_state.dart';
import 'mode_rules.dart';
import 'position_pickers.dart';
import 'rhythm_chain_tracker.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';
import 'step_type.dart';

// Re-exports des types extraits — les 9 fichiers de rules et les call
// sites externes importent `career_session_generator.dart` et y trouvent
// toujours ces types.
export 'bpm_pacing.dart' show BpmPacing;
export 'capability_clamp_surface.dart' show CapabilityClampSurface;
export 'capability_clamps.dart' show CapabilityClamps;
export 'final_picker.dart' show FinalPicker;
export 'humiliation_gates.dart' show HumiliationGates;
export 'mode_continuity_state.dart' show ModeContinuityState;
export 'position_pickers.dart' show PositionPickers;
export 'mode_rules.dart'
    show
        DraftCtx,
        FinalCtx,
        FinalVariant,
        GenFacadeSurface,
        IntroCtx,
        ModeRules,
        PostFinalCtx,
        PostFinalVariant,
        RecoveryAvailability,
        RecoveryCtx,
        clampHeldDuration,
        tryDescendFrom,
        tryDescendToWithGuard;
export 'rhythm_chain_tracker.dart' show RhythmChainTracker;
export 'session_config.dart' show SessionConfig;
export 'session_runtime_state.dart' show SessionRuntimeState;
export 'step_draft.dart' show StepDraft;
export 'step_type.dart' show StepType;

part 'career_session_generator_stamina.dart';
part 'career_session_generator_mode_rules.dart';
part 'career_session_generator_mode_picker.dart';
part 'career_session_generator_difficulty_dispatch.dart';
part 'career_session_generator_punishment.dart';
part 'career_session_generator_rhythmic_pattern_buffer.dart';
part 'career_session_generator_milestone_scheduler.dart';

/// Registry par défaut des règles par mode — couvre les 9 modes du jeu.
/// Injecté au `CareerSessionGenerator` quand aucun `rules` n'est passé au
/// constructeur (cas standard). Un test ou un module externe peut passer
/// un registry de sa fabrication (par exemple pour mocker une rule).
///
/// Const map : les rules sont stateless avec des const constructors, donc
/// la map est const-évaluable et thread-safe.
///
/// Vit ici (et non dans `mode_rules.dart`, library autonome) pour éviter
/// un cycle d'import : la const map référence les 9 implémentations
/// concrètes qui dépendent de `career_session_generator.dart` via le
/// re-export de `ModeRules` / `DraftCtx` / etc.
const Map<SessionMode, ModeRules> defaultModeRulesRegistry = {
  SessionMode.rhythm: RhythmRules(),
  SessionMode.lick: LickRules(),
  SessionMode.hold: HoldRules(),
  SessionMode.biffle: BiffleRules(),
  SessionMode.beg: BegRules(),
  SessionMode.hand: HandRules(),
  SessionMode.breath: BreathRules(),
  SessionMode.freestyle: FreestyleRules(),
  SessionMode.suckle: SuckleRules(),
};

/// Résultat d'une génération : la session figée à passer au controller +
/// le profil d'endurance projeté (utile à l'overlay debug `StaminaBar`) +
/// l'axe de capacité surchargé sur cette séance (`null` hors carrière / profil
/// neuf) — consommé par le coach (Phase 4) pour ses phrases « on bat ton
/// record de … ».
class CareerGenerationResult {
  final Session session;
  final List<double> staminaProfile;
  final CapabilityAxis? overloadAxis;

  const CareerGenerationResult({
    required this.session,
    required this.staminaProfile,
    this.overloadAxis,
  });
}

/// Génère une session procédurale en fonction du niveau choisi et de la
/// durée demandée. Voir `(plan local)`
/// pour la spec complète de l'algorithme.
class CareerSessionGenerator {
  // ─── CONSTANTES ──────────────────────────────────────────────────────────

  static const int _finisherBudgetSeconds = 12;

  /// Budget réservé en fin de session pour la phase d'accélération qui
  /// précède le hold final (bas niveaux uniquement). Permet d'enchaîner
  /// proprement effort → finisher sans dépasser la durée demandée.
  static const int _preFinisherBudgetSeconds = 30;

  // ─── RNG ─────────────────────────────────────────────────────────────────

  final Random _rng;

  // ─── PARAMÈTRES DE SESSION (figés par [generate]) ────────────────────────
  // 16 inputs immuables regroupés dans `SessionConfig`, re-posé en début
  // de chaque `generate()` / `generatePunishment()`. Toute lecture passe
  // directement par `_config.xxx` (cf.
  // `career_session_generator_session_config.dart` pour la liste complète
  // et la doc des champs). Les anciens getters projection ont été
  // supprimés — l'immutabilité de `_config` rend l'accès direct sûr.

  late SessionConfig _config;

  // ─── ÉTAT DE TRACKING (mutable pendant la génération) ────────────────────
  // 13 fields scratchpad regroupés dans `SessionRuntimeState`, re-posé en
  // début de chaque `generate()` / `generatePunishment()` via
  // `SessionRuntimeState.fresh(rng:)`. Toute lecture/écriture passe
  // directement par `_state.xxx` (cf.
  // `career_session_generator_session_runtime_state.dart` pour la liste
  // complète et la doc des champs). Les anciens getters/setters projection
  // ont été supprimés — l'aliasing du field `_state` est sûr (la référence
  // est stable même si son contenu mute pendant la séance).

  late SessionRuntimeState _state;

  // Sous-systèmes runtime autonomes. `_rhythmChain` est recréé à chaque
  // `generate()` après que `_state` + `_capClamps` sont posés (il consomme
  // `motion_streak` comfort + overload factor projetés). Le pattern buffer
  // reste un objet stable avec son propre `clear()` au début de séance.
  late RhythmChainTracker _rhythmChain;
  final _RhythmicPatternBuffer _patternBuffer = _RhythmicPatternBuffer();

  /// Surface exposée aux `ModeRules` (cf. `GenFacade`). Recréée à chaque
  /// `generate()` / `generatePunishment()` après que `_positionPickers` et
  /// les autres sous-systèmes sont posés : la facade capture les références
  /// stables (`_config`, `_state`, `_positionPickers`…) en field, pas via
  /// un handle vers le générateur.
  late GenFacade _facade;

  /// 2ᵉ enveloppe (immuable pour la séance) — recréée à chaque appel à
  /// [generate] après que l'axe de surcharge a été choisi.
  late CapabilityClamps _capClamps;

  /// Picker du final + post-final — recréé à chaque appel à [generate]
  /// après que [_capClamps] est posé. Consomme `_capClamps` pour le clamp
  /// terminal des holds throat/full.
  late FinalPicker _finalPicker;

  /// Pickers de position (hold / beg / from-to / simplex / etc.) —
  /// recréés à chaque appel à [generate] / [generatePunishment].
  late PositionPickers _positionPickers;

  /// Registry des règles par mode injecté au constructeur. Par défaut le
  /// `_rules` standard ; un test ou un module externe
  /// peut passer un registry alternatif (mocker une rule, ajouter un mode
  /// expérimental sans toucher au reste).
  ///
  /// Propagé à chaque sous-système qui consomme polymorphiquement les
  /// rules (`CapabilityClamps`, `FinalPicker`, `StaminaModel.delta`,
  /// `_ModePicker.continuityMultiplier`, `HumiliationGates.*`,
  /// `_DifficultyDispatch._mapDifficultyToStep`).
  final Map<SessionMode, ModeRules> _rules;

  CareerSessionGenerator({
    int? seed,
    Map<SessionMode, ModeRules>? rules,
  })  : _rng = seed != null ? Random(seed) : Random(),
        _rules = rules ?? defaultModeRulesRegistry;

  // ─── Profil de capacités — 2ᵉ enveloppe de difficulté ────────────────────

  /// Sélectionne l'axe de surcharge pour la séance via
  /// `CapabilityClamps.pickOverloadAxis`. Retourne `(axis, factor)`
  /// (jamais null) — au caller (`generate` / `generatePunishment`) de
  /// l'injecter dans `SessionConfig`. Émet un debugPrint si un axe est
  /// effectivement surchargé.
  ({CapabilityAxis? axis, double factor}) _pickOverload({
    required CapabilityProfile? profile,
    required Map<CapabilityAxis, double> ceilings,
  }) {
    final pick = CapabilityClamps.pickOverloadAxis(
      profile: profile,
      ceilings: ceilings,
      rng: _rng,
    );
    if (kDebugMode && pick.axis != null) {
      final sr = profile?.stateOf(pick.axis!).successRate ?? 0.0;
      debugPrint('[career-gen] overload axis=${pick.axis!.storageKey} '
          'factor=${pick.factor.toStringAsFixed(3)} '
          'sr=${sr.toStringAsFixed(2)}');
    }
    return (axis: pick.axis, factor: pick.factor);
  }

  /// Adaptateur d'instance pour `CapabilityClamps.clampToCapability` —
  /// applique la 2ᵉ enveloppe (profondeur / BPM / durée) ET les bornes
  /// utilisateur Custom en cascade.
  StepDraft _clampToCapability(StepDraft d) => _capClamps.clampToCapability(d);

  CareerGenerationResult generate({
    required int level,
    required PhraseBank bank,
    int? durationSeconds,
    bool includeHand = true,
    int encoreChainIndex = 0,
    String? openingPhrase,
    bool quickie = false,
    SpecializationAllocation? specialization,
    bool intense = false,
    double obedience = 100.0,
    double humiliationCareer = 0.0,
    double humiliationSession = 0.0,
    Set<UnlockKey> unlockedKeys = const {},
    Map<SessionMode, double> coachModeWeights = const {},
    String? sessionName,
    String? sessionNameQuickie,

    /// Profil anatomique de la joueuse. Default = tout disponible
    /// (rétrocompat carrière / tests). Quand `hasBalls = false`, aucun
    /// step sur `Position.balls` n'est généré (filtre `_isUnlocked`
    /// précoce, indépendant du gating milestone).
    AnatomyProfile anatomy = AnatomyProfile.defaults,

    /// Plan d'insertion des milestones pédagogiques. `MilestonePlan.none`
    /// = séance standard sans milestone (cas Custom / scénarios /
    /// surprise / Supplier / encore).
    MilestonePlan milestones = MilestonePlan.none,

    /// 2ᵉ enveloppe de difficulté (profil de capacités + plafonds figés
    /// par fail). `CapabilityInputs.none` = aucun gating capacité.
    /// `overloadAxis` est ignoré ici (`generate()` pioche son axe via
    /// `_pickOverload`) — seul `generatePunishment` le consomme.
    CapabilityInputs capability = CapabilityInputs.none,

    /// Surcharges propres au mode Custom (intensité plancher, plafond
    /// profondeur, bornes BPM / hold, `noStats`). `CustomOverrides.none`
    /// = comportement carrière standard, aucune surcharge.
    CustomOverrides custom = CustomOverrides.none,
  }) {
    // Invariants `milestones` : on ne peut pas les déplacer dans le
    // constructeur de `MilestonePlan` car `.placement` n'est pas
    // const-eval-friendly (ce qui casserait `static const MilestonePlan.none`,
    // lui-même utilisé comme valeur par défaut de ce param).
    assert(
      milestones.finalMilestone == null ||
          milestones.finalMilestone!.placement ==
              MilestonePlacement.finalApotheose,
      'finalMilestone doit avoir placement=finalApotheose',
    );
    assert(
      milestones.bodies.every((m) => m.placement == MilestonePlacement.body),
      'milestones.bodies doivent avoir placement=body',
    );
    assert(
      milestones.bodies.length <= 2,
      'milestones.bodies : au plus 2 milestones body par séance pour l\'instant',
    );
    final cfg = CareerLevel.forLevel(level);
    final overload = _pickOverload(
      profile: capability.profile,
      ceilings: capability.sessionCeilings,
    );
    _config = SessionConfig(
      level: level,
      includeHand: includeHand,
      maxDepthIndex: custom.maxDepthIndex ?? cfg.maxDepthIndex,
      deepProbability: cfg.deepProbability,
      spec: specialization ?? SpecializationAllocation.empty(),
      anatomy: anatomy,
      coachModeWeights: coachModeWeights,
      bpmRange: custom.normalizedBpmRange,
      holdDurationRange: custom.normalizedHoldDurationRange,
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedience,
      capProfile: capability.profile,
      capCeilings: capability.sessionCeilings,
      overloadAxis: overload.axis,
      overloadFactor: overload.factor,
    );
    _state = SessionRuntimeState.fresh(rng: _rng);
    _state.unlockedKeys = unlockedKeys;
    _patternBuffer.clear();
    // 2ᵉ enveloppe immuable construite après le choix de l'axe de surcharge —
    // recréée à chaque appel à `generate()` pour intégrer profile/ceilings/
    // overload/bornes-Custom courants. Consommée via les adaptateurs
    // `_clampToCapability` / `_capabilityCapFor` / `_overloadFactorFor`.
    _capClamps = CapabilityClamps(
      config: _config,
      bpmRange: _config.bpmRange,
      holdRange: _config.holdDurationRange,
      rules: _rules,
    );
    // Recréé à chaque séance (compteur à 0 naturellement) après `_capClamps`
    // dont on lit le facteur de surcharge `motion_streak`. Plus de
    // `reset()` explicite — la composition rend l'invariant mécanique.
    _rhythmChain = RhythmChainTracker(
      state: _state,
      motionStreakComfort:
          _config.capProfile?.comfortOf(CapabilityAxis.rhythmMotionStreak),
      motionStreakOverloadFactor:
          _capClamps.overloadFactorFor(CapabilityAxis.rhythmMotionStreak),
    );
    _finalPicker = FinalPicker(
      config: _config,
      unlockedKeys: _state.unlockedKeys,
      rng: _rng,
      capClamps: _capClamps,
      rules: _rules,
    );
    _positionPickers = PositionPickers(
      config: _config,
      unlockedKeys: _state.unlockedKeys,
      rng: _rng,
      rules: _rules,
    );
    _facade = GenFacade._(
      config: _config,
      state: _state,
      rng: _rng,
      rhythmChain: _rhythmChain,
      positionPickers: _positionPickers,
    );
    // Mode "Session bâclée" : 6 min par défaut, intense tout du long. Floor
    // d'intensité appliqué au tirage de difficulté + on saute l'intro douce
    // et la pré-finition. Une durée explicite reste prioritaire (cas de la
    // session surprise qui demande 60-240s avec dramaturgie quickie).
    //
    // Mode "intense" : régénération post-Supplier. On garde la durée
    // demandée mais on supprime le soft intro et on applique un plancher
    // de difficulté solide pour que la suite ressente vraiment le level up.
    final effectiveDuration =
        durationSeconds ?? (quickie ? 6 * 60 : cfg.durationSeconds);
    final intensityFloor =
        custom.intensityFloor ?? (quickie ? 0.65 : (intense ? 0.55 : 0.0));
    // Nombre de boosts en phase finish : table par niveau + bonus encore
    // (chaîne encore = +2 boosts par cran, sans plafond explicite côté
    // générateur). Le caller borne le nombre d'encores enchaînés via le
    // gating `_canEncore`.
    final boostsCount = cfg.boostsCount + max(0, encoreChainIndex) * 2;
    // Pré-calculés ici (et non plus juste avant la pré-finition) pour
    // pouvoir construire [_GenContext] en une seule fois après les locaux
    // dérivés. Aucune dépendance sur l'opening step / la boucle main —
    // tout vient de `level`, `quickie`, `intense`, `milestones.finalMilestone`.
    final isLowLevel = level <= 2 && !quickie && !intense;
    final finalMilestone = milestones.finalMilestone;
    final useFinalMilestone = finalMilestone != null;
    final finalBudget = useFinalMilestone
        ? finalMilestone.durationSeconds
        : _finisherBudgetSeconds;
    final genUntil = effectiveDuration -
        finalBudget -
        (isLowLevel && !useFinalMilestone ? _preFinisherBudgetSeconds : 0);

    // `_state.salivaSim` et `_state.salivaSimSecond` sont posés par
    // `SessionRuntimeState.fresh()` plus haut.
    final steps = <SessionStep>[];
    final profile =
        List<double>.filled(effectiveDuration + 60, StaminaModel.cap);

    var time = 0;
    var stamina = StaminaModel.cap;

    // DTO partagé par les helpers de phase. Construit une fois ici et passé
    // à chacun pour éviter de répéter les ~10 args (cfg/bank/effectiveDuration/
    // level/...) à chaque appel. Le curseur `(time, stamina)` reste hors-ctx
    // et threadé via record return values.
    final ctx = _GenContext(
      steps: steps,
      profile: profile,
      encoreChainIndex: encoreChainIndex,
      effectiveDuration: effectiveDuration,
      boostsCount: boostsCount,
      genUntil: genUntil,
      intensityFloor: intensityFloor,
      quickie: quickie,
      noStats: custom.noStats,
      cfg: cfg,
      bank: bank,
      sessionName: sessionName,
      sessionNameQuickie: sessionNameQuickie,
      milestoneTextResolver: milestones.textResolver,
      insertedBodies: milestones.bodies,
    );

    // Insertion différée des milestones d'apprentissage. Pour permettre
    // une chauffe avant de tomber sur la séquence pédagogique, chaque
    // milestone vise une position de séance (par défaut `insertAtMinSeconds`
    // = 60s, `insertAtMaxSeconds` = 0.4 × durée pour la 1ʳᵉ ; 0.75 × durée
    // pour la 2ᵉ). L'insertion se fait dans la boucle main dès que `time`
    // atteint la target, ou en urgence dès que `time >= maxInsert`.
    //
    // Cas spécial `insertAtMinSeconds <= 0` : la 1ʳᵉ milestone EST l'intro,
    // on remplace le first step classique. Compatible avec une seule body
    // uniquement (deux milestones à t=0, ça n'a pas de sens).
    //
    // Pour les sessions longues (cf. career_screen.dart), on insère 2 body
    // milestones : la 1ʳᵉ vers 30 % de la durée, la 2ᵉ vers 65 %, avec un
    // buffer de 60 s minimum entre la fin de la 1ʳᵉ et le début de la 2ᵉ
    // — sans quoi on ferme la 2ᵉ (fallback à 1 body, comportement actuel).
    final milestoneScheduler = _MilestoneScheduler.fromBodies(
      this,
      bodies: milestones.bodies,
      effectiveDuration: effectiveDuration,
    );

    // Step #0 obligatoirement non text-only à time=0 (sinon _lastConfigStep
    // reste null côté controller, casse la restauration post-fail). Une
    // phrase soft d'amorce y est attachée pour ne pas démarrer la séance
    // dans le silence. En mode bâclée, intro raccourcie pour aller au but.
    //
    // Si la milestone remplace l'intro, on l'insère ici à t=0 et c'est
    // son premier step qui tient le rôle de step #0 non text-only.
    if (milestoneScheduler.replacesIntro) {
      final r = milestoneScheduler.insertIntroReplacement(
        ctx,
        time: time,
        stamina: stamina,
      );
      time = r.time;
      stamina = r.stamina;
    } else {
      final first = _clampToCapability(_firstStep(
        quickie: quickie,
        intense: intense,
      ));
      // Phase 4 — coach audible : si un axe est surchargé cette séance et qu'on
      // est sur un démarrage de séance normale (pas Supplier/encore = pas
      // d'`openingPhrase` imposée, pas bâclée), une chance ∝ niveau de poser une
      // phrase « attempt » (« aujourd'hui on bat ton record de gorge ») à la
      // place de l'ouverture générique. Coach sans `progressPhrases` pour cet
      // axe → `null` → on retombe sur l'ouverture habituelle (silence par défaut).
      String? attemptPhrase;
      if (_config.overloadAxis != null &&
          openingPhrase == null &&
          !quickie &&
          _rng.nextDouble() <
              CapabilityRegulator.progressPhraseChanceForLevel(level)) {
        final raw = bank.pickProgressPhrase(
            _config.overloadAxis!.storageKey, 'attempt', _rng);
        if (raw != null && raw.isNotEmpty) attemptPhrase = raw;
      }
      final firstText = attemptPhrase ??
          openingPhrase ??
          _pickPhraseForDraft(bank, first, 'soft');
      steps.add(_draftToStep(first, time: 0, text: firstText));
      _state.recordLastAction(first, firstText);
      _state.lastBpm = first.bpm ?? _state.lastBpm;
      _trackPushedStep(first.mode, first.to,
          from: first.from, bpm: first.bpm, duration: first.duration);
      final staminaBefore = stamina;
      stamina = StaminaModel.apply(stamina, first, 0.0, cfg, rules: _rules);
      StaminaModel.fillProfile(profile, 0, first.duration ?? 1, stamina,
          valueStart: staminaBefore);
      _advanceSalivaSim(first);
      time += first.duration ?? 1;
    }

    // Pour les bas niveaux on réserve un créneau supplémentaire avant le
    // finisher pour insérer une légère accélération de fin (cf. plus bas).
    // Modes bâclée / intense : pas de pré-finition, on enchaîne directement
    // — la régen post-Supplier doit déjà être à fond, pas besoin de la
    // pré-accélérer.
    //
    // `isLowLevel`, `useFinalMilestone`, `finalBudget`, `genUntil` désormais
    // pré-calculés en tête de [generate] (cf. construction de `ctx` plus haut).
    while (time < genUntil) {
      // Phase 1 — Insertion milestone : on traite les pending dans
      // l'ordre, dès que `time` atteint la target (`>= targetTime`),
      // OU dès qu'on dépasse la borne max (insertion en urgence pour
      // ne pas la louper). Le cas time < target continue à empiler des
      // steps de chauffe normalement.
      final milestoneInsert = milestoneScheduler.tryInsertAt(
        ctx,
        time: time,
        stamina: stamina,
      );
      if (milestoneInsert != null) {
        time = milestoneInsert.time;
        stamina = milestoneInsert.stamina;
        if (time >= genUntil) break;
        continue;
      }
      // Phase 2 — Mini-vague (+ breath long post-vague) : 2-3 steps à
      // BPM montant qui cassent la diagonale d'intensité, suivis d'un
      // breath long de récup. Inséré toutes les ~4-5 min sur sessions
      // longues ≥ 12 min à partir du niveau 5.
      final miniWave = _tryEmitMiniWaveCycle(ctx, time: time, stamina: stamina);
      if (miniWave != null) {
        time = miniWave.time;
        stamina = miniWave.stamina;
        continue;
      }
      // Phase 3 — Ordre de déglutition forcé : beg libre court quand la
      // simulation salive sature.
      final swallow = _tryEmitSwallowOrder(ctx, time: time, stamina: stamina);
      if (swallow != null) {
        time = swallow.time;
        stamina = swallow.stamina;
        continue;
      }
      // Phase 4 — Main step : tirage de difficulté → mode → cascade de
      // diversification (BPM / amplitude / capacités) → sas breath
      // conditionnel → diversification en sous-segments → fake breath
      // optionnel → chain action attachée. Toujours émet.
      final main = _emitMainStepCycle(ctx, time: time, stamina: stamina);
      time = main.time;
      stamina = main.stamina;
    }

    // Si la boucle main s'est terminée sans avoir inséré toutes les
    // milestones (durée trop courte pour atteindre la fenêtre, ou
    // `genUntil` faible après le first step), on force l'insertion ici
    // pour qu'elles soient jouées avant le finisher. Cas rare mais on ne
    // veut pas perdre une milestone silencieusement.
    final drain = milestoneScheduler.insertAllRemaining(
      ctx,
      time: time,
      stamina: stamina,
    );
    time = drain.time;
    stamina = drain.stamina;

    // À partir d'ici on entre dans la fenêtre **finish** (pré-finisher +
    // boosts + final + son d'orgasme). Les commentaires aléatoires sont
    // coupés sur cette fenêtre par le contrôleur, pour ne pas qu'une
    // phrase random vienne se chevaucher avec la dramaturgie scriptée
    // (boost « continue je viens », chime, annonce milestone, etc.).
    final silentFinishStartTime = time;

    // Cas milestone-final : la séquence imposée remplace l'ensemble
    // pré-finisher + boosts + step finisher. Pas d'amorce générée — la
    // milestone porte sa propre dramaturgie d'apothéose. On termine la
    // session juste après la séquence (+ congrats text-only) pour laisser
    // `_finish` enchaîner sur la phrase finale + finale_chime.
    if (useFinalMilestone) {
      final finalMilestoneStartTime = time;
      final finalResult = _pushMilestoneSequence(
        ctx,
        milestone: finalMilestone,
        time: time,
        stamina: stamina,
      );
      time = finalResult.time;
      stamina = finalResult.stamina;

      // Catégorise le final pour piocher le bon `finale_chime` côté
      // BeepEngine. Basé sur le dernier step de config de la séquence
      // (= l'action sur laquelle la coach jouit).
      final lastConfigStep = finalMilestone.sequence.lastWhere(
          (s) => !s.isTextOnly,
          orElse: () => finalMilestone.sequence.last);
      final lastDraft = _stepToDraft(lastConfigStep, SessionMode.rhythm);
      final finalCategory = _rules[lastDraft.mode]!.finalCategory(lastDraft);

      // Marque l'instant où le dernier step de config de la milestone
      // démarre (= moment où le chime doit retentir). `time` (avant ce
      // bloc) a déjà été incrémenté de finalMilestone.durationSeconds, on
      // recule donc à `finalMilestoneStartTime + lastConfigStep.time` pour
      // pointer le bon instant absolu.
      final finalStepStartTime = finalMilestoneStartTime + lastConfigStep.time;

      steps.add(SessionStep(
        time: time,
        text: bank.pickCongrats(_rng),
      ));

      return _assembleResult(
        ctx,
        time: time,
        stamina: stamina,
        milestoneStartTime: milestoneScheduler.bodyStartTime,
        milestoneDurationSeconds: milestoneScheduler.bodyDurationSeconds,
        secondMilestoneStartTime: milestoneScheduler.secondBodyStartTime,
        secondMilestoneDurationSeconds:
            milestoneScheduler.secondBodyDurationSeconds,
        finalCategory: finalCategory,
        silentFinishStartTime: silentFinishStartTime,
        finalStepStartTime: finalStepStartTime,
        finalMilestoneId: finalMilestone.id,
        finalMilestoneStartTime: finalMilestoneStartTime,
        finalMilestoneDurationSeconds: finalMilestone.durationSeconds,
      );
    }

    // Position cible du pré-finisher : profondeur « normale » du niveau,
    // capée par `_config.maxDepthIndex`. Sert de transition vers le final.
    final preFinisherTarget = _positionPickers.pickFinisherPosition();

    // Pré-finisher : pour les bas niveaux, courte accélération (rythme
    // un peu plus rapide que le plafond habituel du niveau) qui débouche
    // sur le final, dans une position d'amorce.
    // Custom : rhythm exclu → skip le pré-finisher (les boosts substitueront
    // le sprint via leur propre fallback de mode).
    if (isLowLevel && !_config.isModeForbidden(SessionMode.rhythm)) {
      final preResult = _emitPreFinisher(
        ctx,
        time: time,
        stamina: stamina,
        preFinisherTarget: preFinisherTarget,
      );
      time = preResult.time;
      stamina = preResult.stamina;
    }

    // Choix du template de finish : `hand_burst` (non humiliant, pure
    // intensité) ou `rhythm_burst` (humiliant). Voir B1 du plan.
    // - humiliation faible (<5) ET niveau ≤ 3 : 70% hand, 30% rhythm
    //   (rhythm sera de toute façon doux à ce niveau, autant pousser via hand)
    // - sinon : 75% rhythm, 25% hand (variété)
    // Custom : si hand est exclu, on force rhythm ; si rhythm est exclu, on
    // force hand ; si les deux sont exclus, on retombe sur un lick au tempo
    // burst (le BPM s'applique, l'humiliation se gate normalement) — moins
    // archétypal mais respecte le ban. L'éditeur Custom garantit qu'au
    // moins un mode bouche reste actif, donc lick est presque toujours dispo.
    //
    // Dose Custom rare/normal/frequent (cf. issue #68) : quand les poids
    // hand/rhythm sont **strictement asymétriques** (cas Custom où la
    // joueuse a explicitement biaisé une dose), on bascule sur le ratio
    // brut des poids comme proba. Le pivot dramaturgique 25/75 vs 70/30
    // ne s'applique qu'en cas d'égalité (cas carrière ou Custom doses
    // toutes neutres). Avant fix #68, les doses ne servaient qu'à exclure
    // (poids 0) : hand=rare + rhythm=frequent en Extrême → 25 % de boosts
    // hand constants. Désormais : 0.4/(0.4+2.2) ≈ 15 %.
    final burstPick = _pickBurstMode(ctx);
    final useHandBurst = burstPick.useHandBurst;
    final burstMode = burstPick.burstMode;

    final boostResult = _emitBoosts(
      ctx,
      time: time,
      stamina: stamina,
      useHandBurst: useHandBurst,
      burstMode: burstMode,
    );
    time = boostResult.time;
    stamina = boostResult.stamina;
    final lastBoostIndex = boostResult.lastBoostIndex;

    // Final : action longue tenue qui clôture la séance. Distinct de la
    // phase « finish » (boosts) ; le final est l'apothéose contemplative.
    // Choisi parmi les candidats valides selon le score d'humiliation, le
    // plafond de profondeur du niveau, et la durée des holds profonds qui
    // scale avec le niveau et la chaîne d'encore.
    // Cap effectif au moment du final (=quasi fin de session, sessionCap
    // probablement saturé). Le générateur ne bénéficie pas des bumps
    // évènementiels (punition complétée etc.) — uniquement de la rampe
    // automatique — donc c'est volontairement conservateur.
    final finalResult = _emitFinalStep(
      ctx,
      time: time,
      stamina: stamina,
      lastBoostIndex: lastBoostIndex,
      burstMode: burstMode,
    );
    time = finalResult.time;
    stamina = finalResult.stamina;
    final finalCategory = finalResult.finalCategory;
    final finalMode = finalResult.finalMode;
    final finalStepStartTime = finalResult.finalStepStartTime;

    final postFinalResult = _emitPostFinal(
      ctx,
      time: time,
      stamina: stamina,
      finalMode: finalMode,
    );
    time = postFinalResult.time;
    stamina = postFinalResult.stamina;

    return _assembleResult(
      ctx,
      time: time,
      stamina: stamina,
      milestoneStartTime: milestoneScheduler.bodyStartTime,
      milestoneDurationSeconds: milestoneScheduler.bodyDurationSeconds,
      secondMilestoneStartTime: milestoneScheduler.secondBodyStartTime,
      secondMilestoneDurationSeconds:
          milestoneScheduler.secondBodyDurationSeconds,
      finalCategory: finalCategory,
      silentFinishStartTime: silentFinishStartTime,
      finalStepStartTime: finalStepStartTime,
    );
  }

  /// Émet **un step complet** dans `ctx.steps` + met à jour le profil
  /// stamina + la sim salive + l'état runtime (`_state.lastX`,
  /// `_rhythmChain`, `_patternBuffer`) + avance le curseur `time`.
  /// Retourne `(time, stamina)` mis à jour.
  ///
  /// Bundle 6-7 opérations qui se répétaient à l'identique sur ~10 sites
  /// (mini-vague, breath conditionnel, partDraft, fake breath, chain,
  /// preFinisher, boost, finalStep, postFinal…). L'ordre interne diffère
  /// légèrement de certains call sites historiques — c'est volontaire et
  /// sûr : ces opérations sont **orthogonales** (chacune mute un store
  /// distinct, aucune ne lit ce qu'une autre écrit dans la même itération).
  ///
  /// Non utilisé pour 3 sites qui ont des sémantiques particulières :
  ///   * **Intro step** (`_firstStep`) — utilise `cfg` direct (sans ctx),
  ///     fallback `?? 1` sur la durée (défensif).
  ///   * **Swallow order** (`_tryEmitSwallowOrder`) — appelle
  ///     `_state.salivaSim.forceSwallow()` au lieu de `_advanceSalivaSim`
  ///     (l'ordre matérialise une obéissance → reset, pas une accumulation).
  ///   * **Séquence milestone** (`_pushMilestoneSequence`) — émet des
  ///     `SessionStep` raw (pas via `_draftToStep`), gère `overrideText`
  ///     i18n, conditionne le tracking au `mStep.isTextOnly`.
  ///
  /// Paramètres :
  ///   * [asTransit] : `false` → `_state.recordLastAction(draft, text)` ;
  ///     `true` → `_state.recordLastTransit(draft.mode, text)`. Cf. doc
  ///     `SessionRuntimeState` pour la sémantique (action = mode/text/
  ///     from/to ; transit = mode/text seulement, préserve `lastFrom/lastTo`).
  ///   * [updateLastBpm] : si `true`, `_state.lastBpm = draft.bpm ?? _state.lastBpm`
  ///     après l'émission. À mettre pour les sites où la diversification
  ///     BPM du **prochain action step** doit comparer contre celui-ci
  ///     (mini-vague, boost). Inutile pour les transit/parts qui préservent
  ///     le `lastBpm` de l'outer step.
  ({int time, double stamina}) _emitStep(
    _GenContext ctx, {
    required StepDraft draft,
    required String text,
    required int time,
    required double stamina,
    required double progress,
    required bool asTransit,
    bool updateLastBpm = false,
  }) {
    ctx.steps.add(_draftToStep(draft, time: time, text: text));
    final staminaBefore = stamina;
    final newStamina =
        StaminaModel.apply(stamina, draft, progress, ctx.cfg, rules: _rules);
    _advanceSalivaSim(draft);
    StaminaModel.fillProfile(
      ctx.profile,
      time,
      draft.duration!,
      newStamina,
      valueStart: staminaBefore,
    );
    if (asTransit) {
      _state.recordLastTransit(draft.mode, text);
    } else {
      _state.recordLastAction(draft, text);
    }
    if (updateLastBpm) {
      _state.lastBpm = draft.bpm ?? _state.lastBpm;
    }
    _trackPushedStep(
      draft.mode,
      draft.to,
      from: draft.from,
      bpm: draft.bpm,
      duration: draft.duration,
    );
    return (time: time + draft.duration!, stamina: newStamina);
  }

  /// Phase 2 du main loop : tentative d'émission d'une **mini-vague** +
  /// **breath long post-vague**. Renvoie `null` si les conditions ne
  /// sont pas réunies (cf. [_shouldEmitMiniWave]). Sinon émet les 2-3
  /// steps de la vague puis (si la place le permet) le breath dédié, et
  /// replanifie `_state.nextMiniWaveAt` à `time + 4-5 min`. Le caller
  /// `continue`-ra la boucle main.
  ///
  /// Mute `ctx.steps`, `ctx.profile` et l'état `_state`. Retourne
  /// `(newTime, newStamina)` quand une vague a été émise.
  ({int time, double stamina})? _tryEmitMiniWaveCycle(
    _GenContext ctx, {
    required int time,
    required double stamina,
  }) {
    if (!_shouldEmitMiniWave(
        time, ctx.effectiveDuration, stamina, ctx.genUntil)) {
      return null;
    }
    final progressForWave = time / ctx.effectiveDuration;
    final humilCapForWave = _config.humilCapAt(time);
    final waveDrafts = _buildMiniWave(humilCapForWave);
    for (final wd in waveDrafts) {
      final waveText = _pickPhraseForDraft(ctx.bank, wd, 'hard');
      final r = _emitStep(
        ctx,
        draft: wd,
        text: waveText,
        time: time,
        stamina: stamina,
        progress: progressForWave,
        asTransit: false,
        updateLastBpm: true,
      );
      time = r.time;
      stamina = r.stamina;
    }
    // Pause longue post-vague : breath dédié dimensionné pour viser
    // ~95 stamina, sortie volontaire du cap [4,12] du sas breath
    // standard — la vague est un mini-finish, on s'autorise une vraie
    // respiration scénarisée derrière pour repartir de plein. Borne
    // [12, 20] s : 12 = baseline minimale même si stamina déjà haute,
    // 20 = plafond pour ne pas casser le rythme dramaturgique de la
    // session. À niveau 9 milieu de séance (regen ≈ 1.6, ≈ 4.5/s),
    // 15-20 s rendent ~70-90 stamina.
    final postWaveProgress = time / ctx.effectiveDuration;
    final postWaveBreath = _buildPostWaveBreath(
        stamina, postWaveProgress, ctx.cfg, ctx.genUntil - time);
    if (postWaveBreath != null) {
      final breathText = _pickPhrase(ctx.bank, SessionMode.breath, 'soft');
      final r = _emitStep(
        ctx,
        draft: postWaveBreath,
        text: breathText,
        time: time,
        stamina: stamina,
        progress: postWaveProgress,
        asTransit: true,
      );
      time = r.time;
      stamina = r.stamina;
    }
    // Replanification : 4-5 minutes après la fin de la vague émise.
    // La séance enchaîne ensuite sur du tirage classique — la stamina
    // restaurée par la pause longue permet d'enchaîner sereinement
    // jusqu'à la prochaine vague.
    _state.nextMiniWaveAt = time + 240 + _rng.nextInt(61);
    return (time: time, stamina: stamina);
  }

  /// Phase 3 du main loop : tentative d'émission d'un **ordre de
  /// déglutition forcé** (beg libre court « avale tout ») quand la
  /// simulation salive sature. Renvoie `null` si les conditions ne sont
  /// pas réunies (cf. [_maybeBuildSwallowOrder]).
  ///
  /// La sim salive retombe à 0 (`forceSwallow`) pour mimer l'obéissance
  /// runtime — le `SessionController` fera de même au beat suivant via
  /// `SalivaEngine.forceSwallow()`. Pose aussi le cooldown 90 s via
  /// `_state.lastSwallowOrderAt`.
  ({int time, double stamina})? _tryEmitSwallowOrder(
    _GenContext ctx, {
    required int time,
    required double stamina,
  }) {
    final swallowDraft = _maybeBuildSwallowOrder(time, ctx.genUntil);
    if (swallowDraft == null) return null;
    final swallowText = ctx.bank.pickSwallowOrder(_rng) ??
        _pickPhrase(ctx.bank, SessionMode.beg, 'hard');
    ctx.steps.add(_draftToStep(swallowDraft, time: time, text: swallowText));
    final staminaBefore = stamina;
    stamina = StaminaModel.apply(
        stamina, swallowDraft, time / ctx.effectiveDuration, ctx.cfg,
        rules: _rules);
    // Conséquence simulée de l'ordre : la sim retombe à 0, comme si
    // la joueuse obéissait. En runtime le SessionController fera de
    // même via `SalivaEngine.forceSwallow()`.
    _state.salivaSim.forceSwallow();
    StaminaModel.fillProfile(ctx.profile, time, swallowDraft.duration!, stamina,
        valueStart: staminaBefore);
    _state.recordLastTransit(SessionMode.beg, swallowText);
    _trackPushedStep(SessionMode.beg, null, duration: swallowDraft.duration);
    time += swallowDraft.duration!;
    _state.lastSwallowOrderAt = time;
    return (time: time, stamina: stamina);
  }

  /// Phase 4 du main loop : génération + émission d'un **main step**.
  /// Toujours émet (jamais `null`) — c'est le cœur de la boucle, appelé
  /// quand les phases d'insertion conditionnelles (milestone, mini-vague,
  /// swallow) ont toutes passé leur tour.
  ///
  /// Flow interne :
  ///   1. Fenêtre de difficulté `[boundedMin, windowMax]` modulée par
  ///      progress + plancher quickie ; tirage `diff`.
  ///   2. Choix recovery vs `_mapDifficultyToStep(diff)` selon stamina
  ///      et seuils obédiance-modulés.
  ///   3. Transformations en cascade : `BegRules.stripAfterSoft` →
  ///      `_enforceHumiliationRequired` → `_applyBpmDiversity` →
  ///      `_diversifyAmplitude` → `BpmPacing.maybeApplyBpmRamp` →
  ///      `_clampToCapability` (2ᵉ enveloppe, dernier mot).
  ///   4. Sas breath conditionnel si la stamina projetée < 0.
  ///   5. Diversification en sous-segments (`BpmPacing.diversifyLongSegment`)
  ///      + émission texte sur le 1ᵉʳ seulement.
  ///   6. Fake breath optionnel (niveau ≥ 12, post-step intense).
  ///   7. Chain action attachée (`draft.chainNext`) sans nouveau texte.
  ///   8. debugPrint en kDebugMode.
  ({int time, double stamina}) _emitMainStepCycle(
    _GenContext ctx, {
    required int time,
    required double stamina,
  }) {
    final progress = time / ctx.effectiveDuration;
    final windowMin = StaminaModel.lerp(0.05, 0.50, progress);
    var windowMax =
        min(StaminaModel.lerp(0.30, 1.00, progress), ctx.cfg.maxDifficultyCap);
    // Floor d'intensité (mode bâclée) : tronque le bas de la fenêtre.
    final flooredMin = max(windowMin, ctx.intensityFloor);
    final boundedMin = min(flooredMin, windowMax - 0.05).clamp(0.0, 1.0);
    windowMax = max(windowMax, boundedMin + 0.05);

    final diff = boundedMin + _rng.nextDouble() * (windowMax - boundedMin);

    final StepDraft initialDraft;
    // Seuils de recovery modulés par l'obéissance : plus elle est haute,
    // plus on respecte l'endurance (recovery déclenché plus tôt). Sur la
    // dernière minute, on les coupe entièrement — la fin de séance ignore
    // l'endurance par contrat.
    final inLastMinute = (ctx.effectiveDuration - time) <= 60;
    // Bonus obédiance sur le seuil de recovery : capé +25 pour pas
    // qu'une obédiance lifetime extrême (200+) pousse le seuil à 80
    // (= recovery quasi-permanente). À obed=100, +25 ; à obed=0, +0.
    final obedienceBonus = (_config.obedience / 100.0).clamp(0.0, 1.0) * 25.0;
    final recoveryThreshold =
        inLastMinute ? -1 : (ctx.quickie ? 15 : 30) + obedienceBonus;
    final recoveryRandomThreshold =
        inLastMinute ? -1 : (ctx.quickie ? 25 : 50) + obedienceBonus;
    if (stamina < recoveryThreshold ||
        (stamina < recoveryRandomThreshold && _rng.nextBool())) {
      initialDraft = _buildRecoveryStep();
    } else {
      initialDraft = _mapDifficultyToStep(diff);
    }
    // Si beg arrive juste après une phase douce (lick / breath), on
    // retire le `from` pour enchaîner sur une supplique purement vocale
    // plutôt que de redemander de tenir une position. Côté stamina,
    // beg avec from=null suit la même branche regen que from=head.
    var draft = BegRules.stripAfterSoft(initialDraft, ctx.steps);

    // Filtre humiliation requise : on garde uniquement ce que le cap
    // effectif (career + session projeté à `time`) permet. La rampe
    // session (+1/min en clean, ×3 max avec obed, capée à sessionCap)
    // est intégrée par `_config.humilCapAt`.
    final humilCap = _config.humilCapAt(time);
    draft = _enforceHumiliationRequired(draft, humilCap);

    // Variété BPM : évite d'enchaîner des steps au même tempo.
    draft = _applyBpmDiversity(draft);
    // Variété amplitude : évite d'enchaîner deux fois exactement la
    // même paire from/to dans le même mode.
    draft = _diversifyAmplitude(draft);
    // Rampe BPM intra-step : pour les steps longs (≥ 30 s) sur amplitude
    // moyenne (≤ mid), pose `bpmEnd` distinct pour raconter une
    // montée / descente sur la durée. Skip throat/full pour ne pas
    // violer le cap pulses (cf. `_capRhythmDurationByPulses`).
    draft = BpmPacing.maybeApplyBpmRamp(draft, progress, _rng, _config.level);
    // 2ᵉ enveloppe (profil de capacités) : dernier mot après les
    // diversifications BPM/amplitude qui ont pu remonter au-dessus du
    // `comfort` prouvé. `_diversifyLongSegment` derrière ne fait que
    // varier « égal ou plus doux », donc pas besoin de re-clamper.
    draft = _clampToCapability(draft);

    // Sas breath conditionnel : on insère un breath UNIQUEMENT si le
    // draft retenu provoquerait un déficit d'endurance (stamina projetée
    // < 0). Pas de breath gratuit quand on a encore 80% — on ne respire
    // que quand on en a vraiment besoin pour tenir la step suivante.
    // Le breath est à durée variable, calée pour combler le déficit.
    // Skip si le draft est lui-même breath (jamais le cas via la boucle
    // standard) ou si on est à <8s du genUntil (laisse la place au
    // pré-finisher / boost).
    if (draft.mode != SessionMode.breath && ctx.genUntil - time > 8) {
      final delta = StaminaModel.delta(draft, progress, ctx.cfg, rules: _rules);
      final projected = stamina + delta;
      if (projected < 0) {
        final breathDraft = _buildBreathRecovery(-projected, progress, ctx.cfg);
        final breathText = _pickPhrase(ctx.bank, SessionMode.breath, 'soft');
        // breath = transit → ne touche pas `_state.lastType` (parenthèse
        // transparente, cf. doc `SessionRuntimeState.recordLastTransit`).
        final r = _emitStep(
          ctx,
          draft: breathDraft,
          text: breathText,
          time: time,
          stamina: stamina,
          progress: progress,
          asTransit: true,
        );
        time = r.time;
        stamina = r.stamina;
      }
    }

    // Diversification interne : si la step dure plus de 40s et qu'elle
    // est rythmique (rhythm/lick/hand), on la split en 2-3 sous-segments
    // avec une variation BPM/profondeur entre chaque, pour qu'une longue
    // phase ne sonne pas comme un loop monotone. Les sous-segments
    // s'autorisent un léger dépassement BPM (≤ +10) — on re-borne donc
    // chacun au profil de capacités.
    final emitDrafts = BpmPacing.diversifyLongSegment(draft, _rng)
        .map(_clampToCapability)
        .toList();

    final tier = diff < 0.33
        ? 'soft'
        : diff < 0.66
            ? 'medium'
            : 'hard';

    for (var partIdx = 0; partIdx < emitDrafts.length; partIdx++) {
      final partDraft = emitDrafts[partIdx];
      // Texte sur le 1er sous-segment seulement : la phrase est cohérente
      // avec le tier global. Les sous-segments suivants déclencheront
      // automatiquement les phrases de transition (cf. C2) puisque BPM
      // ou profondeur change entre eux.
      final partText =
          partIdx == 0 ? _pickPhraseForDraft(ctx.bank, partDraft, tier) : '';
      final r = _emitStep(
        ctx,
        draft: partDraft,
        text: partText,
        time: time,
        stamina: stamina,
        progress: progress,
        asTransit: false,
      );
      time = r.time;
      stamina = r.stamina;
    }

    // **Fake breath** (à partir du niveau 12) : après un step intense
    // (rythme to=throat/full ou hold throat/full), on a une chance
    // d'insérer un breath très court (2-3 s) qui mime une vraie pause
    // mais qui ne suffit pas à reconstituer la stamina. La step suivante
    // tirée par la boucle continuera sur sa lancée — la joueuse croit
    // souffler, en fait elle reprend direct. Effet de surprise validé
    // pour les niveaux avancés où la dramaturgie peut se permettre
    // d'être trompeuse. Pas en dernière minute (on respecte le finish
    // scriptée), pas si on est déjà en déficit (un vrai breath était
    // déjà inséré plus haut).
    final fakeBreath = _maybeBuildFakeBreath(
      lastEmitted: emitDrafts.isNotEmpty ? emitDrafts.last : draft,
      currentStamina: stamina,
      time: time,
      genUntil: ctx.genUntil,
      bank: ctx.bank,
    );
    if (fakeBreath != null) {
      final r = _emitStep(
        ctx,
        draft: fakeBreath.draft,
        text: fakeBreath.text,
        time: time,
        stamina: stamina,
        progress: progress,
        asTransit: true,
      );
      time = r.time;
      stamina = r.stamina;
    }

    // Chain action attachée au draft principal (beg + suite continue) :
    // émise immédiatement après les sous-segments, sans nouveau texte
    // d'intro (la consigne est déjà dans la phrase du beg).
    final chain = draft.chainNext;
    if (chain != null && chain.duration != null) {
      final r = _emitStep(
        ctx,
        draft: chain,
        text: '',
        time: time,
        stamina: stamina,
        progress: progress,
        asTransit: false,
      );
      time = r.time;
      stamina = r.stamina;
    }

    if (kDebugMode) {
      debugPrint(
        '[career-gen] t=$time mode=${draft.mode.name} '
        'bpm=${draft.bpm} from=${draft.from?.name} to=${draft.to?.name} '
        'dur=${draft.duration} diff=${diff.toStringAsFixed(2)} '
        'stamina=${stamina.toStringAsFixed(1)} '
        'parts=${emitDrafts.length}',
      );
    }

    return (time: time, stamina: stamina);
  }

  /// Vrai si on doit émettre une **mini-vague** au pas courant de la
  /// boucle main. Conditions cumulatives :
  /// - durée totale ≥ 12 min (sinon pas le temps de respirer entre la
  ///   vague et le finish ; les sessions courtes gardent leur diagonale
  ///   d'intensité simple).
  /// - niveau ≥ 5 (pédagogie : on ne surprend pas une débutante avec
  ///   un mini-finish dramatique au milieu de la séance).
  /// - `time >= _state.nextMiniWaveAt` (replanifié après chaque vague).
  /// - `genUntil - time >= 90 s` (laisse une marge avant la phase finish
  ///   pour ne pas chevaucher pré-finisher / boosts).
  /// - stamina ≥ 35 (assoupli vs 50 initial : sur les profils profondeur
  ///   + endurance basse, la stamina creuse vite et la vague était
  ///   skippée systématiquement aux 5-6 min. La pause longue post-vague
  ///   replenit derrière, donc on peut émettre depuis une stamina plus
  ///   modeste sans casser la dramaturgie).
  bool _shouldEmitMiniWave(
      int time, int effectiveDuration, double stamina, int genUntil) {
    if (effectiveDuration < 720) return false;
    if (_config.level < 5) return false;
    if (time < _state.nextMiniWaveAt) return false;
    if (genUntil - time < 90) return false;
    if (stamina < 35) return false;
    // La mini-vague est intégralement rhythm (cf. `_buildMiniWave`) : si
    // rhythm est exclu en Custom, on ne sait pas la jouer — on la skip
    // proprement plutôt que d'émettre un mode banni.
    if (_config.isModeForbidden(SessionMode.rhythm)) return false;
    return true;
  }

  /// Construit la séquence de la mini-vague : 2 à 3 steps rythmés à BPM
  /// montant, chacun à profondeur progressive (head→mid puis head→mid
  /// puis head→throat si débloqué). Variations de `to` choisies pour ne
  /// pas trigger le détecteur de pattern plat (`_patternBuffer.wouldBeFlat`)
  /// et pour matérialiser la montée à l'oreille (BPMs espacés de 20).
  ///
  /// Chaque step est filtré par `_enforceHumiliationRequired(humilCap)` :
  /// si la vague propose un step trop humiliant pour le cap courant, il
  /// dégrade vers du plus doux automatiquement (ex throat → mid). Si après
  /// dégradation un step duplique le précédent, il est skip plutôt que
  /// re-poussé — la vague peut donc se réduire à 2 steps en pratique.
  List<StepDraft> _buildMiniWave(double humilCap) {
    final hasThroat = _state.unlockedKeys.contains(UnlockKey.throatHoldShort) ||
        _config.maxDepthIndex >= Position.throat.index;
    // Steps montants : BPMs espacés de 20 pour que la variance détectée
    // par `_patternBuffer.wouldBeFlat` (< 10) ne déclenche pas. Choix
    // mode=rhythm sur les 3 steps pour cohérence dramaturgique (un seul
    // mode = montée homogène). `to` qui change évite aussi le pattern
    // plat — la diversification interne ne peut pas le casser.
    final raw = <StepDraft>[
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 100,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 120,
        from: Position.head,
        to: Position.mid,
        duration: 10,
      ),
      StepDraft(
        mode: SessionMode.rhythm,
        bpm: 135,
        from: Position.head,
        to: hasThroat ? Position.throat : Position.mid,
        duration: 8,
      ),
    ];
    final out = <StepDraft>[];
    Position? prevTo;
    int? prevBpm;
    for (final s in raw) {
      final filtered = _enforceHumiliationRequired(s, humilCap);
      // Skip si la dégradation rend ce step identique au précédent
      // (mêmes from/to/bpm) — la vague compresserait sinon en plat.
      if (filtered.to == prevTo && filtered.bpm == prevBpm) continue;
      out.add(filtered);
      prevTo = filtered.to;
      prevBpm = filtered.bpm;
    }
    // Garde au minimum 2 steps : si la cascade a tout aplati (cas humil
    // très basse en début de niveau 5), on retombe sur les 2 premiers
    // steps de `raw` sans filtre humil, qui sont volontairement modérés
    // (head→mid 100/120 — req mécanique très basse). On les borne quand
    // même au profil de capacités.
    if (out.length < 2) {
      return raw.take(2).map(_clampToCapability).toList();
    }
    return out;
  }

  /// Construit la **pause longue post-vague** : breath dédié dont la
  /// durée vise à remonter la stamina à ~95 (`_postWaveBreathTarget`).
  /// Distinct du sas breath standard (`_buildBreathRecovery`) qui cap à
  /// 12 s — ici on s'autorise jusqu'à 20 s parce que la vague est un
  /// mini-finish dramatique : on assume une vraie respiration scénarisée
  /// derrière, pas un soupir de 6 s.
  ///
  /// Borne basse 12 s : même si la stamina est déjà haute (cas vague
  /// dégradée par humilCap qui n'a pas creusé), on garde une pause
  /// audible — le silence post-vague est un moment dramaturgique.
  ///
  /// Borne haute 20 s : au-delà, la pause devient plus longue que la
  /// vague elle-même (~30 s) et le coach radoterait du soft. La regen
  /// finit le job sur les phases libres suivantes si besoin.
  ///
  /// Retourne null si moins de 12 s sont disponibles avant `genUntil`
  /// (rare : la vague checke déjà `genUntil - time >= 90`, mais la
  /// vague elle-même consomme jusqu'à 30 s, donc on revérifie ici).
  StepDraft? _buildPostWaveBreath(
    double stamina,
    double progress,
    CareerLevel cfg,
    int remainingSeconds,
  ) {
    if (remainingSeconds < 12) return null;
    final regen = StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    final regenPerSec = 2.8 * regen;
    const target = 95.0;
    final deficit = (target - stamina).clamp(0.0, target);
    final raw = regenPerSec <= 0 ? 12.0 : deficit / regenPerSec;
    // Borne dur entre [12, 20] et capée par le temps restant avant le
    // pré-finisher / boosts pour ne pas marcher sur la dramaturgie de
    // fin de session.
    final upperBound = remainingSeconds < 20 ? remainingSeconds : 20;
    final dur = raw.ceil().clamp(12, upperBound);
    return StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Construit éventuellement un step **swallow_order** : beg libre court
  /// (5-7 s) qui matérialise l'ordre coach « avale tout » quand la sim
  /// salive sature. Sans ce mécanisme, `SalivaEngine` est un compteur
  /// silencieux — la jauge monte, l'auto-déglutition se déclenche
  /// silencieusement, et la mécanique "saliva" n'a aucun rendu côté
  /// dramaturgie. Avec ce step, un overflow projeté devient un moment
  /// audible : phrase impérative + mini-pause beg libre.
  ///
  /// Conditions cumulatives :
  /// - `_state.salivaSim.value >= 80` : marge de 10 sous le seuil overflow (90)
  ///   pour anticiper et ne pas attendre que ça déborde réellement
  ///   (l'auto-swallow runtime peut intercepter à 75 et masquer).
  /// - `time - _state.lastSwallowOrderAt >= 90` : cooldown 90 s pour ne pas
  ///   spammer les ordres en série (cas spé sloppy à fond sur lick).
  /// - `genUntil - time >= 60` : marge avant le finish — la dramaturgie
  ///   scriptée ne doit pas être interrompue par un ordre opportuniste.
  /// - `begLibre` débloqué (sinon on imposerait une mécanique avant la
  ///   pédagogie qui la déverrouille).
  ///
  /// Retourne null si une condition manque.
  StepDraft? _maybeBuildSwallowOrder(int time, int genUntil) {
    if (_state.salivaSim.value < 80.0) return null;
    if (time - _state.lastSwallowOrderAt < 90) return null;
    if (genUntil - time < 60) return null;
    if (!_state.unlockedKeys.contains(UnlockKey.begLibre)) return null;
    final dur = 5 + _rng.nextInt(3); // [5, 7]
    return StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Adaptateur d'instance pour `FinalPicker.buildPostFinalDraft`. Injecte
  /// le `holdCeilingIdx` calculé depuis `_state.unlockedKeys` + `_config.maxDepthIndex`
  /// — qui n'est pas dans `FinalPicker` car partagé avec `_pickHoldPosition`
  /// et d'autres call sites.
  StepDraft _buildPostFinalDraft(SessionMode finalMode, double humilCap) =>
      _finalPicker.buildPostFinalDraft(
        finalMode: finalMode,
        humilCap: humilCap,
        holdCeilingIdx: _milestoneHoldCeilingIdx(),
      );

  /// Convertit un [SessionStep] (issu du JSON ou d'une milestone) en
  /// [StepDraft] interne pour pouvoir le passer à `_applyStaminaChange`.
  /// Convention uniforme : hold/beg portent leur position dans `to` ;
  /// aucun swap.
  StepDraft _stepToDraft(SessionStep step, SessionMode defaultMode) {
    final mode = step.mode ?? defaultMode;
    return StepDraft(
      mode: mode,
      bpm: step.bpm,
      from: step.from,
      to: step.to,
      duration: step.duration ?? 0,
    );
  }

  /// Émet une séquence milestone (body ou final) dans la timeline en cours.
  ///
  /// Logique partagée entre l'insertion d'une milestone body (closure
  /// `insertPending` dans [generate]) et le path final-milestone : itère
  /// `m.sequence`, ajoute chaque step à `ctx.steps` avec son `text`
  /// éventuellement surchargé via `ctx.milestoneTextResolver`, met à jour
  /// stamina + simu salive, fillProfile, et tracke la continuité par type.
  /// À la fin, met à jour `_state.lastMode` / `_state.lastText` à partir du dernier step.
  ///
  /// Retourne `(newTime, newStamina)` — le caller continue avec ces valeurs.
  /// `time` ressort incrémenté de `milestone.durationSeconds`. Les listes
  /// `ctx.steps` et `ctx.profile` sont mutées en place.
  ({int time, double stamina}) _pushMilestoneSequence(
    _GenContext ctx, {
    required LevelMilestone milestone,
    required int time,
    required double stamina,
  }) {
    var t = time;
    var s = stamina;
    for (final mStep in milestone.sequence) {
      // Si une surcharge i18n existe pour ce step (clé = offset `time` du
      // step dans la sequence), on l'utilise à la place du `text` du JSON
      // principal.
      final overrideText =
          ctx.milestoneTextResolver?.call(milestone.id, mStep.time);
      ctx.steps.add(SessionStep(
        time: t + mStep.time,
        text: overrideText ?? mStep.text,
        mode: mStep.mode,
        bpm: mStep.bpm,
        from: mStep.from,
        to: mStep.to,
        duration: mStep.duration,
        swallowMode: mStep.swallowMode,
      ));
      // Simulation stamina/salive pour chaque step de la séquence, pour que
      // la projection reste cohérente.
      final mDraft = _stepToDraft(mStep, SessionMode.rhythm);
      final staminaBefore = s;
      s = StaminaModel.apply(s, mDraft, t / ctx.effectiveDuration, ctx.cfg,
          rules: _rules);
      _advanceSalivaSim(mDraft);
      StaminaModel.fillProfile(
          ctx.profile, t + mStep.time, mStep.duration ?? 0, s,
          valueStart: staminaBefore);
      // Tracking de continuité par type — chaque step de la séquence compte
      // (la séquence peut elle-même alterner bouche/transit).
      if (mStep.mode != null && !mStep.isTextOnly) {
        _trackPushedStep(mStep.mode!, mStep.to,
            from: mStep.from, bpm: mStep.bpm, duration: mStep.duration);
      }
    }
    // Met à jour le « dernier mode/texte » avec le dernier step de la
    // milestone — sert au filtrage anti-répétition de la suite générée.
    final lastStep = milestone.sequence.last;
    _state.lastMode = lastStep.mode ?? _state.lastMode;
    _state.lastText = lastStep.text;
    t += milestone.durationSeconds;
    return (time: t, stamina: s);
  }

  /// Émet le step de pré-finisher (courte accélération rythme `head→target`
  /// qui prépare la phase boosts). Utilisé uniquement pour les bas niveaux —
  /// le caller garde la guard `isLowLevel && !_config.isModeForbidden(rhythm)` autour
  /// de l'appel pour ne pas changer la séquence RNG (la position est pickée
  /// avant l'appel).
  ///
  /// Mute `ctx.steps` et `ctx.profile` en place. Met à jour
  /// `_state.lastMode/_state.lastText` et tracke la continuité.
  /// Retourne `(newTime, newStamina)`.
  ({int time, double stamina}) _emitPreFinisher(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required Position preFinisherTarget,
  }) {
    final preDur = 22 + _rng.nextInt(9); // [22, 30]
    final preBpm = 62 + _rng.nextInt(9); // [62, 70]
    final preDraft = _clampToCapability(StepDraft(
      mode: SessionMode.rhythm,
      bpm: preBpm,
      from: Position.head,
      to: preFinisherTarget,
      duration: preDur,
    ));
    final preText = _pickPhraseForDraft(ctx.bank, preDraft, 'medium');
    return _emitStep(
      ctx,
      draft: preDraft,
      text: preText,
      time: time,
      stamina: stamina,
      progress: time / ctx.effectiveDuration,
      asTransit: true,
    );
  }

  /// Choix du mode pour la phase de boosts (`hand_burst` non humiliant vs
  /// `rhythm_burst` humiliant). Gère :
  ///  - le biais dramaturgique 70/30 vs 25/75 selon humil + niveau ;
  ///  - les exclusions Custom (`_config.isModeForbidden`) avec repli `lick` quand
  ///    hand ET rhythm sont bannis ;
  ///  - le ratio de poids brut quand les doses hand/rhythm sont asymétriques
  ///    (cf. issue #68).
  ///
  /// Consomme un tirage RNG quand les deux modes sont autorisés.
  ({bool useHandBurst, SessionMode burstMode}) _pickBurstMode(_GenContext ctx) {
    final handForbidden = _config.isModeForbidden(SessionMode.hand);
    final rhythmForbidden = _config.isModeForbidden(SessionMode.rhythm);
    final preferHandBase =
        _config.humiliationCareer < 5 && _config.level <= 3 ? 0.70 : 0.25;
    if (handForbidden && rhythmForbidden) {
      // chemin "rhythm-like" : BPM cap/floor rhythm
      return (useHandBurst: false, burstMode: SessionMode.lick);
    }
    if (handForbidden) {
      return (useHandBurst: false, burstMode: SessionMode.rhythm);
    }
    if (rhythmForbidden) {
      return (useHandBurst: true, burstMode: SessionMode.hand);
    }
    final handWeight = _config.coachModeWeights[SessionMode.hand] ?? 1.0;
    final rhythmWeight = _config.coachModeWeights[SessionMode.rhythm] ?? 1.0;
    final dosesAreSymmetric = (handWeight - rhythmWeight).abs() < 0.01;
    final preferHand = dosesAreSymmetric
        ? preferHandBase
        : handWeight / (handWeight + rhythmWeight);
    final useHandBurst = _rng.nextDouble() < preferHand;
    return (
      useHandBurst: useHandBurst,
      burstMode: useHandBurst ? SessionMode.hand : SessionMode.rhythm,
    );
  }

  /// Boucle des boosts de la phase finish — sprint déterministe de
  /// `ctx.boostsCount` steps qui ramp BPM et profondeur de manière monotone
  /// croissante. Renvoie l'index du dernier step ajouté à `ctx.steps` (pour
  /// que l'annonce du final puisse y faire référence si besoin), ainsi que
  /// les nouveaux `(time, stamina)`.
  ///
  /// Les listes `ctx.steps` et `ctx.profile` sont mutées en place. Met à
  /// jour `_state.lastMode/_state.lastText/_state.lastBpm` à chaque boost émis et tracke la
  /// continuité.
  ({int time, double stamina, int? lastBoostIndex}) _emitBoosts(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required bool useHandBurst,
    required SessionMode burstMode,
  }) {
    // Plafond humiliation pour les bursts. Hand n'est pas gating par
    // humiliation (cap inutile), mais on laisse `_enforceHumiliationRequired`
    // tourner — il rejettera juste si la profondeur du draft demande trop.
    // Cap assoupli pour les boosts : projection au temps `time` du début
    // de la phase finish, +8 de tolérance pour permettre des bursts un
    // poil au-dessus du cap mécanique strict (tradition du finish).
    final boostHumilCap = _config.humilCapAt(time) + 8.0;
    // Nombre total de boosts : table par niveau + bonus encore (fixé en
    // amont via `boostsCount`). Plus de boucle conditionnelle sur la
    // jauge — le sprint est entièrement déterministe.
    final totalBoosts = max(1, ctx.boostsCount);
    // **BPM cap qui scale par niveau ET par chaîne d'encore** : niveau 1
    // plafonne à ~110 BPM (hand) / 130 (rhythm), +4 BPM/niveau jusqu'à un
    // plafond de garde-fou à 300 (très haut — c'est le `comfort` du profil
    // de capacités qui borne en pratique, via `_clampToCapability`). Le
    // mode encore ajoute +8 BPM par cran de chaîne pour intensifier le
    // sprint sans changer le nombre de boosts.
    final levelBpmBoost =
        ((_config.level - 1) * 4 + max(0, ctx.encoreChainIndex) * 8)
            .clamp(0, 70);
    final bpmCap = useHandBurst
        ? (110 + levelBpmBoost).clamp(110, 300)
        : (130 + levelBpmBoost).clamp(130, 300);
    final bpmFloor = useHandBurst ? 80 : 100;
    // Cap de profondeur des boosts gaté par les milestones effectivement
    // acquittées (cf. `_milestoneRhythmCeilingIdx`) : throat ouvert si
    // `throatPulse` débloqué (intro_throat_pulse), full si `fullPulse`
    // (intro_full_pulse). Indépendant du niveau seul — sauter des milestones
    // ne donne pas accès aux profondeurs. Borné par `_config.maxDepthIndex` en
    // sécurité, et par mid (idx 2) au minimum (un boost ne descend jamais
    // sous mid pour rester reconnaissable comme un sprint).
    final boostMaxToIdx = max(2, _milestoneRhythmCeilingIdx());
    int? lastBoostIndex;
    // Monotonie ascendante : la phase finish ne doit JAMAIS ralentir. Chaque
    // boost démarre sur un BPM ≥ au précédent (idem pour la profondeur `to`).
    int prevBoostBpm = 0;
    int prevBoostToIdx = 0;
    final plannedBoosts = totalBoosts;
    var t = time;
    var s = stamina;
    for (var boostsAdded = 0; boostsAdded < totalBoosts; boostsAdded++) {
      // Durée variable : 12 à 16 s par défaut, +1s par cran de chaîne
      // encore pour allonger un peu chaque sprint.
      final boostDur =
          12 + _rng.nextInt(5) + max(0, ctx.encoreChainIndex).clamp(0, 4);
      // Progression linéaire 0→1 sur les `plannedBoosts`. Plancher 0.4 :
      // pas de démarrage mou.
      final progress = plannedBoosts <= 1
          ? 1.0
          : ((boostsAdded + 1) / plannedBoosts).clamp(0.4, 1.0);
      final targetBpm = (bpmFloor + progress * (bpmCap - bpmFloor)).round();
      // Jitter ±5 BPM autour de la cible pour ne pas répéter exactement
      // le même tempo deux boosts d'affilée. Capé par bpmCap.
      final shift = _rng.nextInt(11) - 5;
      final bpmRaw = (targetBpm + shift).clamp(bpmFloor, bpmCap);
      // Plancher monotone : on ne descend jamais sous le BPM du boost
      // précédent.
      final bpm =
          bpmRaw <= prevBoostBpm ? min(prevBoostBpm + 4, bpmCap) : bpmRaw;
      // Profondeur : ramp aussi sur la progression. Plancher `prevBoostToIdx`
      // garantit la monotonie.
      final rampDenom = plannedBoosts <= 1 ? 1 : (plannedBoosts - 1);
      final progressionToIdx =
          (boostMaxToIdx - 2 + 2 * (boostsAdded / rampDenom).clamp(0.0, 1.0))
              .round()
              .clamp(2, boostMaxToIdx);
      final toIdx = max(prevBoostToIdx, progressionToIdx);
      final boostTo = Position.values[toIdx];
      // `from` : 2 crans au-dessus si possible (amplitude max), sinon 1 cran.
      final boostFromIdx =
          _rng.nextBool() && toIdx >= 2 ? max(0, toIdx - 2) : max(0, toIdx - 1);
      final boostFrom = Position.values[boostFromIdx];
      final boostDraftRaw = StepDraft(
        mode: burstMode,
        bpm: bpm,
        from: boostFrom,
        to: boostTo,
        duration: boostDur,
      );
      // Hand : pas de gating humil → on garde amplitude max. Rhythm : cap
      // normal du finish. Dans les deux cas, `_clampToCapability` (qui
      // applique aussi les bornes utilisateur Custom).
      final boostDraft = useHandBurst
          ? _clampToCapability(boostDraftRaw)
          : _enforceHumiliationRequired(boostDraftRaw, boostHumilCap);
      // Tier dédié `boost` ; fallback `hard` si la bank n'a rien.
      var boostText = _pickPhraseForDraft(ctx.bank, boostDraft, 'boost');
      if (boostText.isEmpty) {
        boostText = _pickPhraseForDraft(ctx.bank, boostDraft, 'hard');
      }
      ctx.steps.add(_draftToStep(boostDraft, time: t, text: boostText));
      lastBoostIndex = ctx.steps.length - 1;
      _state.recordLastTransit(boostDraft.mode, boostText);
      _state.lastBpm = boostDraft.bpm ?? _state.lastBpm;
      _trackPushedStep(boostDraft.mode, boostDraft.to,
          from: boostDraft.from,
          bpm: boostDraft.bpm,
          duration: boostDraft.duration);
      final staminaBeforeBoost = s;
      s = StaminaModel.apply(s, boostDraft, 1.0, ctx.cfg, rules: _rules);
      _advanceSalivaSim(boostDraft);
      StaminaModel.fillProfile(ctx.profile, t, boostDur, s,
          valueStart: staminaBeforeBoost);
      t += boostDur;
      // Mémorise BPM/profondeur retenus (post-dégradation humil) pour que le
      // boost suivant ne puisse pas redescendre sous ce palier.
      prevBoostBpm = boostDraft.bpm ?? prevBoostBpm;
      if (boostDraft.to != null) {
        prevBoostToIdx = max(prevBoostToIdx, boostDraft.to!.index);
      }
    }
    return (time: t, stamina: s, lastBoostIndex: lastBoostIndex);
  }

  /// Émet le step final (apothéose contemplative). Choix via [FinalPicker.pickFinal] selon
  /// humil cap projeté à `time` et plafond de profondeur. Phrase : annonce du
  /// changement de mode si différent du dernier boost (« sors ta langue,
  /// j'arrive »), sinon phrase d'action standard.
  ///
  /// Retourne `(time, stamina, finalCategory, finalMode, finalStepStartTime)`.
  /// Mute `ctx.steps` et `ctx.profile` en place.
  ({
    int time,
    double stamina,
    FinalCategory finalCategory,
    SessionMode finalMode,
    int finalStepStartTime,
  }) _emitFinalStep(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required int? lastBoostIndex,
    required SessionMode burstMode,
  }) {
    // Cap effectif au moment du final (=quasi fin de session, sessionCap
    // probablement saturé). Le générateur ne bénéficie pas des bumps
    // évènementiels (punition complétée etc.) — uniquement de la rampe
    // automatique — donc c'est volontairement conservateur.
    final finalHumilCap = _config.humilCapAt(time);
    // En chaîne encore, on allonge le final pour que la dramaturgie de
    // « tu en veux encore » se traduise aussi côté apothéose. Bornée par
    // le clamp de `_finalPicker.pickFinal` pour rester raisonnable.
    final finishMul = 1.0 + max(0, ctx.encoreChainIndex) * 0.10;
    final finisherDraft = _finalPicker.pickFinal(
      humilCap: finalHumilCap,
      maxDepth: _config.maxDepthIndex,
      finishMul: finishMul,
    );
    final finalCategory =
        _rules[finisherDraft.mode]!.finalCategory(finisherDraft);
    final finalMode = finisherDraft.mode;

    // Annonce du final : si le finisher change de mode (ex. dernier boost =
    // hand, finisher = lick), on pose une phrase qui annonce le changement
    // physique imminent. Sinon, phrase d'action standard.
    final announcePhrase = (lastBoostIndex != null && burstMode != finalMode)
        ? ctx.bank.pickFinalAnnouncement(
            preMode: burstMode,
            finalMode: finalMode,
            rng: _rng,
          )
        : null;
    final finalActionPhrase = ctx.bank.pickFinalAction(
      mode: finalMode,
      holdPosition: finalMode == SessionMode.hold ? finisherDraft.from : null,
      rng: _rng,
    );
    final finalStepText = (announcePhrase != null && announcePhrase.isNotEmpty)
        ? announcePhrase
        : (finalActionPhrase ?? '');
    final finalStepStartTime = time;
    final r = _emitStep(
      ctx,
      draft: finisherDraft,
      text: finalStepText,
      time: time,
      stamina: stamina,
      progress: 1.0,
      asTransit: true,
    );
    return (
      time: r.time,
      stamina: r.stamina,
      finalCategory: finalCategory,
      finalMode: finalMode,
      finalStepStartTime: finalStepStartTime,
    );
  }

  /// Émet le step post-final (aftercare ~12 s après l'orgasme). Mode
  /// contrastant choisi par [_buildPostFinalDraft] selon le mode final +
  /// l'humil. Phrase : cascade `post_final_beg` / `post_final_lick` /
  /// `post_final` / `congrats`. Retourne `(time, stamina)`.
  ({int time, double stamina}) _emitPostFinal(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required SessionMode finalMode,
  }) {
    final postFinalDraft = _clampToCapability(
        _buildPostFinalDraft(finalMode, _config.humilCapAt(time)));
    // Phrase : pool mode-spécifique (beg = CONSIGNE de supplique ;
    // lick = consigne d'aftercare humiliant) puis cascade sur le pool
    // générique. Default `pickPostFinalText` retourne `null` → on saute
    // direct à la cascade générique. Garantit un text non-vide via le
    // fallback final `pickCongrats`.
    final modeSpecific =
        _rules[postFinalDraft.mode]!.pickPostFinalText(ctx.bank, _rng);
    final postFinalText = modeSpecific ??
        ctx.bank.pickPostFinal(_rng) ??
        ctx.bank.pickCongrats(_rng);
    return _emitStep(
      ctx,
      draft: postFinalDraft,
      text: postFinalText,
      time: time,
      stamina: stamina,
      progress: 1.0,
      asTransit: true,
    );
  }

  /// Construit le [CareerGenerationResult] final à partir des accumulateurs
  /// `ctx.steps` / `ctx.profile` et du curseur `time`. Tronque le profil à la
  /// durée effective (= `time + 2`), assemble la [Session] avec toutes ses
  /// métadonnées (milestones body + final si présentes).
  ///
  /// Partagé entre le path final-milestone (early return) et le path
  /// standard (boosts + final + post-final).
  CareerGenerationResult _assembleResult(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required int? milestoneStartTime,
    required int? milestoneDurationSeconds,
    required int? secondMilestoneStartTime,
    required int? secondMilestoneDurationSeconds,
    required FinalCategory finalCategory,
    required int silentFinishStartTime,
    required int finalStepStartTime,
    String? finalMilestoneId,
    int? finalMilestoneStartTime,
    int? finalMilestoneDurationSeconds,
  }) {
    final finalDuration = time + 2;
    final trimmedProfile = List<double>.generate(
      finalDuration,
      (i) => i < ctx.profile.length ? ctx.profile[i] : stamina,
    );
    return CareerGenerationResult(
      session: Session(
        id: 'career:lvl${_config.level}:${ctx.effectiveDuration}s${ctx.quickie ? ":q" : ""}',
        name: ctx.quickie
            ? (ctx.sessionNameQuickie ??
                'Carrière niveau ${_config.level} — bâclée')
            : (ctx.sessionName ?? 'Carrière niveau ${_config.level}'),
        description: 'Session générée — ${ctx.effectiveDuration} s',
        durationSeconds: finalDuration,
        defaultMode: SessionMode.rhythm,
        steps: ctx.steps,
        milestoneId:
            ctx.insertedBodies.isNotEmpty ? ctx.insertedBodies[0].id : null,
        milestoneStartTime: milestoneStartTime,
        milestoneDurationSeconds: milestoneDurationSeconds,
        secondMilestoneId:
            ctx.insertedBodies.length >= 2 ? ctx.insertedBodies[1].id : null,
        secondMilestoneStartTime: secondMilestoneStartTime,
        secondMilestoneDurationSeconds: secondMilestoneDurationSeconds,
        finalMilestoneId: finalMilestoneId,
        finalMilestoneStartTime: finalMilestoneStartTime,
        finalMilestoneDurationSeconds: finalMilestoneDurationSeconds,
        finalCategory: finalCategory,
        silentFinishStartTime: silentFinishStartTime,
        finalStepTime: finalStepStartTime,
        noStats: ctx.noStats,
      ),
      staminaProfile: trimmedProfile,
      overloadAxis: _config.overloadAxis,
    );
  }

  /// Step d'intro. Modes hardcodés pour quickie / intense (besoins
  /// dramaturgiques spécifiques). En séance normale, panel de variantes
  /// douces : lick et rhythm en amplitude limitée, plus une option hand
  /// pour la variété. Filtré par `_config.maxDepthIndex` (head→mid n'apparaît pas
  /// si le niveau plafonne à head) et `_config.includeHand`.
  StepDraft _firstStep({
    bool quickie = false,
    bool intense = false,
  }) {
    if (intense) {
      // Plus profond et plus rapide que quickie : la régen post-Supplier
      // est censée prouver que l'utilisatrice « monte d'un niveau ».
      // Profondeur plafonnée par les milestones acquittées (jamais throat
      // sans `throat_pulse`, jamais full sans `full_pulse`) — on borne aussi
      // à throat (idx 3) pour ne jamais lancer un intense full d'amorce.
      final to = Position.values[_milestoneRhythmCeilingIdx().clamp(2, 3)];
      // Custom : rhythm exclu → on retombe sur hand (rythmé proche), sinon
      // lick (langue) ou hold (statique) en dernier recours. Cascade
      // pilotée par `introPriority` côté rules (rhythm=0 → hand=1 → lick=2
      // → hold=3). Construction déléguée à `buildIntroStep` : les rules
      // rythmées consomment les 4 params straight, hold ignore bpm/from.
      final intenseMode = _pickIntroMode();
      return _rules[intenseMode]!.buildIntroStep(IntroCtx(
        bpm: 90,
        from: Position.head,
        to: to,
        duration: 10,
      ));
    }
    if (quickie) {
      // Quickie : même cascade que l'intense (rhythm → hand → lick →
      // hold) via `introPriority` côté rules, construction via
      // `buildIntroStep`.
      final quickieMode = _pickIntroMode();
      return _rules[quickieMode]!.buildIntroStep(const IntroCtx(
        bpm: 75,
        from: Position.head,
        to: Position.mid,
        duration: 8,
      ));
    }
    // Panel de variantes filtré par milestones : `rhythm_mid_basic`
    // (intro_deeper_basics, niveau 2) gate les variantes head→mid /
    // tip→mid. Sans cette milestone, on retombe sur lick / rhythm tip→head
    // / hand tip→head (toutes débloquées via intro_basics niveau 1).
    final variants = <StepDraft>[
      const StepDraft(
        mode: SessionMode.lick,
        bpm: 60,
        from: Position.tip,
        to: Position.head,
        duration: 20,
      ),
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 65,
        from: Position.tip,
        to: Position.head,
        duration: 16,
      ),
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 70,
        from: Position.head,
        to: Position.mid,
        duration: 14,
      ),
      const StepDraft(
        mode: SessionMode.rhythm,
        bpm: 65,
        from: Position.tip,
        to: Position.mid,
        duration: 16,
      ),
      if (_config.includeHand)
        const StepDraft(
          mode: SessionMode.hand,
          bpm: 55,
          from: Position.tip,
          to: Position.head,
          duration: 18,
        ),
    ];
    final allowed = variants
        .where(_isUnlocked)
        .where((v) => !_config.isModeForbidden(v.mode))
        .toList();
    if (allowed.isEmpty) {
      // Pas de variante alignée à la fois sur les unlocks et le dosage —
      // on retombe sur la 1ʳᵉ variante non interdite, sinon la 1ʳᵉ tout court.
      final notForbidden =
          variants.where((v) => !_config.isModeForbidden(v.mode)).toList();
      return notForbidden.isEmpty ? variants.first : notForbidden.first;
    }
    return allowed[_rng.nextInt(allowed.length)];
  }

  /// Construit un step `breath` dont la durée est calculée pour combler
  /// exactement un déficit d'endurance projeté. Borné à [3, 15] secondes :
  /// au-delà, on préfère raccourcir la step suivante plutôt qu'imposer
  /// une respi interminable.
  /// Tente de générer un « faux breath » : un breath ultra-court (2-3 s)
  /// inséré juste après un step intense pour faire croire à une pause,
  /// alors que la step suivante reprendra direct sur son tirage normal.
  /// Effet de surprise réservé aux profils déjà habitués à l'humiliation
  /// — sur les débutantes (humil career bas), le contrat pédagogique
  /// reste « breath = vraie respiration » ; mentir à une joueuse qui
  /// vient d'apprendre à respirer briserait sa confiance dans le moteur.
  ///
  /// Conditions cumulatives :
  /// - humiliation career ≥ 20 (seuil = la joueuse a déjà été poussée
  ///   suffisamment pour que le ton taquin/dominateur fasse sens)
  /// - dernier step émis = effort intense (rhythm/hand to ∈ {throat, full}
  ///   à BPM ≥ 90, ou hold to ∈ {throat, full})
  /// - pas dans la dernière minute (on laisse le finish scripté tranquille)
  /// - stamina courante ≥ 30 (sinon un vrai breath était déjà inséré, pas
  ///   besoin de tromperie supplémentaire)
  /// - probabilité 25 % (rare = surprise ; trop fréquent = effet usé)
  ///
  /// Retourne null si une condition n'est pas remplie.
  ({StepDraft draft, String text})? _maybeBuildFakeBreath({
    required StepDraft lastEmitted,
    required double currentStamina,
    required int time,
    required int genUntil,
    required PhraseBank bank,
  }) {
    // Convention `_state.unlockedKeys.isEmpty` = mode hérité (Custom / scénarios /
    // debug) : pas de gating, le mécanisme reste actif. En carrière le
    // déblocage passe par la milestone `intro_fake_breath` qui accorde la
    // clé `fakeBreath` ; tant qu'elle n'est pas acquittée, rien ne sort.
    if (_state.unlockedKeys.isNotEmpty &&
        !_state.unlockedKeys.contains(UnlockKey.fakeBreath)) {
      return null;
    }
    if (genUntil - time < 30) return null; // pas trop près du finish
    if (currentStamina < 30) return null; // déjà en dette, vrai breath plus bas
    if (!_rules[lastEmitted.mode]!.isIntenseForFakeBreath(lastEmitted)) {
      return null;
    }
    if (_rng.nextDouble() >= 0.25) return null;
    // 2-3 s : assez pour entendre un soupir, trop peu pour vraiment
    // récupérer (à 2.8 stamina/s = 5-8 stamina rendus, peanuts face au
    // coût d'un step intense ~25-40).
    final dur = 2 + _rng.nextInt(2);
    final draft = StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
    // Phrase : on tire d'abord dans le tier `fake_breath` (phrases taquines
    // « une seconde, c'est tout », « tu crois qu'on s'arrête ? »). Fallback
    // sur `hard` si la bank n'a pas encore le pool dédié — au moins le ton
    // reste sec/dominateur, pas une phrase douce qui casse la surprise.
    var text = _pickPhrase(bank, SessionMode.breath, 'fake_breath');
    if (text.isEmpty) {
      text = _pickPhrase(bank, SessionMode.breath, 'hard');
    }
    return (draft: draft, text: text);
  }

  StepDraft _buildBreathRecovery(
    double deficit,
    double progress,
    CareerLevel cfg,
  ) {
    final regen = StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    // Cohérent avec `_staminaDelta` pour breath : `dur * 2.8 * regen`
    // (vitesse de récup poussée pour que le breath reste plus court
    // que les steps d'action — cf. règle de design dans `_staminaDelta`).
    final regenPerSec = 2.8 * regen;
    // Cible : combler le déficit ET reconstruire un petit buffer de
    // stamina pour pouvoir enchaîner 2-3 steps derrière. Buffer baissé
    // (35 → 22) : à 2.8 stamina/s, 22 = 8 s déjà — au-delà le breath
    // devient plus long que l'action qu'il sépare. Cap haut 18 → 12 s
    // dans la même logique : un soupir, pas une vraie phase. Si la
    // dette reste après 12 s, c'est au moteur d'insérer un nouveau
    // breath plus tard, pas à un breath unique de tout absorber.
    const targetBuffer = 22.0;
    final raw =
        (deficit + targetBuffer) / (regenPerSec <= 0 ? 1.0 : regenPerSec);
    final dur = raw.ceil().clamp(4, 12);
    return StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Tirage d'un step "respi active" : mode parmi les `ModeRules` qui
  /// opt-in à `isRecoveryCandidate`, BPM ≤ 60 pour déclencher la regen
  /// d'endurance. Le mode `breath` n'est plus tiré ici — il est désormais
  /// inséré strictement sur déficit d'endurance projeté (cf.
  /// `_buildBreathRecovery`), pas comme une option d'humeur générale.
  ///
  /// L'orchestration est mode-agnostique : on collecte les candidats via
  /// le registry, on applique les filtres communs (dose Custom, friction
  /// de continuité), on délègue l'assemblage à la rule retenue. La
  /// logique mode-specific (durée, gating unlock, choix de position) vit
  /// dans `ModeRules.isRecoveryCandidate` / `buildRecovery`.
  StepDraft _buildRecoveryStep() {
    final bpm = 45 + _rng.nextInt(14); // [45, 58]
    final dur = 10 + _rng.nextInt(9); // [10, 18]
    // Convention `_state.unlockedKeys.isEmpty` = mode hérité : pas de gating, tous
    // les modes opt-in passent par défaut (cf. `_isUnlocked`).
    final avail = RecoveryAvailability(
      heritage: _state.unlockedKeys.isEmpty,
      unlockedKeys: _state.unlockedKeys,
      includeHand: _config.includeHand,
    );
    final candidates = <SessionMode>[
      for (final entry in _rules.entries)
        if (entry.value.isRecoveryCandidate(avail)) entry.key,
    ];
    // Exclusions Custom (dose `none`) : la recovery ne doit pas ramener un
    // mode que la joueuse a explicitement banni. Si tout est exclu, on
    // retombe sur lick (le garde-fou de l'éditeur Custom assure que lick
    // OU rhythm OU hold est resté ≥ rare — si lick lui-même est exclu, le
    // mode bouche restant reprend la main au step suivant via mapDifficulty).
    candidates.removeWhere(_config.isModeForbidden);
    if (candidates.isEmpty) candidates.add(SessionMode.lick);
    final pool = _filterRepeated(candidates);
    // Tirage pondéré pour que la friction de continuité par type s'applique
    // aussi à la recovery (sans ça, une recovery uniforme repousse souvent
    // langue/libre alors que la séance vient juste de quitter bouche).
    final mode = _pickWeightedMode(pool);
    final draft = _rules[mode]!.buildRecovery(RecoveryCtx(
      gen: _facade,
      bpm: bpm,
      duration: dur,
    ));
    // Gating unlock : si le mode/draft tiré n'est pas encore débloqué (ex :
    // biffle avant niveau 5, beg libre avant niveau 3, freestyle avant
    // niveau 4), on dégrade. Évite que la phase de récup laisse passer une
    // action contractuellement réservée à plus tard.
    if (!_isUnlocked(draft)) {
      return StepDraft(
        mode: SessionMode.lick,
        bpm: bpm,
        from: Position.tip,
        to: Position.head,
        duration: dur,
      );
    }
    return draft;
  }

  /// Adaptateur d'instance pour `_ModePicker.pickWeighted` — injecte `_config.spec`,
  /// `_config.coachModeWeights`, le snapshot de continuité et `_rng`.
  SessionMode _pickWeightedMode(List<SessionMode> candidates) =>
      _ModePicker.pickWeighted(
        candidates,
        spec: _config.spec,
        coachWeights: _config.coachModeWeights,
        continuity: _state.continuitySnapshot(),
        rng: _rng,
        rules: _rules,
      );

  /// Mode retenu pour la chaîne de fallback « intro intense / quickie »
  /// (cf. `_firstStep`). Trie les rules par `introPriority` croissante,
  /// retient la première non-forbidden. Le mode de rang max (hold)
  /// reste le fallback ultime même quand `_config.isModeForbidden(hold)` —
  /// l'éditeur Custom garantit qu'au moins un mode bouche reste, mais
  /// si tout est exclu, hold doit sortir pour préserver le contrat
  /// historique (la cascade `rhythm → hand → lick → hold` finissait
  /// toujours par hold).
  SessionMode _pickIntroMode() {
    final ranked = _rules.entries
        .where((e) => e.value.introPriority != null)
        .toList()
      ..sort(
          (a, b) => a.value.introPriority!.compareTo(b.value.introPriority!));
    for (final e in ranked) {
      if (!_config.isModeForbidden(e.key)) return e.key;
    }
    return ranked.last.key;
  }

  /// Notifie les 3 sous-systèmes runtime après un step poussé :
  ///   * `_rhythmChain` : cumule / reset selon mode et durée.
  ///   * `_state.recordContinuity(type)` : `lastType` / `stepsInLastType`
  ///     / `stepsOutsideBouche`.
  ///   * `_patternBuffer.record(...)` : buffer roulant des 3 derniers
  ///     rythmés (filtre interne sur mode).
  void _trackPushedStep(SessionMode mode, Position? to,
      {Position? from, int? bpm, int? duration}) {
    _rhythmChain.onStepPushed(mode, duration);
    _state.recordContinuity(_rules[mode]!.classify(to));
    _patternBuffer.record(mode, from: from, to: to, bpm: bpm);
  }

  // ─── Position pickers (adapteurs vers `PositionPickers`) ────────────────
  //
  // Les délégations consommées par les rules (`sampleFromTo`, `pickHold`,
  // `maybePickBegWithChain`, `capRhythmDurationByPulses`…) vivent désormais
  // sur `GenFacade` qui wrappe directement `PositionPickers` / `BpmPacing`.
  // Restent ici uniquement les adaptateurs encore consommés par le
  // générateur lui-même (orchestration) ou ses parts (`_DifficultyDispatch`).

  int _milestoneHoldCeilingIdx() => _positionPickers.milestoneHoldCeilingIdx();

  int _milestoneRhythmCeilingIdx() =>
      _positionPickers.milestoneRhythmCeilingIdx();

  (double, double, double) _sampleSimplex3() =>
      _positionPickers.sampleSimplex3();

  /// Délégué à [`SessionRuntimeState.advanceSalivaSim`].
  void _advanceSalivaSim(StepDraft draft) => _state.advanceSalivaSim(draft);

  // ─── Phase 5 — Punitions générées & bornées ────────────────────────────

  /// Génère une punition contextuelle pour la séance carrière (cf. §7 de la
  /// spec). À utiliser à la place du tirage dans `punishments.json` en mode
  /// carrière. Hors carrière (Custom, scénarios JSON, mini-punitions
  /// inopinées), le contrôleur garde le tirage statique.
  ///
  /// Algo : palette hardcodée de compositions « max humiliation qui passe »
  /// (parité avec `_finalPicker.pickFinal`), bornée par les ceilings de session et le
  /// `comfort` du profil de capacités via `_clampToCapability`. Fallback en
  /// escalier (rythme `head→mid` rapide → hand ultime) pour rester jouable
  /// même à humilCap quasi-nul.
  ///
  /// L'axe surchargé de la séance ([CapabilityInputs.overloadAxis]) est
  /// honoré côté **clamp** (le `comfort` de cet axe est élargi du facteur
  /// de surcharge dans `_clampToCapability` via `_capabilityCapFor`) —
  /// mais **pas côté sélection** : on ne filtre pas par affinité d'axe,
  /// on prend strictement le plus humiliant qui passe (décision projet).
  Punishment generatePunishment({
    required int level,
    required PhraseBank bank,
    required Set<UnlockKey> unlockedKeys,
    required CapabilityInputs capability,
    SpecializationAllocation? specialization,
    double humiliationCareer = 0.0,
    double humiliationSession = 0.0,
    double obedience = 100.0,
    bool includeHand = true,
    Map<SessionMode, double> coachModeWeights = const {},
    AnatomyProfile anatomy = AnatomyProfile.defaults,
  }) {
    // Réinitialise l'état comme le ferait `generate`, pour que les helpers
    // (`_clampToCapability`, `_isUnlocked`, `_pickPhrase`...) lisent les
    // mêmes invariants. On ne touche pas aux champs spécifiques au tirage
    // de session (`_state.lastMode`, `_rhythmChain`, etc.) — sans objet ici.
    //
    // Surcharge : on honore l'axe imposé par la séance (pas de re-tirage).
    // Le facteur est dérivé de la `successRate` du profil par
    // `CapabilityInputs.overloadFactor` (no-op = 1.0 si pas de profil).
    _config = SessionConfig(
      level: level,
      includeHand: includeHand,
      // `generatePunishment` n'expose pas ces 2 bornes — défauts neutres
      // (full ouvert, deepProbability à 1.0) cohérents avec l'ancien comportement.
      maxDepthIndex: Position.values.length - 1,
      deepProbability: 1.0,
      spec: specialization ?? SpecializationAllocation.empty(),
      anatomy: anatomy,
      coachModeWeights: coachModeWeights,
      // Pas de bornes utilisateur Custom : les punitions ne sont pas
      // générées en Custom (cf. _generateCareerPunishmentOrNull côté
      // SessionController qui retourne null hors carrière).
      bpmRange: null,
      holdDurationRange: null,
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedience,
      capProfile: capability.profile,
      capCeilings: capability.sessionCeilings,
      overloadAxis: capability.overloadAxis,
      overloadFactor: capability.overloadFactor,
    );
    _state = SessionRuntimeState.fresh(rng: _rng);
    _state.unlockedKeys = unlockedKeys;
    // Punition générée hors `generate()` → on doit aussi (re)bâtir
    // `_capClamps` ici, sinon le `_clampToCapability` qui sert à matérialiser
    // chaque step de la compo lit un field non initialisé.
    _capClamps = CapabilityClamps(
      config: _config,
      bpmRange: null,
      holdRange: null,
      rules: _rules,
    );
    // `_rhythmChain` n'est pas consommé par `generatePunishment` (les
    // compositions ne déclenchent pas de chaîne rythme), mais on le
    // (re)pose pour idempotence avec `generate()` — la facade le tient
    // en field, un null planterait au moment du `_facade` construct.
    _rhythmChain = RhythmChainTracker(
      state: _state,
      motionStreakComfort:
          _config.capProfile?.comfortOf(CapabilityAxis.rhythmMotionStreak),
      motionStreakOverloadFactor:
          _capClamps.overloadFactorFor(CapabilityAxis.rhythmMotionStreak),
    );
    // `_finalPicker` et `_positionPickers` ne sont pas consommés par
    // `generatePunishment`, mais on les initialise par sécurité
    // (idempotence avec `generate()`).
    _finalPicker = FinalPicker(
      config: _config,
      unlockedKeys: _state.unlockedKeys,
      rng: _rng,
      capClamps: _capClamps,
      rules: _rules,
    );
    _positionPickers = PositionPickers(
      config: _config,
      unlockedKeys: _state.unlockedKeys,
      rng: _rng,
      rules: _rules,
    );
    _facade = GenFacade._(
      config: _config,
      state: _state,
      rng: _rng,
      rhythmChain: _rhythmChain,
      positionPickers: _positionPickers,
    );

    // Palette + sélection + matérialisation déléguées à
    // `_PunishmentBuilder` (cf. `career_session_generator_punishment.dart`).
    // Le state d'instance a été (re)posé en haut de cette méthode — le
    // builder lit gen._xxx directement.
    return _PunishmentBuilder.buildFor(this, bank, includeHand);
  }

  /// Applique `BpmPacing.diversifyBpm` au draft si pertinent (modes avec
  /// BPM, hors hold/beg/breath/freestyle qui n'en ont pas), et met à jour
  /// `_state.lastBpm`. Retourne le draft (potentiellement modifié).
  ///
  /// Reste sur l'instance car écrit `_state.lastBpm` (mutation d'état).
  StepDraft _applyBpmDiversity(StepDraft d) {
    final bpm = d.bpm;
    if (bpm == null) return d;
    final newBpm = BpmPacing.diversifyBpm(bpm, _state.lastBpm, _rng);
    _state.lastBpm = newBpm;
    if (newBpm == bpm) return d;
    return StepDraft(
      mode: d.mode,
      bpm: newBpm,
      from: d.from,
      to: d.to,
      duration: d.duration,
    );
  }

  /// Force une légère variation de la cible `to` (ou de `from` si `to`
  /// est null) si le draft a exactement la même amplitude que le step
  /// précédent. Sert pour rhythm/lick/hand/biffle : empêche d'enchaîner
  /// deux head→mid identiques **et** détecte une monotonie sur fenêtre
  /// élargie (3 derniers émis + draft = même mode + même `to` + BPMs
  /// resserrés). Quand l'un des deux cas se déclenche, décale d'un cran
  /// vers le haut ou le bas selon le mode :
  /// - rhythm : `_milestoneRhythmCeilingIdx()` (gating milestone)
  /// - lick / hand : full ouvert (pas de tension de profondeur)
  /// - biffle : pas concerné (from/to null par convention)
  StepDraft _diversifyAmplitude(StepDraft d) {
    final ceiling = _rules[d.mode]!.amplitudeDiversifyCeiling(_facade);
    if (ceiling == null) return d;
    final lastFrom = _state.lastFrom;
    final lastTo = _state.lastTo;
    final exactSameAsLast = lastFrom != null &&
        lastTo != null &&
        d.from == lastFrom &&
        d.to == lastTo;
    // Le détecteur fenêtre 3 ne déclenche que si on a déjà 3 émissions
    // rythmées en buffer. Tant qu'il n'y en a pas (début de session), on
    // s'appuie uniquement sur le check classique sur le step précédent.
    final flatPattern = _patternBuffer.wouldBeFlat(d);
    if (!exactSameAsLast && !flatPattern) return d;
    // Même amplitude que le step précédent OU pattern plat sur 3 steps :
    // on décale `to` d'un cran.
    final toIdx = d.to?.index;
    if (toIdx == null) return d;
    final ceil = ceiling;
    final fromIdx = d.from?.index ?? 0;
    final canUp = toIdx + 1 <= ceil;
    final canDown = toIdx - 1 > fromIdx;
    final int newToIdx;
    if (canUp && canDown) {
      newToIdx = _rng.nextBool() ? toIdx + 1 : toIdx - 1;
    } else if (canUp) {
      newToIdx = toIdx + 1;
    } else if (canDown) {
      newToIdx = toIdx - 1;
    } else {
      // Impossible de varier `to` : tente sur `from`.
      if (fromIdx > 0 && fromIdx + 1 < toIdx) {
        return StepDraft(
          mode: d.mode,
          bpm: d.bpm,
          from: Position.values[fromIdx - 1],
          to: d.to,
          duration: d.duration,
        );
      }
      return d;
    }
    return StepDraft(
      mode: d.mode,
      bpm: d.bpm,
      from: d.from,
      to: Position.values[newToIdx],
      duration: d.duration,
    );
  }

  /// Convertit un [StepDraft] interne en [SessionStep] sérialisable.
  /// Pour les modes hold/beg, swap `from` (position cible interne au draft)
  /// vers `to` côté SessionStep — sémantique « on tient jusqu'à cette
  /// position ». Convention uniforme : hold/beg portent leur position dans
  /// `to`, les autres modes (rhythm/lick/hand/biffle) utilisent from→to
  /// pour l'alternance. Plus de swap, le draft interne et le SessionStep
  /// produit utilisent la même convention.
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

  /// Retourne l'`UnlockKey` requise pour jouer [draft], `null` si l'action
  /// est libre par défaut. Le mapping se base sur les milestones existantes
  /// (cf. `assets/career/milestones.json`).
  // _unlockKeyFor, _stepDownOne, _lubricationCapDelta, _deepestOf et
  // _isUnlocked + _finalUnlocked vivent désormais dans
  // `career_session_generator_humiliation.dart` (`HumiliationGates`).
  // Adaptateurs d'instance pour ceux qui restent appelés directement :

  /// Adaptateurs d'instance pour `HumiliationGates` : injectent
  /// `_config.anatomy`, `_state.unlockedKeys` et la projection salive `_state.salivaSim.value`
  /// pour garder les call sites brefs (un seul argument au lieu de quatre).
  bool _isUnlocked(StepDraft d) => HumiliationGates.isUnlocked(
        d,
        anatomy: _config.anatomy,
        unlockedKeys: _state.unlockedKeys,
        rules: _rules,
      );

  // `_finalUnlocked` n'est plus appelé depuis l'instance (consommé par
  // `FinalPicker` qui appelle directement `HumiliationGates.finalUnlocked`).
  // Plus d'adaptateur ici.

  /// Adaptateur d'instance pour `HumiliationGates.enforceRequired` : injecte
  /// `_config.anatomy`, `_state.unlockedKeys`, la salive courante, et le callback de
  /// clamp capacité (qui reste sur l'instance car il consulte `_config.capProfile`).
  StepDraft _enforceHumiliationRequired(StepDraft draft, double available) =>
      HumiliationGates.enforceRequired(
        draft,
        available,
        clampToCapability: _clampToCapability,
        anatomy: _config.anatomy,
        unlockedKeys: _state.unlockedKeys,
        saliva: _state.salivaSim.value,
        rules: _rules,
      );

  /// Retire `_state.lastMode` des candidats si une alternative existe et que le
  /// mode est « ponctuel » (breath / beg / biffle / hold / freestyle) — deux
  /// events identiques d'affilé y sonneraient comme un bug.
  ///
  /// Pour les modes « flow » (rhythm / lick / hand), on **accepte la
  /// répétition** : la variété passe par les paramètres (BPM via
  /// `_applyBpmDiversity` qui force ≥18 BPM de delta, profondeur via
  /// `_diversifyAmplitude` qui décale d'un cran). Sans cette fenêtre de
  /// rester sur le même mode, on sortait nécessairement de rythme à chaque
  /// step ; l'utilisateur a relevé que la séance ressemblait à une rotation
  /// stricte au lieu de phases prolongées avec variation.
  /// Adaptateur d'instance pour `_ModePicker.filterRepeated` — injecte
  /// `_state.lastMode`.
  List<SessionMode> _filterRepeated(List<SessionMode> candidates) =>
      _ModePicker.filterRepeated(candidates, _state.lastMode);

  /// Tire une phrase pour [mode]/[tier] en évitant la même qu'au step
  /// précédent (`_state.lastText`). Quelques essais suffisent : si la banque ne
  /// contient qu'une seule entrée pour ce couple, on accepte la répétition.
  ///
  /// Si [context] est fourni, le filtrage par contraintes de la
  /// [PhraseEntry] est appliqué (profondeur min/max, BPM min/max). Pour
  /// les call sites qui manipulent un `StepDraft`, utiliser
  /// [_pickPhraseForDraft] qui calcule le contexte automatiquement.
  ///
  /// **Auto-bump par obédiance** : plus l'obédiance lifetime est haute,
  /// plus la coach pioche dans les tiers durs. Tu obéis bien → on durcit
  /// le ton. Le bump n'affecte pas les tiers `boost` et `finale` (qui ont
  /// leur dramaturgie propre, indépendante de l'obédiance).
  /// - obed ≥ 30 : `soft` → `medium` à 30 %
  /// - obed ≥ 80 : `soft` → `medium` à 70 % ; `medium` → `hard` à 30 %
  /// - obed ≥ 150 : `soft` → `medium` à 90 % ; `medium` → `hard` à 60 %
  ///
  /// Si le tier ciblé n'a pas de phrase pour ce mode, le `pickFor` retombe
  /// transparentement sur le tier d'origine — pas de risque de chaîne vide.
  String _pickPhrase(
    PhraseBank bank,
    SessionMode mode,
    String tier, {
    PhraseContext? context,
  }) {
    final effectiveTier = _bumpTierByObedience(tier);
    for (var i = 0; i < 4; i++) {
      final phrase = bank.pickFor(mode, effectiveTier, _rng, context: context);
      if (phrase.isEmpty || phrase != _state.lastText) return phrase;
    }
    return bank.pickFor(mode, effectiveTier, _rng, context: context);
  }

  /// Variante de [_pickPhrase] qui extrait le contexte (profondeur, BPM)
  /// depuis un draft de step. Permet aux phrases tier d'être filtrées par
  /// les contraintes (« nez collé » réservé à `to=full`, « respire par le
  /// nez » réservé à `to ≤ mid`, etc.).
  String _pickPhraseForDraft(
    PhraseBank bank,
    StepDraft draft,
    String tier,
  ) {
    return _pickPhrase(
      bank,
      draft.mode,
      tier,
      context: PhraseContext(
        mode: draft.mode,
        depth: draft.to ?? draft.from,
        bpm: draft.bpm,
      ),
    );
  }

  /// Bump conditionnel d'un tier de phrase selon `_config.obedience`. Cf. doc
  /// de `_pickPhrase`. Ne touche pas aux tiers `boost`/`finale`.
  String _bumpTierByObedience(String tier) {
    if (tier == 'boost' || tier == 'finale') return tier;
    final obed = _config.obedience;
    final roll = _rng.nextDouble();
    if (tier == 'soft') {
      double pSoftToMedium;
      if (obed >= 150) {
        pSoftToMedium = 0.90;
      } else if (obed >= 80) {
        pSoftToMedium = 0.70;
      } else if (obed >= 30) {
        pSoftToMedium = 0.30;
      } else {
        return tier;
      }
      return roll < pSoftToMedium ? 'medium' : tier;
    }
    if (tier == 'medium') {
      double pMediumToHard;
      if (obed >= 150) {
        pMediumToHard = 0.60;
      } else if (obed >= 80) {
        pMediumToHard = 0.30;
      } else {
        return tier;
      }
      return roll < pMediumToHard ? 'hard' : tier;
    }
    return tier;
  }
}

/// Bundle des paramètres « figés pour la session » consommés par les helpers
/// de phase de [CareerSessionGenerator.generate]. Construit une seule fois
/// au début de l'appel après que tous les paramètres dérivés sont calculés
/// (`effectiveDuration`, `intensityFloor`, `boostsCount`, `genUntil`…).
///
/// Évite de répéter les mêmes 6-8 args (`cfg`, `bank`, `effectiveDuration`,
/// `encoreChainIndex`, `steps`, `profile`…) dans la signature de chaque
/// helper. Les helpers piochent ce dont ils ont besoin via `ctx.x`.
///
/// **Pas inclus** : le curseur live `(time, stamina)`. Ces deux scalaires
/// sont threadés via record return values pour séparer ce qui est *fixé*
/// (ctx) de ce qui *évolue à chaque step* (cursor).
///
/// **Pas dupliqué depuis `_config`** : `level`, `includeHand`, `obedience`
/// vivent dans `SessionConfig` (immuable). Les helpers ont `this` donc
/// y accèdent via `_config.x` — pas la peine de les copier ici.
///
/// **Mutables internes** : [steps] et [profile] sont des `List` mutées en
/// place par les helpers. Le DTO les expose comme `final` (la référence
/// liste ne change pas), mais le contenu est l'accumulateur de la séance.
class _GenContext {
  final List<SessionStep> steps;
  final List<double> profile;

  final int encoreChainIndex;
  final int effectiveDuration;
  final int boostsCount;
  final int genUntil;
  final double intensityFloor;
  final bool quickie;
  final bool noStats;
  final CareerLevel cfg;
  final PhraseBank bank;
  final String? sessionName;
  final String? sessionNameQuickie;
  final String? Function(String milestoneId, int stepTime)?
      milestoneTextResolver;
  final List<LevelMilestone> insertedBodies;

  const _GenContext({
    required this.steps,
    required this.profile,
    required this.encoreChainIndex,
    required this.effectiveDuration,
    required this.boostsCount,
    required this.genUntil,
    required this.intensityFloor,
    required this.quickie,
    required this.noStats,
    required this.cfg,
    required this.bank,
    required this.sessionName,
    required this.sessionNameQuickie,
    required this.milestoneTextResolver,
    required this.insertedBodies,
  });
}
