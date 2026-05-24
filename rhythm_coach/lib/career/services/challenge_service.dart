/// Service du système de défis intra-séance (Phase 1).
///
/// Responsabilités :
/// - Persiste le toggle `challenges.enabled` (défaut true) et le flag
///   `challenges.tutorial_seen` (posé après le 1ᵉʳ défi terminé).
/// - Construit un `Challenge` à partir du profil de capacités + axe choisi
///   via cascade : (1) tête de la file showcase (TODO — branche
///   `feat/specialization-showcase-queue` pas mergée), (2) fallback
///   `CapabilityClamps.pickOverloadAxis` standard, étendu à un coefficient
///   `× 1.30` (vs `× 1.03-1.15` du ratchet normal). Cf.
///   `kChallengeOverloadFactor` plus bas pour le choix du facteur.
/// - Mappe l'axe choisi vers un step défi concret (mode + position + BPM
///   + durée nominale).
///
/// Spec complète : doc local `~/beatbitch_challenges.md`.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
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
///
/// `1.30` (et non `1.50`) : un facteur trop dur produit des sauts irréalistes
/// sur les axes franchissant gorge (`head→throat` × 1.5 BPM = injouable au
/// 1ᵉʳ non-tuto) et rend la cascade de défis successifs impossible à 2-3
/// itérations. À 1.30 le défi reste exigeant sans crasher la progression.
const double kChallengeOverloadFactor = 1.30;

/// Plancher de durée pour la prolongation « tient encore » du mode ouvert,
/// en secondes (cf. spec § 3.1).
const int kChallengeExtensionFloorSeconds = 10;

/// Fraction du `comfort` utilisée pour calculer la prolongation (cf. spec).
const double kChallengeExtensionComfortFraction = 0.30;

/// BPM de départ pour les défis BPM exploratoires (axe vierge, aucun
/// comfort prouvé). Démarrage doux qui amène progressivement à la cible
/// via la rampe — la joueuse découvre l'axe sans saut brutal.
const int kChallengeBpmRampStart = 50;

/// Durée du seuil défi tutoriel sur axe robuste (hold throat 5 s).
/// L'idée du premier défi : « est-ce que tu es capable de le faire ? ».
/// 5 s suffisent à prouver la capacité sans présumer du niveau de la
/// joueuse — le coach a le temps d'annoncer puis le seuil arrive vite,
/// et l'auto-bump d'humiliation à `HumiliationScale.requiredFor(hold,
/// throat, 5)` débloque toute la chaîne hold précédente.
const int kChallengeTutorialDurationSeconds = 5;

/// Axes « franchissement gorge » dont le défi se mesure naturellement en
/// nombre de passages de la barre gorge plutôt qu'en durée. Une rampe BPM
/// 60→169 sur un head→throat fait dériver la durée nécessaire d'un facteur
/// 2-3 selon l'allure, alors qu'un compteur « 5 franchissements » reste
/// stable et lisible pour la joueuse.
const Set<CapabilityAxis> kCrossingsChallengeAxes = {
  CapabilityAxis.rhythmBpmCeilThroat,
  CapabilityAxis.rhythmBpmCeilFull,
  CapabilityAxis.gorgeCrossingsBpmThroat,
  CapabilityAxis.gorgeCrossingsBpmFull,
};

/// Progression du nombre de franchissements visés selon le nombre de défis
/// déjà joués sur l'axe — formule fermée, pas de plafond :
/// `5 + n × (n + 5) / 2` (deltas 3, 4, 5, 6, …).
///
/// Échantillons : 0→5, 1→8, 2→12, 3→17, 4→23, 5→30, 10→80. Le 1er défi
/// reste très court (la joueuse découvre le système, cherche les boutons).
/// Les suivants montent crescendo, sans cap — un palier élevé reflète
/// une joueuse qui a déjà encaissé plusieurs défis du type.
int crossingsTargetForAttempts(int attempts) {
  if (attempts <= 0) return 5;
  return 5 + (attempts * (attempts + 5)) ~/ 2;
}

/// Service stateless de persistance du toggle/tutoriel + factory de défis.
/// Toutes les opérations de persistance lisent/écrivent `SharedPreferences`
/// (pas de cache local — alignement avec le pattern `StatsService`).
class ChallengeService {
  static const String keyEnabled = 'challenges.enabled';
  static const String keyTutorialSeen = 'challenges.tutorial_seen';
  static const String _kAttemptsPrefix = 'challenges.attempts.';

  /// `true` quand la joueuse a activé les défis dans `CareerScreen`.
  /// Défaut `true` : le tutoriel scripté au 1ᵉʳ défi (hold throat 5 s,
  /// tooltips et textes coach pédagogiques) absorbe le choc pour une
  /// joueuse qui découvre le système, et le fail défi est doux
  /// (soft-cap × 0.92, pas de flow punition). La joueuse peut désactiver
  /// le toggle dans `CareerScreen` à tout moment.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyEnabled) ?? true;
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

  /// Reset toutes les clés (toggle, tuto, compteurs d'essais par axe).
  /// Câblé au bouton reset du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyEnabled);
    await prefs.remove(keyTutorialSeen);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_kAttemptsPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// Nombre de défis déjà joués sur [axis] (tous outcomes confondus :
  /// success / fail / skip / timeout — un défi entamé compte, qu'il
  /// aboutisse ou pas). Sert à la calibration du nombre de franchissements
  /// visés (cf. [crossingsTargetForAttempts]).
  Future<int> attemptsCount(CapabilityAxis axis) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_kAttemptsPrefix${axis.storageKey}') ?? 0;
  }

  /// Incrémente le compteur d'essais sur [axis] (appelé à la fin de tout
  /// défi, peu importe l'outcome). Idempotence non garantie : un appel
  /// par défi terminé.
  Future<void> incrementAttempts(CapabilityAxis axis) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_kAttemptsPrefix${axis.storageKey}';
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  /// Construit un défi pour la séance ou retourne `null` si aucun axe
  /// candidat n'est éligible (cas dégénéré).
  ///
  /// [excludeAxes] : axes déjà couverts par des milestones insérées cette
  /// séance — exclus pour éviter l'empilement (cf. spec § 5.5).
  /// [isTutorial] : `true` au premier défi de la joueuse, force un défi
  /// scripté sur axe robuste (`holdThroatStreak` 5 s).
  Future<Challenge?> buildForSession({
    required CapabilityProfile? profile,
    required Map<CapabilityAxis, double> ceilings,
    required Set<CapabilityAxis> excludeAxes,
    required Random rng,
    required bool isTutorial,
    SpecializationBranch? showcaseBranch,
  }) async {
    if (isTutorial) {
      return _buildTutorialChallenge();
    }
    // Cascade showcase (spec § 5.1, étape 1) : si une branche est en
    // tête de file `SpecializationService.peekShowcase()`, on essaye de
    // honorer le point spé fraîchement dépensé en piochant un axe
    // pilotant de cette branche AVANT le tirage standard. Skip si
    // aucun axe candidat de la branche n'a un `comfort` prouvé
    // (l'exploratoire ne peut pas matérialiser un seuil cible — on
    // retombe alors sur le pickOverloadAxis standard puis l'exploratoire).
    if (showcaseBranch != null) {
      final axis = _pickAxisOfBranch(
        branch: showcaseBranch,
        profile: profile,
        excludeAxes: excludeAxes,
      );
      if (axis != null) {
        final comfort = profile!.comfortOf(axis)!;
        final crossings = await _resolveCrossingsTargetFor(axis);
        return _buildChallenge(
            axis: axis, comfort: comfort, targetCrossings: crossings);
      }
    }
    final axis = _pickAxis(
      profile: profile,
      ceilings: ceilings,
      excludeAxes: excludeAxes,
      rng: rng,
    );
    if (axis != null) {
      final comfort = profile?.comfortOf(axis);
      if (comfort != null) {
        final crossings = await _resolveCrossingsTargetFor(axis);
        return _buildChallenge(
            axis: axis, comfort: comfort, targetCrossings: crossings);
      }
    }
    // Phase 2 — fallback exploratoire : aucun axe candidat avec un
    // `comfort` prouvé (profil neuf ou toutes les ressources figées),
    // mais on peut peut-être amorcer un axe vierge. Cf. spec § 3.2.
    final exploratoryAxis = _pickExploratoryAxis(
      profile: profile,
      excludeAxes: excludeAxes,
      rng: rng,
    );
    if (exploratoryAxis == null) return null;
    final crossings = await _resolveCrossingsTargetFor(exploratoryAxis);
    return _buildExploratoryChallenge(
        axis: exploratoryAxis, targetCrossings: crossings);
  }

  /// Retourne le compteur de franchissements à viser pour [axis], ou `null`
  /// si l'axe n'est pas un axe « franchissement » (cf. [kCrossingsChallengeAxes]).
  /// La valeur dépend du nombre de défis déjà joués sur cet axe
  /// (progression {0:5, 1:8, 2:12, 3+:16}).
  Future<int?> _resolveCrossingsTargetFor(CapabilityAxis axis) async {
    if (!kCrossingsChallengeAxes.contains(axis)) return null;
    final attempts = await attemptsCount(axis);
    return crossingsTargetForAttempts(attempts);
  }

  /// Phase finale défis — sélectionne le plus ancien axe pilotant de la
  /// [branch] (`lastSeenSession` min) avec un `comfort` prouvé. Sert à
  /// honorer un point spé fraîchement dépensé en proposant un défi sur
  /// cette branche. Exclut les axes [excludeAxes] (milestones déjà
  /// insérées) pour éviter l'empilement. Retourne `null` si aucun axe
  /// candidat n'est éligible — le caller retombe alors sur le
  /// pickOverloadAxis standard.
  CapabilityAxis? _pickAxisOfBranch({
    required SpecializationBranch branch,
    required CapabilityProfile? profile,
    required Set<CapabilityAxis> excludeAxes,
  }) {
    if (profile == null) return null;
    final candidates = <CapabilityAxis>[
      for (final a in CapabilityClamps.overloadableAxes)
        if (branchOf(a) == branch &&
            !excludeAxes.contains(a) &&
            profile.comfortOf(a) != null)
          a,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => profile
        .stateOf(a)
        .lastSeenSession
        .compareTo(profile.stateOf(b).lastSeenSession));
    return candidates.first;
  }

  /// Phase 2 — sélection d'un axe exploratoire (sans `best` connu). Pioche
  /// parmi les axes pilotants `CapabilityClamps.overloadableAxes` qui :
  /// 1. N'ont pas de donnée (`bestOf(axis) == null`)
  /// 2. Ne sont pas dans `excludeAxes` (milestones déjà couvertes)
  ///
  /// La sélection est uniforme dans l'ensemble candidat — pas de
  /// hiérarchie : le générateur aurait sinon besoin de connaître le
  /// niveau de la joueuse pour pondérer, ce qui est hors scope V1.
  CapabilityAxis? _pickExploratoryAxis({
    required CapabilityProfile? profile,
    required Set<CapabilityAxis> excludeAxes,
    required Random rng,
  }) {
    final candidates = <CapabilityAxis>[
      for (final a in CapabilityClamps.overloadableAxes)
        if (!excludeAxes.contains(a) &&
            (profile == null || profile.bestOf(a) == null))
          a,
    ];
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Cascade d'axe (Phase 1 — étape 2 et au-delà ; l'étape 1 showcase est
  /// résolue plus haut dans `buildForSession`) :
  /// 1. (déjà tenté en amont) `SpecializationService.peekShowcase()` → axe
  ///    pilotant de la branche.
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

  /// Construit un défi exploratoire à partir d'un axe vierge. Le seuil
  /// vient de [Challenge.initialEstimateSecondsForAxis] (palier débutante
  /// par type d'axe). Pas de `comfortAtCalibration` (jamais prouvé).
  ///
  /// Pour les axes BPM exploratoires : rampe douce depuis `kChallengeBpmRampStart`
  /// (~50 BPM) jusqu'au seuil estimé — démarrage gentil pour découvrir.
  Challenge _buildExploratoryChallenge({
    required CapabilityAxis axis,
    int? targetCrossings,
  }) {
    final kind = _kindOf(axis);
    final threshold = Challenge.initialEstimateSecondsForAxis(axis);
    final mode = _modeOf(axis);
    final from = _fromOf(axis);
    final to = _toOf(axis);
    final isBpm = kind == ChallengeAxisKind.bpm;
    final bpm = isBpm ? kChallengeBpmRampStart : null;
    final bpmEnd = isBpm ? threshold : null;
    return Challenge(
      axis: axis,
      kind: kind,
      targetThreshold: threshold,
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      bpmEnd: bpmEnd,
      branch: branchOf(axis),
      targetCrossings: targetCrossings,
      isExploratory: true,
    );
  }

  /// Pour les axes BPM, le step défi est une **rampe** : on démarre à
  /// `bpm = round(comfort)` (= ce que la joueuse tient déjà confortablement)
  /// et on va jusqu'à `bpmEnd = targetThreshold` (= comfort × facteur sur
  /// `maximize`, comfort / facteur sur `minimize`) sur la durée du step.
  /// La durée est désormais **par axe** (cf. `Challenge._nominalBpmOrDepthDurationFor`)
  /// — typiquement 7-25 s selon la zone. Donne au défi sa qualité
  /// progressive : la joueuse sent le rythme dériver, pas un saut brutal.
  Challenge _buildChallenge({
    required CapabilityAxis axis,
    required double comfort,
    int? targetCrossings,
  }) {
    final kind = _kindOf(axis);
    final threshold = thresholdFor(kind, comfort, axis);
    final mode = _modeOf(axis);
    final from = _fromOf(axis);
    final to = _toOf(axis);
    final isBpm = kind == ChallengeAxisKind.bpm;
    final bpm = isBpm ? comfort.round() : null;
    final bpmEnd = isBpm ? threshold : null;
    return Challenge(
      axis: axis,
      kind: kind,
      targetThreshold: threshold,
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
      bpmEnd: bpmEnd,
      branch: branchOf(axis),
      comfortAtCalibration: comfort,
      targetCrossings: targetCrossings,
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

  /// Calibrage du seuil cible selon [kind] et le sens de l'axe.
  ///
  /// - Axe `maximize` (la plupart) : `comfort × kChallengeOverloadFactor`
  ///   pour durée et BPM ; `comfort + 1` cran pour profondeur.
  /// - Axe `minimize` (planchers BPM, dose mini breath) : surcharge =
  ///   atteindre une valeur **plus basse** → on divise par le facteur (BPM)
  ///   et on retire un cran (profondeur — théorique : aucun axe minimize
  ///   depthCran n'existe à ce jour). Plancher BPM à 18 (
  ///   `CapabilityRegulator.kBpmFloorPractical`) pour rester dans la zone
  ///   exploitable du `BeepEngine` / `CameraMotionDetector` [24..300].
  ///
  /// **Note** : en pratique, aucun axe `minimize` n'est aujourd'hui dans
  /// `CapabilityClamps.overloadableAxes` (les floors BPM / `breathMinDose`
  /// sont exclus côté générateur — rien ne les consomme). La branche
  /// minimize reste défensive : si un axe minimize est ajouté plus tard,
  /// le seuil ira dans le bon sens. Exposé via `@visibleForTesting` car
  /// inaccessible par `buildForSession` sans modifier `overloadableAxes`.
  @visibleForTesting
  static int thresholdFor(
    ChallengeAxisKind kind,
    double comfort,
    CapabilityAxis axis,
  ) {
    final isMinimize = axis.recordKind == CapabilityRecordKind.minimize;
    switch (kind) {
      case ChallengeAxisKind.duration:
        final raw = isMinimize
            ? comfort / kChallengeOverloadFactor
            : comfort * kChallengeOverloadFactor;
        return raw.round();
      case ChallengeAxisKind.bpm:
        final raw = isMinimize
            ? comfort / kChallengeOverloadFactor
            : comfort * kChallengeOverloadFactor;
        final rounded = raw.round();
        return isMinimize ? (rounded < 18 ? 18 : rounded) : rounded;
      case ChallengeAxisKind.depthCran:
        // ±1 cran (cf. spec § 3.1, profondeur = cran discret).
        final delta = isMinimize ? -1 : 1;
        return (comfort.round() + delta).clamp(0, Position.values.length - 1);
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

  /// Position de départ du step défi.
  ///
  /// **Convention rythme** : `from < to` strict (cf.
  /// `feedback_step_amplitude` mémoire — pas de `head→head` ni d'égalité).
  /// Les axes `rhythm.bpm_ceil.<bande>` mesurent le BPM tenu dans une
  /// bande de profondeur définie par `to` (cf. `CapabilityClamps.rhythmBpmCeilAxisFor`) :
  /// le `from` doit donc être *moins profond* que `to`.
  ///
  /// **Convention hold** : `from == to` (la position est tenue). Le hold
  /// utilise `from`, le BeepEngine joue le sample de la position.
  static Position? _fromOf(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
        return Position.throat;
      case CapabilityAxis.holdFullStreak:
        return Position.full;
      // Rhythm shallow : head→mid (amplitude légère, bande `to ≤ mid`).
      case CapabilityAxis.rhythmBpmCeilShallow:
        return Position.head;
      // Rhythm throat : head→throat (franchissement gorge à vitesse
      // calibrée — l'axe mesure le BPM en bande throat).
      case CapabilityAxis.rhythmBpmCeilThroat:
        return Position.head;
      // Rhythm full : mid→full (franchissement profond, le `from` ne
      // peut pas être head pour rester réaliste à BPM élevé).
      case CapabilityAxis.rhythmBpmCeilFull:
        return Position.mid;
      case CapabilityAxis.rhythmMotionStreak:
      case CapabilityAxis.rhythmDepthMax:
      case CapabilityAxis.effortNoBreathStreak:
      case CapabilityAxis.noswallowStreak:
        return Position.head;
      default:
        return null;
    }
  }

  /// Position d'arrivée du step défi. Pour les rhythms : `to` est la
  /// position la plus profonde (le critère d'amplitude). Pour les holds :
  /// `to == from` (position tenue ; on garde les deux pour cohérence avec
  /// la convention hold du générateur).
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

  /// Retourne les autres axes pilotants qui produiraient un défi
  /// **visuellement identique** à [axis] côté joueuse : même mode, même
  /// `from`, même `to`, et même `kind` (durée vs BPM rampe vs profondeur —
  /// inclure `kind` préserve la variété entre un défi rythme à BPM constant
  /// et un défi rythme avec rampe BPM, qui ne se ressentent pas pareil).
  /// Sert au caller à élargir l'exclusion entre 2 picks successifs d'une
  /// même session — sinon une joueuse ayant plusieurs axes hold throat
  /// (`holdThroatStreak` + `gorgeApneeStreak` + `gorgeEngagementStreak`)
  /// verrait deux défis « hold throat » différents uniquement par leur
  /// durée dérivée du `comfort` de chaque axe (cf. retour stefsub v0.5.0).
  /// L'axe lui-même n'est jamais inclus dans le retour : le caller a déjà
  /// fait `excludeAxes.add(picked)` derrière le pick.
  static Set<CapabilityAxis> axesSharingVisualSignature(CapabilityAxis axis) {
    final mode = _modeOf(axis);
    final from = _fromOf(axis);
    final to = _toOf(axis);
    final kind = _kindOf(axis);
    return {
      for (final a in CapabilityAxis.values)
        if (a != axis &&
            _modeOf(a) == mode &&
            _fromOf(a) == from &&
            _toOf(a) == to &&
            _kindOf(a) == kind)
          a,
    };
  }

  /// Construit le `SessionStep` matérialisant le défi (consommé par le
  /// générateur lors de l'insertion à 60 %). Propage `bpmEnd` pour les
  /// défis BPM en rampe (le BeepEngine interpole linéairement entre
  /// `bpm` et `bpmEnd` sur la durée).
  static SessionStep stepFor(Challenge ch, {required int time}) {
    return SessionStep(
      time: time,
      from: ch.from,
      to: ch.to,
      bpm: ch.bpm,
      bpmEnd: ch.bpmEnd,
      duration: ch.nominalDurationSeconds,
      mode: ch.mode,
    );
  }
}
