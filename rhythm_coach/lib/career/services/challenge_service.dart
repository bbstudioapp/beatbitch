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
import '../../services/beep_engine.dart';
import '../../services/capability_axis.dart';
import '../../services/capability_service.dart';
import '../models/challenge.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';
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

  /// Clé de persistance des axes pickés dans la dernière session de défis.
  /// Sert à éviter de proposer **exactement le même set** deux séances de
  /// suite : sur un profil jeune (peu d'axes prouvés), `pickOverloadAxis`
  /// retombe sinon sur la même séquence à chaque tirage (cf. retour
  /// stefsub v0.5.0). L'exclusion est *non bloquante* — le caller retombe
  /// sur le tirage standard si la pool restante est vide.
  static const String keyLastSessionAxes = 'challenges.last_session_axes';

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

  /// Reset toutes les clés (toggle, tuto, compteurs d'essais par axe,
  /// historique anti-répétition). Câblé au bouton reset du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyEnabled);
    await prefs.remove(keyTutorialSeen);
    await prefs.remove(keyLastSessionAxes);
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_kAttemptsPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// Axes des défis pickés à la **dernière session** (toutes outcomes
  /// confondues — un défi proposé compte, qu'il ait été passé, raté ou
  /// skip). Vide après reset / si aucune session de défi n'a été lancée.
  /// Lu par le caller au démarrage de la session suivante pour les ajouter
  /// à `excludeAxes` du premier essai. Stockage : `setStringList` des
  /// `storageKey`. Les clés inconnues (axe disparu après refacto) sont
  /// silencieusement ignorées au load.
  Future<Set<CapabilityAxis>> lastSessionAxes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(keyLastSessionAxes) ?? const <String>[];
    final out = <CapabilityAxis>{};
    for (final key in raw) {
      for (final a in CapabilityAxis.values) {
        if (a.storageKey == key) {
          out.add(a);
          break;
        }
      }
    }
    return out;
  }

  /// Persiste les axes des défis pickés pour cette session. Écrase l'historique
  /// précédent : on ne mémorise que la **dernière** session, pas une fenêtre
  /// glissante (rétention plus longue empilerait l'exclusion et empêcherait
  /// la rotation sur les axes une fois la pool épuisée). Appelée par le
  /// caller juste après la génération des défis — l'anti-répétition couvre
  /// donc les défis *proposés*, pas seulement ceux *joués* (une joueuse qui
  /// quitte avant le 1ᵉʳ défi ne reverra pas le même set non plus).
  Future<void> recordSessionChallenges(Iterable<CapabilityAxis> axes) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = axes.map((a) => a.storageKey).toList(growable: false);
    await prefs.setStringList(keyLastSessionAxes, keys);
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
    Set<UnlockKey> unlocks = const {},
  }) async {
    if (isTutorial) {
      return _buildTutorialChallenge();
    }
    // Gating profondeur (cf. retour stefsub v0.5.0) : un défi qui exige
    // une profondeur cible (head→throat, throat, full…) ne doit pas être
    // proposé tant que la joueuse n'a pas validé cette profondeur en
    // session normale via `rhythm.depth_max.comfort`. Sans ce filtre, la
    // 1ʳᵉ rencontre avec head→throat se ferait sous forme d'un défi long
    // alors que la session normale clampe à mid. Le tuto reste exempté
    // (forcé sur holdThroatStreak via _buildTutorialChallenge plus haut).
    //
    // Gating unlocks pour axes « modèle gorge » (apnée / engagement) : ils
    // nécessitent des unlocks pédagogiques préalables (fullPulse+fullHold
    // pour l'apnée, throatPulse pour l'engagement) — sans ça, on demande
    // à la joueuse une séquence qui mélange profondeurs qu'elle n'a pas
    // encore débloquées. Pas appliqué en mode hérité (set vide).
    final depthGated = depthGatedAxes(profile);
    final unlockGated =
        unlocks.isEmpty ? const <CapabilityAxis>{} : unlockGatedAxes(unlocks);
    final effectiveExclude = <CapabilityAxis>{
      ...excludeAxes,
      ...depthGated,
      ...unlockGated,
    };
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
        excludeAxes: effectiveExclude,
      );
      if (axis != null) {
        final comfort = profile!.comfortOf(axis)!;
        final crossings = await _resolveCrossingsTargetFor(axis);
        return _buildChallenge(
            axis: axis,
            comfort: comfort,
            targetCrossings: crossings,
            profile: profile);
      }
    }
    final axis = _pickAxis(
      profile: profile,
      ceilings: ceilings,
      excludeAxes: effectiveExclude,
      rng: rng,
    );
    if (axis != null) {
      final comfort = profile?.comfortOf(axis);
      if (comfort != null) {
        final crossings = await _resolveCrossingsTargetFor(axis);
        return _buildChallenge(
            axis: axis,
            comfort: comfort,
            targetCrossings: crossings,
            profile: profile);
      }
    }
    // Phase 2 — fallback exploratoire : aucun axe candidat avec un
    // `comfort` prouvé (profil neuf ou toutes les ressources figées),
    // mais on peut peut-être amorcer un axe vierge. Cf. spec § 3.2.
    final exploratoryAxis = _pickExploratoryAxis(
      profile: profile,
      excludeAxes: effectiveExclude,
      rng: rng,
    );
    if (exploratoryAxis == null) return null;
    final crossings = await _resolveCrossingsTargetFor(exploratoryAxis);
    return _buildExploratoryChallenge(
        axis: exploratoryAxis, targetCrossings: crossings, profile: profile);
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
    CapabilityProfile? profile,
  }) {
    final kind = _kindOf(axis);
    final threshold = Challenge.initialEstimateSecondsForAxis(axis);
    final mode = _modeOf(axis);
    final (from, to) = _resolveAmplitude(axis: axis, profile: profile);
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
    CapabilityProfile? profile,
  }) {
    final kind = _kindOf(axis);
    final threshold = thresholdFor(kind, comfort, axis);
    final mode = _modeOf(axis);
    final (from, to) = _resolveAmplitude(axis: axis, profile: profile);
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

  /// Résout `(from, to)` pour un défi sur [axis], en dégradant l'amplitude
  /// selon `rhythm.depth_max.comfort` pour les axes d'endurance/vitesse
  /// non-profondeur (cf. [_amplitudeDegradedAxes]).
  ///
  /// Sans cette dégradation, `rhythmMotionStreak` (endurance rythme
  /// cumulée, accumulée passivement par toute session de rythme) propose
  /// un défi `rhythm head→throat` à une joueuse qui n'a jamais touché à
  /// throat en session normale (clampée à mid par `rhythm.depth_max`).
  /// Le défi devient alors le 1ᵉʳ contact avec l'amplitude profonde —
  /// brutal et incohérent (cf. retour stefsub v0.5.0).
  ///
  /// Pour les axes profondeur explicites (`holdThroatStreak`,
  /// `rhythmBpmCeilThroat`, etc.), l'amplitude reste celle de l'axe :
  /// c'est leur rôle d'exposer la limite, le gating en amont
  /// ([_depthGatedAxes]) garantit qu'ils ne sont proposés que sur des
  /// profils où la profondeur est déjà prouvée.
  static (Position?, Position?) _resolveAmplitude({
    required CapabilityAxis axis,
    required CapabilityProfile? profile,
  }) {
    final from = _fromOf(axis);
    final to = _toOf(axis);
    if (!_amplitudeDegradedAxes.contains(axis)) return (from, to);
    if (to == null || profile == null) return (from, to);
    final depthComfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (depthComfort == null) return (from, to);
    final maxIdx = depthComfort.round().clamp(0, Position.values.length - 1);
    if (to.index <= maxIdx) return (from, to);
    final clampedTo = Position.values[maxIdx];
    if (from == null) return (from, clampedTo);
    // Convention rythme : `from < to` strict. Si le clamp ramène `to` à
    // la hauteur de `from`, on descend `from` d'un cran pour préserver
    // l'amplitude.
    if (from.index >= clampedTo.index) {
      final newFromIdx =
          (clampedTo.index - 1).clamp(0, Position.values.length - 1);
      return (Position.values[newFromIdx], clampedTo);
    }
    return (from, clampedTo);
  }

  /// Axes pour lesquels l'amplitude proposée par le défi est bornée par
  /// `rhythm.depth_max.comfort` — leur sémantique est endurance/vitesse,
  /// pas profondeur, donc rien ne justifie d'imposer une amplitude que la
  /// joueuse n'a jamais touchée. Cf. [_resolveAmplitude].
  static const Set<CapabilityAxis> _amplitudeDegradedAxes = {
    CapabilityAxis.rhythmMotionStreak,
    CapabilityAxis.effortNoBreathStreak,
    CapabilityAxis.noswallowStreak,
  };

  /// Profondeur minimale (en `rhythm.depth_max.comfort`) exigée pour
  /// proposer un défi sur [axis]. `null` si l'axe n'a pas d'exigence (modes
  /// hand/lick/biffle, axes endurance shallow, axes d'endurance dégradés
  /// via [_amplitudeDegradedAxes]). Sert au gating dans [buildForSession]
  /// — un axe dont l'exigence n'est pas satisfaite est exclu du tirage.
  static Position? _axisDepthGate(CapabilityAxis axis) {
    switch (axis) {
      case CapabilityAxis.holdThroatStreak:
      case CapabilityAxis.gorgeApneeStreak:
      case CapabilityAxis.gorgeEngagementStreak:
      case CapabilityAxis.gorgeCrossingsBpmThroat:
      case CapabilityAxis.rhythmBpmCeilThroat:
        return Position.throat;
      case CapabilityAxis.holdFullStreak:
      case CapabilityAxis.gorgeCrossingsBpmFull:
      case CapabilityAxis.rhythmBpmCeilFull:
        return Position.full;
      // ignore: no_default_cases
      default:
        return null;
    }
  }

  /// `true` si la profondeur exigée par [axis] est satisfaite côté
  /// `rhythm.depth_max.comfort`. Retourne `true` pour les axes non gatés
  /// (pas d'exigence). `false` si pas de profil OU si l'axe demande une
  /// profondeur strictement au-dessus de `comfort` (joueuse neuve incluse :
  /// pas de défi profond tant qu'aucune base n'est posée).
  ///
  /// [rhythmDepthMax] n'est jamais gaté ici — son rôle explicite est de
  /// pousser la profondeur d'un cran, donc il doit pouvoir proposer une
  /// cible au-delà du `comfort` courant.
  static bool _axisDepthRequirementMet(
      CapabilityAxis axis, CapabilityProfile? profile) {
    final required = _axisDepthGate(axis);
    if (required == null) return true;
    if (profile == null) return false;
    final depthComfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (depthComfort == null) return false;
    return depthComfort.round() >= required.index;
  }

  /// Pré-requis `UnlockKey` d'un axe — set vide si l'axe n'a pas de
  /// dépendance d'unlock. Sémantique : ces axes proposent une **séquence
  /// de défi** qui mélange plusieurs profondeurs / actions, et n'a de sens
  /// pédagogiquement que si la joueuse a déjà débloqué les profondeurs
  /// participantes. Sans ces gates, on lui demanderait un défi mixé
  /// (hold throat + hold full + rythme profond) alors qu'elle n'a pas
  /// validé `fullPulse`/`fullHold` ni `throatPulse` côté session normale.
  static Set<UnlockKey> _axisUnlockRequirements(CapabilityAxis axis) {
    switch (axis) {
      // Apnée gorge — défi qui alterne hold throat, hold full, et rythme
      // profond (head→throat / mid→full). Demande la maîtrise du fond.
      case CapabilityAxis.gorgeApneeStreak:
        return const {UnlockKey.fullPulse, UnlockKey.fullHold};
      // Engagement gorge — défi qui mélange holds + rythmes profonds avec
      // uniquement les profondeurs débloquées (palier accessible plus tôt).
      case CapabilityAxis.gorgeEngagementStreak:
        return const {UnlockKey.throatPulse};
      default:
        return const {};
    }
  }

  /// Axes à exclure du tirage tant que tous leurs [UnlockKey] pré-requis
  /// ne sont pas dans [acquired]. Pendant en mode hérité (set vide),
  /// retourne vide → aucun gating par unlock (compat sessions hors
  /// carrière). Exposé pour les tests.
  static Set<CapabilityAxis> unlockGatedAxes(Set<UnlockKey> acquired) {
    return {
      for (final a in CapabilityAxis.values)
        if (_axisUnlockRequirements(a).isNotEmpty &&
            !acquired.containsAll(_axisUnlockRequirements(a)))
          a,
    };
  }

  /// Axes à exclure du tirage tant que leur profondeur cible n'est pas
  /// atteinte. Consommé par [buildForSession] qui les ajoute à
  /// `excludeAxes` avant chaque pick — cohérent avec le mécanisme
  /// existant d'exclusion des axes déjà couverts par milestones. Exposé
  /// (sans préfixe `_`) pour permettre aux tests d'asserter directement
  /// le gating sans monter une session complète.
  static Set<CapabilityAxis> depthGatedAxes(CapabilityProfile? profile) {
    return {
      for (final a in CapabilityAxis.values)
        if (_axisDepthGate(a) != null && !_axisDepthRequirementMet(a, profile))
          a,
    };
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
  ///   pour durée et BPM ; `comfort + 1` cran pour profondeur. Le seuil BPM
  ///   est plafonné à [BeepEngine.kMaxBpm] — au-delà, le moteur joue plat
  ///   et le nombre annoncé n'est plus qu'un décor.
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
        // Plafond `maximize` symétrique du plancher `minimize` : une
        // bannière ne doit jamais annoncer un BPM que le moteur ne peut
        // pas produire, même si le `comfort` en base est déjà dérivé.
        return isMinimize
            ? (rounded < 18 ? 18 : rounded)
            : (rounded > BeepEngine.kMaxBpm ? BeepEngine.kMaxBpm : rounded);
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
      // Rhythm throat / franchissement gorge throat : head→throat
      // (franchissement gorge à vitesse calibrée). Le compteur de
      // franchissements côté contrôleur exige un `to` non-null (cf. `_toOf`).
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.gorgeCrossingsBpmThroat:
        return Position.head;
      // Rhythm full / franchissement gorge full : mid→full (franchissement
      // profond, le `from` ne peut pas être head pour rester réaliste à
      // BPM élevé).
      case CapabilityAxis.rhythmBpmCeilFull:
      case CapabilityAxis.gorgeCrossingsBpmFull:
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
      // `to` = position de comptage des franchissements. Indispensable non-null
      // pour les axes `kCrossingsChallengeAxes` : `_onChallengeBeatIfCrossingsTracked`
      // n'incrémente `_challengeCrossingsCount` que sur `e.to == ch.to`, donc un
      // `to` null fige le compteur à 0 et le défi ne se termine jamais.
      case CapabilityAxis.rhythmBpmCeilThroat:
      case CapabilityAxis.gorgeCrossingsBpmThroat:
      case CapabilityAxis.rhythmMotionStreak:
        return Position.throat;
      case CapabilityAxis.rhythmBpmCeilFull:
      case CapabilityAxis.gorgeCrossingsBpmFull:
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
