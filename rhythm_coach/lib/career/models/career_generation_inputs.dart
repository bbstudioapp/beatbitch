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

import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import 'level_milestone.dart';

/// Surcharges propres au mode **Custom** (et utilisées par certains
/// scénarios de tests). Tous null / false par défaut = mode carrière
/// standard, aucune contrainte custom appliquée. L'éditeur Custom
/// (`custom_mode_screen.dart`) pousse les 5 champs simultanément.
///
/// Sémantique des champs : cf. doc inline. Ces overrides s'appliquent
/// **par-dessus** les valeurs dérivées du `CareerLevel` (`maxDepthIndex`
/// du niveau, plancher de difficulté `quickie`/`intense`, etc.) — ils
/// ne les remplacent que quand non-null.
class CustomOverrides {
  /// Plancher de difficulté appliqué au tirage dès le début de séance
  /// (prime sur la valeur dérivée de `quickie`/`intense`).
  final double? intensityFloor;

  /// Plafond de profondeur (index `Position`) qui prime sur celui du
  /// `CareerLevel`. Permet au mode custom de borner rhythm/hold sans
  /// toucher au niveau virtuel.
  final int? maxDepthIndex;

  /// Bornes BPM utilisateur (mode Custom). Tuple `(min, max)`. Appliquées
  /// à la fin du bornage à tous les modes rythmés (rhythm / lick / biffle
  /// / hand). `null` = pas de bornage utilisateur (le générateur garde
  /// ses bornes dérivées du niveau).
  final (int, int)? bpmRange;

  /// Bornes de durée pour les steps tenus (hold + beg avec position),
  /// imposées par l'utilisateur (mode Custom). `null` = pas de bornage.
  final (int, int)? holdDurationRange;

  /// Si true, la `Session` générée est marquée `noStats` → le
  /// `SessionController` n'écrit rien dans `StatsService`. Le mode
  /// Custom est un bac à sable et passe toujours `true` ici.
  final bool noStats;

  const CustomOverrides({
    this.intensityFloor,
    this.maxDepthIndex,
    this.bpmRange,
    this.holdDurationRange,
    this.noStats = false,
  });

  /// Aucune surcharge — comportement carrière standard.
  static const CustomOverrides none = CustomOverrides();
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
  /// L'invariant `bodies.length ≤ 2` est vérifié par un `assert` côté
  /// générateur.
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
}
