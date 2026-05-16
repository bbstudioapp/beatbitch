import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/anatomy_profile.dart';
import '../../models/final_category.dart';
import '../../models/punishment.dart';
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import '../../services/humiliation_engine.dart';
import '../../services/saliva_engine.dart';
import '../models/career_level.dart';
import '../models/level_milestone.dart';
import '../models/phrase_bank.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';

part 'career_session_generator_stamina.dart';
part 'career_session_generator_bpm.dart';
part 'career_session_generator_humiliation.dart';
part 'career_session_generator_capability.dart';
part 'career_session_generator_mode_picker.dart';
part 'career_session_generator_final_picker.dart';

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

  // ─── PARAMÈTRES DE SESSION (settables par [generate]) ────────────────────
  // Posés au début de chaque appel à `generate`. Lus par les helpers de
  // tirage / clamp tout au long de la génération. Aucun n'est modifié au
  // cours d'une même session.

  /// Toggle propagé depuis [generate]. Filtre hand ET biffle des candidats
  /// (les coups de queue impliquent de tenir avec la main, donc cohérent
  /// d'exclure les deux ensemble).
  bool _includeHand = true;

  /// Plafond de profondeur autorisé (index Position) — appliqué à
  /// `_sampleFromTo` et `_pickHoldPosition`. Valeur par défaut 4 (full).
  /// Renseigné par `generate` à partir du `CareerLevel`.
  int _maxDepthIndex = 4;

  /// Probabilité de retenir une position profonde (throat/full) quand le
  /// plafond la permet. Permet de raréfier sans bannir.
  double _deepProbability = 1.0;

  /// Allocation de spécialisation propagée pour pondérer le tirage des
  /// candidats et les paramètres internes (BPM, amplitude, durée). Si
  /// non fournie : map vide → comportement neutre.
  SpecializationAllocation _spec = SpecializationAllocation.empty();

  /// Niveau global du joueur passé à `generate`. Utilisé pour gater les
  /// branches de tirage qui n'ont de sens qu'à un certain niveau (ex :
  /// post-final humiliant biaisé par spé sloppy/obeissance, réservé aux
  /// niveaux avancés où la dramaturgie peut sortir du cadre doux).
  int _level = 1;

  // ─── ÉTAT DE TRACKING (mutable pendant la génération) ────────────────────
  // Champs mis à jour à chaque step poussé. Servent à la continuité, à la
  // variété (anti-répétition mode/BPM/profondeur) et au pacing (mini-vagues,
  // ordres salive). Tous reset au début de `generate`.

  /// `time` (en secondes) à partir duquel une **mini-vague** peut être
  /// insérée dans la boucle main. Cf. `_shouldEmitMiniWave` pour les
  /// conditions cumulatives. Initialisée à 5-6 min dans `generate`. Une
  /// vague émise repousse à `time + 6-7 min`. Vise à casser la diagonale
  /// d'intensité unique du début au finish sur les sessions longues —
  /// 1 à 3 mini-vagues sur une session de 25-45 min.
  int _nextMiniWaveAt = 0;

  /// `time` du dernier ordre de déglutition forcé (`swallow_order`).
  /// Sert au cooldown 90 s entre deux ordres : sans ça, une joueuse spé
  /// sloppy avec lick à fond sature en permanence et le coach radoterait
  /// « avale » toutes les 30 s. Initialisée à -120 dans `generate` pour
  /// laisser un premier ordre arriver dès la fin de la rampe initiale
  /// si la salive monte vite.
  int _lastSwallowOrderAt = -120;

  /// Dernier mode poussé dans la séance, pour éviter qu'un même mode
  /// (breath, beg, …) se déclenche deux steps d'affilé. Reset dans `generate`.
  SessionMode? _lastMode;

  /// Durée cumulée (en secondes) des steps `rhythm` poussés consécutivement.
  /// Tout step d'un autre mode (breath compris) reset à 0. Sert au cap
  /// « rythme soutenu » : tant que `rhythmHeadMidSustained` n'est pas
  /// débloqué, la chaîne rythme consécutive est plafonnée à 60 s par
  /// `_capRhythmConsecutive` / `_canChainRhythm` dans `_mapDifficultyToStep`.
  /// La milestone `intro_rhythm_sustained` enseigne et débloque ce
  /// dépassement.
  int _consecutiveRhythmSeconds = 0;

  /// Type effectif du dernier step poussé (= cluster sémantique :
  /// bouche / langue / libre-main). Sert à forcer une continuité par
  /// type sur plusieurs steps consécutifs : la séance est censée se
  /// concentrer sur la bouche, les autres types sont des intros / des
  /// respirations entre deux phases bouche.
  ///
  /// Les steps `transit` (breath / freestyle) sont des parenthèses
  /// transparentes : ils ne touchent ni `_lastType` ni `_stepsInLastType`,
  /// pour qu'un breath de récup au milieu d'une série bouche n'efface pas
  /// la continuité.
  _StepType? _lastType;
  int _stepsInLastType = 0;

  /// Nombre de steps **consécutifs** posés en dehors du type `bouche`.
  /// Reset à 0 dès qu'un step bouche est poussé. Sert à imposer un cap
  /// dur sur la durée d'une excursion hors bouche : passé un certain
  /// nombre de steps cumulés (peu importe que ce soit langue ou
  /// libre-main), on force le retour à bouche.
  ///
  /// Distinct de `_stepsInLastType` qui reset à chaque changement de
  /// type — ce compteur-là tient sur tout l'écart bouche → bouche.
  int _stepsOutsideBouche = 0;

  /// Dernière phrase TTS poussée, pour éviter de répéter la même phrase
  /// scriptée d'un step à l'autre. Reset dans `generate`.
  String _lastText = '';

  /// Dernier BPM appliqué à un step (rhythm/lick/biffle/hand). Sert à
  /// forcer la variété : un nouveau BPM trop proche du précédent est
  /// décalé de 18–30 BPM par `_diversifyBpm`.
  int? _lastBpm;

  /// Dernier couple (from, to) appliqué pour les modes à amplitude
  /// (rhythm/lick/hand/biffle). Sert à forcer une variation de profondeur
  /// quand le step suivant tombe sur exactement la même paire.
  Position? _lastFrom;
  Position? _lastTo;

  /// Buffer roulant des 3 derniers steps rythmés émis (mode + from + to +
  /// bpm). Sert à détecter un **pattern plat** sur une fenêtre élargie :
  /// même mode + même profondeur cible + variance BPM < 10 sur 3 steps
  /// consécutifs = monotone, on force une diversification au step suivant.
  /// Sans cette fenêtre, `_diversifyAmplitude` ne regardait que le step
  /// strictement précédent et laissait passer des séries du genre
  /// `head→mid 90 / head→mid 92 / head→mid 88` (BPMs proches mais différents
  /// donc check classique satisfait, alors que l'oreille perçoit un plat).
  /// Les steps transit (breath / freestyle) sont **ignorés** : un breath
  /// de récup au milieu d'une série rythmée ne casse pas la perception du
  /// pattern, on veut qu'il continue à compter.
  final List<_RecentEmit> _recentEmits = [];

  // ─── SIMULATION SALIVE ───────────────────────────────────────────────────
  // Mime le runtime `SalivaEngine` pour anticiper les ordres de déglutition
  // au moment du draft. Reset à chaque `generate`.

  /// Simulateur de salive utilisé pendant la génération. Mime le
  /// comportement du `SalivaEngine` runtime : production par mode/position,
  /// auto-déglutition au-dessus de 75. Sert à projeter la lubrification
  /// au moment du draft d'un step throat/full (cf. Phase 4). En V1 le
  /// SwallowMode est assumé `allowed` (le générateur n'émet pas encore de
  /// steps forbidden auto-générés ; les milestones les portent en dur).
  late SalivaEngine _salivaSim;
  int _salivaSimSecond = 0;

  // ─── GATING & CONTENU AUTORISÉ ───────────────────────────────────────────
  // Set d'unlocks, profil anatomique, poids coach. Posés par `generate`,
  // lus partout pour autoriser/exclure des modes ou des actions.

  /// Set des `UnlockKey` débloquées pour la génération en cours. Une action
  /// dont la clé n'est pas dedans est rejetée par `_isUnlocked` et dégradée
  /// par `_stepDownOne`. Vide = aucune clé requise (mode héritage).
  Set<UnlockKey> _unlockedKeys = const {};

  /// Profil anatomique de la joueuse — pour gater les zones non disponibles
  /// dans son setup (testicules absents → tous les steps `Position.balls`
  /// rejetés par `_isUnlocked`). Default = tout disponible (rétrocompat
  /// pour tests / mode hérité). Le call site carrière / Custom passe la
  /// valeur lue depuis `UserProfileService.anatomy`.
  AnatomyProfile _anatomy = AnatomyProfile.defaults;

  /// Multiplicateur de poids par mode, fourni par le coach actif. Combiné
  /// **multiplicativement** par-dessus la pondération spé dans `_modeWeight`.
  /// Mode absent = 1.0 (neutre). Cf. CoachMeta.modeWeights.
  ///
  /// **Convention** : un poids strictement à 0 est lu comme une exclusion
  /// dure (utilisé par le Mode Custom — dose `none` ⇒ 0.0). `_isModeForbidden`
  /// l'expose et est consulté par tous les call sites qui tirent ou
  /// hardcodent un mode pour ne jamais émettre un mode exclu.
  Map<SessionMode, double> _coachModeWeights = const {};

  /// True si le mode est exclu par le caller via `coachModeWeights[m] == 0`.
  /// Un coach normal ne pose jamais 0 (cf. CoachMeta) → toujours false hors
  /// Custom. En Custom, c'est le dosage `none` de `CustomSessionConfig` qui
  /// pose le 0 et qui doit être honoré partout (palette finale, mini-vagues,
  /// pré-finisher, intro, recovery…), pas seulement dans `_pickWeightedMode`.
  bool _isModeForbidden(SessionMode m) {
    final w = _coachModeWeights[m];
    return w != null && w <= 0;
  }

  // ─── HUMILIATION & OBÉDIANCE (snapshot au start de session) ──────────────
  // Lus par `_humilCapAt` (cascade humil) et `_pickPhrase` (bump tier).
  // Pas modifiés pendant la génération.

  /// Score career d'humiliation (persisté lifetime) au démarrage de la
  /// session. Sert au tirage spécifique de certains modes (lick :
  /// amplitudes complètes seulement à partir de 2).
  double _humiliationCareer = 0.0;

  /// Score session d'humiliation (intra-session) au moment de la
  /// génération. Vaut 0 pour une session normale, > 0 sur encore
  /// enchaîné ou régénération en cours de séance (Supplier / retry
  /// milestone). Le générateur projette une rampe par-dessus ce score
  /// basée sur le tick automatique (cf. [_humilCapAt]).
  double _humiliationSession = 0.0;

  /// Score d'obédiance au démarrage de la session (cf. param `obedience`
  /// de `generate`). Pilote le tier de phrase auto-bumpé dans `_pickPhrase`
  /// (plus c'est élevé, plus la coach pioche dans `medium`/`hard`) et le
  /// `recoveryThreshold` (plus c'est élevé, plus on respecte l'endurance).
  double _obedience = 0.0;

  // ─── CAPACITÉ & SURCHARGE (2ᵉ enveloppe carrière) ────────────────────────
  // Profil persisté + plafonds figés sur fail + axe surchargé cette séance.
  // Lus par `_clampToCapability` / `_capabilityCapFor`.

  /// Profil de capacités (2ᵉ enveloppe de difficulté, carrière uniquement).
  /// `null` = pas de gating capacité (mode Custom, scénarios JSON, tests
  /// hérités) — convention parallèle à `_unlockedKeys.isEmpty`. On lit
  /// `comfort` (rendu adaptatif par `CapabilityRegulator`) pour borner les
  /// steps, et `successRate` pour moduler la surcharge.
  CapabilityProfile? _capProfile;

  /// Plafonds figés sur un appui FAIL pendant la session courante (§6 de la
  /// spec) — propagés par `SessionController.capabilitySessionCeilings` aux
  /// régénérations en cours de séance (Supplier / retry milestone) et au
  /// premier maillon d'un encore enchaîné. Vide hors carrière.
  Map<CapabilityAxis, double> _capCeilings = const {};

  /// Axe surchargé cette session (surcharge **isolée** : un seul axe est
  /// poussé au-delà de son `comfort`, les autres restent clampés — c'est ce
  /// qui rend un « je peux pas » attribuable, cf. §5/§6). `null` hors carrière
  /// ou si le profil n'a aucune donnée exploitable (joueuse neuve).
  CapabilityAxis? _overloadAxis;

  /// Facteur de surcharge appliqué au `comfort` de [_overloadAxis] (1.03→1.15,
  /// modulé par sa `successRate`). 1.0 pour tout autre axe.
  double _overloadFactor = 1.0;

  // ─── SURCHARGES MODE CUSTOM ──────────────────────────────────────────────
  // Bornes utilisateur (BPM, durée des holds) qui priment sur la capacité.
  // Hors mode Custom → tuple `null` → aucun bornage supplémentaire.

  /// Bornes BPM imposées par l'utilisateur en mode Custom (cf. `generate(
  /// bpmRange:)`). `null` = pas de bornage utilisateur (carrière, scénario,
  /// custom à valeurs par défaut). Le `_clampToCapability` final passe par
  /// `_clampToCustomLimits` qui force le BPM des modes rythmés (rhythm /
  /// lick / biffle / hand) dans cet intervalle.
  (int, int)? _bpmRange;

  /// Bornes de durée pour les steps tenus (hold + beg avec position) imposées
  /// par l'utilisateur en mode Custom. `null` = pas de bornage. Appliqué
  /// après `_clampToCapability` — donc compatible avec les caps profil de
  /// capacité, qui peuvent encore raboter par-dessus (mais en pratique le
  /// profil est null pour Custom).
  (int, int)? _holdDurationRange;

  // ─── CATALOGUE STATIQUE ──────────────────────────────────────────────────

  // `_overloadableAxes` (set des axes pilotants pour la surcharge),
  // `_minNullable`, `_rhythmBpmCeilAxisFor`, `_capabilityCapFor`,
  // `_overloadFactorFor`, `_pickOverloadAxis`, `_clampToCapability` et
  // `_clampToCustomLimits` ont migré dans
  // `career_session_generator_capability.dart` (`_CapabilityClamps`).
  // Le générateur construit un `_CapabilityClamps` au début de chaque
  // `generate()` (après que l'axe de surcharge a été choisi) et l'expose
  // via des adaptateurs courts plus bas.

  /// 2ᵉ enveloppe (immuable pour la séance) — recréée à chaque appel à
  /// [generate] après que l'axe de surcharge a été choisi.
  late _CapabilityClamps _capClamps;

  /// Picker du final + post-final — recréé à chaque appel à [generate]
  /// après que [_capClamps] est posé. Consomme `_capClamps` pour le clamp
  /// terminal des holds throat/full.
  late _FinalPicker _finalPicker;

  CareerSessionGenerator({int? seed})
      : _rng = seed != null ? Random(seed) : Random();

  /// Cap effectif d'humiliation projeté au temps `seconds` depuis le
  /// début de la session générée. Modèle 2 thermomètres :
  ///
  ///   `cap(t) = career + min(session + tickRate × t/60, sessionCap)`
  ///
  /// avec `tickRate = 1 × accel(obed)` (cf. `HumiliationEngine.onTickSecond`).
  /// La projection ne tient pas compte des bumps évènementiels (punition
  /// complétée, hold profond complété…) — c'est volontairement
  /// conservateur, le runtime peut accepter des actions un poil plus
  /// dures que ce que la rampe seule prédit.
  double _humilCapAt(int seconds) {
    final accel = (1.0 + _obedience / 100.0).clamp(1.0, 3.0);
    final tickRate = HumiliationEngine.bumpPerInterval * accel; // par minute
    final added = tickRate * seconds / 60.0;
    final session =
        (_humiliationSession + added).clamp(0.0, HumiliationEngine.sessionCap);
    return _humiliationCareer + session;
  }

  // ─── Profil de capacités — 2ᵉ enveloppe de difficulté ────────────────────

  /// Adaptateur d'instance pour `_CapabilityClamps.overloadFactorFor` —
  /// utilisé par `_effectiveRhythmChainCapSeconds` pour étendre le cap de
  /// chaîne rythme si `rhythmMotionStreak` est l'axe surchargé.
  double _overloadFactorFor(CapabilityAxis axis) =>
      _capClamps.overloadFactorFor(axis);

  /// Sélectionne l'axe de surcharge via `_CapabilityClamps.pickOverloadAxis`
  /// et persiste le résultat dans les fields d'instance — consommés en aval
  /// par les autres helpers (`_emitFinalStep`, etc.) et exposés sur le
  /// `CareerGenerationResult`.
  void _pickOverloadAxis() {
    final pick = _CapabilityClamps.pickOverloadAxis(
      profile: _capProfile,
      ceilings: _capCeilings,
      rng: _rng,
    );
    _overloadAxis = pick.axis;
    _overloadFactor = pick.factor;
    if (kDebugMode && pick.axis != null) {
      final sr = _capProfile?.stateOf(pick.axis!).successRate ?? 0.0;
      debugPrint('[career-gen] overload axis=${pick.axis!.storageKey} '
          'factor=${pick.factor.toStringAsFixed(3)} '
          'sr=${sr.toStringAsFixed(2)}');
    }
  }

  /// Adaptateur d'instance pour `_CapabilityClamps.clampToCapability` —
  /// applique la 2ᵉ enveloppe (profondeur / BPM / durée) ET les bornes
  /// utilisateur Custom en cascade.
  _StepDraft _clampToCapability(_StepDraft d) =>
      _capClamps.clampToCapability(d);

  /// Normalise une plage BPM utilisateur : trie `(min, max)` et borne aux
  /// limites globales (`CustomSessionConfig.minBpmLimit`/`maxBpmLimit`). Si
  /// la plage est nulle ou couvre tout le spectre par défaut, on la retourne
  /// telle quelle (un range hors-bornes ne sera jamais atteint par le
  /// générateur, c'est OK — pas la peine de masquer).
  (int, int)? _normalizeBpmRange((int, int)? raw) {
    if (raw == null) return null;
    var (lo, hi) = raw;
    if (lo > hi) {
      final tmp = lo;
      lo = hi;
      hi = tmp;
    }
    return (lo, hi);
  }

  (int, int)? _normalizeHoldRange((int, int)? raw) {
    if (raw == null) return null;
    var (lo, hi) = raw;
    if (lo > hi) {
      final tmp = lo;
      lo = hi;
      hi = tmp;
    }
    // Plancher à 1s : un hold à 0s n'a aucun sens (le step est consommé en un
    // tick, c'est juste un bip).
    if (lo < 1) lo = 1;
    if (hi < 1) hi = 1;
    return (lo, hi);
  }

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
    List<LevelMilestone> insertedBodies = const [],
    LevelMilestone? finalMilestone,
    Set<UnlockKey> unlockedKeys = const {},
    String? Function(String milestoneId, int stepTime)? milestoneTextResolver,
    Map<SessionMode, double> coachModeWeights = const {},
    String? sessionName,
    String? sessionNameQuickie,
    // ─── Surcharges pour le mode « Custom » (rétrocompat : tous null /
    //     false par défaut = comportement carrière inchangé) ───────────────
    /// Plancher de difficulté appliqué au tirage dès le début de séance
    /// (prime sur la valeur dérivée de quickie/intense).
    double? intensityFloorOverride,

    /// Plafond de profondeur (index `Position`) qui prime sur celui du
    /// `CareerLevel`. Permet au mode custom de borner rhythm/hold.
    int? maxDepthIndexOverride,

    /// Bornes BPM utilisateur (mode Custom). Tuple `(min, max)`. Appliquées
    /// à la fin du bornage à tous les modes rythmés (rhythm / lick / biffle /
    /// hand). `null` = pas de bornage.
    (int, int)? bpmRange,

    /// Bornes de durée pour les steps tenus (hold + beg avec position),
    /// imposées par l'utilisateur (mode Custom). `null` = pas de bornage.
    (int, int)? holdDurationRange,

    /// Si true, la `Session` générée est marquée `noStats` → le
    /// `SessionController` n'écrit rien dans `StatsService`.
    bool noStats = false,
    // ─── Profil de capacités (2ᵉ enveloppe de difficulté, carrière only) ──
    /// Profil persisté lu pour borner les steps : profondeur, BPM et durée
    /// ne dépassent pas le `comfort` (= `best` naïf en Phase 2) de chaque
    /// axe pilotant. `null` → aucun gating capacité (Custom, scénarios JSON).
    CapabilityProfile? capabilityProfile,

    /// Plafonds figés sur un FAIL de la session en cours (§6) — encore plus
    /// contraignants que `comfort` quand présents. Passés par les
    /// régénérations en cours de séance (Supplier / retry milestone) et le
    /// premier maillon d'un encore enchaîné via
    /// `SessionController.capabilitySessionCeilings`.
    Map<CapabilityAxis, double> capabilitySessionCeilings = const {},

    /// Profil anatomique de la joueuse. Default = tout disponible
    /// (rétrocompat carrière / tests). Quand `hasBalls = false`, aucun
    /// step sur `Position.balls` n'est généré (filtre `_isUnlocked`
    /// précoce, indépendant du gating milestone).
    AnatomyProfile anatomy = AnatomyProfile.defaults,
  }) {
    assert(
      finalMilestone == null ||
          finalMilestone.placement == MilestonePlacement.finalApotheose,
      'finalMilestone doit avoir placement=finalApotheose',
    );
    assert(
      insertedBodies.every((m) => m.placement == MilestonePlacement.body),
      'insertedBodies doivent avoir placement=body',
    );
    assert(
      insertedBodies.length <= 2,
      'insertedBodies : au plus 2 milestones body par séance pour l\'instant',
    );
    final cfg = CareerLevel.forLevel(level);
    _includeHand = includeHand;
    _maxDepthIndex = maxDepthIndexOverride ?? cfg.maxDepthIndex;
    _deepProbability = cfg.deepProbability;
    _spec = specialization ?? SpecializationAllocation.empty();
    _level = level;
    // Première mini-vague entre 4 et 5 minutes : laisse l'intro et le
    // début de chauffe se dérouler sans rupture, puis le générateur peut
    // poser un mini-finish pour casser la monotonie. Cadence resserrée
    // (vs 5-6 min initial) pour viser 3 vagues sur une session 19 min.
    _nextMiniWaveAt = 240 + _rng.nextInt(61);
    _lastSwallowOrderAt = -120;
    _lastMode = null;
    _lastText = '';
    _lastBpm = null;
    _lastFrom = null;
    _lastTo = null;
    _lastType = null;
    _stepsInLastType = 0;
    _stepsOutsideBouche = 0;
    _consecutiveRhythmSeconds = 0;
    _recentEmits.clear();
    _unlockedKeys = unlockedKeys;
    _coachModeWeights = coachModeWeights;
    _humiliationCareer = humiliationCareer;
    _humiliationSession = humiliationSession;
    _obedience = obedience;
    _capProfile = capabilityProfile;
    _capCeilings = capabilitySessionCeilings;
    _anatomy = anatomy;
    _bpmRange = _normalizeBpmRange(bpmRange);
    _holdDurationRange = _normalizeHoldRange(holdDurationRange);
    _pickOverloadAxis();
    // 2ᵉ enveloppe immuable construite après le choix de l'axe de surcharge —
    // recréée à chaque appel à `generate()` pour intégrer profile/ceilings/
    // overload/bornes-Custom courants. Consommée via les adaptateurs
    // `_clampToCapability` / `_capabilityCapFor` / `_overloadFactorFor`.
    _capClamps = _CapabilityClamps(
      profile: _capProfile,
      ceilings: _capCeilings,
      overloadAxis: _overloadAxis,
      overloadFactor: _overloadFactor,
      bpmRange: _bpmRange,
      holdRange: _holdDurationRange,
    );
    _finalPicker = _FinalPicker(
      level: _level,
      anatomy: _anatomy,
      unlockedKeys: _unlockedKeys,
      spec: _spec,
      coachModeWeights: _coachModeWeights,
      includeHand: _includeHand,
      rng: _rng,
      capClamps: _capClamps,
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
        intensityFloorOverride ?? (quickie ? 0.65 : (intense ? 0.55 : 0.0));
    // Nombre de boosts en phase finish : table par niveau + bonus encore
    // (chaîne encore = +2 boosts par cran, sans plafond explicite côté
    // générateur). Le caller borne le nombre d'encores enchaînés via le
    // gating `_canEncore`.
    final boostsCount = cfg.boostsCount + max(0, encoreChainIndex) * 2;
    // Pré-calculés ici (et non plus juste avant la pré-finition) pour
    // pouvoir construire [_GenContext] en une seule fois après les locaux
    // dérivés. Aucune dépendance sur l'opening step / la boucle main —
    // tout vient de `level`, `quickie`, `intense`, `finalMilestone`.
    final isLowLevel = level <= 2 && !quickie && !intense;
    final useFinalMilestone = finalMilestone != null;
    final finalBudget = useFinalMilestone
        ? finalMilestone.durationSeconds
        : _finisherBudgetSeconds;
    final genUntil = effectiveDuration -
        finalBudget -
        (isLowLevel && !useFinalMilestone ? _preFinisherBudgetSeconds : 0);

    _salivaSim = SalivaEngine()..reset();
    _salivaSimSecond = 0;
    final steps = <SessionStep>[];
    final profile =
        List<double>.filled(effectiveDuration + 60, _StaminaModel.cap);

    var time = 0;
    var stamina = _StaminaModel.cap;

    // DTO partagé par les helpers de phase. Construit une fois ici et passé
    // à chacun pour éviter de répéter les ~10 args (cfg/bank/effectiveDuration/
    // level/...) à chaque appel. Le curseur `(time, stamina)` reste hors-ctx
    // et threadé via record return values.
    final ctx = _GenContext(
      steps: steps,
      profile: profile,
      level: level,
      encoreChainIndex: encoreChainIndex,
      effectiveDuration: effectiveDuration,
      boostsCount: boostsCount,
      genUntil: genUntil,
      intensityFloor: intensityFloor,
      obedience: obedience,
      quickie: quickie,
      intense: intense,
      includeHand: includeHand,
      isLowLevel: isLowLevel,
      useFinalMilestone: useFinalMilestone,
      noStats: noStats,
      cfg: cfg,
      bank: bank,
      sessionName: sessionName,
      sessionNameQuickie: sessionNameQuickie,
      milestoneTextResolver: milestoneTextResolver,
      insertedBodies: insertedBodies,
      finalMilestone: finalMilestone,
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
    final pending = <_PendingMilestoneInsert>[];
    for (var i = 0; i < insertedBodies.length; i++) {
      final m = insertedBodies[i];
      final defaultMaxFraction = i == 0 ? 0.40 : 0.75;
      final defaultTargetFraction = i == 0 ? 0.30 : 0.65;
      final maxInsert = m.insertAtMaxSeconds ??
          (effectiveDuration * defaultMaxFraction).round();
      final minInsert = m.insertAtMinSeconds ?? 60;
      final target = (effectiveDuration * defaultTargetFraction).round();
      pending.add(_PendingMilestoneInsert(
        milestone: m,
        minInsert: minInsert,
        maxInsert: maxInsert,
        targetTime: target.clamp(minInsert, maxInsert),
      ));
    }
    final firstPending = pending.isNotEmpty ? pending.first : null;
    final bool milestoneReplacesIntro = pending.length == 1 &&
        firstPending != null &&
        firstPending.minInsert <= 0;
    int? milestoneStartTime;
    int? milestoneDurationSeconds;
    int? secondMilestoneStartTime;
    int? secondMilestoneDurationSeconds;

    void insertPending(_PendingMilestoneInsert p, int index) {
      final m = p.milestone;
      if (p.inserted) return;
      p.inserted = true;
      final startedAt = time;
      final result = _pushMilestoneSequence(
        ctx,
        milestone: m,
        time: time,
        stamina: stamina,
      );
      time = result.time;
      stamina = result.stamina;
      if (index == 0) {
        milestoneStartTime = startedAt;
        milestoneDurationSeconds = m.durationSeconds;
      } else {
        secondMilestoneStartTime = startedAt;
        secondMilestoneDurationSeconds = m.durationSeconds;
      }
      // Réutilisation post-acquittement : les unlocks de la milestone
      // deviennent disponibles pour les steps générés APRÈS la séquence
      // (corps restant, pré-finisher, boosts, final). On suppose succès au
      // runtime — sur fail la session est replanifiée par le contrôleur, ce
      // qui régénère un set d'unlocks cohérent.
      if (m.unlocks.isNotEmpty) {
        _unlockedKeys = {..._unlockedKeys, ...m.unlocks};
      }
      // Recale le min de la prochaine pending : `m.endTime + 60s` buffer
      // (sinon les 2 séquences pédagogiques s'enchaînent sans souffle).
      if (index + 1 < pending.length) {
        final nextMin = time + 60;
        final next = pending[index + 1];
        next.minInsert = max(next.minInsert, nextMin);
        // Si le buffer pousse au-delà du maxInsert de la 2ᵉ, on le repousse
        // pour laisser l'insertion se faire (relâchement plutôt que skip).
        if (next.minInsert > next.maxInsert) {
          next.maxInsert = next.minInsert + m.durationSeconds;
        }
        next.targetTime = next.targetTime.clamp(next.minInsert, next.maxInsert);
      }
    }

    // Step #0 obligatoirement non text-only à time=0 (sinon _lastConfigStep
    // reste null côté controller, casse la restauration post-fail). Une
    // phrase soft d'amorce y est attachée pour ne pas démarrer la séance
    // dans le silence. En mode bâclée, intro raccourcie pour aller au but.
    //
    // Si la milestone remplace l'intro, on l'insère ici à t=0 et c'est
    // son premier step qui tient le rôle de step #0 non text-only.
    if (milestoneReplacesIntro) {
      insertPending(pending.first, 0);
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
      if (_overloadAxis != null &&
          openingPhrase == null &&
          !quickie &&
          _rng.nextDouble() <
              CapabilityRegulator.progressPhraseChanceForLevel(level)) {
        final raw =
            bank.pickProgressPhrase(_overloadAxis!.storageKey, 'attempt', _rng);
        if (raw != null && raw.isNotEmpty) attemptPhrase = raw;
      }
      final firstText = attemptPhrase ??
          openingPhrase ??
          _pickPhraseForDraft(bank, first, 'soft');
      steps.add(_draftToStep(first, time: 0, text: firstText));
      _lastMode = first.mode;
      _lastText = firstText;
      _lastBpm = first.bpm ?? _lastBpm;
      _lastFrom = first.from;
      _lastTo = first.to;
      _trackPushedStep(first.mode, first.to,
          from: first.from, bpm: first.bpm, duration: first.duration);
      final staminaBefore = stamina;
      stamina = _StaminaModel.apply(stamina, first, 0.0, cfg);
      _StaminaModel.fillProfile(profile, 0, first.duration ?? 1, stamina,
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
      // Insertion milestone : on traite les pending dans l'ordre, dès que
      // `time` atteint la target (`>= targetTime`), OU dès qu'on dépasse
      // la borne max (insertion en urgence pour ne pas la louper). Le cas
      // time < target continue à empiler des steps de chauffe normalement.
      var nextPendingIndex = -1;
      for (var idx = 0; idx < pending.length; idx++) {
        if (!pending[idx].inserted) {
          nextPendingIndex = idx;
          break;
        }
      }
      if (nextPendingIndex >= 0) {
        final p = pending[nextPendingIndex];
        if (time >= p.targetTime || time >= p.maxInsert) {
          insertPending(p, nextPendingIndex);
          if (time >= genUntil) break;
          continue;
        }
      }
      // Mini-vague : 2-3 steps enchaînés à BPM montant qui cassent la
      // diagonale d'intensité unique du début au finish. Inséré toutes
      // les ~4-5 minutes sur les sessions longues (≥ 12 min) à partir du
      // niveau 5. Cf. `_shouldEmitMiniWave`.
      if (_shouldEmitMiniWave(time, effectiveDuration, stamina, genUntil)) {
        final progressForWave = time / effectiveDuration;
        final humilCapForWave = _humilCapAt(time);
        final waveDrafts = _buildMiniWave(humilCapForWave);
        for (final wd in waveDrafts) {
          final waveText = _pickPhraseForDraft(bank, wd, 'hard');
          steps.add(_draftToStep(wd, time: time, text: waveText));
          final staminaBefore = stamina;
          stamina = _StaminaModel.apply(stamina, wd, progressForWave, cfg);
          _advanceSalivaSim(wd);
          _StaminaModel.fillProfile(profile, time, wd.duration!, stamina,
              valueStart: staminaBefore);
          _lastMode = wd.mode;
          _lastText = waveText;
          _lastFrom = wd.from;
          _lastTo = wd.to;
          _lastBpm = wd.bpm ?? _lastBpm;
          _trackPushedStep(wd.mode, wd.to,
              from: wd.from, bpm: wd.bpm, duration: wd.duration);
          time += wd.duration!;
        }
        // Pause longue post-vague : breath dédié dimensionné pour viser
        // ~95 stamina, sortie volontaire du cap [4,12] du sas breath
        // standard — la vague est un mini-finish, on s'autorise une vraie
        // respiration scénarisée derrière pour repartir de plein. Borne
        // [12, 20] s : 12 = baseline minimale même si stamina déjà haute,
        // 20 = plafond pour ne pas casser le rythme dramaturgique de la
        // session. À niveau 9 milieu de séance (regen ≈ 1.6, ≈ 4.5/s),
        // 15-20 s rendent ~70-90 stamina.
        final postWaveProgress = time / effectiveDuration;
        final postWaveBreath = _buildPostWaveBreath(
            stamina, postWaveProgress, cfg, genUntil - time);
        if (postWaveBreath != null) {
          final breathText = _pickPhrase(bank, SessionMode.breath, 'soft');
          steps.add(_draftToStep(postWaveBreath, time: time, text: breathText));
          final staminaBefore = stamina;
          stamina = _StaminaModel.apply(
              stamina, postWaveBreath, postWaveProgress, cfg);
          _advanceSalivaSim(postWaveBreath);
          _StaminaModel.fillProfile(
              profile, time, postWaveBreath.duration!, stamina,
              valueStart: staminaBefore);
          _lastMode = SessionMode.breath;
          _lastText = breathText;
          _trackPushedStep(SessionMode.breath, null,
              duration: postWaveBreath.duration);
          time += postWaveBreath.duration!;
        }
        // Replanification : 4-5 minutes après la fin de la vague émise.
        // La séance enchaîne ensuite sur du tirage classique — la stamina
        // restaurée par la pause longue permet d'enchaîner sereinement
        // jusqu'à la prochaine vague.
        _nextMiniWaveAt = time + 240 + _rng.nextInt(61);
        continue;
      }
      // Ordre de déglutition forcé : quand la simulation salive sature,
      // on transforme la jauge silencieuse en mécanique gameplay — un
      // beg libre court « avale tout » avec phrase dédiée. Cf.
      // `_maybeBuildSwallowOrder` pour les conditions.
      final swallowDraft = _maybeBuildSwallowOrder(time, genUntil);
      if (swallowDraft != null) {
        final swallowText = bank.pickSwallowOrder(_rng) ??
            _pickPhrase(bank, SessionMode.beg, 'hard');
        steps.add(_draftToStep(swallowDraft, time: time, text: swallowText));
        final staminaBefore = stamina;
        stamina = _StaminaModel.apply(
            stamina, swallowDraft, time / effectiveDuration, cfg);
        // Conséquence simulée de l'ordre : la sim retombe à 0, comme si
        // la joueuse obéissait. En runtime le SessionController fera de
        // même via `SalivaEngine.forceSwallow()`.
        _salivaSim.forceSwallow();
        _StaminaModel.fillProfile(
            profile, time, swallowDraft.duration!, stamina,
            valueStart: staminaBefore);
        _lastMode = SessionMode.beg;
        _lastText = swallowText;
        _trackPushedStep(SessionMode.beg, null,
            duration: swallowDraft.duration);
        time += swallowDraft.duration!;
        _lastSwallowOrderAt = time;
        continue;
      }
      final progress = time / effectiveDuration;
      final windowMin = _StaminaModel.lerp(0.05, 0.50, progress);
      var windowMax =
          min(_StaminaModel.lerp(0.30, 1.00, progress), cfg.maxDifficultyCap);
      // Floor d'intensité (mode bâclée) : tronque le bas de la fenêtre.
      final flooredMin = max(windowMin, intensityFloor);
      final boundedMin = min(flooredMin, windowMax - 0.05).clamp(0.0, 1.0);
      windowMax = max(windowMax, boundedMin + 0.05);

      final diff = boundedMin + _rng.nextDouble() * (windowMax - boundedMin);

      final _StepDraft initialDraft;
      // Seuils de recovery modulés par l'obéissance : plus elle est haute,
      // plus on respecte l'endurance (recovery déclenché plus tôt). Sur la
      // dernière minute, on les coupe entièrement — la fin de séance ignore
      // l'endurance par contrat.
      final inLastMinute = (effectiveDuration - time) <= 60;
      // Bonus obédiance sur le seuil de recovery : capé +25 pour pas
      // qu'une obédiance lifetime extrême (200+) pousse le seuil à 80
      // (= recovery quasi-permanente). À obed=100, +25 ; à obed=0, +0.
      final obedienceBonus = (obedience / 100.0).clamp(0.0, 1.0) * 25.0;
      final recoveryThreshold =
          inLastMinute ? -1 : (quickie ? 15 : 30) + obedienceBonus;
      final recoveryRandomThreshold =
          inLastMinute ? -1 : (quickie ? 25 : 50) + obedienceBonus;
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
      var draft = _stripBegFromAfterSoft(initialDraft, steps);

      // Filtre humiliation requise : on garde uniquement ce que le cap
      // effectif (career + session projeté à `time`) permet. La rampe
      // session (+1/min en clean, ×3 max avec obed, capée à sessionCap)
      // est intégrée par `_humilCapAt`.
      final humilCap = _humilCapAt(time);
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
      draft = _BpmPacing.maybeApplyBpmRamp(draft, progress, _rng, _level);
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
      if (draft.mode != SessionMode.breath && genUntil - time > 8) {
        final delta = _StaminaModel.delta(draft, progress, cfg);
        final projected = stamina + delta;
        if (projected < 0) {
          final breathDraft = _buildBreathRecovery(-projected, progress, cfg);
          final breathText = _pickPhrase(bank, SessionMode.breath, 'soft');
          steps.add(_draftToStep(breathDraft, time: time, text: breathText));
          final staminaBefore = stamina;
          stamina = _StaminaModel.apply(stamina, breathDraft, progress, cfg);
          _advanceSalivaSim(breathDraft);
          _StaminaModel.fillProfile(
              profile, time, breathDraft.duration!, stamina,
              valueStart: staminaBefore);
          time += breathDraft.duration!;
          _lastMode = SessionMode.breath;
          _lastText = breathText;
          // breath = transit → ne touche pas _lastType (parenthèse
          // transparente). On l'appelle quand même pour cohérence si la
          // règle évoluait.
          _trackPushedStep(SessionMode.breath, null,
              duration: breathDraft.duration);
        }
      }

      // Diversification interne : si la step dure plus de 40s et qu'elle
      // est rythmique (rhythm/lick/hand), on la split en 2-3 sous-segments
      // avec une variation BPM/profondeur entre chaque, pour qu'une longue
      // phase ne sonne pas comme un loop monotone. Les sous-segments
      // s'autorisent un léger dépassement BPM (≤ +10) — on re-borne donc
      // chacun au profil de capacités.
      final emitDrafts = _BpmPacing.diversifyLongSegment(draft, _rng)
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
            partIdx == 0 ? _pickPhraseForDraft(bank, partDraft, tier) : '';
        final staminaBefore = stamina;
        stamina = _StaminaModel.apply(stamina, partDraft, progress, cfg);
        _advanceSalivaSim(partDraft);
        steps.add(_draftToStep(partDraft, time: time, text: partText));
        _lastMode = partDraft.mode;
        _lastText = partText;
        _lastFrom = partDraft.from;
        _lastTo = partDraft.to;
        _trackPushedStep(partDraft.mode, partDraft.to,
            from: partDraft.from,
            bpm: partDraft.bpm,
            duration: partDraft.duration);
        _StaminaModel.fillProfile(profile, time, partDraft.duration!, stamina,
            valueStart: staminaBefore);
        time += partDraft.duration!;
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
        genUntil: genUntil,
        bank: bank,
      );
      if (fakeBreath != null) {
        final staminaBeforeFake = stamina;
        stamina = _StaminaModel.apply(stamina, fakeBreath.draft, progress, cfg);
        _advanceSalivaSim(fakeBreath.draft);
        steps.add(
            _draftToStep(fakeBreath.draft, time: time, text: fakeBreath.text));
        _lastMode = SessionMode.breath;
        _lastText = fakeBreath.text;
        _trackPushedStep(SessionMode.breath, null,
            duration: fakeBreath.draft.duration);
        _StaminaModel.fillProfile(
            profile, time, fakeBreath.draft.duration!, stamina,
            valueStart: staminaBeforeFake);
        time += fakeBreath.draft.duration!;
      }

      // Chain action attachée au draft principal (beg + suite continue) :
      // émise immédiatement après les sous-segments, sans nouveau texte
      // d'intro (la consigne est déjà dans la phrase du beg).
      final chain = draft.chainNext;
      if (chain != null && chain.duration != null) {
        final staminaBefore = stamina;
        stamina = _StaminaModel.apply(stamina, chain, progress, cfg);
        _advanceSalivaSim(chain);
        steps.add(_draftToStep(chain, time: time, text: ''));
        _lastMode = chain.mode;
        _lastText = '';
        _lastFrom = chain.from;
        _lastTo = chain.to;
        _trackPushedStep(chain.mode, chain.to,
            from: chain.from, bpm: chain.bpm, duration: chain.duration);
        _StaminaModel.fillProfile(profile, time, chain.duration!, stamina,
            valueStart: staminaBefore);
        time += chain.duration!;
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
    }

    // Si la boucle main s'est terminée sans avoir inséré toutes les
    // milestones (durée trop courte pour atteindre la fenêtre, ou
    // `genUntil` faible après le first step), on force l'insertion ici
    // pour qu'elles soient jouées avant le finisher. Cas rare mais on ne
    // veut pas perdre une milestone silencieusement.
    for (var idx = 0; idx < pending.length; idx++) {
      if (!pending[idx].inserted) {
        insertPending(pending[idx], idx);
      }
    }

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
      final finalCategory = _categorizeFinal(lastDraft);

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
        milestoneStartTime: milestoneStartTime,
        milestoneDurationSeconds: milestoneDurationSeconds,
        secondMilestoneStartTime: secondMilestoneStartTime,
        secondMilestoneDurationSeconds: secondMilestoneDurationSeconds,
        finalCategory: finalCategory,
        silentFinishStartTime: silentFinishStartTime,
        finalStepStartTime: finalStepStartTime,
        finalMilestoneId: finalMilestone.id,
        finalMilestoneStartTime: finalMilestoneStartTime,
        finalMilestoneDurationSeconds: finalMilestone.durationSeconds,
      );
    }

    // Position cible du pré-finisher : profondeur « normale » du niveau,
    // capée par `_maxDepthIndex`. Sert de transition vers le final.
    final preFinisherTarget = _pickFinisherPosition(level);

    // Pré-finisher : pour les bas niveaux, courte accélération (rythme
    // un peu plus rapide que le plafond habituel du niveau) qui débouche
    // sur le final, dans une position d'amorce.
    // Custom : rhythm exclu → skip le pré-finisher (les boosts substitueront
    // le sprint via leur propre fallback de mode).
    if (isLowLevel && !_isModeForbidden(SessionMode.rhythm)) {
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
      milestoneStartTime: milestoneStartTime,
      milestoneDurationSeconds: milestoneDurationSeconds,
      secondMilestoneStartTime: secondMilestoneStartTime,
      secondMilestoneDurationSeconds: secondMilestoneDurationSeconds,
      finalCategory: finalCategory,
      silentFinishStartTime: silentFinishStartTime,
      finalStepStartTime: finalStepStartTime,
    );
  }

  /// Vrai si on doit émettre une **mini-vague** au pas courant de la
  /// boucle main. Conditions cumulatives :
  /// - durée totale ≥ 12 min (sinon pas le temps de respirer entre la
  ///   vague et le finish ; les sessions courtes gardent leur diagonale
  ///   d'intensité simple).
  /// - niveau ≥ 5 (pédagogie : on ne surprend pas une débutante avec
  ///   un mini-finish dramatique au milieu de la séance).
  /// - `time >= _nextMiniWaveAt` (replanifié après chaque vague).
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
    if (_level < 5) return false;
    if (time < _nextMiniWaveAt) return false;
    if (genUntil - time < 90) return false;
    if (stamina < 35) return false;
    // La mini-vague est intégralement rhythm (cf. `_buildMiniWave`) : si
    // rhythm est exclu en Custom, on ne sait pas la jouer — on la skip
    // proprement plutôt que d'émettre un mode banni.
    if (_isModeForbidden(SessionMode.rhythm)) return false;
    return true;
  }

  /// Construit la séquence de la mini-vague : 2 à 3 steps rythmés à BPM
  /// montant, chacun à profondeur progressive (head→mid puis head→mid
  /// puis head→throat si débloqué). Variations de `to` choisies pour ne
  /// pas trigger le détecteur de pattern plat (`_isFlatRhythmicPattern`)
  /// et pour matérialiser la montée à l'oreille (BPMs espacés de 20).
  ///
  /// Chaque step est filtré par `_enforceHumiliationRequired(humilCap)` :
  /// si la vague propose un step trop humiliant pour le cap courant, il
  /// dégrade vers du plus doux automatiquement (ex throat → mid). Si après
  /// dégradation un step duplique le précédent, il est skip plutôt que
  /// re-poussé — la vague peut donc se réduire à 2 steps en pratique.
  List<_StepDraft> _buildMiniWave(double humilCap) {
    final hasThroat = _unlockedKeys.contains(UnlockKey.throatHoldShort) ||
        _maxDepthIndex >= Position.throat.index;
    // Steps montants : BPMs espacés de 20 pour que la variance détectée
    // par `_isFlatRhythmicPattern` (< 10) ne déclenche pas. Choix
    // mode=rhythm sur les 3 steps pour cohérence dramaturgique (un seul
    // mode = montée homogène). `to` qui change évite aussi le pattern
    // plat — la diversification interne ne peut pas le casser.
    final raw = <_StepDraft>[
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 100,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 120,
        from: Position.head,
        to: Position.mid,
        duration: 10,
      ),
      _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 135,
        from: Position.head,
        to: hasThroat ? Position.throat : Position.mid,
        duration: 8,
      ),
    ];
    final out = <_StepDraft>[];
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
  _StepDraft? _buildPostWaveBreath(
    double stamina,
    double progress,
    CareerLevel cfg,
    int remainingSeconds,
  ) {
    if (remainingSeconds < 12) return null;
    final regen = _StaminaModel.lerp(
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
    return _StepDraft(
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
  /// - `_salivaSim.value >= 80` : marge de 10 sous le seuil overflow (90)
  ///   pour anticiper et ne pas attendre que ça déborde réellement
  ///   (l'auto-swallow runtime peut intercepter à 75 et masquer).
  /// - `time - _lastSwallowOrderAt >= 90` : cooldown 90 s pour ne pas
  ///   spammer les ordres en série (cas spé sloppy à fond sur lick).
  /// - `genUntil - time >= 60` : marge avant le finish — la dramaturgie
  ///   scriptée ne doit pas être interrompue par un ordre opportuniste.
  /// - `begLibre` débloqué (sinon on imposerait une mécanique avant la
  ///   pédagogie qui la déverrouille).
  ///
  /// Retourne null si une condition manque.
  _StepDraft? _maybeBuildSwallowOrder(int time, int genUntil) {
    if (_salivaSim.value < 80.0) return null;
    if (time - _lastSwallowOrderAt < 90) return null;
    if (genUntil - time < 60) return null;
    if (!_unlockedKeys.contains(UnlockKey.begLibre)) return null;
    final dur = 5 + _rng.nextInt(3); // [5, 7]
    return _StepDraft(
      mode: SessionMode.beg,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Adaptateur d'instance pour `_FinalPicker.buildPostFinalDraft`. Injecte
  /// le `holdCeilingIdx` calculé depuis `_unlockedKeys` + `_maxDepthIndex`
  /// — qui n'est pas dans `_FinalPicker` car partagé avec `_pickHoldPosition`
  /// et d'autres call sites.
  _StepDraft _buildPostFinalDraft(SessionMode finalMode, double humilCap) =>
      _finalPicker.buildPostFinalDraft(
        finalMode: finalMode,
        humilCap: humilCap,
        holdCeilingIdx: _milestoneHoldCeilingIdx(),
      );

  /// Convertit un [SessionStep] (issu du JSON ou d'une milestone) en
  /// [_StepDraft] interne pour pouvoir le passer à `_applyStaminaChange`.
  /// Convention uniforme : hold/beg portent leur position dans `to` ;
  /// aucun swap.
  _StepDraft _stepToDraft(SessionStep step, SessionMode defaultMode) {
    final mode = step.mode ?? defaultMode;
    return _StepDraft(
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
  /// À la fin, met à jour `_lastMode` / `_lastText` à partir du dernier step.
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
      s = _StaminaModel.apply(s, mDraft, t / ctx.effectiveDuration, ctx.cfg);
      _advanceSalivaSim(mDraft);
      _StaminaModel.fillProfile(
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
    _lastMode = lastStep.mode ?? _lastMode;
    _lastText = lastStep.text;
    t += milestone.durationSeconds;
    return (time: t, stamina: s);
  }

  /// Émet le step de pré-finisher (courte accélération rythme `head→target`
  /// qui prépare la phase boosts). Utilisé uniquement pour les bas niveaux —
  /// le caller garde la guard `isLowLevel && !_isModeForbidden(rhythm)` autour
  /// de l'appel pour ne pas changer la séquence RNG (la position est pickée
  /// avant l'appel).
  ///
  /// Mute `ctx.steps` et `ctx.profile` en place. Met à jour
  /// `_lastMode/_lastText` et tracke la continuité.
  /// Retourne `(newTime, newStamina)`.
  ({int time, double stamina}) _emitPreFinisher(
    _GenContext ctx, {
    required int time,
    required double stamina,
    required Position preFinisherTarget,
  }) {
    final preDur = 22 + _rng.nextInt(9); // [22, 30]
    final preBpm = 62 + _rng.nextInt(9); // [62, 70]
    final preDraft = _clampToCapability(_StepDraft(
      mode: SessionMode.rhythm,
      bpm: preBpm,
      from: Position.head,
      to: preFinisherTarget,
      duration: preDur,
    ));
    final preText = _pickPhraseForDraft(ctx.bank, preDraft, 'medium');
    ctx.steps.add(_draftToStep(preDraft, time: time, text: preText));
    _lastMode = SessionMode.rhythm;
    _lastText = preText;
    _trackPushedStep(SessionMode.rhythm, preDraft.to,
        from: preDraft.from, bpm: preDraft.bpm, duration: preDraft.duration);
    final staminaBeforePre = stamina;
    final newStamina = _StaminaModel.apply(
        stamina, preDraft, time / ctx.effectiveDuration, ctx.cfg);
    _StaminaModel.fillProfile(
        ctx.profile, time, preDraft.duration ?? preDur, newStamina,
        valueStart: staminaBeforePre);
    _advanceSalivaSim(preDraft);
    return (time: time + (preDraft.duration ?? preDur), stamina: newStamina);
  }

  /// Choix du mode pour la phase de boosts (`hand_burst` non humiliant vs
  /// `rhythm_burst` humiliant). Gère :
  ///  - le biais dramaturgique 70/30 vs 25/75 selon humil + niveau ;
  ///  - les exclusions Custom (`_isModeForbidden`) avec repli `lick` quand
  ///    hand ET rhythm sont bannis ;
  ///  - le ratio de poids brut quand les doses hand/rhythm sont asymétriques
  ///    (cf. issue #68).
  ///
  /// Consomme un tirage RNG quand les deux modes sont autorisés.
  ({bool useHandBurst, SessionMode burstMode}) _pickBurstMode(_GenContext ctx) {
    final handForbidden = _isModeForbidden(SessionMode.hand);
    final rhythmForbidden = _isModeForbidden(SessionMode.rhythm);
    final preferHandBase =
        _humiliationCareer < 5 && ctx.level <= 3 ? 0.70 : 0.25;
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
    final handWeight = _coachModeWeights[SessionMode.hand] ?? 1.0;
    final rhythmWeight = _coachModeWeights[SessionMode.rhythm] ?? 1.0;
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
  /// jour `_lastMode/_lastText/_lastBpm` à chaque boost émis et tracke la
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
    final boostHumilCap = _humilCapAt(time) + 8.0;
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
        ((ctx.level - 1) * 4 + max(0, ctx.encoreChainIndex) * 8).clamp(0, 70);
    final bpmCap = useHandBurst
        ? (110 + levelBpmBoost).clamp(110, 300)
        : (130 + levelBpmBoost).clamp(130, 300);
    final bpmFloor = useHandBurst ? 80 : 100;
    // Cap de profondeur des boosts gaté par les milestones effectivement
    // acquittées (cf. `_milestoneRhythmCeilingIdx`) : throat ouvert si
    // `throatPulse` débloqué (intro_throat_pulse), full si `fullPulse`
    // (intro_full_pulse). Indépendant du niveau seul — sauter des milestones
    // ne donne pas accès aux profondeurs. Borné par `_maxDepthIndex` en
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
      final boostDraftRaw = _StepDraft(
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
      _lastMode = boostDraft.mode;
      _lastText = boostText;
      _lastBpm = boostDraft.bpm ?? _lastBpm;
      _trackPushedStep(boostDraft.mode, boostDraft.to,
          from: boostDraft.from,
          bpm: boostDraft.bpm,
          duration: boostDraft.duration);
      final staminaBeforeBoost = s;
      s = _StaminaModel.apply(s, boostDraft, 1.0, ctx.cfg);
      _advanceSalivaSim(boostDraft);
      _StaminaModel.fillProfile(ctx.profile, t, boostDur, s,
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

  /// Émet le step final (apothéose contemplative). Choix via [_pickFinal] selon
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
    final finalHumilCap = _humilCapAt(time);
    // En chaîne encore, on allonge le final pour que la dramaturgie de
    // « tu en veux encore » se traduise aussi côté apothéose. Bornée par
    // le clamp de `_pickFinal` pour rester raisonnable.
    final finishMul = 1.0 + max(0, ctx.encoreChainIndex) * 0.10;
    final finisherDraft = _pickFinal(
      humilCap: finalHumilCap,
      includeHand: ctx.includeHand,
      maxDepth: _maxDepthIndex,
      finishMul: finishMul,
    );
    final finalCategory = _categorizeFinal(finisherDraft);
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
    final finisherStep =
        _draftToStep(finisherDraft, time: time, text: finalStepText);
    _lastMode = finalMode;
    _lastText = finalStepText;
    _trackPushedStep(finalMode, finisherDraft.to,
        from: finisherDraft.from,
        bpm: finisherDraft.bpm,
        duration: finisherDraft.duration);
    final finisherDuration = finisherDraft.duration!;
    ctx.steps.add(finisherStep);
    final staminaBeforeFinisher = stamina;
    final newStamina =
        _StaminaModel.apply(stamina, finisherDraft, 1.0, ctx.cfg);
    _StaminaModel.fillProfile(ctx.profile, time, finisherDuration, newStamina,
        valueStart: staminaBeforeFinisher);
    _advanceSalivaSim(finisherDraft);
    return (
      time: time + finisherDuration,
      stamina: newStamina,
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
    final postFinalDraft =
        _clampToCapability(_buildPostFinalDraft(finalMode, _humilCapAt(time)));
    // Phrase : beg porte une CONSIGNE de supplique (jamais un compliment
    // doux) ; lick post-final porte une consigne d'aftercare humiliant.
    // Cascade pour ne jamais tomber sur un text vide.
    final String postFinalText;
    if (postFinalDraft.mode == SessionMode.beg) {
      postFinalText = ctx.bank.pickPostFinalBeg(_rng) ??
          ctx.bank.pickPostFinal(_rng) ??
          ctx.bank.pickCongrats(_rng);
    } else if (postFinalDraft.mode == SessionMode.lick) {
      postFinalText = ctx.bank.pickPostFinalLick(_rng) ??
          ctx.bank.pickPostFinal(_rng) ??
          ctx.bank.pickCongrats(_rng);
    } else {
      postFinalText =
          ctx.bank.pickPostFinal(_rng) ?? ctx.bank.pickCongrats(_rng);
    }
    final postFinalDuration = postFinalDraft.duration!;
    ctx.steps
        .add(_draftToStep(postFinalDraft, time: time, text: postFinalText));
    final staminaBeforePostFinal = stamina;
    final newStamina =
        _StaminaModel.apply(stamina, postFinalDraft, 1.0, ctx.cfg);
    _StaminaModel.fillProfile(ctx.profile, time, postFinalDuration, newStamina,
        valueStart: staminaBeforePostFinal);
    _advanceSalivaSim(postFinalDraft);
    _lastMode = postFinalDraft.mode;
    _lastText = postFinalText;
    _trackPushedStep(postFinalDraft.mode, postFinalDraft.to,
        from: postFinalDraft.from,
        bpm: postFinalDraft.bpm,
        duration: postFinalDraft.duration);
    return (time: time + postFinalDuration, stamina: newStamina);
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
        id: 'career:lvl${ctx.level}:${ctx.effectiveDuration}s${ctx.quickie ? ":q" : ""}',
        name: ctx.quickie
            ? (ctx.sessionNameQuickie ??
                'Carrière niveau ${ctx.level} — bâclée')
            : (ctx.sessionName ?? 'Carrière niveau ${ctx.level}'),
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
      overloadAxis: _overloadAxis,
    );
  }

  /// Step d'intro. Modes hardcodés pour quickie / intense (besoins
  /// dramaturgiques spécifiques). En séance normale, panel de variantes
  /// douces : lick et rhythm en amplitude limitée, plus une option hand
  /// pour la variété. Filtré par `_maxDepthIndex` (head→mid n'apparaît pas
  /// si le niveau plafonne à head) et `_includeHand`.
  _StepDraft _firstStep({
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
      // lick (langue) ou hold (statique) en dernier recours.
      final intenseMode = !_isModeForbidden(SessionMode.rhythm)
          ? SessionMode.rhythm
          : !_isModeForbidden(SessionMode.hand)
              ? SessionMode.hand
              : !_isModeForbidden(SessionMode.lick)
                  ? SessionMode.lick
                  : SessionMode.hold;
      if (intenseMode == SessionMode.hold) {
        return _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: to,
          duration: 10,
        );
      }
      return _StepDraft(
        mode: intenseMode,
        bpm: 90,
        from: Position.head,
        to: to,
        duration: 10,
      );
    }
    if (quickie) {
      // Quickie : rhythm exclu → idem fallback hand/lick/hold.
      final quickieMode = !_isModeForbidden(SessionMode.rhythm)
          ? SessionMode.rhythm
          : !_isModeForbidden(SessionMode.hand)
              ? SessionMode.hand
              : !_isModeForbidden(SessionMode.lick)
                  ? SessionMode.lick
                  : SessionMode.hold;
      if (quickieMode == SessionMode.hold) {
        return const _StepDraft(
          mode: SessionMode.hold,
          bpm: null,
          from: null,
          to: Position.mid,
          duration: 8,
        );
      }
      return _StepDraft(
        mode: quickieMode,
        bpm: 75,
        from: Position.head,
        to: Position.mid,
        duration: 8,
      );
    }
    // Panel de variantes filtré par milestones : `rhythm_mid_basic`
    // (intro_deeper_basics, niveau 2) gate les variantes head→mid /
    // tip→mid. Sans cette milestone, on retombe sur lick / rhythm tip→head
    // / hand tip→head (toutes débloquées via intro_basics niveau 1).
    final variants = <_StepDraft>[
      const _StepDraft(
        mode: SessionMode.lick,
        bpm: 60,
        from: Position.tip,
        to: Position.head,
        duration: 20,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 65,
        from: Position.tip,
        to: Position.head,
        duration: 16,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 70,
        from: Position.head,
        to: Position.mid,
        duration: 14,
      ),
      const _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 65,
        from: Position.tip,
        to: Position.mid,
        duration: 16,
      ),
      if (_includeHand)
        const _StepDraft(
          mode: SessionMode.hand,
          bpm: 55,
          from: Position.tip,
          to: Position.head,
          duration: 18,
        ),
    ];
    final allowed = variants
        .where(_isUnlocked)
        .where((v) => !_isModeForbidden(v.mode))
        .toList();
    if (allowed.isEmpty) {
      // Pas de variante alignée à la fois sur les unlocks et le dosage —
      // on retombe sur la 1ʳᵉ variante non interdite, sinon la 1ʳᵉ tout court.
      final notForbidden =
          variants.where((v) => !_isModeForbidden(v.mode)).toList();
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
  ({_StepDraft draft, String text})? _maybeBuildFakeBreath({
    required _StepDraft lastEmitted,
    required double currentStamina,
    required int time,
    required int genUntil,
    required PhraseBank bank,
  }) {
    // Convention `_unlockedKeys.isEmpty` = mode hérité (Custom / scénarios /
    // debug) : pas de gating, le mécanisme reste actif. En carrière le
    // déblocage passe par la milestone `intro_fake_breath` qui accorde la
    // clé `fakeBreath` ; tant qu'elle n'est pas acquittée, rien ne sort.
    if (_unlockedKeys.isNotEmpty &&
        !_unlockedKeys.contains(UnlockKey.fakeBreath)) {
      return null;
    }
    if (genUntil - time < 30) return null; // pas trop près du finish
    if (currentStamina < 30) return null; // déjà en dette, vrai breath plus bas
    final isIntenseRhythm = (lastEmitted.mode == SessionMode.rhythm ||
            lastEmitted.mode == SessionMode.hand) &&
        (lastEmitted.to == Position.throat ||
            lastEmitted.to == Position.full) &&
        (lastEmitted.bpm ?? 0) >= 90;
    final isIntenseHold = lastEmitted.mode == SessionMode.hold &&
        (lastEmitted.to == Position.throat || lastEmitted.to == Position.full);
    if (!isIntenseRhythm && !isIntenseHold) return null;
    if (_rng.nextDouble() >= 0.25) return null;
    // 2-3 s : assez pour entendre un soupir, trop peu pour vraiment
    // récupérer (à 2.8 stamina/s = 5-8 stamina rendus, peanuts face au
    // coût d'un step intense ~25-40).
    final dur = 2 + _rng.nextInt(2);
    final draft = _StepDraft(
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

  _StepDraft _buildBreathRecovery(
    double deficit,
    double progress,
    CareerLevel cfg,
  ) {
    final regen = _StaminaModel.lerp(
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
    return _StepDraft(
      mode: SessionMode.breath,
      bpm: null,
      from: null,
      to: null,
      duration: dur,
    );
  }

  /// Tirage d'un step "respi active" : mode parmi lick/biffle/beg/freestyle,
  /// BPM ≤ 60 pour déclencher la regen d'endurance. Le mode `breath` n'est
  /// plus tiré ici — il est désormais inséré strictement sur déficit
  /// d'endurance projeté (cf. `_buildBreathRecovery`), pas comme une option
  /// d'humeur générale.
  _StepDraft _buildRecoveryStep() {
    // Convention `_unlockedKeys.isEmpty` = mode hérité : pas de gating, tous
    // les modes sont candidats (cf. `_isUnlocked`). Pour les modes carrière,
    // on ne propose que ceux dont la milestone d'introduction est acquittée.
    final heritage = _unlockedKeys.isEmpty;
    final canBeg = heritage || _unlockedKeys.contains(UnlockKey.begLibre);
    final canBiffleRecovery =
        heritage || _unlockedKeys.contains(UnlockKey.biffleBasic);
    // Freestyle gaté uniquement par sa milestone (intro_freestyle, niveau
    // 7) — on ne double-check plus le niveau, l'acquittement de la
    // milestone est l'unique source de vérité.
    final canFreestyle =
        heritage || _unlockedKeys.contains(UnlockKey.freestyle);
    final candidates = [
      SessionMode.lick,
      if (_includeHand && canBiffleRecovery) SessionMode.biffle,
      if (canBeg) SessionMode.beg,
      if (canFreestyle) SessionMode.freestyle,
      // Rhythm très doux comme « récup en bouche » : BPM bas, tip→head,
      // coût stamina modéré. Toujours candidat — la friction de continuité
      // décide s'il gagne (en bouche : ×3.0, hors bouche : ×3.0 voire +
      // selon la durée d'excursion). Sans ça, une recovery déclenchée
      // depuis bouche reste systématiquement bloquée hors bouche, et le
      // pattern « rhythm → recovery → rhythm » fait des séries de 1 step.
      SessionMode.rhythm,
      // Hold court tip/head : bisou prolongé / immobilisation douce. Sert
      // à insérer l'alternance rhythm/hold même pendant les phases où la
      // stamina est basse (sinon on n'a que des hold sur les rares moments
      // hors recovery). Coût stamina faible à cette profondeur.
      SessionMode.hold,
    ];
    // Exclusions Custom (dose `none`) : la recovery ne doit pas ramener un
    // mode que la joueuse a explicitement banni. Si tout est exclu, on
    // retombe sur lick (le garde-fou de l'éditeur Custom assure que lick
    // OU rhythm OU hold est resté ≥ rare — si lick lui-même est exclu, le
    // mode bouche restant reprend la main au step suivant via mapDifficulty).
    candidates.removeWhere(_isModeForbidden);
    if (candidates.isEmpty) candidates.add(SessionMode.lick);
    final pool = _filterRepeated(candidates);
    // Tirage pondéré pour que la friction de continuité par type s'applique
    // aussi à la recovery (sans ça, une recovery uniforme repousse souvent
    // langue/libre alors que la séance vient juste de quitter bouche).
    final mode = _pickWeightedMode(pool);
    final bpm = 45 + _rng.nextInt(14); // [45, 58]
    final dur = 10 + _rng.nextInt(9); // [10, 18]
    _StepDraft draft;
    if (mode == SessionMode.beg) {
      // Récup vocale par défaut : sans position (= beg libre). Si begLibre
      // n'est pas encore débloqué, on dégrade via _enforceHumiliationRequired
      // qui retombera sur beg head ou lick selon la situation.
      final begDur = 6 + _rng.nextInt(6);
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: null,
        duration: begDur,
      );
    } else if (mode == SessionMode.freestyle) {
      // Phase libre : neutre. Encadre le repos sans bip de loop.
      final freeDur = 8 + _rng.nextInt(8);
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: null,
        duration: freeDur,
      );
    } else if (mode == SessionMode.rhythm) {
      // Rhythm en recovery = bouche douce. La baseline (tip→head) reste
      // ouverte tant que la joueuse n'a pas appris la gorge — gate sur
      // `throatHoldShort` plutôt que `holdMidShort` : les premiers paliers
      // ont besoin de variété (tip→head, tip→mid, head→mid se mélangent),
      // ce serait trop pauvre de tout aligner sur head→mid dès le niveau 4.
      // À partir du moment où la gorge est débloquée, le rhythm de
      // recovery passe à head→mid — la baseline doit refléter le niveau.
      // BPM bas — le coût stamina reste modéré pour ne pas creuser la
      // dette d'endurance qu'on cherche justement à combler ailleurs.
      final hasThroat = _unlockedKeys.contains(UnlockKey.throatHoldShort);
      draft = _StepDraft(
        mode: mode,
        bpm: bpm,
        from: hasThroat ? Position.head : Position.tip,
        to: hasThroat ? Position.mid : Position.head,
        duration: dur,
      );
    } else if (mode == SessionMode.hold) {
      // Hold court en recovery — la position dépend du niveau de la
      // joueuse : tant qu'elle n'a pas dépassé hold mid, c'est tip ou head
      // (bisou / gland tenu, vraie respiration). Dès que throat est
      // débloqué, le hold de récup n'a plus de sens à profondeur basse —
      // on garde le hold mais à la profondeur max (= throat ou full),
      // assumée comme l'unique geste de tenue. La durée courte (4-7s)
      // garde une marge de respi avant de redescendre.
      final ceilingIdx = _milestoneHoldCeilingIdx();
      final holdDur = 4 + _rng.nextInt(4);
      final Position to;
      if (ceilingIdx >= Position.throat.index) {
        // Throat ou full débloqué : on tient profond même en récup.
        // Le user a explicitement validé la règle — pas de hold doux quand
        // tu sais tenir gorge.
        to = ceilingIdx >= Position.full.index && _rng.nextDouble() < 0.30
            ? Position.full
            : Position.throat;
      } else if (ceilingIdx >= Position.mid.index) {
        to = Position.mid;
      } else {
        to = _rng.nextBool() ? Position.tip : Position.head;
      }
      draft = _StepDraft(
        mode: mode,
        bpm: null,
        from: null,
        to: to,
        duration: holdDur,
      );
    } else {
      final (from, to) = _sampleFromTo(0.3);
      draft = _StepDraft(
        mode: mode,
        bpm: bpm,
        from: from,
        to: to,
        duration: dur,
      );
    }
    // Gating unlock : si le mode/draft tiré n'est pas encore débloqué (ex :
    // biffle avant niveau 5, beg libre avant niveau 3, freestyle avant
    // niveau 4), on dégrade. Évite que la phase de récup laisse passer une
    // action contractuellement réservée à plus tard.
    if (!_isUnlocked(draft)) {
      return _StepDraft(
        mode: SessionMode.lick,
        bpm: bpm,
        from: Position.tip,
        to: Position.head,
        duration: dur,
      );
    }
    return draft;
  }

  /// Convertit la difficulté `diff ∈ [0, 1]` en step concret. Le budget est
  /// réparti aléatoirement entre les axes BPM, amplitude et durée — donc un
  /// step "hard" peut être lent profond endurant, ou rapide plus court, etc.
  _StepDraft _mapDifficultyToStep(double diff) {
    final candidates = <SessionMode>[];
    if (diff < 0.30) {
      candidates.add(SessionMode.lick);
    }
    // Bouche disponible quoi qu'il arrive si on y est déjà ou si on en
    // est sorti depuis longtemps : à diff < 0.20 le panel par défaut ne
    // contient que lick/hand, donc sans cette injection on est mécaniquement
    // forcé de quitter bouche au step suivant — la friction de continuité
    // n'a plus rien à pousser. La cohérence par type (séries de plusieurs
    // steps sur bouche) ne marche que si rhythm reste un candidat valide
    // pendant la phase de chauffe.
    if ((diff >= 0.20 ||
            _stepsOutsideBouche >= 2 ||
            _lastType == _StepType.bouche) &&
        _canChainRhythm()) {
      candidates.add(SessionMode.rhythm);
    }
    // Hold candidat dès diff >= 0.20 normalement, mais aussi dès diff >= 0.10
    // si on est déjà en bouche : permet l'alternance rhythm/hold à
    // l'intérieur d'une série bouche (sinon les phases de chauffe restaient
    // 100 % rhythm uniforme — l'utilisateur attend rythme/rythme/hold/…).
    if (diff >= 0.20 || (_lastType == _StepType.bouche && diff >= 0.10)) {
      candidates.add(SessionMode.hold);
    }
    // biffle : candidat seulement si `biffleBasic` est débloqué (pré-filtre
    // sur le mode pour éviter une cascade systématique de dégradation
    // biffle → lick quand la milestone n'est pas acquise). Le pré-filtre
    // respecte la convention héritée (`_unlockedKeys.isEmpty` = pas de
    // gating) pour ne pas casser les sessions hors carrière.
    final canBiffle =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.biffleBasic);
    if (diff >= 0.40 && _includeHand && canBiffle) {
      candidates.add(SessionMode.biffle);
    }
    if (_includeHand && diff >= 0.10) {
      // Hand est dispo dès le début : repose la bouche, aide à varier le
      // tempo. Seuil bas pour qu'il apparaisse aussi en bas niveau (sinon
      // les fenêtres de difficulté basses des premiers paliers le bloquent
      // trop souvent — feedback : « aucune au premier niveau »).
      candidates.add(SessionMode.hand);
    }
    // beg : candidat seulement si begLibre est déjà acquis (prérequis
    // transverse à toutes les formes de beg, cf. `_isUnlocked`). Convention
    // héritée appliquée aussi (set vide = pas de gating).
    final canBeg =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.begLibre);
    if (canBeg) {
      // Sa difficulté effective est portée par `from` (head = doux,
      // full = comme un hold profond), pas par diff.
      candidates.add(SessionMode.beg);
    }
    // suckle : geste latéral (head ou balls). En carrière, gaté par la
    // milestone `intro_suckle_head` qui accorde `UnlockKey.suckleHead`. En
    // mode hérité (Custom, scénarios), on l'ajoute inconditionnellement —
    // sa dose Custom (ModeDose.none ⇒ forbidden) le retire ensuite via
    // `removeWhere(_isModeForbidden)`. Sans cet ajout, la dose Custom
    // était de fait ignorée : suckle n'était jamais tiré.
    final canSuckle =
        _unlockedKeys.isEmpty || _unlockedKeys.contains(UnlockKey.suckleHead);
    if (canSuckle) {
      candidates.add(SessionMode.suckle);
    }
    // breath n'est jamais un step "d'effort" : il n'est tiré que par
    // _buildRecoveryStep quand l'endurance est basse, jamais ici.
    // Exclusions Custom (dose `none`) : retirer les modes interdits avant
    // tirage. Si tout est exclu, on retombe sur un mode bouche encore
    // actif (l'éditeur Custom garantit qu'au moins un mouth mode reste
    // ≥ rare via son garde-fou). On essaie lick → hold → rhythm pour
    // privilégier le mode le plus doux disponible, et rhythm en dernier
    // ressort pour ne jamais crasher si une config était corrompue.
    candidates.removeWhere(_isModeForbidden);
    if (candidates.isEmpty) {
      for (final m in const [
        SessionMode.lick,
        SessionMode.hold,
        SessionMode.rhythm,
      ]) {
        if (!_isModeForbidden(m)) {
          candidates.add(m);
          break;
        }
      }
      if (candidates.isEmpty) candidates.add(SessionMode.rhythm);
    }
    final mode = _pickWeightedMode(_filterRepeated(candidates));

    final (aBpm, aAmp, aDur) = _sampleSimplex3();
    var bpmScore = (diff * 3 * aBpm).clamp(0.0, 1.0);
    var ampScore = (diff * 3 * aAmp).clamp(0.0, 1.0);
    var durScore = (diff * 3 * aDur).clamp(0.0, 1.0);
    // Bonus de spé sur les axes (capés 1.0). Coefs renforcés (+0.05 →
    // +0.08/pt) pour que la branche choisie pousse plus visiblement les
    // paramètres : 5 pts en profondeur = +0.40 ampScore, donc des
    // amplitudes mid→full / throat→full bien plus fréquentes.
    bpmScore = (bpmScore + 0.08 * _pts(SpecializationBranch.rythmeBiffle))
        .clamp(0.0, 1.0);
    ampScore = (ampScore + 0.08 * _pts(SpecializationBranch.profondeur))
        .clamp(0.0, 1.0);
    durScore = (durScore + 0.08 * _pts(SpecializationBranch.endurance))
        .clamp(0.0, 1.0);

    switch (mode) {
      case SessionMode.rhythm:
        final bpm = _StaminaModel.lerp(60.0, 140.0, bpmScore).round();
        final (from, to) = _sampleFromTo(ampScore);
        var dur = _scaleDuration(
          _StaminaModel.lerp(20.0, 60.0, durScore),
          enduranceFactor: 0.05,
        );
        // Cap par nombre d'aller-retours sur les profondeurs throat/full :
        // un step rythme à `to=throat` ne devrait pas enchaîner 30+ pulses
        // consécutifs (à 90 bpm, 60 s = 45 throats — la joueuse étouffe).
        // Cf. règle « passé to:throat, on se limite à un certain nombre
        // d'aller-retours par step ». Le cap est calculé en secondes :
        // durMax = maxPulses × 120 / bpm (×2 car pulse = 2 beats).
        dur = _capRhythmDurationByPulses(dur, bpm, to);
        // Cap rythme soutenu : tant que la milestone
        // `intro_rhythm_sustained` n'a pas été acquittée, la chaîne rythme
        // consécutive est plafonnée à 60 s. Le candidat n'arrive ici que
        // si `_canChainRhythm()` était vrai au tirage, donc il reste au
        // moins `_minRhythmStepSeconds` de marge.
        dur = _capRhythmConsecutive(dur);
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.biffle:
        // Biffle = coups de queue sur le visage : pas de notion de
        // position. from/to restent null.
        final bpm = _StaminaModel.lerp(80.0, 140.0, bpmScore).round();
        final dur = _scaleDuration(
          _StaminaModel.lerp(15.0, 40.0, durScore),
          enduranceFactor: 0.05,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: null, to: null, duration: dur);
      case SessionMode.hold:
        // Convention uniforme hold/beg : la position tenue est dans `to`
        // (matche BeepEngine et le format SessionStep des JSON).
        final to = _pickHoldPosition(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(8.0, 30.0, max(durScore, bpmScore)),
          enduranceFactor: 0.08,
        );
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: dur);
      case SessionMode.lick:
        // Sloppy : monte le BPM minimum (≥ 65 = lick humide / saliveux).
        final sloppyPts = _pts(SpecializationBranch.sloppy);
        final lickBpmScore = sloppyPts > 0 ? max(bpmScore, 0.3) : bpmScore;
        final bpm = _StaminaModel.lerp(55.0, 80.0, lickBpmScore).round();
        // Tirage spécifique lick : tip→head forcé tant qu'humiliation < 2,
        // toutes amplitudes (incluant tip → throat/full) à partir de 2.
        final (from, to) = _sampleFromToForLick(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(10.0, 25.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.breath:
        final dur = _StaminaModel.lerp(6.0, 15.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
      case SessionMode.beg:
        // Convention uniforme hold/beg : la position tenue est dans `to`.
        // Obéissance : beg plus profonds (ampScore boosté localement) et
        // plus longs.
        final obPts = _pts(SpecializationBranch.obeissance);
        final begAmp = (ampScore + 0.10 * obPts).clamp(0.0, 1.0);
        final to = _pickBegPosition(begAmp);
        final baseDur = _scaleDuration(
          _StaminaModel.lerp(7.0, 16.0, durScore),
          enduranceFactor: 0.04,
          extraFactor: obPts * 0.06,
        );
        final chained = _maybePickBegWithChain(
          to: to,
          obPts: obPts,
        );
        if (chained != null) return chained;
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: baseDur);
      case SessionMode.hand:
        // Hand sert d'outil d'excitation/endurance pure : sa fréquence peut
        // grimper sans coût d'humiliation. Plage très large pour permettre
        // récup lente (60 BPM) jusqu'à burst frénétique (180 BPM).
        final bpm = _StaminaModel.lerp(60.0, 180.0, bpmScore).round();
        // Tirage spécifique hand : la main tient la base de la queue, donc
        // l'amplitude reste dans le haut (jamais plus profond que throat).
        // En revanche tip→head et head→head sont autorisés (le tirage
        // commun les exclut pour les autres modes).
        final (from, to) = _sampleFromToForHand(ampScore);
        final dur = _scaleDuration(
          _StaminaModel.lerp(15.0, 30.0, durScore),
          enduranceFactor: 0.04,
        );
        return _StepDraft(
            mode: mode, bpm: bpm, from: from, to: to, duration: dur);
      case SessionMode.freestyle:
        final dur = _StaminaModel.lerp(8.0, 18.0, durScore).round();
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: null, duration: dur);
      case SessionMode.suckle:
        // Aspiration : pas de BPM (pulse fixe ~1.2s côté audio), position
        // tenue dans `to`. Cibles valides = head ou balls (cf. `_isUnlocked`).
        // - En carrière : unlock `suckleHead` au level 4-5, `suckleBalls`
        //   plus tard ; le filtre `_isUnlocked` rejette ce qui n'est pas
        //   encore acquis et la cascade dégrade.
        // - En mode hérité (Custom) : balls n'est candidat que si l'anatomy
        //   l'inclut et que la profondeur max le permet (`_maxDepthIndex >=
        //   Position.balls.index`). On biaise vers head (zone classique) avec
        //   ~30 % de chances de tirer balls quand dispo, pour rester audible
        //   mais marginal.
        final dur = _scaleDuration(
          _StaminaModel.lerp(8.0, 18.0, durScore),
          enduranceFactor: 0.04,
        );
        final ballsAllowed = _anatomy.hasBalls &&
            _maxDepthIndex >= Position.balls.index &&
            (_unlockedKeys.isEmpty ||
                _unlockedKeys.contains(UnlockKey.suckleBalls));
        final to = (ballsAllowed && _rng.nextDouble() < 0.30)
            ? Position.balls
            : Position.head;
        return _StepDraft(
            mode: mode, bpm: null, from: null, to: to, duration: dur);
    }
  }

  /// Capture l'état mutable de continuité (lasts + compteurs) pour le passer
  /// au picker statique. Reconstruit à chaque pick — 4 lectures de fields,
  /// cheap.
  _ModeContinuityState _continuitySnapshot() => _ModeContinuityState(
        lastType: _lastType,
        stepsInLastType: _stepsInLastType,
        stepsOutsideBouche: _stepsOutsideBouche,
        lastMode: _lastMode,
      );

  /// Adaptateur d'instance pour `_ModePicker.pickWeighted` — injecte `_spec`,
  /// `_coachModeWeights`, le snapshot de continuité et `_rng`.
  SessionMode _pickWeightedMode(List<SessionMode> candidates) =>
      _ModePicker.pickWeighted(
        candidates,
        spec: _spec,
        coachWeights: _coachModeWeights,
        continuity: _continuitySnapshot(),
        rng: _rng,
      );

  // `_modeWeight` est consommé uniquement par `_ModePicker.pickWeighted`
  // (inline). Plus d'adaptateur ici.

  // `_continuityMultiplier` a migré dans `_ModePicker.continuityMultiplier`
  // (passé un `_ModeContinuityState`). Plus de call site externe.

  /// Met à jour `_lastType` / `_stepsInLastType` après push d'un step,
  /// et alimente `_recentEmits` (buffer 3 derniers, modes rythmés
  /// uniquement) pour la détection de pattern plat.
  ///
  /// Les steps `transit` (breath / freestyle) sont une parenthèse
  /// transparente : ils ne touchent ni le tracking de type ni le buffer
  /// `_recentEmits` — un breath de récup au milieu d'une série rythmée ne
  /// doit pas remettre le compteur à zéro côté détection de monotonie.
  /// Plafond (en secondes) de la chaîne `rhythm` consécutive — comportement
  /// **historique**, utilisé tant que le profil de capacités n'a pas de donnée
  /// `motion_streak` : tant que `rhythmHeadMidSustained` n'est pas acquis, le
  /// générateur force une rupture au-delà ; la milestone `intro_rhythm_sustained`
  /// lève ce mur. En carrière avec un profil renseigné, c'est l'endurance
  /// **prouvée par la joueuse** (`motion_streak.comfort`) qui gouverne — cf.
  /// `_effectiveRhythmChainCapSeconds`.
  static const int _rhythmChainCapSeconds = 60;

  /// Borne basse du cap de chaîne rythme dérivé du profil — qu'une donnée
  /// `motion_streak` anormalement courte ne hache pas tout le rythme.
  static const int _rhythmChainCapFloorSeconds = 24;

  /// Plancher de durée d'un step `rhythm` poussé via `_mapDifficultyToStep`.
  /// Sert à éviter qu'un step soit tronqué à 1-2 s par `_capRhythmConsecutive`
  /// quand on est presque au cap. En dessous, on retire `rhythm` des
  /// candidats au tirage (`_canChainRhythm`).
  static const int _minRhythmStepSeconds = 8;

  /// Cap effectif (en secondes) de la chaîne `rhythm` consécutive :
  /// - profil renseigné (carrière) → `motion_streak.comfort` (surchargé si
  ///   `motion_streak` est l'axe poussé), planché à `_rhythmChainCapFloorSeconds` ;
  /// - sinon → comportement historique (`_rhythmChainCapSeconds`, levé par
  ///   l'unlock `rhythmHeadMidSustained`).
  int get _effectiveRhythmChainCapSeconds {
    final c = _capProfile?.comfortOf(CapabilityAxis.rhythmMotionStreak);
    if (c != null) {
      final v =
          (c * _overloadFactorFor(CapabilityAxis.rhythmMotionStreak)).round();
      return v < _rhythmChainCapFloorSeconds ? _rhythmChainCapFloorSeconds : v;
    }
    return _unlockedKeys.contains(UnlockKey.rhythmHeadMidSustained)
        ? 1 << 20 // de fait illimité
        : _rhythmChainCapSeconds;
  }

  /// Vrai si on peut encore ajouter un step `rhythm` à la chaîne sans
  /// dépasser le cap (cf. `_effectiveRhythmChainCapSeconds`).
  bool _canChainRhythm() {
    return _consecutiveRhythmSeconds + _minRhythmStepSeconds <=
        _effectiveRhythmChainCapSeconds;
  }

  /// Tronque la durée d'un step `rhythm` pour respecter le cap chaîne
  /// consécutive. No-op si la marge restante est suffisante.
  int _capRhythmConsecutive(int dur) {
    final remaining =
        _effectiveRhythmChainCapSeconds - _consecutiveRhythmSeconds;
    if (remaining <= 0) return dur; // _canChainRhythm aurait dû filtrer
    return min(dur, remaining);
  }

  void _trackPushedStep(SessionMode mode, Position? to,
      {Position? from, int? bpm, int? duration}) {
    // Cap rythme soutenu : on cumule la durée des `rhythm` consécutifs.
    // Tout autre mode (breath compris — c'est une vraie pause de souffle)
    // remet le compteur à zéro.
    if (mode == SessionMode.rhythm) {
      _consecutiveRhythmSeconds += duration ?? 0;
    } else {
      _consecutiveRhythmSeconds = 0;
    }
    final type = _classifyStep(mode, to);
    if (type == _StepType.transit) return;
    if (type == _StepType.bouche) {
      _stepsOutsideBouche = 0;
    } else {
      _stepsOutsideBouche++;
    }
    if (type == _lastType) {
      _stepsInLastType++;
    } else {
      _lastType = type;
      _stepsInLastType = 1;
    }
    // Buffer pattern plat : on n'enregistre que les modes à amplitude
    // (rhythm / lick / hand / biffle) — ce sont les seuls où la notion de
    // « même profondeur + même BPM » fait sens. Les hold / beg ne portent
    // pas de BPM, et leur monotonie est gérée ailleurs (variation de
    // position dans `_pickHoldPosition` / `_lastFrom`).
    if (mode == SessionMode.rhythm ||
        mode == SessionMode.lick ||
        mode == SessionMode.hand ||
        mode == SessionMode.biffle) {
      _recentEmits.add((mode: mode, from: from, to: to, bpm: bpm));
      while (_recentEmits.length > 3) {
        _recentEmits.removeAt(0);
      }
    }
  }

  /// Vrai si le draft proposé prolongerait un **pattern plat** : les 3
  /// derniers émis + le draft sont tous (a) du même mode rythmé,
  /// (b) à la même profondeur cible `to`, (c) avec une variance BPM
  /// < 10 sur les 4 valeurs. Sans cette fenêtre élargie, une série
  /// `head→mid 88 / head→mid 92 / head→mid 90` glissait à travers le
  /// check classique (BPMs « différents ») alors que l'oreille perçoit
  /// un plat. Le seuil < 10 reste serré : 10 BPM de variance c'est déjà
  /// audible, on n'intervient que sous ce seuil.
  bool _isFlatRhythmicPattern(_StepDraft d) {
    if (_recentEmits.length < 3) return false;
    if (d.bpm == null || d.to == null) return false;
    if (!_recentEmits.every((e) => e.mode == d.mode)) return false;
    if (!_recentEmits.every((e) => e.to == d.to)) return false;
    final bpms = <int>[
      for (final e in _recentEmits)
        if (e.bpm != null) e.bpm!,
      d.bpm!,
    ];
    if (bpms.length < 4) return false;
    final maxB = bpms.reduce(max);
    final minB = bpms.reduce(min);
    return (maxB - minB) < 10;
  }

  // `_modeBaseWeight` a migré dans `_ModePicker.baseWeight` (prend
  // `SpecializationAllocation` en param). Plus de call site externe.

  /// Applique aux durées les multiplicateurs de spé, capés.
  /// `enduranceFactor` = bonus par point Endurance ; `extraFactor` = bonus
  /// brut additionnel.
  int _scaleDuration(
    double base, {
    double enduranceFactor = 0.0,
    double extraFactor = 0.0,
  }) {
    final mul = 1.0 +
        enduranceFactor * _pts(SpecializationBranch.endurance) +
        extraFactor;
    final capped = mul.clamp(1.0, 1.6);
    return (base * capped).round();
  }

  int _pts(SpecializationBranch b) => _spec.pointsIn(b);

  /// Si [draft] est un `beg` qui suit immédiatement un `lick` ou un
  /// `breath`, retourne une copie sans position tenue (récup vocale pure).
  /// Sinon, renvoie [draft] tel quel.
  _StepDraft _stripBegFromAfterSoft(
    _StepDraft draft,
    List<SessionStep> steps,
  ) {
    if (draft.mode != SessionMode.beg) return draft;
    if (draft.to == null) return draft;
    if (steps.isEmpty) return draft;
    final prev = steps.last.mode;
    if (prev != SessionMode.lick && prev != SessionMode.breath) return draft;
    return _StepDraft(
      mode: draft.mode,
      bpm: draft.bpm,
      from: draft.from,
      to: null,
      duration: draft.duration,
    );
  }

  /// Cap la durée d'un step rythmé par le **nombre d'aller-retours** sur
  /// la profondeur cible. Évite qu'un step `to=throat` à 90 bpm dure 60 s
  /// (= 45 pulses = la joueuse n'a aucune respi). Au-delà de mid, on borne
  /// le nombre de pulses par step. Mid et plus haut : pas de cap.
  ///
  /// Convention : 1 pulse = 1 aller-retour from↔to (= 2 beats à BPM donné).
  /// Donc `durMax = maxPulses × 120 / bpm` secondes.
  ///
  /// **Cap dynamique selon l'humiliation career** : à la première fois où
  /// la joueuse aborde la profondeur, son humil career est faible (juste
  /// au seuil de la milestone : ~10 pour throat, ~25 pour full), donc cap
  /// bas (6/4 pulses). À mesure qu'elle accumule l'humil, le cap monte —
  /// et la spé pertinente (profondeur, rythmeBiffle) le pousse encore.
  /// On se base sur l'humil plutôt que le niveau global parce que c'est
  /// l'humil qui mesure la pratique réelle de la profondeur, pas le
  /// passage de palier (un niveau 20 spé sloppy a peu d'humil profondeur,
  /// un niveau 12 spé profondeur en a beaucoup plus).
  /// Adapteur de `_BpmPacing.capRhythmDurationByPulses` qui injecte les
  /// 3 champs d'état nécessaires depuis l'instance.
  int _capRhythmDurationByPulses(int dur, int bpm, Position? to) =>
      _BpmPacing.capRhythmDurationByPulses(
        dur,
        bpm,
        to,
        humiliationCareer: _humiliationCareer,
        rythmePts: _pts(SpecializationBranch.rythmeBiffle),
        profondeurPts: _pts(SpecializationBranch.profondeur),
      );

  /// Tire un couple (from, to) tel que `from.index < to.index` strictement.
  ///
  /// `ampScore = 0` → head→mid (baseline). `ampScore = 1` → tip→full ou
  /// mid→full. Garantit la contrainte from < to.
  ///
  /// Choix de design : `from = head` est la baseline, `from = tip` reste
  /// possible mais minoritaire (~15%) — sinon on se retrouve avec une
  /// majorité de tip→head en début de session, alors que la position de
  /// référence pour la coach est head.
  /// [capByDepth] = true → ceiling et probabilité de profondeur appliqués
  /// (rythme : la profondeur est gated par milestone). false → toutes
  /// profondeurs autorisées (lick : la langue n'a pas de tension de
  /// profondeur ; le filtre se fait en aval via `_isUnlocked` quand `to`
  /// requiert une milestone, ex: `lick_full`).
  (Position, Position) _sampleFromTo(double ampScore,
      {bool capByDepth = true}) {
    final clamped = ampScore.clamp(0.0, 1.0);
    // Min mid (idx 2) au lieu de head (idx 1) : l'amplitude minimale est
    // head→mid, pas tip→head.
    final ceiling = capByDepth ? _maxDepthIndex.clamp(2, 4) : 4;
    var deepestIdx = _StaminaModel.lerp(2.0, ceiling.toDouble(), clamped)
        .round()
        .clamp(2, ceiling);
    // Bonus Profondeur (spé) : remonte la probabilité de profond, dans
    // la limite du plafond du tirage.
    final depthPts = _pts(SpecializationBranch.profondeur);
    final effectiveDeepProb = capByDepth ? _deepProbability : 1.0;
    final boostedDeepProb =
        (effectiveDeepProb + 0.08 * depthPts).clamp(0.0, 1.0);
    // Si le tirage demande une position profonde (≥ throat) mais que la
    // probabilité ne le permet pas, on rabat sur mid.
    if (deepestIdx >= 3 && _rng.nextDouble() >= boostedDeepProb) {
      deepestIdx = 2;
    }
    final int shallowestIdx;
    if (deepestIdx >= 3 && _rng.nextDouble() < 0.15) {
      // ~15% : tip pour les amplitudes pleines (tip→full marque bien).
      shallowestIdx = 0;
    } else {
      // Sinon : head ou plus profond (jamais tip), uniforme entre les
      // positions admissibles.
      shallowestIdx = 1 + _rng.nextInt(deepestIdx - 1);
    }
    return (
      Position.values[shallowestIdx],
      Position.values[deepestIdx],
    );
  }

  /// Tirage spécifique au mode hand. **Une seule variation** en standalone :
  /// `head→throat`. La main enveloppe la base de la verge ; aller plus haut
  /// que les lèvres (= head) n'a pas de sens anatomique, et la varier sur
  /// 3-4 amplitudes brouillait la lecture acoustique sans gain dramaturgique.
  /// Le BPM (60–180, choisi par `bpmScore`) reste le levier de variété.
  ///
  /// `ampScore` est ignoré ici — la variation viendra des futurs combos
  /// hand+rhythm où `from` du hand s'aligne sur le `from` du rhythm
  /// (ex. rhythm mid→throat → hand mid→throat, parce que la main ne peut
  /// pas être plus haut que les lèvres pendant le combo).
  (Position, Position) _sampleFromToForHand(double ampScore) {
    return (Position.head, Position.throat);
  }

  /// Tirage spécifique au mode lick. Tant que `_humiliationCareer < 2`,
  /// le lick reste sur tip→head (l'utilisatrice n'a pas encore appris à
  /// lécher plus profond). À partir de 2, toutes les amplitudes sont
  /// autorisées sans cap niveau — la langue n'a pas de tension de
  /// profondeur (`capByDepth: false`). Si le tirage tombe sur to=full
  /// sans la milestone `lick_full`, le filtre `_isUnlocked` en cascade
  /// dégrade.
  (Position, Position) _sampleFromToForLick(double ampScore) {
    if (_humiliationCareer < 2.0) {
      return (Position.tip, Position.head);
    }
    return _sampleFromTo(ampScore, capByDepth: false);
  }

  /// Profondeur max débloquée pour un hold, basée sur les milestones :
  /// fullHoldShort > throatHoldShort > holdMidShort > head (socle de base).
  /// Capée aussi par `_maxDepthIndex` (cohérence niveau).
  ///
  /// Sémantique design : « le seul hold qui a du sens est le plus profond
  /// que tu sais tenir ». Aller moins profond perd le côté narratif —
  /// l'utilisatrice qui sait tenir gorge n'a aucune raison de tenir mid
  /// pendant une session normale, c'est juste de la baisse arbitraire.
  /// Les holds tip/head n'ont pas de clé (socle ouvert par `intro_basics`)
  /// → en carrière sans milestone hold acquise, le plancher est `head`.
  int _milestoneHoldCeilingIdx() {
    final int milestoneCap;
    if (_unlockedKeys.contains(UnlockKey.fullHoldShort)) {
      milestoneCap = Position.full.index;
    } else if (_unlockedKeys.contains(UnlockKey.throatHoldShort)) {
      milestoneCap = Position.throat.index;
    } else if (_unlockedKeys.contains(UnlockKey.holdMidShort)) {
      milestoneCap = Position.mid.index;
    } else if (_unlockedKeys.isEmpty) {
      // Hérité (mode démo / scénario non-carrière) : on retombe sur le cap
      // de niveau. Évite que le mode démo se fige sur head.
      milestoneCap = _maxDepthIndex;
    } else {
      // Carrière, socle de base : head est le hold le plus profond libre.
      milestoneCap = Position.head.index;
    }
    return min(milestoneCap, _maxDepthIndex);
  }

  /// Choix de la position d'un hold. Règle : on ne tient **que la profondeur
  /// max débloquée**. Si full est ouverte, on tire entre throat et full
  /// (ampScore + spé profondeur biaisent vers full). Si throat est le max,
  /// on ne tient que throat — pas de retour à mid arbitraire. Au tout début
  /// (mid max), on tient mid.
  Position _pickHoldPosition(double ampScore) {
    final ceilingIdx = _milestoneHoldCeilingIdx();
    final depthPts = _pts(SpecializationBranch.profondeur);
    // Cas full ouvert : choix throat / full pondéré par ampScore + spé.
    if (ceilingIdx >= Position.full.index) {
      final adjusted = (ampScore + 0.10 * depthPts).clamp(0.0, 1.0);
      final boostedFullProb =
          (_deepProbability + 0.10 * depthPts).clamp(0.0, 1.0);
      // Plus ampScore est haut, plus on penche full ; mais on respecte
      // aussi `_deepProbability` du niveau pour ne pas spammer du full
      // dès le palier d'ouverture.
      final wantsFull = adjusted >= 0.55 && _rng.nextDouble() < boostedFullProb;
      return wantsFull ? Position.full : Position.throat;
    }
    // Cap inférieur ou égal à throat : on tient strictement le max.
    return Position.values[ceilingIdx];
  }

  /// Cap de profondeur autorisé pour les modes rythmés (rhythm/hand) en
  /// `to`, basé sur les milestones effectivement acquittées :
  /// - `fullPulse` (intro_full_pulse) → full ouvert
  /// - `throatPulse` (intro_throat_pulse) → throat ouvert
  /// - sinon → plafond mid (la joueuse n'a pas encore appris la profondeur)
  ///
  /// Capé aussi par `_maxDepthIndex` en sécurité (cohérence niveau).
  /// Indépendant du niveau : c'est l'acquittement de la milestone qui
  /// débloque, pas le passage de palier.
  int _milestoneRhythmCeilingIdx() {
    final int milestoneCap;
    if (_unlockedKeys.contains(UnlockKey.fullPulse)) {
      milestoneCap = Position.full.index;
    } else if (_unlockedKeys.contains(UnlockKey.throatPulse)) {
      milestoneCap = Position.throat.index;
    } else {
      milestoneCap = Position.mid.index;
    }
    return min(milestoneCap, _maxDepthIndex);
  }

  /// Choix de la position du pré-finisher (transition rythmée juste avant
  /// les boosts, bas niveaux). Le cap suit `_milestoneRhythmCeilingIdx`
  /// — gating par milestones acquittées, jamais par niveau seul.
  Position _pickFinisherPosition(int level) {
    final ceilingIdx = _milestoneRhythmCeilingIdx();
    if (ceilingIdx <= Position.mid.index) return Position.mid;
    if (ceilingIdx == Position.throat.index) {
      // throatPulse acquis : 30% mid (variété) / 70% throat.
      return _rng.nextDouble() < 0.30 ? Position.mid : Position.throat;
    }
    // ceilingIdx == full → fullPulse acquis : tirage parmi mid/throat/full.
    final r = _rng.nextDouble();
    if (r < 0.30) return Position.mid;
    if (r < 0.70) return Position.throat;
    return Position.full;
  }

  /// Tente de transformer un beg simple en beg + action enchaînée
  /// (« dis X et continue à me sucer »). Retourne `null` quand aucun
  /// template ne passe les unlocks ou quand le tirage aléatoire l'emporte.
  /// Probabilité 0.20 → 0.60 selon l'obéissance investie.
  ///
  /// **Palette V1** (gating naturel par `_isUnlocked` sur les composants) :
  /// 1. beg libre 12 s + rhythm tip→head 80 BPM 18 s
  /// 2. beg libre 10 s + lick tip→head 70 BPM 14 s
  /// 3. beg libre 12 s + hold head 6 s
  /// 4. beg head 8 s + lick head→mid 65 BPM 12 s (gated begThroat)
  ///
  /// Le tirage est uniforme parmi les templates dont les deux composants
  /// passent `_isUnlocked`. `null` si aucun ne passe.
  _StepDraft? _maybePickBegWithChain({
    required Position? to,
    required int obPts,
  }) {
    // Pour V1, on n'attache une chain que sur un beg libre (to == null).
    // Les beg avec position tenue (mid/throat/full) sont déjà mécaniquement
    // chargés, on ne veut pas y greffer une seconde action en plus.
    if (to != null) return null;
    final probability = 0.20 + 0.05 * obPts;
    if (_rng.nextDouble() > probability.clamp(0.20, 0.60)) return null;

    final holdCeilingIdx = _milestoneHoldCeilingIdx();
    final candidates = <(_StepDraft, _StepDraft)>[];
    for (final tpl in _begChainTemplates) {
      // Si le chainNext est un hold à profondeur sous le palier de hold
      // débloqué par milestones, on filtre — un hold tip/head qui suit
      // un beg alors qu'on maîtrise mid est une régression. On NE le
      // promote pas en silence (durée 6 s d'un template tip/head ne
      // tient pas une bouchée à throat ou full) — on retire juste le
      // template du tirage.
      final chain = tpl.$2;
      if (chain.mode == SessionMode.hold &&
          chain.to != null &&
          chain.to!.index < holdCeilingIdx) {
        continue;
      }
      if (!_isUnlocked(tpl.$1) || !_isUnlocked(tpl.$2)) continue;
      // Custom (dose `none`) : on ne propose pas un beg-with-chain dont la
      // suite est sur un mode banni. Le beg en lui-même est aussi gaté (si
      // beg=none, le tirage de beg ne sera pas atteint en amont, mais on
      // re-check ici pour rester explicite).
      if (_isModeForbidden(tpl.$1.mode)) continue;
      if (_isModeForbidden(tpl.$2.mode)) continue;
      candidates.add(tpl);
    }
    if (candidates.isEmpty) return null;
    final pick = candidates[_rng.nextInt(candidates.length)];
    return _StepDraft(
      mode: pick.$1.mode,
      bpm: pick.$1.bpm,
      from: pick.$1.from,
      to: pick.$1.to,
      duration: pick.$1.duration,
      chainNext: pick.$2,
    );
  }

  /// Templates `(beg, chainAction)` pour la palette `_maybePickBegWithChain`.
  /// La durée du beg est l'enveloppe : pour un beg libre on l'écrase par
  /// `baseDuration` clampé entre les deux bornes définies ici (utilisé
  /// comme min/max). Pour un beg ancré (`to != null`), on garde tel quel.
  static const List<(_StepDraft, _StepDraft)> _begChainTemplates = [
    // Beg libre + rhythm tip→head 80 BPM 18 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      _StepDraft(
        mode: SessionMode.rhythm,
        bpm: 80,
        from: Position.tip,
        to: Position.head,
        duration: 18,
      ),
    ),
    // Beg libre + lick tip→head 70 BPM 14 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 10,
      ),
      _StepDraft(
        mode: SessionMode.lick,
        bpm: 70,
        from: Position.tip,
        to: Position.head,
        duration: 14,
      ),
    ),
    // Beg libre + hold head 6 s.
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      _StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: Position.head,
        duration: 6,
      ),
    ),
    // Beg head + lick head→mid 65 BPM 12 s — profil obéissance avancée
    // (gated par begThroat car beg to non-null).
    (
      _StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: Position.head,
        duration: 8,
      ),
      _StepDraft(
        mode: SessionMode.lick,
        bpm: 65,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
    ),
  ];

  /// Choix de la position d'un beg selon ampScore. Retourne null pour
  /// `ampScore < 0.40` → beg libre (sans position). Sinon : mid → throat
  /// → full. Jamais head ou tip (pas de sens : un beg léger doit être
  /// libre, ancrer la position de tenue ne commence qu'à mid).
  Position? _pickBegPosition(double ampScore) {
    if (ampScore < 0.40) return null;
    if (ampScore < 0.65) return Position.mid;
    if (ampScore < 0.85) return Position.throat;
    return Position.full;
  }

  /// Tire un point uniforme sur le simplexe 3D (a + b + c = 1, tous > 0).
  /// Méthode des "barres de Dirichlet" : 2 cuts uniformes dans [0,1] triés
  /// délimitent 3 segments.
  (double, double, double) _sampleSimplex3() {
    final a = _rng.nextDouble();
    final b = _rng.nextDouble();
    final lo = min(a, b);
    final hi = max(a, b);
    return (lo, hi - lo, 1.0 - hi);
  }

  // _lerp, _fillProfile, _positionDepth, _staminaDelta, _applyStaminaChange
  // + constante `_StaminaModel.cap` (renommée `_StaminaModel.cap`) ont migré dans
  // `career_session_generator_stamina.dart` (fichier part). Accès toujours
  // gratuit depuis cette classe — c'est la même library.

  /// Avance la simulation salive pour un draft. Mute `_salivaSim` et
  /// `_salivaSimSecond`. Appelé en parallèle de chaque simulation excit
  /// principale via [_emitDraftOnSims].
  void _advanceSalivaSim(_StepDraft draft) {
    final dur = draft.duration ?? 0;
    if (dur <= 0) return;
    for (var s = 0; s < dur; s++) {
      _salivaSim.onTickSecond(
        mode: draft.mode,
        from: draft.from,
        to: draft.to,
        swallowMode: SwallowMode.allowed,
        elapsedSecond: _salivaSimSecond,
      );
      _salivaSimSecond++;
    }
  }

  /// Adaptateur d'instance pour `_FinalPicker.pickFinal`. Le paramètre
  /// `includeHand` est ignoré (lu depuis `_finalPicker.includeHand` qui
  /// est posé une fois par `generate()`) — l'API reste pour compat
  /// historique.
  _StepDraft _pickFinal({
    required double humilCap,
    required bool includeHand,
    required int maxDepth,
    required double finishMul,
  }) =>
      _finalPicker.pickFinal(
        humilCap: humilCap,
        maxDepth: maxDepth,
        finishMul: finishMul,
      );

  // ─── Phase 5 — Punitions générées & bornées ────────────────────────────

  /// Génère une punition contextuelle pour la séance carrière (cf. §7 de la
  /// spec). À utiliser à la place du tirage dans `punishments.json` en mode
  /// carrière. Hors carrière (Custom, scénarios JSON, mini-punition
  /// résilience), le contrôleur garde le tirage statique.
  ///
  /// Algo : palette hardcodée de compositions « max humiliation qui passe »
  /// (parité avec `_pickFinal`), bornée par les ceilings de session et le
  /// `comfort` du profil de capacités via `_clampToCapability`. Fallback en
  /// escalier (rythme `head→mid` rapide → hand ultime) pour rester jouable
  /// même à humilCap quasi-nul.
  ///
  /// L'axe surchargé de la séance ([capabilityOverloadAxis]) est honoré côté
  /// **clamp** (le `comfort` de cet axe est élargi du facteur de surcharge
  /// dans `_clampToCapability` via `_capabilityCapFor`) — mais **pas côté
  /// sélection** : on ne filtre pas par affinité d'axe, on prend strictement
  /// le plus humiliant qui passe (décision projet).
  Punishment generatePunishment({
    required int level,
    required PhraseBank bank,
    required Set<UnlockKey> unlockedKeys,
    required CapabilityProfile? capabilityProfile,
    Map<CapabilityAxis, double> capabilitySessionCeilings = const {},
    CapabilityAxis? capabilityOverloadAxis,
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
    // de session (`_lastMode`, `_consecutiveRhythmSeconds`, etc.) — sans
    // objet ici.
    _level = level;
    _includeHand = includeHand;
    _unlockedKeys = unlockedKeys;
    _capProfile = capabilityProfile;
    _capCeilings = capabilitySessionCeilings;
    _anatomy = anatomy;
    _spec = specialization ?? SpecializationAllocation.empty();
    _humiliationCareer = humiliationCareer;
    _humiliationSession = humiliationSession;
    _obedience = obedience;
    _coachModeWeights = coachModeWeights;
    _lastText = '';
    // Surcharge : on honore l'axe imposé par la séance (pas de re-tirage).
    // Le facteur est reconstruit depuis la `successRate` du profil (même
    // formule que `_pickOverloadAxis`). Si pas de profil → 1.0 (no-op).
    _overloadAxis = capabilityOverloadAxis;
    _overloadFactor =
        (capabilityOverloadAxis != null && capabilityProfile != null)
            ? CapabilityRegulator.surchargeFactor(
                capabilityProfile.stateOf(capabilityOverloadAxis).successRate)
            : 1.0;
    // Punition générée hors `generate()` → on doit aussi (re)bâtir
    // `_capClamps` ici, sinon le `_clampToCapability` qui sert à matérialiser
    // chaque step de la compo lit un field non initialisé. Pas de
    // `_bpmRange`/`_holdDurationRange` côté Custom (les punitions ne sont pas
    // générées en Custom), donc on laisse les bornes utilisateur à null.
    _capClamps = _CapabilityClamps(
      profile: _capProfile,
      ceilings: _capCeilings,
      overloadAxis: _overloadAxis,
      overloadFactor: _overloadFactor,
      bpmRange: null,
      holdRange: null,
    );
    // `_finalPicker` n'est pas consommé par `generatePunishment`, mais on
    // l'initialise par sécurité (idempotence avec `generate()`).
    _finalPicker = _FinalPicker(
      level: _level,
      anatomy: _anatomy,
      unlockedKeys: _unlockedKeys,
      spec: _spec,
      coachModeWeights: _coachModeWeights,
      includeHand: _includeHand,
      rng: _rng,
      capClamps: _capClamps,
    );

    final humilCap = _humiliationCareer + _humiliationSession;

    // ─── Palette V1 (5 compos, parité dramaturgique avec `_pickFinal`) ───
    final candidates = <_PunishmentCompo>[
      // Biffle rapide court — le moins humiliant qui reste punitif. Gaté
      // `includeHand` (biffle implique la main, comme dans `_pickFinal`).
      const _PunishmentCompo(
        id: 'biffle_burst',
        drafts: [
          _StepDraft(
            mode: SessionMode.biffle,
            bpm: 135,
            from: null,
            to: null,
            duration: 25,
          ),
        ],
        reqHumil: 13.0,
        handRequired: true,
      ),
      // Franchissement `head→throat` rapide — axe « crossings BPM throat ».
      const _PunishmentCompo(
        id: 'crossings_burst',
        drafts: [
          _StepDraft(
            mode: SessionMode.rhythm,
            bpm: 110,
            from: Position.head,
            to: Position.throat,
            duration: 25,
          ),
        ],
        reqHumil: 14.0,
      ),
      // Torture lente profonde — rhythm `throat→full` BPM bas (= airless,
      // pas de fenêtre de respiration) + hold full final.
      const _PunishmentCompo(
        id: 'slow_torture',
        drafts: [
          _StepDraft(
            mode: SessionMode.rhythm,
            bpm: 35,
            from: Position.throat,
            to: Position.full,
            duration: 30,
          ),
          _StepDraft(
            mode: SessionMode.hold,
            bpm: null,
            from: null,
            to: Position.full,
            duration: 8,
          ),
        ],
        reqHumil: 16.0,
      ),
      // Throat sans pitié — rhythm `throat→full` rapide + hold final.
      const _PunishmentCompo(
        id: 'throat_relentless',
        drafts: [
          _StepDraft(
            mode: SessionMode.rhythm,
            bpm: 100,
            from: Position.throat,
            to: Position.full,
            duration: 28,
          ),
          _StepDraft(
            mode: SessionMode.hold,
            bpm: null,
            from: null,
            to: Position.full,
            duration: 8,
          ),
        ],
        reqHumil: 18.0,
      ),
      // Chaîne de holds profonds avec courte fenêtre breath au milieu —
      // la plus humiliante de la palette V1.
      const _PunishmentCompo(
        id: 'deep_hold_chain',
        drafts: [
          _StepDraft(
            mode: SessionMode.hold,
            bpm: null,
            from: null,
            to: Position.throat,
            duration: 10,
          ),
          _StepDraft(
            mode: SessionMode.breath,
            bpm: null,
            from: null,
            to: null,
            duration: 4,
          ),
          _StepDraft(
            mode: SessionMode.hold,
            bpm: null,
            from: null,
            to: Position.full,
            duration: 12,
          ),
        ],
        reqHumil: 20.0,
      ),
    ];

    // Filtre humilCap + unlocks composants + gating hand. Sélection = max
    // humiliant valide (parité `_pickFinal` : tri par `req` croissante,
    // `valid.last`).
    final valid = candidates.where((c) {
      if (c.handRequired && !includeHand) return false;
      if (c.reqHumil > humilCap) return false;
      return c.drafts.every(_isUnlocked);
    }).toList()
      ..sort((a, b) => a.reqHumil.compareTo(b.reqHumil));
    if (valid.isNotEmpty) {
      return _materializePunishment(valid.last, bank);
    }

    // ─── Escalier fallback — ordre du plus exigeant au plus doux ──────────
    // Étape 1 : rythme `head→mid` rapide (req≈5). Reste une vraie punition
    // (BPM élevé) tant qu'on a un peu d'humil derrière. À niv. 2-3 c'est
    // ici qu'on tombe en pratique pour une séance fragile.
    const lastResort = _PunishmentCompo(
      id: 'last_resort_rhythm',
      drafts: [
        _StepDraft(
          mode: SessionMode.rhythm,
          bpm: 120,
          from: Position.head,
          to: Position.mid,
          duration: 22,
        ),
      ],
      reqHumil: 5.0,
    );
    if (lastResort.reqHumil <= humilCap &&
        lastResort.drafts.every(_isUnlocked)) {
      return _materializePunishment(lastResort, bank);
    }

    // Étape 2 : filet ultime hand `head→mid` 50 BPM. req=0, toujours
    // jouable. N'arrive qu'à humilCap≈0 + tous les autres bloqués — pas en
    // pratique sur une joueuse carrière (mais évite tout crash).
    const handFallback = _PunishmentCompo(
      id: 'hand_fallback',
      drafts: [
        _StepDraft(
          mode: SessionMode.hand,
          bpm: 50,
          from: Position.head,
          to: Position.mid,
          duration: 15,
        ),
      ],
      reqHumil: 0.0,
    );
    return _materializePunishment(handFallback, bank);
  }

  /// Convertit une composition (drafts non-clampés) en [Punishment] runtime :
  /// passe chaque draft par `_clampToCapability` (ceilings + comfort), injecte
  /// un texte coach tiré dans le tier `hard` du mode (silencieux pour
  /// `breath`, qui est une transition), et pose les `time` cumulés.
  Punishment _materializePunishment(_PunishmentCompo compo, PhraseBank bank) {
    final steps = <SessionStep>[];
    var time = 0;
    for (final raw in compo.drafts) {
      final clamped = _clampToCapability(raw);
      final dur = clamped.duration ?? 0;
      String text = '';
      if (clamped.mode != SessionMode.breath) {
        text = _pickPhraseForDraft(bank, clamped, 'hard');
      }
      steps.add(SessionStep(
        time: time,
        text: text,
        mode: clamped.mode,
        bpm: clamped.bpm,
        bpmEnd: clamped.bpmEnd,
        from: clamped.from,
        to: clamped.to,
        duration: dur,
      ));
      time += dur;
    }
    return Punishment(
      id: compo.id,
      name: compo.id,
      durationSeconds: time,
      steps: steps,
    );
  }

  /// Applique `_BpmPacing.diversifyBpm` au draft si pertinent (modes avec
  /// BPM, hors hold/beg/breath/freestyle qui n'en ont pas), et met à jour
  /// `_lastBpm`. Retourne le draft (potentiellement modifié).
  ///
  /// Reste sur l'instance car écrit `_lastBpm` (mutation d'état).
  _StepDraft _applyBpmDiversity(_StepDraft d) {
    final bpm = d.bpm;
    if (bpm == null) return d;
    final newBpm = _BpmPacing.diversifyBpm(bpm, _lastBpm, _rng);
    _lastBpm = newBpm;
    if (newBpm == bpm) return d;
    return _StepDraft(
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
  _StepDraft _diversifyAmplitude(_StepDraft d) {
    if (d.mode != SessionMode.rhythm &&
        d.mode != SessionMode.lick &&
        d.mode != SessionMode.hand &&
        d.mode != SessionMode.biffle) {
      return d;
    }
    final lastFrom = _lastFrom;
    final lastTo = _lastTo;
    final exactSameAsLast = lastFrom != null &&
        lastTo != null &&
        d.from == lastFrom &&
        d.to == lastTo;
    // Le détecteur fenêtre 3 ne déclenche que si on a déjà 3 émissions
    // rythmées en buffer. Tant qu'il n'y en a pas (début de session), on
    // s'appuie uniquement sur le check classique sur le step précédent.
    final flatPattern = _isFlatRhythmicPattern(d);
    if (!exactSameAsLast && !flatPattern) return d;
    // Même amplitude que le step précédent OU pattern plat sur 3 steps :
    // on décale `to` d'un cran.
    final toIdx = d.to?.index;
    if (toIdx == null) return d;
    final ceil =
        d.mode == SessionMode.rhythm ? _milestoneRhythmCeilingIdx() : 4;
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
        return _StepDraft(
          mode: d.mode,
          bpm: d.bpm,
          from: Position.values[fromIdx - 1],
          to: d.to,
          duration: d.duration,
        );
      }
      return d;
    }
    return _StepDraft(
      mode: d.mode,
      bpm: d.bpm,
      from: d.from,
      to: Position.values[newToIdx],
      duration: d.duration,
    );
  }

  // _diversifyBpm, _diversifyLongSegment, _maybeApplyBpmRamp,
  // _capRhythmDurationByPulses (statique) ont migré dans
  // `career_session_generator_bpm.dart` (`_BpmPacing`). Les sites d'appel
  // passent directement par cette classe, sauf _capRhythmDurationByPulses
  // qui garde un adaptateur d'instance plus haut pour injecter
  // `_humiliationCareer` et les points de spé.

  /// Convertit un [_StepDraft] interne en [SessionStep] sérialisable.
  /// Pour les modes hold/beg, swap `from` (position cible interne au draft)
  /// vers `to` côté SessionStep — sémantique « on tient jusqu'à cette
  /// position ». Convention uniforme : hold/beg portent leur position dans
  /// `to`, les autres modes (rhythm/lick/hand/biffle) utilisent from→to
  /// pour l'alternance. Plus de swap, le draft interne et le SessionStep
  /// produit utilisent la même convention.
  SessionStep _draftToStep(_StepDraft draft,
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

  /// Catégorise le draft retenu par `_pickFinal` pour piocher la bonne
  /// variante de `finale_chime` côté `BeepEngine`. Mapping :
  /// - hand any, hold tip → easy
  /// - hold head, hold mid, biffle → medium
  /// - hold throat → hard
  /// - hold full → extreme
  /// Cas non couverts (ne devraient pas survenir vu les options de
  /// `_pickFinal`) → `medium` par défaut.
  FinalCategory _categorizeFinal(_StepDraft d) {
    if (d.mode == SessionMode.hand) return FinalCategory.easy;
    if (d.mode == SessionMode.biffle) return FinalCategory.medium;
    if (d.mode == SessionMode.hold) {
      switch (d.to) {
        case Position.tip:
          return FinalCategory.easy;
        case Position.head:
        case Position.mid:
          return FinalCategory.medium;
        case Position.throat:
          return FinalCategory.hard;
        case Position.full:
          return FinalCategory.extreme;
        case Position.balls:
          // Très humiliant (sloppy + soumis) mais sans la composante
          // apnée/asphyxie de full → palier `hard`, pas `extreme`.
          return FinalCategory.hard;
        case null:
          return FinalCategory.medium;
      }
    }
    return FinalCategory.medium;
  }

  /// Retourne l'`UnlockKey` requise pour jouer [draft], `null` si l'action
  /// est libre par défaut. Le mapping se base sur les milestones existantes
  /// (cf. `assets/career/milestones.json`).
  // _unlockKeyFor, _stepDownOne, _lubricationCapDelta, _deepestOf et
  // _isUnlocked + _finalUnlocked vivent désormais dans
  // `career_session_generator_humiliation.dart` (`_HumiliationGates`).
  // Adaptateurs d'instance pour ceux qui restent appelés directement :

  /// Adaptateurs d'instance pour `_HumiliationGates` : injectent
  /// `_anatomy`, `_unlockedKeys` et la projection salive `_salivaSim.value`
  /// pour garder les call sites brefs (un seul argument au lieu de quatre).
  bool _isUnlocked(_StepDraft d) => _HumiliationGates.isUnlocked(
        d,
        anatomy: _anatomy,
        unlockedKeys: _unlockedKeys,
      );

  // `_finalUnlocked` n'est plus appelé depuis l'instance (consommé par
  // `_FinalPicker` qui appelle directement `_HumiliationGates.finalUnlocked`).
  // Plus d'adaptateur ici.

  /// Adaptateur d'instance pour `_HumiliationGates.enforceRequired` : injecte
  /// `_anatomy`, `_unlockedKeys`, la salive courante, et le callback de
  /// clamp capacité (qui reste sur l'instance car il consulte `_capProfile`).
  _StepDraft _enforceHumiliationRequired(_StepDraft draft, double available) =>
      _HumiliationGates.enforceRequired(
        draft,
        available,
        clampToCapability: _clampToCapability,
        anatomy: _anatomy,
        unlockedKeys: _unlockedKeys,
        saliva: _salivaSim.value,
      );

  /// Retire `_lastMode` des candidats si une alternative existe et que le
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
  /// `_lastMode`.
  List<SessionMode> _filterRepeated(List<SessionMode> candidates) =>
      _ModePicker.filterRepeated(candidates, _lastMode);

  /// Tire une phrase pour [mode]/[tier] en évitant la même qu'au step
  /// précédent (`_lastText`). Quelques essais suffisent : si la banque ne
  /// contient qu'une seule entrée pour ce couple, on accepte la répétition.
  ///
  /// Si [context] est fourni, le filtrage par contraintes de la
  /// [PhraseEntry] est appliqué (profondeur min/max, BPM min/max). Pour
  /// les call sites qui manipulent un `_StepDraft`, utiliser
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
      if (phrase.isEmpty || phrase != _lastText) return phrase;
    }
    return bank.pickFor(mode, effectiveTier, _rng, context: context);
  }

  /// Variante de [_pickPhrase] qui extrait le contexte (profondeur, BPM)
  /// depuis un draft de step. Permet aux phrases tier d'être filtrées par
  /// les contraintes (« nez collé » réservé à `to=full`, « respire par le
  /// nez » réservé à `to ≤ mid`, etc.).
  String _pickPhraseForDraft(
    PhraseBank bank,
    _StepDraft draft,
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

  /// Bump conditionnel d'un tier de phrase selon `_obedience`. Cf. doc
  /// de `_pickPhrase`. Ne touche pas aux tiers `boost`/`finale`.
  String _bumpTierByObedience(String tier) {
    if (tier == 'boost' || tier == 'finale') return tier;
    final obed = _obedience;
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

/// Cluster sémantique d'un step, utilisé pour assurer la cohérence de
/// la séance : on doit rester plusieurs steps consécutifs sur le même
/// type avant d'en changer (sauf `transit` qui est une parenthèse
/// transparente : breath de récup, freestyle).
///
/// - `bouche` (rhythm, hold, beg-non-libre) : cœur de l'app, on y
///   passe la majorité du temps.
/// - `langue` (lick) : variante douce, intros et transitions.
/// - `libreMain` (hand, biffle, beg-libre) : la bouche est libre, la
///   stim vient de la main / d'un coup / d'une supplique vocale pure.
/// - `transit` (breath, freestyle) : pause neutre, ne casse pas la
///   continuité du type courant.
enum _StepType { bouche, langue, libreMain, transit }

/// Snapshot léger d'un step rythmé déjà émis, conservé dans le buffer
/// roulant `_recentEmits`. Sert à `_isFlatRhythmicPattern` pour détecter
/// une monotonie sur fenêtre 3 (mêmes mode + to + BPMs proches).
typedef _RecentEmit = ({
  SessionMode mode,
  Position? from,
  Position? to,
  int? bpm,
});

/// Classe un step (mode + position éventuelle) en `_StepType`. La
/// position est nécessaire pour `beg` : un beg avec `to` tenu = la
/// bouche reste sur la verge pendant la supplique → `bouche` ; un
/// beg libre (sans `to`) = supplique purement vocale → `libreMain`.
_StepType _classifyStep(SessionMode mode, Position? to) {
  switch (mode) {
    case SessionMode.rhythm:
    case SessionMode.hold:
      return _StepType.bouche;
    case SessionMode.lick:
      return _StepType.langue;
    case SessionMode.hand:
    case SessionMode.biffle:
      return _StepType.libreMain;
    case SessionMode.beg:
      return to == null ? _StepType.libreMain : _StepType.bouche;
    case SessionMode.breath:
    case SessionMode.freestyle:
      return _StepType.transit;
    case SessionMode.suckle:
      // Aspiration : bouche au contact (head ou balls). On classe comme
      // `bouche` pour bénéficier de la même friction de continuité que
      // hold/beg-tenu — éviter d'enchaîner deux modes bouche sans pause.
      return _StepType.bouche;
  }
}

/// Brouillon de step interne au générateur, avant matérialisation en
/// `SessionStep` (il manque `time` et `text` qui sont décidés au push).
class _StepDraft {
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
  final _StepDraft? chainNext;

  const _StepDraft({
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

/// Composition de punition carrière (Phase 5). Tuple
/// `(id, drafts, reqHumil, handRequired)` qui mime la palette de `_pickFinal`
/// — drafts non-clampés (le clamp se fait au moment de la matérialisation
/// via `_materializePunishment`).
class _PunishmentCompo {
  final String id;
  final List<_StepDraft> drafts;
  final double reqHumil;

  /// Si vrai, la compo est exclue quand `includeHand == false` (compo qui
  /// implique la main, comme `biffle_burst`).
  final bool handRequired;

  const _PunishmentCompo({
    required this.id,
    required this.drafts,
    required this.reqHumil,
    this.handRequired = false,
  });
}

/// Bundle des paramètres « figés pour la session » consommés par les helpers
/// de phase de [CareerSessionGenerator.generate]. Construit une seule fois
/// au début de l'appel après que tous les paramètres dérivés sont calculés
/// (`effectiveDuration`, `intensityFloor`, `boostsCount`, `genUntil`, `isLowLevel`,
/// `useFinalMilestone`…).
///
/// Évite de répéter les mêmes 6-8 args (`cfg`, `bank`, `effectiveDuration`,
/// `level`, `encoreChainIndex`, `steps`, `profile`…) dans la signature de
/// chaque helper. Les helpers piochent ce dont ils ont besoin via `ctx.x`.
///
/// **Pas inclus** : le curseur live `(time, stamina)`. Ces deux scalaires
/// sont threadés via record return values pour séparer ce qui est *fixé*
/// (ctx) de ce qui *évolue à chaque step* (cursor).
///
/// **Mutables internes** : [steps] et [profile] sont des `List` mutées en
/// place par les helpers. Le DTO les expose comme `final` (la référence
/// liste ne change pas), mais le contenu est l'accumulateur de la séance.
class _GenContext {
  final List<SessionStep> steps;
  final List<double> profile;

  final int level;
  final int encoreChainIndex;
  final int effectiveDuration;
  final int boostsCount;
  final int genUntil;
  final double intensityFloor;
  final double obedience;
  final bool quickie;
  final bool intense;
  final bool includeHand;
  final bool isLowLevel;
  final bool useFinalMilestone;
  final bool noStats;
  final CareerLevel cfg;
  final PhraseBank bank;
  final String? sessionName;
  final String? sessionNameQuickie;
  final String? Function(String milestoneId, int stepTime)?
      milestoneTextResolver;
  final List<LevelMilestone> insertedBodies;
  final LevelMilestone? finalMilestone;

  const _GenContext({
    required this.steps,
    required this.profile,
    required this.level,
    required this.encoreChainIndex,
    required this.effectiveDuration,
    required this.boostsCount,
    required this.genUntil,
    required this.intensityFloor,
    required this.obedience,
    required this.quickie,
    required this.intense,
    required this.includeHand,
    required this.isLowLevel,
    required this.useFinalMilestone,
    required this.noStats,
    required this.cfg,
    required this.bank,
    required this.sessionName,
    required this.sessionNameQuickie,
    required this.milestoneTextResolver,
    required this.insertedBodies,
    required this.finalMilestone,
  });
}

/// État mutable d'une milestone body en attente d'insertion dans la séance.
/// Le générateur traite `pending` dans l'ordre — chaque insertion repousse
/// la `minInsert` de la suivante pour conserver un buffer ≥ 60 s.
class _PendingMilestoneInsert {
  final LevelMilestone milestone;
  int minInsert;
  int maxInsert;
  int targetTime;
  bool inserted = false;

  _PendingMilestoneInsert({
    required this.milestone,
    required this.minInsert,
    required this.maxInsert,
    required this.targetTime,
  });
}
