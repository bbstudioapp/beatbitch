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
enum ChallengePhase {
  /// Pas de défi actif (état par défaut).
  none,

  /// Breath du défi (~13 s) — annonce coach + boutons `PASSE` et `GO`
  /// visibles. La joueuse peut appuyer `GO` pour démarrer le défi tout
  /// de suite (le countdown 3-2-1 s'enclenche), ou laisser le breath se
  /// dérouler — le countdown se lance automatiquement à `breath - 3 s`.
  breath,

  /// Compte à rebours 3-2-1 (TTS + gros chiffre dans le banner). Pas de
  /// bouton. Dure 3 s. À la fin, transition automatique vers `live`.
  countdown,

  /// Défi en cours, avant `seuil - 3 s`. Aucun bouton défi visible.
  live,

  /// `seuil - 3 s` franchi → annonce d'extension dite, toujours pas de
  /// bouton (le seuil n'est pas encore atteint).
  preExtend,

  /// Seuil atteint → boutons `JE TIENS ENCORE` / `JE M'ARRÊTE` affichés,
  /// timer timeout 8 s armé.
  atSeuil,

  /// `JE TIENS ENCORE` pressé → mode ouvert, prolongation
  /// `max(10, comfort × 0.30)` s, re-prompt à expiration.
  openExtension,

  /// Défi terminé, outcome déjà appliqué.
  ended,
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

  /// BPM du step défi quand applicable (rhythm, biffle).
  final int? bpm;

  /// `comfort` de l'axe au moment de la calibration. Sert au calcul de la
  /// prolongation `max(10, comfort × 0.30)` et à l'imputation des outcomes.
  /// `null` si profil neuf (cas dégénéré géré par le tutoriel).
  final double? comfortAtCalibration;

  /// Vrai pour le premier défi de la joueuse — séquence scriptée avec
  /// tooltips et textes coach pédagogiques (flag `challenges.tutorial_seen`).
  final bool isTutorial;

  /// Vrai pour un défi **exploratoire** (Phase 2) — axe vierge sans
  /// `bestOf` connu, donc impossible de poser un seuil cible × 1.50.
  /// Conséquences sur la machine d'états (cf. `SessionController`) :
  /// - Pas de phase `preExtend` (« tu peux rester là si tu veux ») : on
  ///   passe directement de `live` à `atSeuil` au seuil initial estimé.
  /// - Le bouton FAIL pendant `live`/`preExtend` est traité comme
  ///   `JE M'ARRÊTE` (cf. spec § 4.4 — pas de notion d'échec puisque pas
  ///   de seuil cible).
  /// - Pas de bumps de base humil/obed +2 sur succès (cf. spec § 5.2) —
  ///   seules les extensions (+1 par « tient encore ») comptent.
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
    this.comfortAtCalibration,
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
  /// les axes durée, sinon une fenêtre fixe pour BPM/profondeur (le défi
  /// y est tenu sur une fenêtre d'observation).
  int get nominalDurationSeconds {
    return switch (kind) {
      ChallengeAxisKind.duration => targetThreshold,
      // Sur BPM et profondeur, on fixe une fenêtre d'observation : le défi
      // est tenu pendant cette fenêtre au paramètre demandé.
      ChallengeAxisKind.bpm => 30,
      ChallengeAxisKind.depthCran => 20,
    };
  }
}

/// Inputs liés au défi à passer à `CareerSessionGenerator.generate(...)`.
/// `ChallengeInputs.none` = aucun défi inséré (comportement carrière
/// standard).
class ChallengeInputs {
  /// Défi à insérer dans la séance (null = aucun).
  final Challenge? challenge;

  const ChallengeInputs({this.challenge});

  static const ChallengeInputs none = ChallengeInputs();

  bool get hasChallenge => challenge != null;
}
