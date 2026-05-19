/// Service du système de défis intra-séance (Phase 1).
///
/// Responsabilités :
/// - Persiste le toggle `challenges.enabled` (défaut false) et le flag
///   `challenges.tutorial_seen` (posé après le 1ᵉʳ défi terminé).
/// - Construit un `Challenge` à partir du profil de capacités + axe choisi
///   via cascade : (1) tête de la file showcase (TODO — branche
///   `feat/specialization-showcase-queue` pas mergée), (2) fallback
///   `CapabilityClamps.pickOverloadAxis` standard, étendu à un coefficient
///   `× 1.50` (vs `× 1.03-1.15` du ratchet normal).
/// - Mappe l'axe choisi vers un step défi concret (mode + position + BPM
///   + durée nominale).
///
/// Spec complète : doc local `~/beatbitch_challenges.md`.
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import '../models/challenge.dart';
import '../models/specialization.dart';
import 'generation/capability_clamps.dart';

/// Coefficient appliqué au `comfort` pour calibrer le seuil cible du défi
/// (durée et BPM). Volontairement plus haut que le ratchet standard
/// (`CapabilityRegulator.surchargeFactor` plafonne à 1.15) : le défi
/// **expose** la surcharge et la pousse à un palier mesurable.
const double kChallengeOverloadFactor = 1.50;

/// Plancher de durée pour la prolongation « tient encore » du mode ouvert,
/// en secondes (cf. spec § 3.1).
const int kChallengeExtensionFloorSeconds = 10;

/// Fraction du `comfort` utilisée pour calculer la prolongation (cf. spec).
const double kChallengeExtensionComfortFraction = 0.30;

/// Durée du seuil défi tutoriel sur axe robuste (hold throat 5 s).
const int kChallengeTutorialDurationSeconds = 5;

/// Service stateless de persistance du toggle/tutoriel + factory de défis.
/// Toutes les opérations de persistance lisent/écrivent `SharedPreferences`
/// (pas de cache local — alignement avec le pattern `StatsService`).
class ChallengeService {
  static const String keyEnabled = 'challenges.enabled';
  static const String keyTutorialSeen = 'challenges.tutorial_seen';

  /// `true` quand la joueuse a explicitement activé les défis dans
  /// `CareerScreen`. Défaut `false` (pour ne pas effrayer les nouvelles
  /// utilisatrices).
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyEnabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, value);
  }

  /// `true` une fois que le 1ᵉʳ défi (tutoriel scripté) a été terminé.
  /// Posé par `SessionController._finishChallenge(...)` à la fin du défi.
  Future<bool> tutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyTutorialSeen) ?? false;
  }

  Future<void> markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyTutorialSeen, true);
  }

  /// Reset les deux clés. Câblé au bouton reset du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyEnabled);
    await prefs.remove(keyTutorialSeen);
  }

  /// Construit un défi pour la séance ou retourne `null` si aucun axe
  /// candidat n'est éligible (cas dégénéré).
  ///
  /// [excludeAxes] : axes déjà couverts par des milestones insérées cette
  /// séance — exclus pour éviter l'empilement (cf. spec § 5.5).
  /// [isTutorial] : `true` au premier défi de la joueuse, force un défi
  /// scripté sur axe robuste (`holdThroatStreak` 5 s).
  Challenge? buildForSession({
    required CapabilityProfile? profile,
    required Map<CapabilityAxis, double> ceilings,
    required Set<CapabilityAxis> excludeAxes,
    required Random rng,
    required bool isTutorial,
  }) {
    if (isTutorial) {
      return _buildTutorialChallenge();
    }
    final axis = _pickAxis(
      profile: profile,
      ceilings: ceilings,
      excludeAxes: excludeAxes,
      rng: rng,
    );
    if (axis == null) return null;
    final comfort = profile?.comfortOf(axis);
    if (comfort == null) return null;
    return _buildChallenge(axis: axis, comfort: comfort);
  }

  /// Cascade d'axe (Phase 1 — sans showcase) :
  /// 1. **TODO** : `SpecializationService.peekShowcase()` (branche
  ///    `feat/specialization-showcase-queue`, pas mergée). Une fois mergée,
  ///    insérer ici la résolution branche → plus vieil axe pilotant.
  /// 2. Fallback : `CapabilityClamps.pickOverloadAxis` (standard Phase 3
  ///    capability profile).
  /// Les axes [excludeAxes] (déjà couverts par milestones) sont retirés du
  /// résultat — la cascade re-pioche si nécessaire.
  CapabilityAxis? _pickAxis({
    required CapabilityProfile? profile,
    required Map<CapabilityAxis, double> ceilings,
    required Set<CapabilityAxis> excludeAxes,
    required Random rng,
  }) {
    // Phase 1 sans cascade showcase : tirage standard.
    // Pour exclure les axes déjà couverts par milestones de la séance,
    // on les ajoute aux ceilings temporairement (pickOverloadAxis exclut
    // les axes figés par un ceiling — cf. capability_clamps.dart l.142).
    final virtualCeilings = <CapabilityAxis, double>{
      ...ceilings,
      for (final a in excludeAxes) a: 0.0,
    };
    final pick = CapabilityClamps.pickOverloadAxis(
      profile: profile,
      ceilings: virtualCeilings,
      rng: rng,
    );
    return pick.axis;
  }

  Challenge _buildTutorialChallenge() {
    return const Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: kChallengeTutorialDurationSeconds,
      mode: SessionMode.hold,
      from: Position.throat,
      to: Position.throat,
      branch: SpecializationBranch.endurance,
      comfortAtCalibration: 5.0,
      isTutorial: true,
    );
  }

  Challenge _buildChallenge({
    required CapabilityAxis axis,
    required double comfort,
  }) {
    final kind = _kindOf(axis);
    final threshold = _thresholdFor(kind, comfort);
    final mode = _modeOf(axis);
    final from = _fromOf(axis);
    final to = _toOf(axis);
    final bpm = kind == ChallengeAxisKind.bpm ? threshold : null;
    return Challenge(
      axis: axis,
      kind: kind,
      targetThreshold: threshold,
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      branch: branchOf(axis),
      comfortAtCalibration: comfort,
    );
  }

  /// Forme du seuil pour un axe — `duration`, `bpm` ou `depthCran`.
  static ChallengeAxisKind _kindOf(CapabilityAxis axis) {
    switch (axis.unit) {
      case CapabilityUnit.seconds:
        return ChallengeAxisKind.duration;
      case CapabilityUnit.bpm:
        return ChallengeAxisKind.bpm;
      case CapabilityUnit.depthCran:
        return ChallengeAxisKind.depthCran;
      case CapabilityUnit.count:
        // Aucun axe pilotant n'a unit=count (gorgeCrossingsLifetime est
        // `pilotant: false`), donc inatteignable depuis pickOverloadAxis.
        return ChallengeAxisKind.duration;
    }
  }

  /// Calibrage du seuil cible selon [kind]. `comfort × 1.50` pour durée et
  /// BPM ; `comfort + 1` cran pour profondeur (round(× 1.5) = +1 cran).
  static int _thresholdFor(ChallengeAxisKind kind, double comfort) {
    switch (kind) {
      case ChallengeAxisKind.duration:
        return (comfort * kChallengeOverloadFactor).round();
      case ChallengeAxisKind.bpm:
        return (comfort * kChallengeOverloadFactor).round();
      case ChallengeAxisKind.depthCran:
        // +1 cran (cf. spec § 3.1, profondeur = cran discret).
        return (comfort.round() + 1).clamp(0, Position.values.length - 1);
    }
  }

  /// Mode du step défi selon l'axe poussé.
  static SessionMode _modeOf(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.holdFullStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
        return SessionMode.hold;
      case CapabilityAxis.biffleStreak:
      case CapabilityAxis.biffleBpmMax:
        return SessionMode.biffle;
      case CapabilityAxis.rhythmBpmCeilShallow:
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.rhythmBpmCeilFull:
      case CapabilityAxis.rhythmDepthMax:
      case CapabilityAxis.rhythmMotionStreak:
      case CapabilityAxis.noswallowStreak:
      case CapabilityAxis.effortNoBreathStreak:
        return SessionMode.rhythm;
      default:
        return SessionMode.rhythm;
    }
  }

  /// Position de départ pour le step défi (pertinent pour hold/rhythm).
  static Position? _fromOf(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
      case CapabilityAxis.rhythmBpmCeilThroat:
        return Position.throat;
      case CapabilityAxis.holdFullStreak:
      case CapabilityAxis.rhythmBpmCeilFull:
        return Position.full;
      case CapabilityAxis.rhythmBpmCeilShallow:
        return Position.head;
      case CapabilityAxis.rhythmMotionStreak:
      case CapabilityAxis.rhythmDepthMax:
      case CapabilityAxis.effortNoBreathStreak:
      case CapabilityAxis.noswallowStreak:
        return Position.head;
      default:
        return null;
    }
  }

  /// Position d'arrivée pour les modes rythmés.
  static Position? _toOf(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.rhythmBpmCeilShallow:
        return Position.mid;
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.rhythmMotionStreak:
        return Position.throat;
      case CapabilityAxis.rhythmBpmCeilFull:
        return Position.full;
      case CapabilityAxis.rhythmDepthMax:
      case CapabilityAxis.effortNoBreathStreak:
      case CapabilityAxis.noswallowStreak:
        return Position.throat;
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
        return Position.throat;
      case CapabilityAxis.holdFullStreak:
        return Position.full;
      default:
        return null;
    }
  }

  /// Mapping axe → branche pilotante (cf. spec § 5.1). `null` si aucune
  /// branche ne pilote l'axe — typique des axes obéissance (qui n'ont pas
  /// d'axe capability) ou de fallback `pickOverloadAxis` neutre.
  static SpecializationBranch? branchOf(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.rhythmDepthMax:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
        return SpecializationBranch.profondeur;
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.holdFullStreak:
      case CapabilityAxis.rhythmMotionStreak:
      case CapabilityAxis.effortNoBreathStreak:
        return SpecializationBranch.endurance;
      case CapabilityAxis.rhythmBpmCeilShallow:
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.rhythmBpmCeilFull:
      case CapabilityAxis.biffleStreak:
      case CapabilityAxis.biffleBpmMax:
        return SpecializationBranch.rythmeBiffle;
      case CapabilityAxis.noswallowStreak:
      case CapabilityAxis.gorgeCrossingsBpmThroat:
      case CapabilityAxis.gorgeCrossingsBpmFull:
        return SpecializationBranch.sloppy;
      default:
        return null;
    }
  }

  /// Construit le `SessionStep` matérialisant le défi (consommé par le
  /// générateur lors de l'insertion à 60 %).
  static SessionStep stepFor(Challenge ch, {required int time}) {
    return SessionStep(
      time: time,
      from: ch.from,
      to: ch.to,
      bpm: ch.bpm,
      duration: ch.nominalDurationSeconds,
      mode: ch.mode,
    );
  }
}
