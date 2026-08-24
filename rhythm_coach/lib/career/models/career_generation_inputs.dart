// Value objects regroupant les paramètres cohérents passés à
// `CareerSessionGenerator.generate()` / `.generatePunishment()`.
//
// Avant ce regroupement, `generate()` exposait 27 named params, dont 3
// grappes thématiques qui voyageaient toujours ensemble selon le
// scénario d'appel :
//
//   * **Custom mode** (5 params null/false par défaut) — l'éditeur
//     Custom les pousse tous, la carrière n'en pousse aucun.
//   * **Milestone plan** (3 params) — `career_screen._start` et le
//     retry pédagogique les poussent ; les autres callers les omettent
//     tous.
//   * **Capability inputs** (2-3 params) — `career_screen.*` et
//     `generatePunishment` les poussent ensemble ; tests carrière
//     idem ; Custom / scénarios JSON / surprise router les omettent.
//
// Bundler ces grappes :
//   - Réduit la signature de `generate()` (27 → 17 named params).
//   - Rend explicite au call site dans quel scénario on est (« Custom »
//     vs « Carrière » vs « surprise »).
//   - Donne un point unique de doc pour chaque grappe (un seul
//     `///` à mettre à jour pour les commentaires).
//
// Les bundles sont **publics** parce qu'ils traversent la frontière
// `lib/career/screens` → `lib/career/services`. Les types qu'ils
// référencent (`CapabilityProfile`, `CapabilityAxis`, `LevelMilestone`)
// vivent déjà ailleurs ; on ne les redéfinit pas.
//
// Tous trois exposent un `const X.none` ou équivalent pour les call
// sites « scénario par défaut » (carrière de base, surprise router,
// tests minimaux).

import '../../models/session_step.dart' show BeatAnchor;
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import 'level_milestone.dart';

/// Helper interne : trie `(min, max)` d'une plage utilisateur (l'éditeur
/// Custom n'empêche pas l'utilisatrice de poser min > max). Renvoie
/// `null` si l'entrée l'est. Partagé par les getters normalisés de
/// [CustomOverrides].
(int, int)? _sortPair((int, int)? raw) {
  if (raw == null) return null;
  var (lo, hi) = raw;
  if (lo > hi) {
    final tmp = lo;
    lo = hi;
    hi = tmp;
  }
  return (lo, hi);
}

/// Surcharges propres au mode **Custom** (et utilisées par certains
/// scénarios de tests). Tous null / false par défaut = mode carrière
/// standard, aucune contrainte custom appliquée. L'éditeur Custom
/// (`custom_mode_screen.dart`) pousse les 5 champs simultanément.
///
/// Sémantique des champs : cf. doc inline. Ces overrides s'appliquent
/// **par-dessus** les valeurs par défaut du générateur (profondeur max =
/// full, plancher de difficulté `quickie`/`intense`, etc.) — ils ne les
/// remplacent que quand non-null.
class CustomOverrides {
  /// Plancher de difficulté appliqué au tirage dès le début de séance
  /// (prime sur la valeur dérivée de `quickie`/`intense`).
  final double? intensityFloor;

  /// Plafond de profondeur (index `Position`) qui prime sur le défaut
  /// `full` du générateur. Permet au mode custom de borner rhythm/hold
  /// sans toucher au niveau virtuel.
  final int? maxDepthIndex;

  /// Bornes BPM utilisateur (mode Custom). Tuple `(min, max)`. Appliquées
  /// à la fin du bornage à tous les modes rythmés (rhythm / lick / biffle
  /// / hand). `null` = pas de bornage utilisateur (le générateur garde
  /// ses bornes dérivées du niveau).
  final (int, int)? bpmRange;

  /// Bornes de durée pour les steps tenus (hold + beg avec position),
  /// imposées par l'utilisateur (mode Custom). `null` = pas de bornage.
  final (int, int)? holdDurationRange;

  /// Aimant du geste rythmé imposé par la config Custom : `(point, ratio)`.
  /// `null` = aucune surcharge, le générateur garde l'ancrage qu'il dérive
  /// seul du niveau (comportement de toutes les séances d'avant ce
  /// réglage, carrière comme Custom). Non-null, il prime sur cette
  /// décision pour les steps `rhythm` et `hold` du corps de séance — la
  /// phase finish (boosts + final) garde la sienne.
  final (BeatAnchor, int)? anchor;

  /// Si true, la `Session` générée est marquée `noStats` → le
  /// `SessionController` n'écrit rien dans `StatsService`. Le mode
  /// Custom est un bac à sable et passe toujours `true` ici.
  final bool noStats;

  const CustomOverrides({
    this.intensityFloor,
    this.maxDepthIndex,
    this.bpmRange,
    this.holdDurationRange,
    this.anchor,
    this.noStats = false,
  });

  /// Aucune surcharge — comportement carrière standard.
  static const CustomOverrides none = CustomOverrides();

  /// Plage BPM normalisée : `(min, max)` réordonné si l'utilisatrice a
  /// posé min > max dans l'éditeur Custom. Le générateur consomme cette
  /// valeur — un range hors-bornes ne sera jamais atteint, c'est OK.
  (int, int)? get normalizedBpmRange => _sortPair(bpmRange);

  /// Plage durée hold normalisée : `(min, max)` réordonné + plancher à
  /// 1 s (un hold à 0 s n'a aucun sens — le step est consommé en un
  /// tick, ce serait juste un bip).
  (int, int)? get normalizedHoldDurationRange {
    final sorted = _sortPair(holdDurationRange);
    if (sorted == null) return null;
    var (lo, hi) = sorted;
    if (lo < 1) lo = 1;
    if (hi < 1) hi = 1;
    return (lo, hi);
  }
}

/// Plan d'insertion des milestones pédagogiques pour la séance courante.
/// `career_screen._start` pousse les 3 champs ; `_handleMilestoneRetry`
/// pousse `bodies` + `textResolver` (sans `finalMilestone`) ; les autres
/// callers omettent tout.
///
/// L'insertion effective est orchestrée par `_MilestoneScheduler` côté
/// générateur (cf. `career_session_generator_milestone_scheduler.dart`).
class MilestonePlan {
  /// Jusqu'à 2 milestones body insérées dans la fenêtre `[30 %, 65 %]`
  /// de la durée par défaut (surchargeable via les champs
  /// `insertAtMinSeconds` / `insertAtMaxSeconds` de chaque milestone).
  /// L'invariant `bodies.length ≤ 2` et le placement body sont validés
  /// par les asserts en tête de `generate()` (impossible de les placer
  /// dans ce constructeur const : `.placement` et `.every` ne sont pas
  /// const-evaluable, ce qui casserait `static const MilestonePlan.none`).
  final List<LevelMilestone> bodies;

  /// Milestone d'apothéose qui remplace l'enchaînement
  /// pré-finisher + boosts + final. `null` = phase finish standard
  /// (boosts générés + final tiré par `_FinalPicker`).
  final LevelMilestone? finalMilestone;

  /// Surcharge i18n des textes des steps de milestone. Reçoit
  /// `(milestone.id, step.time)` et retourne le texte localisé à
  /// utiliser, ou `null` pour retomber sur le `text` du JSON principal.
  final String? Function(String milestoneId, int stepTime)? textResolver;

  const MilestonePlan({
    this.bodies = const [],
    this.finalMilestone,
    this.textResolver,
  });

  /// Aucune milestone — séance standard (chauffe → finish).
  static const MilestonePlan none = MilestonePlan();
}

/// 2ᵉ enveloppe de difficulté (profil de capacités, carrière only).
/// Posé `none` pour les scénarios sans gating capacité (Custom,
/// scénarios JSON, surprise router, tests « profil neuf »). Pour la
/// carrière, `profile` est toujours fourni dès qu'il y a des données
/// persistées.
///
/// `overloadAxis` n'est consommé que par `generatePunishment` (la
/// session principale choisit son axe via `_pickOverload` en début de
/// `generate()` — le champ y est ignoré).
class CapabilityInputs {
  /// Profil persisté lu pour borner les steps : profondeur, BPM et durée
  /// ne dépassent pas le `comfort` (= `best` naïf en Phase 2) de chaque
  /// axe pilotant. `null` → aucun gating capacité.
  final CapabilityProfile? profile;

  /// Plafonds figés sur un FAIL de la session en cours (§6) — encore plus
  /// contraignants que `comfort` quand présents. Passés par les
  /// régénérations en cours de séance (Supplier / retry milestone) et le
  /// premier maillon d'un encore enchaîné via
  /// `SessionController.capabilitySessionCeilings`.
  final Map<CapabilityAxis, double> sessionCeilings;

  /// Axe de surcharge **imposé** pour la séance (consommé par
  /// `generatePunishment` uniquement — `generate()` en pioche un
  /// lui-même via `_pickOverload`). Le `SessionController` persiste
  /// l'axe choisi par `generate()` et le repasse à `generatePunishment`
  /// au moment du fail.
  final CapabilityAxis? overloadAxis;

  const CapabilityInputs({
    this.profile,
    this.sessionCeilings = const {},
    this.overloadAxis,
  });

  /// Aucune donnée capacité — pas de gating, le générateur ne consulte
  /// pas le profil. Default pour Custom / scénarios / tests neufs.
  static const CapabilityInputs none = CapabilityInputs();

  /// Facteur de surcharge imposé à l'axe [overloadAxis] : dérivé du
  /// `successRate` persisté via [CapabilityRegulator.surchargeFactor].
  /// Renvoie `1.0` (no-op) si l'axe ou le profil sont absents — c'est le
  /// cas par défaut côté `generate()` (qui choisit son axe + son facteur
  /// via `_pickOverload` et ignore donc ce getter).
  ///
  /// Consommé par `generatePunishment` pour honorer l'axe surchargé
  /// **imposé par la séance principale**, sans re-tirer un nouveau facteur.
  double get overloadFactor {
    final axis = overloadAxis;
    final p = profile;
    if (axis == null || p == null) return 1.0;
    return CapabilityRegulator.surchargeFactor(p.stateOf(axis).successRate);
  }
}
