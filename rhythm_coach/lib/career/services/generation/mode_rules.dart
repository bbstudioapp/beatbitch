// Library autonome — contrat `ModeRules`, value objects de contexte
// (`DraftCtx`, `RecoveryCtx`, `PostFinalCtx`, `FinalCtx`, `IntroCtx`,
// `RecoveryAvailability`), variantes (`PostFinalVariant`, `FinalVariant`)
// et helpers mutualisés (`tryDescendToWithGuard`, `tryDescendFrom`,
// `clampHeldDuration`) — partagés entre le générateur et les 9 rules.
//
// Sorti du `part of 'career_session_generator.dart'` historique pour
// casser le cycle `ModeRules ↔ GenFacade` (A.PR2 du plan de refacto). Les
// rules ne dépendent plus de la classe concrète `GenFacade` — elles
// consomment l'interface `GenFacadeSurface` ci-dessous, dont `GenFacade`
// (toujours `part of` côté générateur) est l'unique implémentation.
//
// `career_session_generator.dart` re-exporte tous les symboles de cette
// library pour préserver la rétrocompat des call sites externes (tests
// notamment).

import 'dart:math';

import '../../../models/anatomy_profile.dart';
import '../../../models/final_category.dart';
import '../../../models/session.dart';
import '../../../models/session_step.dart';
import '../../../services/capability_axis.dart';
import '../../models/career_level.dart';
import '../../models/phrase_bank.dart';
import '../../models/specialization.dart';
import '../../models/unlock_key.dart';
import 'capability_clamp_surface.dart';
import 'rhythm_chain_tracker.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';
import 'step_type.dart';

/// Surface du générateur exposée aux `ModeRules` — strictement tout ce
/// qu'une rule a le droit de consommer via `ctx.gen.X` (state stable,
/// samplers position, caps milestone et pacing). Ajouter une méthode ou
/// un getter ici est un acte explicite (« j'élargis l'API que les modes
/// peuvent voir »).
///
/// Implémentation unique : `GenFacade` (côté `career_session_generator.dart`).
/// La rule manipule l'interface — pas la classe concrète — pour rester
/// découplée du générateur.
abstract class GenFacadeSurface {
  // ─── State stable lu par les rules ─────────────────────────────────
  SessionConfig get config;
  SessionRuntimeState get state;
  Random get rng;
  RhythmChainTracker get rhythmChain;

  // ─── Plafonds milestone ────────────────────────────────────────────
  int milestoneHoldCeilingIdx();
  int milestoneRhythmCeilingIdx();

  // ─── Samplers position ─────────────────────────────────────────────
  (Position, Position) sampleFromTo(double ampScore, {bool capByDepth = true});
  (Position, Position) sampleFromToForHand(double ampScore);
  (Position, Position) sampleFromToForLick(double ampScore);
  Position pickHoldPosition(double ampScore);
  Position? pickBegPosition(double ampScore);
  StepDraft? maybePickBegWithChain({
    required Position? to,
    required int obPts,
  });

  // ─── Caps pacing ───────────────────────────────────────────────────
  int capRhythmDurationByPulses(int dur, int bpm, Position? to);
}

/// Contexte d'assemblage d'un step passé à `ModeRules.build`. Porte les
/// trois scores déjà budgétés par l'orchestrateur (cf.
/// `_DifficultyDispatch._mapDifficultyToStep` pour la simplex + le bonus
/// de spé par axe) et un handle vers le générateur (`GenFacadeSurface`)
/// pour accéder aux samplers, caps, lecture de spé et state stable.
///
/// Le couplage passe exclusivement par `GenFacadeSurface` (pas d'accès
/// direct aux internes du générateur). Si une rule a besoin d'une donnée
/// supplémentaire, l'ajouter à l'interface plutôt que de gonfler le ctx.
class DraftCtx {
  const DraftCtx({
    required this.bpmScore,
    required this.ampScore,
    required this.durScore,
    required this.gen,
  });

  final double bpmScore;
  final double ampScore;
  final double durScore;
  final GenFacadeSurface gen;
}

/// Snapshot des conditions d'éligibilité d'un mode à la phase de récup,
/// passé à `ModeRules.isRecoveryCandidate`. Construit une seule fois par
/// `_buildRecoveryStep` et partagé avec toutes les rules consultées.
///
/// `heritage` (= `unlockedKeys.isEmpty`) marque les sessions hors-carrière :
/// dans ce mode, le gating par milestone est court-circuité (tous les
/// modes passent par défaut). Symétrique de la convention déjà appliquée
/// par `_isUnlocked` ailleurs.
class RecoveryAvailability {
  const RecoveryAvailability({
    required this.heritage,
    required this.unlockedKeys,
    required this.includeHand,
  });

  final bool heritage;
  final Set<UnlockKey> unlockedKeys;
  final bool includeHand;
}

/// Contexte d'assemblage d'un draft de récup passé à
/// `ModeRules.buildRecovery`. Le BPM et la durée par défaut sont tirés
/// une seule fois par `_buildRecoveryStep` pour garantir une cohérence
/// inter-modes du contrat de récup (BPM ≤ 60, fenêtre 10–18 s) ; les
/// rules qui dérivent leur propre durée (beg 6–11 s, freestyle 8–15 s,
/// hold 4–7 s) peuvent simplement les ignorer.
class RecoveryCtx {
  const RecoveryCtx({
    required this.gen,
    required this.bpm,
    required this.duration,
  });

  final GenFacadeSurface gen;
  final int bpm;
  final int duration;
}

/// Snapshot passé à `ModeRules.postFinalVariants`. Construit une fois
/// par `FinalPicker.buildPostFinalDraft` avec `bpm`/`duration` tirés et
/// le mode du final tout juste joué. Les rules consomment ces données
/// pour gater leurs variantes (`finalMode` exclut le mode du final pour
/// l'alternance ; `holdCeilingIdx` rend les holds peu profonds obsolètes
/// si la joueuse a acquis un palier plus profond).
class PostFinalCtx {
  const PostFinalCtx({
    required this.finalMode,
    required this.bpm,
    required this.duration,
    required this.includeHand,
    required this.unlockedKeys,
    required this.holdCeilingIdx,
    required this.isModeForbidden,
  });

  final SessionMode finalMode;
  final int bpm;
  final int duration;
  final bool includeHand;
  final Set<UnlockKey> unlockedKeys;
  final int holdCeilingIdx;

  /// Callback dose Custom : un mode à dose `none` doit être exclu
  /// (cf. `FinalPicker._isModeForbidden`). Threadé via fonction pour
  /// éviter de coupler la rule à `coachModeWeights`.
  final bool Function(SessionMode) isModeForbidden;
}

/// Variante de step post-final proposée par une rule. Plusieurs
/// variantes par mode sont autorisées (`hold` propose tip + head, `beg`
/// propose libre + head). Le picker concatène toutes les variantes de
/// toutes les rules, filtre sur `req <= humilCap && !blocked`, trie par
/// `req` décroissante et tire uniformément dans le top-3 (avec biais
/// spé sloppy → lick / obeissance → beg).
class PostFinalVariant {
  const PostFinalVariant({
    required this.req,
    required this.blocked,
    required this.draft,
  });

  /// Seuil humiliation requis pour que la variante entre dans la palette.
  final double req;

  /// Variante exclue par les contraintes du contexte (mode déjà joué en
  /// final, profondeur de hold obsolète, dose Custom à 0, unlock absent).
  final bool blocked;

  /// Draft pré-construit. Allocation négligeable (~7 fields) — pas de
  /// gain mesurable à laisser ce build paresseux.
  final StepDraft draft;
}

/// Snapshot passé à `ModeRules.finalVariants`. Bundle tous les
/// paramètres dont une rule a besoin pour construire ses propositions
/// d'apothéose : seuil humiliation à atteindre (`humilCap`), plafond
/// profondeur (`maxDepth`), multiplicateur durée encore (`finishMul`),
/// niveau global, anatomie, unlocks, toggle hand, points endurance
/// pour le scaling de durée, et durées pré-calculées
/// (`fastDur` / `shortHoldDur` partagées entre plusieurs variantes).
///
/// Les **BPM aléatoires** (hand baseline / biffle) sont pré-tirés par
/// le picker **avant** la collecte des variantes — sinon l'itération
/// du registry (rhythm→lick→hold→biffle→…→hand) rebattrait le rng et
/// ferait diverger les sessions reproductibles vs la version
/// pré-refacto. `handBaselineBpm == null` signale aussi « pas de hand
/// baseline cette séance » (niveau ≥ 4), idem `biffleBpm == null` pour
/// `includeHand == false`.
class FinalCtx {
  const FinalCtx({
    required this.humilCap,
    required this.maxDepth,
    required this.finishMul,
    required this.level,
    required this.anatomy,
    required this.unlockedKeys,
    required this.includeHand,
    required this.endPts,
    required this.fastDur,
    required this.shortHoldDur,
    required this.handBaselineBpm,
    required this.biffleBpm,
  });

  final double humilCap;
  final int maxDepth;
  final double finishMul;
  final int level;
  final AnatomyProfile anatomy;
  final Set<UnlockKey> unlockedKeys;
  final bool includeHand;
  final int endPts;
  final int fastDur;
  final int shortHoldDur;

  /// BPM hand baseline pré-tiré côté picker (null = pas de hand baseline,
  /// niveau ≥ 4).
  final int? handBaselineBpm;

  /// BPM biffle pré-tiré côté picker (null = `includeHand == false`).
  final int? biffleBpm;
}

/// Variante de step final (apothéose) proposée par une rule. Plusieurs
/// variantes par mode sont autorisées (`hold` propose tip/head/mid +
/// throat/full conditionnels, `lick` propose tip→head + full→balls).
/// Le picker concatène toutes les variantes, filtre par
/// `_finalUnlocked(gate) && !_isModeForbidden(mode) && humilCap >= req
/// && _isUnlocked(draft)`, trie par `req` croissante et retient la **plus
/// humiliante** (`valid.last`) — distinct du post-final qui sample top-3.
class FinalVariant {
  const FinalVariant({
    required this.req,
    required this.gate,
    required this.draft,
  });

  /// Seuil humiliation requis pour que la variante entre dans la palette.
  final double req;

  /// Clé d'unlock dédiée final (distincte de l'unlock du composant — un
  /// hold mid en final exige `finalHoldMid`, pas `holdMidShort` qui
  /// couvre l'usage en corps de séance). `null` = libre par défaut (cas
  /// hand baseline : fallback universel).
  final UnlockKey? gate;

  /// Draft pré-construit (durée déjà trimée pour les holds profonds via
  /// [`FinalPicker.trimHoldFinalDuration`]).
  final StepDraft draft;
}

/// Contexte d'assemblage d'un step d'intro intense/quickie passé à
/// `ModeRules.buildIntroStep`. Construit par `_firstStep` avec les
/// valeurs « fixture » (intense : bpm=90 / from=head / to=clamped /
/// dur=10 ; quickie : bpm=75 / from=head / to=mid / dur=8). Les rules
/// rythmées (rhythm/hand/lick) consomment les 4 params straight ; hold
/// ignore bpm/from et garde uniquement to+duration (la position tenue +
/// la durée).
class IntroCtx {
  const IntroCtx({
    required this.bpm,
    required this.from,
    required this.to,
    required this.duration,
  });

  final int bpm;
  final Position from;
  final Position to;
  final int duration;
}

/// Contexte d'assemblage d'une mini-vague passé à
/// `ModeRules.buildMiniWaveSegment`. La rule retourne la séquence brute
/// de drafts (2-3 steps montants) ; le filtrage humil + clamp capacité +
/// dédoublonnage post-cascade reste côté générateur (qui consomme les
/// snapshots d'instance `_enforceHumiliationRequired` / `_clampToCapability`).
///
/// `hasThroat` permet à la rule de varier le `to` du dernier step de la
/// vague (throat si débloqué, sinon mid). Pas d'autre paramètre — la
/// vague est dramaturgiquement homogène (mode unique, BPMs hardcodés à
/// 100 / 120 / 135 dans l'implémentation rhythm).
class MiniWaveCtx {
  const MiniWaveCtx({required this.hasThroat});

  final bool hasThroat;
}

/// Contexte d'assemblage d'un step **swallow_order** passé à
/// `ModeRules.buildSwallowOrder`. La rule retourne un draft court qui
/// matérialise l'ordre coach « avale tout » quand la sim salive sature
/// (cf. `_maybeBuildSwallowOrder` côté générateur).
///
/// Le seul paramètre est la rng — la rule décide elle-même de la durée
/// pour préserver la sémantique « beg libre court 5-7 s » sans
/// hardcoder la fenêtre dans l'orchestrateur. Le check `begLibre` et
/// les conditions d'éligibilité (sim ≥ 80, cooldown, marge finish) sont
/// pré-filtrés par le générateur en amont — la rule peut compter sur
/// le fait qu'on est dans une fenêtre dramaturgique valide.
class SwallowCtx {
  const SwallowCtx({required this.rng});

  final Random rng;
}

/// Contexte d'assemblage d'un **breath de récupération** passé à
/// `ModeRules.buildBreathRecovery`. La rule calcule la durée à partir
/// du déficit projeté de stamina et de la regen courante, et retourne
/// un draft court (typiquement 4-12 s) qui comble juste assez pour
/// reprendre 2-3 steps derrière.
///
/// Toutes les conditions d'éligibilité (`draft.mode != breath`, marge
/// `genUntil - time > 8`, `projected < 0`) sont pré-filtrées côté
/// générateur — la rule est appelée uniquement quand l'insertion est
/// décidée.
class BreathRecoveryCtx {
  const BreathRecoveryCtx({
    required this.deficit,
    required this.progress,
    required this.cfg,
  });

  /// Manque de stamina projeté (positif = combien il manque pour
  /// terminer le step suivant à zéro).
  final double deficit;

  /// Progression dans la séance ∈ [0, 1] — pilote la regen via
  /// `CareerLevel.regen{Start,End}Multiplier`.
  final double progress;

  final CareerLevel cfg;
}

/// Contexte d'assemblage de la **pause longue post-vague** passé à
/// `ModeRules.buildPostWaveBreath`. Distinct de [BreathRecoveryCtx]
/// parce que la pause post-vague vise un plafond de stamina (~95)
/// plutôt qu'à combler un déficit, et s'autorise une fenêtre plus
/// large (12-20 s vs 4-12 s) — c'est un moment dramaturgique
/// scénarisé, pas un sas opportuniste.
///
/// Peut retourner `null` côté rule si le contexte ne permet pas
/// d'émettre la pause (cas `remainingSeconds < 12`).
class PostWaveBreathCtx {
  const PostWaveBreathCtx({
    required this.stamina,
    required this.progress,
    required this.cfg,
    required this.remainingSeconds,
  });

  final double stamina;
  final double progress;
  final CareerLevel cfg;
  final int remainingSeconds;
}

/// Contexte d'assemblage d'un **faux-breath** passé à
/// `ModeRules.buildFakeBreath`. La rule retourne un draft très court
/// (typiquement 2-3 s) qui matérialise un soupir feint sans vraie
/// récup — phrase taquine, pas un sas d'endurance.
///
/// Le test de profil intense (`isIntenseForFakeBreath`), le check
/// d'unlock `fakeBreath`, le dé 25 % et les gates stamina/marge finish
/// sont pré-filtrés côté générateur — la rule est appelée uniquement
/// quand l'insertion est décidée.
class FakeBreathCtx {
  const FakeBreathCtx({required this.rng});

  final Random rng;
}

/// Contexte d'assemblage du **pré-finisher** passé à
/// `ModeRules.buildPreFinisher`. La rule retourne un draft court
/// `head → preFinisherTarget` qui prépare la phase boosts (transition
/// rythmique avant l'apothéose, bas niveaux uniquement — cf.
/// `_emitPreFinisher` côté générateur).
///
/// `preFinisherTarget` est **pré-pickée** par l'orchestrateur via
/// `_positionPickers.pickFinisherPosition` (consomme du rng + état) ;
/// la rule la consomme telle quelle. Seules les **tirages bpm/durée**
/// (2 appels rng) restent côté rule pour préserver la sémantique
/// « courte accélération 62-70 BPM × 22-30 s » sans hardcoder les
/// fenêtres dans l'orchestrateur. Le clamp capacité et le pick de
/// phrase restent côté générateur — la rule est appelée uniquement
/// quand l'insertion est décidée (guard `isLowLevel &&
/// !isModeForbidden(preFinisherCore)`).
class PreFinisherCtx {
  const PreFinisherCtx({
    required this.rng,
    required this.preFinisherTarget,
  });

  final Random rng;
  final Position preFinisherTarget;
}

/// Contexte d'assemblage des variantes de **step d'intro standard**
/// (= sessions normales, hors intense/quickie qui passent par
/// [IntroCtx]) passé à `ModeRules.firstStepVariants`. Chaque rule
/// opt-in renvoie sa palette pré-construite ; le générateur concatène
/// toutes les variantes du registry, filtre par `_isUnlocked` +
/// `!isModeForbidden`, tire au hasard.
///
/// `includeHand` est threadé pour que `HandRules` sache si sa variante
/// d'amorce doit entrer dans la palette (ancien guard
/// `if (_config.includeHand)` côté générateur, désormais porté par la
/// rule). Les autres rules ignorent ce champ.
class IntroStandardCtx {
  const IntroStandardCtx({required this.includeHand});

  final bool includeHand;
}

/// Rôles sémantiques d'un mode au sein du générateur. Chaque rôle
/// désigne une **fonction dramaturgique** (sas breath, ordre
/// d'avalement, boost humiliant, etc.) — pas une identité technique.
/// Permet au générateur d'invoquer « le mode qui joue le rôle X »
/// plutôt que de hardcoder `SessionMode.rhythm` / `SessionMode.beg` /
/// `SessionMode.breath` dans la logique d'orchestration.
///
/// Cf. phase B du plan de refacto `~/beatbitch_refacto_career_gen.md` :
/// les rôles remplacent progressivement les literals `SessionMode.*` du
/// générateur, ouvrant la voie à des modes additionnels ou à un re-mapping
/// éditorial (ex. confier le `swallowOrder` à un autre mode que `beg`)
/// sans toucher au cœur de l'orchestration.
enum ModeSemanticRole {
  /// Mode de respiration / récup neutre (sas breath, fallback recovery,
  /// gate du sas « si mode != breath »).
  breath,

  /// Mode utilisé pour l'ordre de déglutition forcé.
  swallowOrder,

  /// Boost humiliant en phase finish (rhythm historique).
  burstHumiliating,

  /// Boost non-humiliant en phase finish (hand historique).
  burstNeutral,

  /// Fallback si les deux `burstX` ci-dessus sont exclus (lick
  /// historique).
  burstFallback,

  /// Mode des steps de mini-vague (rhythm historique).
  miniWaveCore,

  /// Mode du pré-finisher bas niveau (rhythm historique).
  preFinisherCore,

  /// Mode du breath long post-mini-vague (= [breath] dans la palette
  /// actuelle, distingué pour permettre un re-mapping futur).
  postWaveBreath,

  /// Fallback recovery si rien d'autre n'est candidat (breath historique).
  recoveryFallback,

  /// Mode statique tenu (hold) — utilisé pour la condition `holdPosition`
  /// du step final.
  staticHeld,

  /// Fallback ultime du main loop quand toutes les candidates ont été
  /// exclues par les filtres (custom doses, range, cascade soft-mouth).
  /// Préserve l'invariant historique du dispatcher : si tout est filtré,
  /// le générateur retombe sur le mode rythmé canonique (rhythm), même
  /// quand `_config.isModeForbidden(rhythm)` — crash-prevention pour les
  /// configs Custom corrompues. Cf. C.PR3.
  mainLoopFallback,
}

/// Snapshot des conditions d'éligibilité d'un mode à la boucle main du
/// dispatcher difficulté, passé à `ModeRules.difficultyRange`. Construit
/// une seule fois par `_DifficultyDispatch._mapDifficultyToStep` et
/// partagé avec toutes les rules consultées.
///
/// Le contexte porte ce qui pilotait l'ancienne cascade de `if` dans le
/// dispatcher : profil d'unlocks acquis, toggle hand, état runtime
/// (`lastType`, `stepsOutsideBouche`) qui relaxe la fenêtre rhythm/hold,
/// et la capacité courante du tracker de chaîne rythmée
/// (`canChainRhythm`). Chaque rule consomme uniquement ce dont elle a
/// besoin pour décider de sa fenêtre `[min, max)` ou de l'exclusion
/// (`null`).
///
/// `heritage` (= `unlockedKeys.isEmpty`) marque les sessions hors-carrière :
/// même convention que [RecoveryAvailability] — dans ce mode, le gating
/// par milestone est court-circuité (canBiffle / canBeg / canSuckle
/// passent par défaut).
class DifficultyCtx {
  const DifficultyCtx({
    required this.unlockedKeys,
    required this.includeHand,
    required this.lastType,
    required this.stepsOutsideBouche,
    required this.canChainRhythm,
  });

  final Set<UnlockKey> unlockedKeys;
  final bool includeHand;

  /// Type sémantique du dernier step émis (`null` au tout début de
  /// séance). Consulté par `RhythmRules` / `HoldRules` qui relaxent leur
  /// fenêtre minimale quand on est déjà en bouche.
  final StepType? lastType;

  /// Nombre de steps consécutifs hors `StepType.bouche` (incrémenté par
  /// `SessionRuntimeState.recordContinuity`). Consulté par `RhythmRules` :
  /// au-delà de 2, on relaxe sa fenêtre min même hors bouche (la
  /// continuité « phase de chauffe » a besoin de pouvoir rentrer en
  /// bouche).
  final int stepsOutsideBouche;

  /// Sortie courante de `RhythmChainTracker.canChain()`. Consulté
  /// uniquement par `RhythmRules` (les autres modes l'ignorent). `false`
  /// = la chaîne rythmée est plafonnée pour ce moment de la séance ; le
  /// candidat rhythm doit sortir de la palette.
  final bool canChainRhythm;
}

/// Règles d'un mode : tout ce qui est spécifique au mode et qui était
/// auparavant porté par les gros switches du générateur (stamina,
/// unlock gate, capability clamp, dégradation, construction de step).
///
/// La plupart des méthodes sont **pures** (signature `(draft, …) →
/// résultat`, pas d'accès à l'état). Seule `build` reçoit un `DraftCtx`
/// qui expose la facade — la rule y consomme ses samplers / caps
/// mode-specific (`config`, `state`, `rng`, `rhythmChain`, `sampleFromTo`,
/// `pickHoldPosition`, `capRhythmDurationByPulses`…) via `ctx.gen.*`.
/// Les helpers numériques partagés vivent côté `StaminaModel`
/// (`positionDepth`, `lerp`).
abstract class ModeRules {
  const ModeRules();

  /// Rôles sémantiques joués par ce mode dans l'orchestration. Consulté
  /// par le générateur via `_resolveModeForRole(role)` qui retourne le
  /// `SessionMode` du registre dont la rule déclare ce rôle. Default
  /// `const {}` (opt-in) — les modes sans rôle dramaturgique particulier
  /// (freestyle, suckle, biffle) gardent le défaut.
  ///
  /// Un même mode peut porter plusieurs rôles (breath couvre `breath` +
  /// `postWaveBreath` + `recoveryFallback`). Inversement, chaque rôle
  /// doit être déclaré par **au plus un** mode du registre — la
  /// résolution `_resolveModeForRole` n'est pas définie sinon (cf. son
  /// `assert` côté générateur).
  Set<ModeSemanticRole> get roles => const {};

  /// Construit la séquence brute d'une mini-vague (cf. `_buildMiniWave`
  /// côté générateur). Default `null` — opt-in : seul le mode qui joue
  /// le rôle [ModeSemanticRole.miniWaveCore] doit override (consulté via
  /// `_resolveModeForRole(miniWaveCore)`).
  ///
  /// La rule retourne 2-3 drafts montants (BPMs espacés ≥ 20 pour ne
  /// pas trigger `_patternBuffer.wouldBeFlat`). Le filtrage humil +
  /// clamp capacité + dédoublonnage post-cascade restent côté générateur.
  List<StepDraft>? buildMiniWaveSegment(MiniWaveCtx ctx) => null;

  /// Construit un step **swallow_order** (cf. `_maybeBuildSwallowOrder`
  /// côté générateur). Default `null` — opt-in : seul le mode qui joue
  /// le rôle [ModeSemanticRole.swallowOrder] doit override (consulté via
  /// `_resolveModeForRole(swallowOrder)`).
  ///
  /// La rule décide elle-même de la durée (typiquement courte, 5-7 s)
  /// pour préserver la sémantique « ordre coach » sans hardcoder la
  /// fenêtre dans l'orchestrateur. Les conditions d'éligibilité
  /// (sim salive saturée, cooldown, marge finish, begLibre débloqué)
  /// sont déjà pré-filtrées en amont — la rule n'a pas à les revérifier.
  StepDraft? buildSwallowOrder(SwallowCtx ctx) => null;

  /// Construit un **breath de récupération** (cf. `_buildBreathRecovery`
  /// côté générateur). Default `null` — opt-in : seul le mode qui joue
  /// le rôle [ModeSemanticRole.breath] doit override.
  ///
  /// La rule calcule la durée à partir du déficit projeté et de la regen
  /// courante, et retourne un draft court (typiquement 4-12 s).
  StepDraft? buildBreathRecovery(BreathRecoveryCtx ctx) => null;

  /// Construit la **pause longue post-vague** (cf. `_buildPostWaveBreath`
  /// côté générateur). Default `null` — opt-in : seul le mode qui joue
  /// le rôle [ModeSemanticRole.postWaveBreath] doit override.
  ///
  /// Peut retourner `null` si la fenêtre disponible est trop courte
  /// (cf. `ctx.remainingSeconds < 12`) — le générateur traite ce cas
  /// comme « pas de pause cette fois ».
  StepDraft? buildPostWaveBreath(PostWaveBreathCtx ctx) => null;

  /// Construit un **faux-breath** (cf. `_maybeBuildFakeBreath` côté
  /// générateur). Default `null` — opt-in : seul le mode qui joue le
  /// rôle [ModeSemanticRole.breath] doit override.
  ///
  /// La rule retourne un draft très court (typiquement 2-3 s). Le
  /// gating (unlock `fakeBreath`, conditions stamina/marge, dé 25 %,
  /// test `isIntenseForFakeBreath` sur le step précédent) est fait
  /// côté générateur — la rule est appelée uniquement quand l'insertion
  /// est décidée.
  StepDraft? buildFakeBreath(FakeBreathCtx ctx) => null;

  /// Construit un step **pré-finisher** (cf. `_emitPreFinisher` côté
  /// générateur). Default `null` — opt-in : seul le mode qui joue le
  /// rôle [ModeSemanticRole.preFinisherCore] doit override (consulté
  /// via `_resolveModeForRole(preFinisherCore)`).
  ///
  /// La rule tire elle-même BPM (62-70) et durée (22-30 s) — la
  /// position `head → preFinisherTarget` est pré-pickée et threadée
  /// via `ctx.preFinisherTarget`. Le clamp capacité, le pick de phrase
  /// et l'émission du step restent côté générateur ; les conditions
  /// d'éligibilité (bas niveau, mode non banni) sont déjà pré-filtrées
  /// en amont — la rule n'a pas à les revérifier.
  StepDraft? buildPreFinisher(PreFinisherCtx ctx) => null;

  /// Mode rythmé à amplitude (`rhythm` / `lick` / `hand` / `biffle`) ?
  /// Consulté par `_RhythmicPatternBuffer` pour ne tracker que les
  /// steps qui ont une mécanique BPM + position pertinents pour la
  /// détection de pattern plat. Les hold / beg / breath / freestyle /
  /// suckle n'ont pas de pattern plat à détecter — leur monotonie est
  /// gérée ailleurs (variation de position dans `_pickHoldPosition` /
  /// `_state.lastFrom`). Default `false` (opt-in).
  ///
  /// Couvre les 4 modes du quatuor rythmé historique :
  /// - `rhythm` : loop BPM alternant from↔to.
  /// - `lick` : variante volume réduit du rhythm.
  /// - `hand` : sample dédié, même mécanique que rhythm.
  /// - `biffle` : loop BPM sample dédié (pas de from/to mais BPM
  ///   significatif → entre dans le filtre).
  bool get isRhythmic => false;

  /// Mode « flow » consommé par `_ModePicker.filterRepeated` — accepte
  /// la répétition immédiate (deux steps identiques d'affilé) parce
  /// que la variété passe par les paramètres (BPM via
  /// `_applyBpmDiversity` ≥ 18 BPM de delta, profondeur via
  /// `_diversifyAmplitude` qui décale d'un cran). Sans cette
  /// tolérance, le générateur sortait nécessairement de rythme à
  /// chaque step — retour utilisateur « la séance ressemble à une
  /// rotation stricte ».
  ///
  /// Distinct de [isRhythmic] : biffle est rhythmic (loop BPM) mais
  /// pas flow — ses coups de queue sur le visage sonneraient comme un
  /// bug s'ils enchaînaient deux fois. Couvre `rhythm`, `lick`,
  /// `hand`. Default `false` (opt-in) — tous les autres modes (hold,
  /// biffle, beg, breath, freestyle, suckle) sont « ponctuels » et
  /// passent par le filtre `lastMode != m` de `filterRepeated`.
  bool get isFlow => false;

  /// Fenêtre de difficulté `[min, max)` dans laquelle le mode est
  /// candidat à la boucle main, ou `null` si le mode n'est pas
  /// éligible compte tenu du contexte (unlock absent, toggle hand off,
  /// chaîne rythmée plafonnée, ou mode non-candidat par construction —
  /// breath / freestyle).
  ///
  /// Sémantique : le dispatcher inclut le mode dans les candidats si
  /// `range != null && range.min ≤ diff < range.max`. La borne haute
  /// est volontairement exclusive (cas lick `[0.0, 0.30)`). Default
  /// `null` (opt-in) — les rules sans fenêtre main loop (breath,
  /// freestyle) gardent le défaut. Cf. C.PR3.
  ({double min, double max})? difficultyRange(DifficultyCtx ctx) => null;

  /// Pondération brute issue de la spécialisation seule (sans coach,
  /// sans friction de continuité) consommée par `_ModePicker.weight`
  /// pour pondérer le tirage du mode dans la boucle main. Default
  /// `1.0` (= neutre, pas de biais spé).
  ///
  /// Chaque rule porte sa propre équation : `RhythmRules` boost
  /// rythmeBiffle + un peu profondeur ; `LickRules` baseline 0.6 +
  /// gros boost sloppy ; `BegRules` boost obeissance ; `HoldRules`
  /// endurance + profondeur ; `BiffleRules` rythmeBiffle + sloppy ;
  /// `HandRules` boost rythmeBiffle léger ; `BreathRules` neutre ;
  /// `FreestyleRules` baseline 0.25 ; `SuckleRules` baseline 0.6 +
  /// sloppy + obéissance.
  ///
  /// Les coefficients exacts vivent côté rule (chaque mode a une
  /// éditorialisation propre — pas extractible vers un mécanisme plus
  /// abstrait sans perdre du sens).
  double baseWeight(SpecializationAllocation spec) => 1.0;

  /// Coût (négatif) ou regen (positif) d'endurance pour le step.
  double delta(StepDraft draft, double progress, CareerLevel cfg);

  /// Cluster sémantique du step (`bouche` / `langue` / `libreMain` /
  /// `transit`) consommé par la friction de continuité (`_ModePicker`)
  /// et le tracking (`SessionRuntimeState.recordContinuity`).
  ///
  /// Le paramètre `to` n'est utilisé que par `beg` (avec position tenue
  /// → `bouche`, libre → `libreMain`) ; les autres rules l'ignorent. Au
  /// moment du tirage d'un candidat (`_ModePicker.continuityMultiplier`),
  /// le caller passe `null` — un beg-candidat est traité comme libre par
  /// défaut (cf. doc du caller).
  StepType classify(Position? to);

  /// Variante de `finale_chime` à piocher si le mode se retrouve en
  /// final d'apothéose (cf. `FinalPicker.pickFinal` côté palette,
  /// `BeepEngine.playFinaleChime` côté audio). Default `medium` —
  /// couvre biffle, lick, rhythm, beg, breath, freestyle, suckle qui
  /// soit n'apparaissent jamais en final, soit reçoivent une finition
  /// neutre. Hand override en `easy` (finition douce), hold override
  /// avec un switch sur `to` (tip→easy, head/mid→medium, throat→hard,
  /// full→extreme, balls→hard).
  FinalCategory finalCategory(StepDraft draft) => FinalCategory.medium;

  /// Clé d'unlock requise pour qu'un step de ce mode soit jouable en mode
  /// carrière, ou `null` quand le step est dans le socle de base (pas de
  /// gate explicite). Default `null` = socle (rhythm tip→head, hold tip…).
  ///
  /// Convention `_isUnlocked` (hors interface ici, mais appliquée par le
  /// caller) : `unlockedKeys.isEmpty` = mode hérité, aucun gating. Cette
  /// méthode ne tient pas compte de cette convention — elle retourne
  /// toujours la clé mécanique.
  UnlockKey? unlockKeyFor(StepDraft draft) => null;

  /// Borne un draft à l'enveloppe « profil de capacités » : profondeur,
  /// BPM et durée ne dépassent pas ce que la joueuse a *prouvé* tenir.
  /// Default = identité (les modes non pilotants — `hand`, `lick`,
  /// `breath`, `freestyle`, `suckle` — ne sont jamais clampés par le
  /// profil ; cf. règle « hand n'est jamais un levier de difficulté »).
  ///
  /// La gestion centrale de `chainNext` (récursion) et de la composition
  /// avec `clampToCustomLimits` (bornes utilisateur Custom) reste côté
  /// `CapabilityClamps.clampToCapability` — chaque rule ne touche qu'à
  /// son draft principal.
  ///
  /// Le second paramètre est typé [CapabilityClampSurface] (interface) et
  /// non `CapabilityClamps` (classe concrète) : la rule ne consomme que
  /// `capabilityCapFor` / `overloadFactorFor` / `clampToCapability(d)`.
  /// Le helper statique `CapabilityClamps.minNullable` reste appelé par
  /// nom de classe — pas dans l'interface (cf. A.PR1 du plan de refacto).
  StepDraft clampToCapability(StepDraft draft, CapabilityClampSurface c) =>
      draft;

  /// Une étape de dégradation : retourne le draft modifié si la rule sait
  /// adoucir, ou `null` pour passer la main au fallback global (lick
  /// tip→head). Appelée en boucle par `HumiliationGates.enforceRequired`
  /// jusqu'à ce que le draft satisfasse `humilCap` ET `isUnlocked`.
  ///
  /// Chaque rule choisit l'ordre de ses propres stratégies (raccourcir,
  /// baisser `to`, baisser `from`, capper BPM, changer de mode) ; on ne
  /// retourne qu'**un seul** cran par appel pour permettre à la cascade
  /// externe de re-vérifier l'humil/unlock après chaque pas.
  StepDraft? tryDegrade(StepDraft draft) => null;

  /// Assemble le `StepDraft` final du mode à partir des scores déjà
  /// budgétés par l'orchestrateur. Voir `DraftCtx` pour la surface du
  /// contexte. La rule consomme ses propres samplers / caps mode-specific
  /// via `ctx.gen.*` (le couplage est explicite, cf. doc de `DraftCtx`).
  ///
  /// **Obligatoire** : toute rule doit override `build`. Le défaut throw
  /// plutôt qu'un fallback silencieux — `_DifficultyDispatch` est
  /// dispatcher pur, il n'y a plus de switch historique vers lequel
  /// retomber.
  StepDraft build(DraftCtx ctx) {
    throw UnimplementedError(
      'ModeRules.build non implémenté pour $runtimeType',
    );
  }

  /// Indique si ce mode est candidat à la phase de récup étant donné
  /// les unlocks acquis et le toggle Hand. Default `false` (opt-in
  /// explicite) — `hand`, `breath` et `suckle` ne sont jamais tirés
  /// en récup, ils gardent le défaut.
  ///
  /// Le filtrage par dose Custom (`coachModeWeights`), la friction de
  /// continuité (`_ModePicker.filterRepeated` / `pickWeighted`) et le
  /// check final `_isUnlocked` (qui dégrade en cascade) restent côté
  /// orchestrateur — ce gate est uniquement « éligibilité par défaut
  /// + unlock requis pour entrer dans la palette ».
  bool isRecoveryCandidate(RecoveryAvailability a) => false;

  /// Construit le draft de récup pour ce mode. Appelé uniquement après
  /// que le mode a été retenu par le tirage pondéré (donc après que
  /// `isRecoveryCandidate` a retourné `true`). Default throw — toute
  /// rule qui opt-in doit override.
  StepDraft buildRecovery(RecoveryCtx ctx) {
    throw UnimplementedError(
      'ModeRules.buildRecovery non implémenté pour $runtimeType',
    );
  }

  /// Variantes de step post-final (aftercare ~12 s après l'orgasme)
  /// proposées par ce mode. Plusieurs variantes par mode sont
  /// autorisées (hold propose tip + head, beg propose libre + head).
  /// Default `const []` (opt-in) — biffle, freestyle, suckle n'ont pas
  /// de variante post-final.
  ///
  /// Le picker (`FinalPicker.buildPostFinalDraft`) concatène toutes
  /// les variantes, filtre sur `req <= humilCap && !blocked`, trie par
  /// `req` décroissante et tire uniformément dans le top-3 (avec biais
  /// spé sloppy → lick / obeissance → beg pour les niveaux ≥ 7).
  List<PostFinalVariant> postFinalVariants(PostFinalCtx ctx) => const [];

  /// Variantes de step final (apothéose) proposées par ce mode.
  /// Plusieurs variantes par mode sont autorisées (hold propose
  /// tip/head/mid + throat/full conditionnels, lick propose tip→head +
  /// full→balls). Default `const []` (opt-in) — rhythm, beg, breath,
  /// freestyle, suckle n'ont pas de variante final.
  ///
  /// Le picker (`FinalPicker.pickFinal`) concatène toutes les
  /// variantes, filtre par `_finalUnlocked(gate)` + `_isModeForbidden`
  /// + `humilCap >= req` + `_isUnlocked(draft)`, trie par `req`
  /// croissante et retient la plus humiliante (`valid.last`), puis
  /// applique `clampToCapability`. Fallback hand → lick / hold head
  /// préservé côté picker pour les sessions où aucune variante ne passe.
  List<FinalVariant> finalVariants(FinalCtx ctx) => const [];

  /// Plafond profondeur (index `Position`) pour la diversification
  /// d'amplitude (cf. `_diversifyAmplitude` côté générateur). `null` =
  /// le mode n'a pas d'amplitude `from→to` à diversifier → la fonction
  /// est no-op (le draft est retourné tel quel).
  ///
  /// Default `null` (opt-in). Override `rhythm` consulte le plafond
  /// milestone (`gen.milestoneRhythmCeilingIdx`) pour ne jamais
  /// dépasser le palier d'unlock acquis. Override `lick` / `hand`
  /// retournent l'index `full` (4) — la profondeur max d'amplitude
  /// n'est pas gatée pour ces modes. `biffle` reste sur le default
  /// `null` (from/to sont null par convention).
  int? amplitudeDiversifyCeiling(GenFacadeSurface gen) => null;

  /// Vrai quand le dernier step émis dans ce mode est suffisamment
  /// intense pour déclencher un faux-breath de 2-3 s (cf.
  /// `_maybeFakeBreath`). Default `false` (opt-in). Override `rhythm`
  /// / `hand` : `to ∈ {throat, full} && bpm ≥ 90`. Override `hold` :
  /// `to ∈ {throat, full}` (BPM null, le hold n'a pas de tempo).
  bool isIntenseForFakeBreath(StepDraft draft) => false;

  /// Pioche la phrase à associer au step post-final pour ce mode, ou
  /// `null` pour laisser le caller retomber sur le pool générique
  /// (`PhraseBank.pickPostFinal`). Default `null` (opt-in).
  /// Override `beg` → `bank.pickPostFinalBeg(rng)` (consigne de
  /// supplique, jamais un compliment doux). Override `lick` →
  /// `bank.pickPostFinalLick(rng)` (consigne d'aftercare humiliant).
  ///
  /// Le caller cascade : `rule.pickPostFinalText(bank, rng)` →
  /// `bank.pickPostFinal(rng)` → `bank.pickCongrats(rng)`. La rng est
  /// consommée à chaque tentative ; semantics identiques au switch
  /// historique sur `mode == beg / lick`.
  String? pickPostFinalText(PhraseBank bank, Random rng) => null;

  /// Rang du mode dans la chaîne de fallback « intro intense / quickie »
  /// (cf. `_firstStep` côté générateur). Plus bas = préféré. `null` =
  /// mode pas candidat à cette chaîne (default opt-in).
  ///
  /// Cascade actuelle (rangs distincts pour ordre total déterministe) :
  /// rhythm (0) → hand (1) → lick (2) → hold (3). Hold occupe le rang
  /// le plus haut = fallback ultime ; le caller préserve hold même si
  /// `_isModeForbidden(hold)` (sinon en Custom dose à 0 partout on
  /// retombe sans candidat).
  int? get introPriority => null;

  /// Assemble le step d'intro intense/quickie pour ce mode à partir
  /// des fixture values posées par `_firstStep` (cf. `IntroCtx`).
  /// Appelée uniquement après que `_pickIntroMode` a retenu ce mode
  /// (donc seuls les modes avec `introPriority != null` reçoivent
  /// l'appel). Default throw — toute rule qui opt-in à `introPriority`
  /// doit override. Rhythm/hand/lick consomment les 4 params straight ;
  /// hold ignore bpm/from et ne garde que `to`+`duration`.
  StepDraft buildIntroStep(IntroCtx ctx) {
    throw UnimplementedError(
      'ModeRules.buildIntroStep non implémenté pour $runtimeType',
    );
  }

  /// Variantes de **step d'intro standard** (sessions normales, hors
  /// intense/quickie qui passent par `buildIntroStep`) proposées par
  /// ce mode. Default `const []` (opt-in) — `rhythm` propose 3
  /// variantes (tip→head 65BPM, head→mid 70BPM, tip→mid 65BPM) ; `lick`
  /// propose tip→head 60BPM 20s ; `hand` propose tip→head 55BPM 18s
  /// quand `ctx.includeHand`. Les autres modes restent silencieux.
  ///
  /// Le générateur (`_firstStep`) concatène toutes les variantes du
  /// registry dans l'ordre d'itération (rhythm → lick → hold → biffle →
  /// beg → hand → breath → freestyle → suckle), filtre par `_isUnlocked`
  /// (gating milestone) et `!_config.isModeForbidden` (dose Custom), puis
  /// tire uniformément. Si tout est filtré, fallback sur la 1ʳᵉ variante
  /// non interdite (sinon la 1ʳᵉ tout court).
  List<StepDraft> firstStepVariants(IntroStandardCtx ctx) => const [];
}

/// Baisse `to` d'un cran en s'arrêtant à `head` (jamais à `tip` — un step
/// rythmique a besoin d'au moins une amplitude tip↔head). Garde-fou
/// collision : si la descente ferait `from >= to` (ex. head→mid → head→head
/// interdit), on retourne `null` pour passer à la stratégie suivante.
/// Helper mutualisé par les modes à amplitude (rhythm / lick / hand).
StepDraft? tryDescendToWithGuard(StepDraft d) {
  if (d.to == null || d.to!.index <= Position.head.index) return null;
  final newToIdx = d.to!.index - 1;
  final fromIdx = d.from?.index ?? -1;
  if (newToIdx <= fromIdx) return null;
  return StepDraft(
    mode: d.mode,
    bpm: d.bpm,
    from: d.from,
    to: Position.values[newToIdx],
    duration: d.duration,
    chainNext: d.chainNext,
  );
}

/// Baisse `from` d'un cran en s'arrêtant à `tip`. Helper mutualisé par les
/// modes à amplitude.
StepDraft? tryDescendFrom(StepDraft d) {
  if (d.from == null || d.from!.index <= Position.tip.index) return null;
  return StepDraft(
    mode: d.mode,
    bpm: d.bpm,
    from: Position.values[d.from!.index - 1],
    to: d.to,
    duration: d.duration,
    chainNext: d.chainNext,
  );
}

/// Cap durée mutualisé hold + beg : convention `to` porte la position
/// tenue (repli `from`). Pour throat / full, on prend le min des deux
/// axes pertinents — la durée tenable de la position ET l'apnée prouvée.
StepDraft clampHeldDuration(StepDraft draft, CapabilityClampSurface c) {
  var dur = draft.duration;
  final held = draft.to ?? draft.from;
  if (held != Position.throat && held != Position.full) return draft;
  final cap = _minNullable(
    c.capabilityCapFor(held == Position.throat
        ? CapabilityAxis.holdThroatStreak
        : CapabilityAxis.holdFullStreak),
    c.capabilityCapFor(CapabilityAxis.gorgeApneeStreak),
  );
  if (cap == null || dur == null || dur <= cap) return draft;
  dur = max(2, cap.floor());
  return StepDraft(
    mode: draft.mode,
    bpm: draft.bpm,
    bpmEnd: draft.bpmEnd,
    from: draft.from,
    to: draft.to,
    duration: dur,
    chainNext: draft.chainNext,
  );
}

/// Minimum de deux doubles nullable. `null` = pas de contrainte → l'autre
/// l'emporte. Doublon volontaire de `CapabilityClamps.minNullable` : cette
/// library est autonome et n'a pas accès à la classe concrète (qui vit en
/// `part of` côté générateur). Les rules continuent d'appeler le helper
/// public statique par nom de classe ; ce `_minNullable` privé sert
/// uniquement à `clampHeldDuration`.
double? _minNullable(double? a, double? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}
