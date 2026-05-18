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
