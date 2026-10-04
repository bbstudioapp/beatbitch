import 'dart:math';

import '../../models/session_step.dart';
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import '../models/session_length_choice.dart';

/// Gates et seuils level-based de la génération de séance.
///
/// Phase 19.2 — extracts purs, sortie identique aux expressions inline
/// d'origine. Les noms reflètent l'**intention métier** pour guider le
/// rewire Phase 19.6 (où ces helpers consommeront `(CapabilityProfile,
/// sessionsCompleted, SessionLengthChoice)` au lieu de `level`).
///
/// Aucun helper ici ne touche au RNG ni à l'état — pure dérivation.
class CareerLevelGates {
  const CareerLevelGates._();

  /// Vrai pour les sessions « débutante » (level 1-2) hors bâclée / intense.
  /// Influe sur la pré-finition (raccourcie) et le pacing global.
  static bool isLowLevelIntro({
    required int level,
    required bool quickie,
    required bool intense,
  }) =>
      level <= 2 && !quickie && !intense;

  /// Vrai au-dessus du seuil d'éligibilité aux mini-vagues mid-session
  /// (cf. `_shouldEmitMiniWave`). En dessous, la diagonale d'intensité
  /// reste monotone du début au finish.
  ///
  /// Phase 19.9 : la mini-vague est désormais gated par le palier de
  /// durée — autorisée uniquement sur `moyenne` et `longue` (les
  /// séances avec assez de marge pour insérer la vague + sa pause longue
  /// post-vague). Le synthLevel (= sessions/2 + 1) reste consulté pour
  /// la pédagogie : pas de mini-vague avant 8 sessions (synthLevel < 5),
  /// la dramaturgie monotone reste la norme pour la débutante.
  ///
  /// Quand `lengthChoice` est null (Custom, debug), seul le synthLevel
  /// est consulté — comportement legacy de Phase 19.2.
  static bool isMiniWaveEligible({
    required int level,
    SessionLengthChoice? lengthChoice,
  }) {
    if (level < 5) return false;
    if (lengthChoice == null) return true;
    return lengthChoice == SessionLengthChoice.moyenne ||
        lengthChoice == SessionLengthChoice.longue;
  }

  /// Vrai quand la palette finale peut basculer sur la coloration spé
  /// (sloppy / obéissance) — au-delà, la dramaturgie tient.
  static bool canColorFinalBySpec(int level) => level >= 7;

  /// Vrai pour les premiers niveaux où le finish hand a une baseline BPM
  /// dédiée (40-60 BPM, sample-friendly pour une débutante).
  static bool usesShortHandFinalBaseline(int level) => level < 4;

  /// Coefficient « preferHandBase » du burst pré-finish : élevé en bas
  /// niveau peu humiliant (favorise hand neutre), réduit ensuite.
  static double burstHandPreference({
    required int level,
    required double humiliationCareer,
  }) =>
      humiliationCareer < 5 && level <= 3 ? 0.70 : 0.25;

  /// Bonus de BPM cap appliqué aux boosts finish, scale par niveau +
  /// chaîne d'encore + escalade explicite (Supplier/Encore). Capé pour
  /// éviter les pics absurdes — le profil de capacités borne en pratique
  /// via `clampToCapability`. Le bonus `intense` (+15) traduit le bouton
  /// d'escalade sur le sprint final : ~équivalent de +3.75 niveaux d'un
  /// coup quand la joueuse a réclamé plus dur.
  static int finishBpmBoostBpm({
    required int level,
    required int encoreChainIndex,
    bool intense = false,
  }) =>
      ((level - 1) * 4 + max(0, encoreChainIndex) * 8 + (intense ? 15 : 0))
          .clamp(0, 70);

  /// Plafond de profondeur (index dans `Position.values`) par défaut pour
  /// une `SessionConfig` quand aucun profil de capacités n'est fourni
  /// (Custom mode, debug, surprise router). Full ouvert — la difficulté
  /// effective est gated en aval par `_clampToCapability` quand un
  /// profil est dispo.
  static int defaultMaxDepthIndex() => Position.full.index;

  /// Plafond de profondeur dérivé du `CapabilityProfile` (Phase 19.7).
  /// Lit `rhythm.depth_max.comfort` (en cran, double), l'arrondit, ajoute
  /// **un cran de sonde** tant que le `best` prouvé est plus profond, et
  /// borne le tout dans `[mid, full]`.
  ///
  /// Plancher à `mid` (= idx 2) : les basics enseignent déjà la
  /// progression jusqu'à `mid` (cf. `intro_deeper_basics`, `intro_hold_mid`,
  /// `intro_biffle`… tous des `rhythm head→mid`). Une session 2 qui
  /// retombe à `tip/head` parce que la session 1 n'a pas réussi à pousser
  /// `rhythm.depth_max` au-delà de `head` (fail, step trop court, …) est
  /// régressive : on serait pédagogiquement plus bas que ce que les
  /// basics couvrent. Plafond à `full` (= idx 4) : on n'autorise pas
  /// `balls` via ce mécanisme — l'anatomie balls a son propre gating.
  ///
  /// Quand le profil ne porte pas encore de donnée pour cet axe
  /// (joueuse neuve, axe jamais sollicité), on retombe sur
  /// [defaultMaxDepthIndex] (= full ouvert) — `_clampToCapability` côté
  /// générateur évite que le tirage déborde, le profil se remplira sur
  /// les premières séances.
  /// Chantier aimant (2026-08-20) : niveau de carrière à partir duquel
  /// l'ancre du geste rythmé peut se poser sur `to` plutôt que rester
  /// systématiquement sur `from`. Aucun seuil n'a été chiffré par Manu
  /// (« de base les from, mais sur les niveaux plus élevés sur les to ») —
  /// valeur interprétée, à valider par lui. Cf. rapport
  /// chantier-aimant-étape-3.
  static const int rhythmAnchorToFloorLevel = 10;

  /// Allers-retours pendant une tenue (cf. `HoldMove`) : à partir de ce
  /// niveau, une tenue d'au moins [holdMovesMinDuration] s en reçoit avec la
  /// probabilité [holdMovesProbability] ; un de plus par tranche de
  /// [holdMovesSecondsPerExtra] s ; vers `full` dans
  /// [holdMovesDownProbability] des cas quand la capacité le permet.
  static const int holdMovesFloorLevel = 5;
  static const int holdMovesMinDuration = 6;
  static const int holdMovesSecondsPerExtra = 8;
  static const double holdMovesProbability = 0.5;
  static const double holdMovesDownProbability = 1 / 3;

  /// Sinon, rafale de micro-mouvements avec la probabilité
  /// [holdMicroProbability], de [holdMicroMinBurst] à [holdMicroMaxBurst] s.
  static const double holdMicroProbability = 0.3;
  static const int holdMicroMinBurst = 3;
  static const int holdMicroMaxBurst = 6;

  /// Force par défaut de l'aimant rythmé — schéma 3:1 de Manu (intervalle
  /// 1,5T sur la position ancrée, 0,5T sur l'autre).
  static const int rhythmAnchorDefaultRatio = 3;

  /// BPM à partir duquel un step rythmé généré compte comme « difficile
  /// dans l'instant » pour la bascule d'ancre au-dessus du plancher —
  /// milieu de la plage `[60,140]` tirée par `RhythmRules.build`.
  static const int rhythmAnchorHarderBpmThreshold = 100;

  /// Décide l'ancrage d'un step rythmé généré. Sous
  /// [rhythmAnchorToFloorLevel], l'ancre reste toujours `from`. Au-dessus,
  /// elle bascule sur `to` pour les steps dont le bpm dépasse
  /// [rhythmAnchorHarderBpmThreshold] (proxy de la difficulté du moment
  /// dans la séance) — donc elle alterne d'un step à l'autre au sein d'une
  /// même séance. Interprétation de la consigne de Manu, cf. rapport
  /// chantier-aimant-étape-3 : les deux conditions cumulées (plancher +
  /// alternance par difficulté) ne sont pas sa parole telle quelle.
  static BeatAnchor rhythmAnchorFor({required int level, required int? bpm}) {
    if (level < rhythmAnchorToFloorLevel) return BeatAnchor.from;
    return (bpm ?? 0) >= rhythmAnchorHarderBpmThreshold
        ? BeatAnchor.to
        : BeatAnchor.from;
  }

  /// Force de l'aimant du final `hold` ancré (chantier aimant étape 4,
  /// 2026-08-21) — Manu : « ok très dur dans ce cas ». Reprend telle quelle
  /// l'illustration montrée à Manu à 60 bpm (~1,8 s sur l'ancre, ~0,2 s sur
  /// l'autre ⇒ 9:1) : le chiffre n'a pas été validé à l'oreille, cf. rapport.
  static const int holdFinalAnchorRatio = 9;

  /// BPM qui cadence les allers-retours du final `hold` ancré — repris de
  /// la même illustration que [holdFinalAnchorRatio], pas confirmé comme
  /// valeur de production.
  static const int holdFinalAnchorBpm = 60;

  /// Vrai quand le final `hold` de la séance peut recevoir l'ancrage « très
  /// dur » sur `to` (chantier aimant étape 4). Réutilise le même plancher
  /// que [rhythmAnchorToFloorLevel] plutôt qu'un nouveau chiffre : Manu n'a
  /// jamais levé la restriction « l'ancrage au fond » pour les profils
  /// débutants, et c'est la même restriction ici — le final n'est qu'une
  /// deuxième source qui la déclenche. Faux quand [to] est `tip` (index 0) :
  /// il n'existe pas de position plus aiguë pour l'aller-retour.
  static bool holdFinalAnchorEligible({
    required int level,
    required Position? to,
  }) =>
      level >= rhythmAnchorToFloorLevel && to != null && to.index > 0;

  static int maxDepthIndexForProfile(CapabilityProfile? profile) {
    if (profile == null) return defaultMaxDepthIndex();
    final comfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (comfort == null) return defaultMaxDepthIndex();
    // Sonde vers le `best` prouvé : quand la profondeur déjà atteinte est plus
    // profonde que la cible courante (compétence rabaissée par un tap-out
    // imputé ou par le decay), on repropose **un cran** au-dessus du comfort.
    // Sans ça le tirage reste borné au comfort, donc `reached` ne dépasse
    // jamais `comfort`, donc le régulateur n'a jamais l'overshoot qui le ferait
    // remonter : descente facile, remontée verrouillée. Jamais au-delà du
    // `best` — on ne sonde que du territoire déjà prouvé.
    //
    // Écrit en ternaire, et **pas** `min(rounded + 1, best.round())` : les
    // deux formules ne coïncident que tant que `best >= comfort`. Sur un
    // profil incohérent (`best < comfort`, atteignable par un import de
    // profil, qui écrit les deux clés sans passer par le régulateur), le
    // `min` rabaisserait le cap SOUS le comfort — l'inverse de ce qu'on
    // corrige. C'est le pendant du `max(comfort, …)` explicite de
    // `capability_clamps.dart`, ici porté par la forme. Le test `cap(3, 2)`
    // de `capability_depth_comfort_vs_best_test.dart` sépare les deux.
    final rounded = comfort.round();
    final best = profile.bestOf(CapabilityAxis.rhythmDepthMax) ?? comfort;
    final probe = best.round() > rounded ? rounded + 1 : rounded;
    return probe.clamp(Position.mid.index, Position.full.index);
  }
}
