/// Modèles du système de défis intra-séance (Phase 1).
///
/// Un défi est une surcharge opt-in (`challenges.enabled`) insérée à ~60 %
/// de la séance, pilotée sur un axe de capacité unique surcoté à
/// `comfort × 1.50`. Trois voies de sortie :
/// - tap-out avant le seuil → fail défi (soft-cap × 0.92, successRate × 0.85)
/// - seuil atteint puis `JE M'ARRÊTE` ou timeout → succès net (+2/+2)
/// - seuil atteint + `JE TIENS ENCORE` × N → succès étendu (+ N × +1/+1)
///
/// Spec complète : doc local `~/beatbitch_challenges.md`.
library;

import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/capability_axis.dart';
import 'specialization.dart';

/// Type d'axe surchargé par le défi — détermine la forme du seuil.
enum ChallengeAxisKind {
  /// Seuil en secondes (hold streaks, motion streak, biffle streak, apnée…).
  duration,

  /// Seuil en BPM (rhythm.bpm_ceil.*, biffle.bpm_max).
  bpm,

  /// Seuil en cran de profondeur (index `Position` ciblé). Réservé à
  /// `CapabilityAxis.rhythmDepthMax`.
  depthCran,
}

/// Résultat final d'un défi — pose les bumps/malus à appliquer.
enum ChallengeOutcome {
  /// Tap-out avant le seuil cible. Soft-cap comfort `× 0.92`, successRate
  /// `× 0.85`. Pas de malus humil/obed.
  fail,

  /// Seuil atteint puis `JE M'ARRÊTE` ou timeout 8 s. Bumps de base
  /// (+2 humil, +2 obed, ratchet comfort, successRate += 0.15).
  netSuccess,

  /// Seuil atteint + 1 ou plusieurs `JE TIENS ENCORE`. Bumps de base
  /// + N × (+1 humil, +1 obed), `best` étendu au-delà du seuil cible.
  extendedSuccess,

  /// `PASSE` pressé pendant le breath de countdown. Malus obédiance -3,
  /// aucun signal capability (la joueuse n'a pas essayé).
  skipped,
}

/// Phase courante d'un défi en cours dans le `SessionController`. Pilote
/// l'affichage des boutons et les annonces coach.
///
/// Gameplay hold-to-keep : le démarrage et la fin du défi sont pilotés
/// par la présence du doigt (touch) ou de la touche espace (desktop) —
/// cf. `SessionController.onChallengeHoldStart/End`.
enum ChallengePhase {
  /// Pas de défi actif (état par défaut).
  none,

  /// Breath du défi — annonce coach + boutons `PASSE` (tap) et `GO`
  /// (hold-to-start) visibles. La joueuse maintient `GO` pour démarrer
  /// le countdown 3-2-1, ou tape `PASSE` pour skipper.
  breath,

  /// Compte à rebours 3-2-1 (TTS + gros chiffre dans le banner). Le
  /// doigt doit rester présent ; un release déclenche la tolérance puis
  /// retour `breath` (1ère fois) ou skip (2e fois). À la fin, transition
  /// automatique vers `live`.
  countdown,

  /// Défi en cours, doigt présent. La perte du doigt arme la tolérance
  /// de release ; si la tolérance expire = fail.
  live,

  /// Seuil atteint — le bouton change de couleur, le coach annonce que
  /// la joueuse peut relâcher ou continuer. Maintenir au-delà = +1
  /// extension par tranche `extensionSeconds`. Release = succès net ou
  /// étendu selon le nombre d'extensions accumulées.
  atSeuil,

  /// Défi terminé, outcome déjà appliqué.
  ended,
}

/// Mode d'input live d'un défi — détermine le geste qui pilote la machine
/// d'états pendant `countdown`/`live`/`atSeuil`.
///
/// Dérivé du mode du step défi (cf. `Challenge.inputMode`), pas stocké : la
/// ligne de partage « statique → hold, dynamique → tap » coïncide exactement
/// avec « mode hold vs autre mode ».
enum ChallengeInputMode {
  /// Le doigt reste présent sur l'écran toute la durée — geste congruent aux
  /// holds statiques (la joueuse est déjà immobile). Le relâchement EST le
  /// signal d'abandon (fail en `live`) ou de validation (succès en `atSeuil`).
  /// C'est le mode historique.
  hold,

  /// Tap `GO` pour démarrer (après le countdown le défi tourne sur sa propre
  /// horloge, sans présence du doigt), tap `STOP` plein largeur pour abandonner
  /// en `live` ou valider en `atSeuil`. Pour les défis dynamiques/longs
  /// (rythme, franchissement, biffle, endurance) où pinner le doigt entre en
  /// compétition avec l'acte physique.
  tapToggle,
}

/// Défi intra-séance immuable, généré par `ChallengeService` à partir du
/// profil de capacités et figé pour toute la durée de la séance. Le
/// `CareerSessionGenerator` consomme la calibration (mode, durée, BPM…)
/// pour matérialiser les steps ; le `SessionController` consomme les
/// méta-informations (seuil, axe, prolongation) pour piloter la machine
/// d'états live et appliquer les outcomes au `_finish`.
class Challenge {
  /// Axe de capacité surchargé pour ce défi.
  final CapabilityAxis axis;

  /// Forme du seuil ([ChallengeAxisKind]).
  final ChallengeAxisKind kind;

  /// Branche de spécialisation pilotant l'axe — sert à consommer la tête
  /// de la file showcase quand toutes les voies de fin matchent
  /// (cf. § 5.1 spec). `null` quand l'axe n'appartient à aucune branche
  /// (ex. axe pilotant via fallback `pickOverloadAxis`).
  final SpecializationBranch? branch;

  /// Seuil cible. Sémantique selon [kind] :
  /// - `duration` → secondes à tenir
  /// - `bpm` → BPM à tenir
  /// - `depthCran` → index `Position` cible (0..5)
  final int targetThreshold;

  /// Mode du step défi (hold / rhythm / biffle…).
  final SessionMode mode;

  /// Position d'ancrage du step défi (hold throat/full, rhythm from/to).
  final Position? from;

  /// Position de fin pour les modes rythmés.
  final Position? to;

  /// BPM du step défi quand applicable (rhythm, biffle). Pour les défis
  /// BPM en rampe (axes `rhythm.bpm_ceil.*` / `biffle.bpm_max`), c'est le
  /// BPM de **départ** — cf. [bpmEnd] pour le BPM d'arrivée.
  final int? bpm;

  /// BPM de **fin de rampe** pour les défis BPM. Le `BeepEngine`
  /// interpole linéairement entre [bpm] (départ) et [bpmEnd] (arrivée)
  /// sur la durée du step défi — cf. `SessionStep.bpmEnd`. La rampe
  /// matérialise le côté progressif du défi : on démarre doux (= comfort
  /// prouvé) et on monte jusqu'à la cible (× 1.50). `null` = pas de
  /// rampe (constant, ou axe non-BPM).
  final int? bpmEnd;

  /// `comfort` de l'axe au moment de la calibration. Sert au calcul de la
  /// prolongation `max(10, comfort × 0.30)` et à l'imputation des outcomes.
  /// `null` si profil neuf (cas dégénéré géré par le tutoriel).
  final double? comfortAtCalibration;

  /// Nombre de franchissements gorge à atteindre pour boucler le défi (=
  /// passer en phase `atSeuil`). Réservé aux défis « franchissement »
  /// (axes `rhythmBpmCeilThroat`, `rhythmBpmCeilFull`, `gorgeCrossingsBpm*`)
  /// dont la mesure naturelle est un compteur, pas une durée — la rampe
  /// BPM rend la durée nominale trompeuse (5 franchissements à 60 BPM ≠
  /// 5 franchissements à 169 BPM). Quand présent, la phase `live` bascule
  /// en `atSeuil` dès que le compteur atteint cette valeur, **ou** que la
  /// durée nominale est atteinte (fallback safety net). `null` pour les
  /// défis durée/profondeur ou rythme non-franchissement.
  final int? targetCrossings;

  /// Vrai pour le premier défi de la joueuse — séquence scriptée avec
  /// tooltips et textes coach pédagogiques (flag `challenges.tutorial_seen`).
  final bool isTutorial;

  /// Vrai pour un défi **exploratoire** (Phase 2) — axe vierge sans
  /// `bestOf` connu, donc impossible de poser un seuil cible × 1.50.
  /// Conséquences sur la machine d'états (cf. `SessionController`) :
  /// - Pas d'annonce coach « tu peux rester là si tu veux » à l'entrée
  ///   `atSeuil` (le seuil est estimé, pas prouvé — pas de cérémonie).
  /// - Pas de bumps de base humil/obed +2 sur succès (cf. spec § 5.2) —
  ///   seules les extensions (durée tenue / `extensionSeconds`) comptent.
  ///
  /// Le `targetThreshold` représente ici le **seuil initial estimé** par
  /// défaut sur l'axe (cf. [initialEstimateSecondsForAxis]) — sert
  /// uniquement à déclencher le premier prompt, pas un objectif.
  final bool isExploratory;

  const Challenge({
    required this.axis,
    required this.kind,
    required this.targetThreshold,
    required this.mode,
    this.branch,
    this.from,
    this.to,
    this.bpm,
    this.bpmEnd,
    this.comfortAtCalibration,
    this.targetCrossings,
    this.isTutorial = false,
    this.isExploratory = false,
  });

  /// Seuil initial estimé par axe pour un défi exploratoire — sert à
  /// déclencher le premier prompt « tu as tenu X, pousse encore ou
  /// arrête » (cf. spec § 3.2).
  ///
  /// Axes durée : 5 s pour hold/apnée/gorge engagement (palier débutante),
  /// 8 s pour biffleStreak, 30 s pour rhythmMotionStreak, 15 s par défaut.
  /// Axes BPM / profondeur : valeur de référence prudente
  /// (60 BPM, cran 1 = head).
  static int initialEstimateSecondsForAxis(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.holdFullStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
        return 5;
      case CapabilityAxis.biffleStreak:
        return 8;
      case CapabilityAxis.rhythmMotionStreak:
        return 30;
      case CapabilityAxis.effortNoBreathStreak:
      case CapabilityAxis.noswallowStreak:
        return 15;
      case CapabilityAxis.rhythmBpmCeilShallow:
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.rhythmBpmCeilFull:
      case CapabilityAxis.gorgeCrossingsBpmThroat:
      case CapabilityAxis.gorgeCrossingsBpmFull:
      case CapabilityAxis.biffleBpmMax:
        return 60; // BPM de référence prudente
      case CapabilityAxis.rhythmDepthMax:
        return 1; // cran `head` (prudent)
      default:
        return 15;
    }
  }

  /// Clé d'axe utilisée pour lookup dans `challengePhrases` côté coach
  /// (cf. `Coach.pickChallengePhrase`).
  String get axisStorageKey => axis.storageKey;

  /// Mode d'input live (cf. [ChallengeInputMode]). Dérivé du [mode] : les
  /// holds statiques gardent la tenue du doigt ; tout le reste (rythme,
  /// biffle, franchissement, endurance) passe en tap `GO`/`STOP`, où la tenue
  /// continue serait ergonomiquement coûteuse pendant un acte rapide.
  ChallengeInputMode get inputMode => mode == SessionMode.hold
      ? ChallengeInputMode.hold
      : ChallengeInputMode.tapToggle;

  /// Durée d'une prolongation « tient encore » en mode ouvert.
  /// Plancher 10 s, sinon `comfort × 0.30`. En exploratoire (`comfort`
  /// inconnu), on fallback sur le plancher 10 s (pas de proportion à
  /// dériver avant que la joueuse n'ait laissé un `best`).
  int get extensionSeconds {
    final c = comfortAtCalibration ?? 0;
    final v = (c * 0.30).round();
    return v < 10 ? 10 : v;
  }

  /// Durée nominale du step défi en secondes — équivaut au seuil cible pour
  /// les axes durée, sinon **par axe** pour BPM/profondeur. Le défi y est
  /// tenu sur une fenêtre d'observation calibrée selon l'effort physiologique
  /// réel : un défi `head→throat 60 BPM` (franchissement gorge) ne mobilise
  /// pas le même effort qu'un `head→mid 60 BPM` (peu profond), donc même
  /// fenêtre = mauvais design.
  ///
  /// Le défi reste **prouvable** : passé le seuil, la voie « JE TIENS ENCORE »
  /// laisse la joueuse continuer librement — pas besoin de fenêtre longue
  /// pour matérialiser l'exploit.
  int get nominalDurationSeconds {
    if (kind == ChallengeAxisKind.duration) return targetThreshold;
    return _nominalBpmOrDepthDurationFor(axis);
  }

  /// Table de durée nominale par axe pour les défis BPM/profondeur. Les axes
  /// durée n'y figurent pas (leur durée = `targetThreshold`).
  ///
  /// Logique des valeurs :
  /// - Bandes peu profondes / pas de pénétration : 20-25 s — la fatigue y
  ///   est progressive, un seuil trop court banaliserait le défi.
  /// - Bandes franchissant gorge / profondes : 7-12 s — le franchissement
  ///   est rapidement fatiguant ; au-dessus on bascule sur l'endurance que
  ///   `extendedSuccess` rémunère mieux.
  /// - Floors BPM (minimize) : équivalent à leur ceil, le défi y est de
  ///   tenir le rythme lent à profondeur donnée.
  /// - `rhythmDepthMax` (depthCran) : 12 s — fenêtre d'observation du cran
  ///   le plus profond tenu.
  /// - Fallback (axe BPM pilotant non listé, p. ex. nouvel axe ajouté) :
  ///   30 s. Volontairement long pour ne pas brutaliser un axe non calibré.
  static int _nominalBpmOrDepthDurationFor(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.rhythmBpmCeilShallow:
        return 25;
      case CapabilityAxis.rhythmBpmCeilThroat:
        return 8;
      case CapabilityAxis.rhythmBpmCeilFull:
        return 7;
      case CapabilityAxis.gorgeCrossingsBpmThroat:
        return 8;
      case CapabilityAxis.gorgeCrossingsBpmFull:
        return 7;
      case CapabilityAxis.biffleBpmMax:
        return 20;
      case CapabilityAxis.rhythmBpmFloorShallow:
        return 20;
      case CapabilityAxis.rhythmBpmFloorThroat:
        return 12;
      case CapabilityAxis.rhythmBpmFloorFull:
        return 8;
      case CapabilityAxis.rhythmDepthMax:
        return 12;
      default:
        return 30;
    }
  }
}

/// Inputs liés aux défis à passer à `CareerSessionGenerator.generate(...)`.
/// `ChallengeInputs.none` = aucun défi inséré (comportement carrière
/// standard).
///
/// Une séance peut désormais (Phase 19.5) porter plusieurs défis
/// intercalés — typiquement 1 pour les paliers courts, 2 pour la
/// longue. Le générateur les insère séquentiellement à des trigger
/// times distribués entre les milestones.
class ChallengeInputs {
  /// Liste ordonnée des défis à insérer (ordre = ordre d'insertion
  /// temporelle). Vide = aucun défi.
  final List<Challenge> challenges;

  const ChallengeInputs({this.challenges = const []});

  /// Sucre syntaxique pour un défi unique (cas le plus fréquent) —
  /// préserve la lisibilité des call sites historiques.
  factory ChallengeInputs.single(Challenge? challenge) => challenge == null
      ? ChallengeInputs.none
      : ChallengeInputs(challenges: [challenge]);

  static const ChallengeInputs none = ChallengeInputs();

  bool get hasChallenge => challenges.isNotEmpty;

  /// Compatibilité : le premier défi de la liste (ou null si vide).
  /// Utilisé par les call sites qui n'ont besoin que du défi principal.
  Challenge? get challenge => challenges.isEmpty ? null : challenges.first;
}
