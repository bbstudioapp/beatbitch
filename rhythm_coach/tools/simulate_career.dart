// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';

/// Simulateur de progression carrière BeatBitch.
///
/// Rejoue N sessions sous différents profils de joueuse (purist endurance,
/// profondeur brutale, sloppy obéissante, hybride prudente, fail-prone,
/// quickie-spammer). Pour chaque profil sort une timeline, un récap, et un
/// rapport de cohérence des paliers.
///
/// Usage : `dart run tools/simulate_career.dart [--profile NAME] [--sessions N]
/// [--seed N] [--format markdown|tsv] [--out PATH]` depuis `rhythm_coach/`.
/// Sans `--profile`, tourne sur tous les profils embarqués.
///
/// Le simulateur **ne touche pas au code de prod**. Il :
///   - lit `assets/career/milestones.json` directement (dart:io) ;
///   - réutilise les bouts pure-Dart : `SessionStep.fromJson`, `SessionMode`,
///     `Position`, `HumiliationScale.requiredFor`, `CapabilityAxis`,
///     `UnlockKey` ;
///   - réimplémente standalone la logique de `MilestoneService.allPendingFor`
///     (humil/level/branchScore/branchAdvance/capability) — `MilestoneService`
///     dépend de `shared_preferences` ;
///   - approxime les deltas humil/obed/best d'après les profils probabilistes ;
///   - ignore le calcul `comfort`/`successRate` du `CapabilityRegulator` (le
///     simulateur ne sert qu'à valider l'**ordre** des paliers, pas la
///     valeur exacte du `comfort`) — on tient `best` monotone et un compteur
///     `lastSeen` pour flagger les decay potentiels.
///
/// Quand un mécanisme change côté prod, relancer le simulateur permet de
/// repérer immédiatement les régressions : milestone qui devient injouable,
/// palier qui se bloque, ordre humil cassé, feature jamais débloquée.

// ─── Enums locaux ─────────────────────────────────────────────────────────

/// Réplique pure de `SpecializationBranch` (qui importe `flutter/material`
/// pour `IconData` — inutilisable depuis un script `dart run`).
enum SpecBranch { endurance, profondeur, rythmeBiffle, obeissance, sloppy }

SpecBranch? _branchFromString(String? raw) {
  if (raw == null) return null;
  final lower = raw.toLowerCase();
  for (final b in SpecBranch.values) {
    if (b.name.toLowerCase() == lower) return b;
  }
  if (lower == 'rythme_biffle' || lower == 'rythme-biffle') {
    return SpecBranch.rythmeBiffle;
  }
  return null;
}

enum MilestonePlace { body, finalApotheose }

// ─── Struct milestone (chargée depuis JSON) ───────────────────────────────

class SimCapReq {
  final CapabilityAxis axis;
  final double min;
  const SimCapReq(this.axis, this.min);
}

class SimMilestone {
  final String id;
  final int minLevel;
  final double humilRequired;
  final List<UnlockKey> unlocks;
  final List<UnlockKey> requires;
  final List<SimCapReq> requiresCapability;
  final List<SpecBranch> branches;
  final MilestonePlace placement;
  final List<SessionStep> sequence;
  final int durationSeconds;

  SimMilestone({
    required this.id,
    required this.minLevel,
    required this.humilRequired,
    required this.unlocks,
    required this.requires,
    required this.requiresCapability,
    required this.branches,
    required this.placement,
    required this.sequence,
    required this.durationSeconds,
  });
}

CapabilityAxis? _axisFromKey(String key) {
  for (final a in CapabilityAxis.values) {
    if (a.storageKey == key) return a;
  }
  return null;
}

List<SimMilestone> _loadMilestones(File f) {
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final list = (raw['milestones'] as List).cast<Map<String, dynamic>>();
  final out = <SimMilestone>[];
  for (final m in list) {
    final id = m['id'] as String;
    final minLevel = (m['level'] as num?)?.toInt() ?? 1;
    final placementRaw = (m['placement'] as String? ?? 'body').toLowerCase();
    final placement =
        (placementRaw == 'final' || placementRaw == 'final_apotheose')
            ? MilestonePlace.finalApotheose
            : MilestonePlace.body;

    // Reproduit MilestoneLoader._parse pour la séquence (avec chainAction).
    final seqRaw = (m['sequence'] as List).cast<Map<String, dynamic>>();
    final sequence = <SessionStep>[];
    for (final s in seqRaw) {
      final parent = SessionStep.fromJson(s);
      sequence.add(parent);
      final chain = parent.chainAction;
      if (chain != null) {
        sequence.add(SessionStep(
          time: parent.time + (parent.duration ?? 0),
          text: chain.text,
          from: chain.from,
          to: chain.to,
          bpm: chain.bpm,
          duration: chain.duration,
          mode: chain.mode,
        ));
      }
    }
    final last = sequence.last;
    final duration = last.time + (last.duration ?? 0);

    final unlocks = (m['unlocks'] as List? ?? const [])
        .map((e) => UnlockKey.fromString(e as String?))
        .whereType<UnlockKey>()
        .toList();
    final requires = (m['requires'] as List? ?? const [])
        .map((e) => UnlockKey.fromString(e as String?))
        .whereType<UnlockKey>()
        .toList();

    final capsRaw = (m['requiresCapability'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final caps = <SimCapReq>[];
    for (final c in capsRaw) {
      final axis = _axisFromKey(c['axis'] as String);
      final mn = (c['min'] as num?)?.toDouble();
      if (axis == null || mn == null) continue;
      caps.add(SimCapReq(axis, mn));
    }

    final brList = m['branches'];
    final branches = <SpecBranch>[];
    if (brList is List) {
      for (final b in brList) {
        final parsed = _branchFromString(b?.toString());
        if (parsed != null) branches.add(parsed);
      }
    } else {
      final single = _branchFromString(m['branch'] as String?);
      if (single != null) branches.add(single);
    }

    out.add(SimMilestone(
      id: id,
      minLevel: minLevel,
      humilRequired: _computeHumilRequired(sequence),
      unlocks: unlocks,
      requires: requires,
      requiresCapability: caps,
      branches: branches,
      placement: placement,
      sequence: sequence,
      durationSeconds: duration,
    ));
  }
  return out;
}

/// Réplique de `MilestoneLoader._computeHumilRequired` (idem que dans
/// `tools/dump_milestone_humil.dart`). Holds consécutifs sur la même position
/// sont agrégés en durée avant évaluation.
double _computeHumilRequired(List<SessionStep> sequence) {
  var maxV = 0.0;
  Position? chainTo;
  int chainDur = 0;

  void flush() {
    if (chainTo == null) return;
    final r = HumiliationScale.requiredFor(
      mode: SessionMode.hold,
      to: chainTo,
      duration: chainDur,
    );
    if (r > maxV) maxV = r;
    chainTo = null;
    chainDur = 0;
  }

  for (final s in sequence) {
    final mode = s.mode ?? SessionMode.rhythm;
    if (mode == SessionMode.hold && s.to != null) {
      if (chainTo == s.to) {
        chainDur += s.duration ?? 0;
      } else {
        flush();
        chainTo = s.to;
        chainDur = s.duration ?? 0;
      }
      continue;
    }
    flush();
    final r = HumiliationScale.requiredFor(
      mode: mode,
      from: s.from,
      to: s.to,
      bpm: s.bpm,
      duration: s.duration,
    );
    if (r > maxV) maxV = r;
  }
  flush();
  return maxV;
}

// ─── Durée carrière par niveau (réplique CareerLevel._durationForLevel) ───

int _durationForLevel(int level) {
  if (level <= 2) return 5 * 60;
  if (level <= 4) return 8 * 60;
  if (level <= 7) return 12 * 60;
  if (level <= 10) return 18 * 60;
  if (level <= 14) return 25 * 60;
  if (level <= 17) return 35 * 60;
  return 45 * 60;
}

// ─── Profil joueuse ───────────────────────────────────────────────────────

/// Une fonction qui calcule, par axe et par session, la valeur que le profil
/// est *capable* de tenir cette séance (clean) — sera consolidée en `best`
/// monotone. Sortie nulle = axe pas sollicité par le profil.
typedef AxisTargetsFn = Map<CapabilityAxis, double> Function(
    int level, SimProfile profile);

class SimProfile {
  final String name;
  final String description;
  final Map<SpecBranch, int> allocation;

  /// Probabilité de fail "ambiant" sur une session (en dehors de la fenêtre
  /// milestone). Affecte l'attribution de level-up et les deltas obed/humil.
  final double failProba;

  /// Probabilité de demander un encore en fin de séance (cumulé linéairement
  /// avec l'éligibilité — niveau ≥ 5 + une des deux voies).
  final double encoreProba;

  /// Probabilité que la session soit lancée en bâclée. La bâclée n'engendre
  /// pas de level-up (cf. `CareerProgressService.recordSessionCompleted`).
  final double quickieProba;

  /// Comportement face à une milestone insérée — proba d'exécution clean.
  /// Le complément est partagé entre fail (60 %) et abandon (40 %).
  final double milestoneCleanProba;

  /// Taux de mini-punition inopinée du coach choisi (proxy : +obed à chaque
  /// punition complétée si la session est clean).
  final double miniPunRate;

  final int sessions;

  /// Quels axes capacités le profil pousse naturellement chaque session.
  /// Doit refléter le style de jeu (purist endurance pousse holdThroatStreak,
  /// profondeur pousse rhythmDepthMax + gorgeApneeStreak, etc.). Les
  /// valeurs sont des cibles que la joueuse *atteint* sur une session clean.
  final AxisTargetsFn axisTargets;

  /// Capacité **initiale** de la joueuse à tenir un défi : 0 = débutante,
  /// 1 = experte. Évolue au fil des sessions via [skillGrowthPerSession]
  /// (courbe d'apprentissage). Pondère `P(fail)` et `expectedExtensions`
  /// par rapport à la difficulté du défi (`_challengeDifficulty`).
  /// Cf. `_resolveChallengeOutcome` et `currentSkillAt`.
  final double skillLevel;

  /// Croissance du skill par session — modélise la progression de la
  /// joueuse au fil de la pratique. Linéaire, plafonné à 1.0. Volontairement
  /// plus élevé chez les débutantes (apprentissage rapide les premières
  /// sessions) et nul chez les expertes (plateau atteint).
  final double skillGrowthPerSession;

  /// Probabilité d'appuyer `PASSE` pendant le breath d'annonce. Indépendant
  /// de la difficulté — c'est un état d'esprit, pas une réaction au défi.
  /// Typiquement faible (~10 %) chez les débutantes apeurées, ~0 ailleurs.
  final double challengeSkipProba;

  const SimProfile({
    required this.name,
    required this.description,
    required this.allocation,
    required this.failProba,
    required this.encoreProba,
    required this.quickieProba,
    required this.milestoneCleanProba,
    required this.miniPunRate,
    required this.sessions,
    required this.axisTargets,
    required this.skillLevel,
    this.skillGrowthPerSession = 0.0,
    this.challengeSkipProba = 0.0,
  });

  int branchPts(SpecBranch b) => allocation[b] ?? 0;

  /// Skill effectif à la session [sessionIndex] (1-indexée). Le skill monte
  /// de [skillGrowthPerSession] par session écoulée, plafonné à 1.0.
  double currentSkillAt(int sessionIndex) {
    final raw = skillLevel + skillGrowthPerSession * (sessionIndex - 1);
    if (raw < 0) return 0;
    if (raw > 1) return 1;
    return raw;
  }
}

// ─── État simulateur par profil ──────────────────────────────────────────

class CapState {
  double best;
  int lastSeen; // index session de dernier push propre
  CapState(this.best, this.lastSeen);
}

class SimState {
  double humilCareer = 0;
  double humilSession = 0;
  double obed = 0;
  int sessionIndex = 0;

  /// Compteurs d'investissement (remplacent l'ancien `level`).
  int totalSeconds = 0;
  int sessionsCompleted = 0; // sessions terminées sans fail/abandon
  int noFailStreak = 0;
  int encoresAsked = 0;

  /// Proxy interne pour les helpers qui consomment encore un `int`
  /// (BPM caps, estimateurs comfort, durée, etc.) — équivalent au
  /// `synthLevel` prod (`CareerDifficultyResolver.synthLevelFor`).
  /// Plus aucun « level-up » : la valeur dérive strictement des
  /// sessions terminées.
  int get synthLevel {
    final n = sessionsCompleted < 0 ? 0 : sessionsCompleted;
    return n ~/ 2 + 1 > 30 ? 30 : n ~/ 2 + 1;
  }

  /// Réputation = formule `ReputationService.snapshot` privée du facteur
  /// `niveau_max × 100` (qu'on cherche précisément à supprimer). Reflète
  /// l'investissement (sessions + endurance + records) sans accélérateur
  /// arbitraire.
  double get reputation {
    final holdFullBest = (caps[CapabilityAxis.holdFullStreak]?.best ?? 0);
    final throatfuckProxy =
        (caps[CapabilityAxis.gorgeCrossingsLifetime]?.best ?? 0);
    return sessionsCompleted * 5.0 +
        noFailStreak * 3.0 +
        holdFullBest * 2.0 +
        throatfuckProxy * 0.5 +
        encoresAsked * 10.0;
  }

  Set<UnlockKey> unlocked = <UnlockKey>{};
  Set<String> completedMilestones = <String>{};
  Map<CapabilityAxis, CapState> caps = <CapabilityAxis, CapState>{};
  // Compteur de candidature (id milestone → sessions où elle est candidate
  // mais non sélectionnée). Cf. `MilestoneService.incrementCandidacyAge`.
  Map<String, int> candidacyAge = <String, int>{};
  // ordre d'acquisition des unlocks (clé → n° session)
  List<({UnlockKey key, int session, String milestone})> unlockHistory = [];

  // ─── Défis ─────────────────────────────────────────────────────────────
  /// `true` une fois que le défi tutoriel a été joué (équivalent du flag
  /// `challenges.tutorial_seen` côté prod).
  bool tutorialSeen = false;

  /// Compteur par outcome — alimente le récap.
  Map<SimChallengeOutcome, int> challengeCounts = {
    for (final o in SimChallengeOutcome.values) o: 0,
  };

  /// Axes records poussés par un défi (vs alimentés par une milestone ou
  /// par le profil). Pour chaque axe : la plus grande `reachedValue` vue.
  Map<CapabilityAxis, double> challengePushedBest = <CapabilityAxis, double>{};

  /// Nombre d'unlocks gagnés via `markCompletedViaChallenge` (incluant
  /// les cascades transitives holds).
  int challengeUnlocksGained = 0;
}

// ─── Enregistrement timeline ──────────────────────────────────────────────

class TimelineRow {
  final int session;
  final int synthLevel;
  final int sessionsCompleted;
  final int totalSeconds;
  final double reputation;
  final double humilCareer;
  final double obed;
  final List<UnlockKey> unlocksGained;
  final String? milestoneBodyInserted;
  final String? milestoneBody2Inserted;
  final String? milestoneFinalInserted;
  final String outcome; // clean / fail / abandon / encore / quickie
  final List<CapabilityAxis> axesTouched;
  final bool synthBumped;
  final String?
      challengeSummary; // ex. `hold.throat × net ×2`, `tut`, null si pas de défi

  TimelineRow({
    required this.session,
    required this.synthLevel,
    required this.sessionsCompleted,
    required this.totalSeconds,
    required this.reputation,
    required this.humilCareer,
    required this.obed,
    required this.unlocksGained,
    required this.milestoneBodyInserted,
    this.milestoneBody2Inserted,
    required this.milestoneFinalInserted,
    required this.outcome,
    required this.axesTouched,
    required this.synthBumped,
    this.challengeSummary,
  });
}

// ─── Sélection milestone (réplique MilestoneService.allPendingFor) ────────

double _humilTolerance(double obed) {
  final ob = obed < 0 ? 0.0 : obed;
  return 1.0 + ob / 50.0;
}

bool _capabilitySatisfied(SimMilestone m, SimState s) {
  if (m.requiresCapability.isEmpty) return true;
  for (final req in m.requiresCapability) {
    final st = s.caps[req.axis];
    if (st == null) return false;
    final minimize = req.axis.recordKind == CapabilityRecordKind.minimize;
    final ok = minimize ? st.best <= req.min : st.best >= req.min;
    if (!ok) return false;
  }
  return true;
}

int _branchScore(SimMilestone m, SimProfile p) {
  if (m.branches.isEmpty) return 0;
  var sum = 0;
  for (final b in m.branches) {
    sum += p.branchPts(b);
  }
  return sum;
}

int _branchAdvance(SimMilestone m, SimProfile p) {
  if (m.branches.isEmpty) return 0;
  var best = 0;
  for (final b in m.branches) {
    final pts = p.branchPts(b);
    if (pts > best) best = pts;
  }
  return best.clamp(0, 3);
}

int _lowestBranchPoints(SimMilestone m, SimProfile p) {
  if (m.branches.isEmpty) return 0;
  var lo = 1 << 30;
  for (final b in m.branches) {
    final pts = p.branchPts(b);
    if (pts < lo) lo = pts;
  }
  return lo == (1 << 30) ? 0 : lo;
}

/// Poids du vieillissement dans le sortScore (cf.
/// `MilestoneService._agingWeight`). Doit rester aligné avec la prod.
const double _kAgingWeight = 0.5;
const double _kLowestBranchWeight = 0.1;

double _sortScore(SimMilestone m, SimProfile p, SimState s) {
  final age = s.candidacyAge[m.id] ?? 0;
  return _branchScore(m, p).toDouble() +
      _kAgingWeight * age -
      _kLowestBranchWeight * _lowestBranchPoints(m, p);
}

/// Renvoie la liste complète des candidates triée — analogue à
/// `MilestoneService.allPendingFor`. Le caller pioche `.first` et passe
/// la queue à `_ageCandidates`.
List<SimMilestone> _allPendingMilestones({
  required List<SimMilestone> catalog,
  required SimState state,
  required SimProfile profile,
  required MilestonePlace placement,
  Set<String> excludeIds = const {},
  Set<UnlockKey> extraUnlockedSimulated = const {},
}) {
  final cap =
      state.humilCareer + state.humilSession + _humilTolerance(state.obed);
  final candidates = catalog
      .where((m) => m.placement == placement)
      .where((m) => !excludeIds.contains(m.id))
      .where(
          (m) => (m.minLevel - _branchAdvance(m, profile)) <= state.synthLevel)
      .where((m) => m.humilRequired <= cap)
      .where((m) => !state.completedMilestones.contains(m.id))
      .where((m) => m.requires.every(state.unlocked.contains))
      // Exclusion mutuelle quand on simule un 2ᵉ pick : si m dépend d'un
      // unlock déjà attribué par le 1er pick simulé, on l'écarte pour ne
      // pas tricher sur l'ordre pédagogique dans la même séance.
      .where((m) => !m.requires.any(extraUnlockedSimulated.contains))
      .where((m) => _capabilitySatisfied(m, state))
      .toList();
  if (candidates.isEmpty) return const [];

  final isBody = placement == MilestonePlace.body;

  int lagOf(SimMilestone m) {
    if (!isBody) return 0;
    return state.synthLevel - (m.minLevel - _branchAdvance(m, profile));
  }

  bool isOverdue(SimMilestone m) {
    if (!isBody) return false;
    // Garde « anti double accélérateur » : si la spé avait déjà rapproché
    // la milestone de ≥ 3 niveaux, overdue ne s'enclenche pas (sinon
    // chaque milestone matchée par une spé maxée passerait overdue dès
    // son apparition, écrasant aging). Aligné avec MilestoneService.
    if (_branchAdvance(m, profile) >= 3) return false;
    return lagOf(m) >= 3;
  }

  candidates.sort((a, b) {
    if (isBody) {
      final ao = isOverdue(a);
      final bo = isOverdue(b);
      if (ao != bo) return ao ? -1 : 1;
      if (ao && bo) {
        final byLag = lagOf(b).compareTo(lagOf(a));
        if (byLag != 0) return byLag;
        final byHumil = a.humilRequired.compareTo(b.humilRequired);
        if (byHumil != 0) return byHumil;
        return a.id.compareTo(b.id);
      }
    }
    final byScore =
        _sortScore(b, profile, state).compareTo(_sortScore(a, profile, state));
    if (byScore != 0) return byScore;
    final byHumil = a.humilRequired.compareTo(b.humilRequired);
    if (byHumil != 0) return byHumil;
    return a.id.compareTo(b.id);
  });
  return candidates;
}

// ─── Heuristique : axes touchés par les steps d'une milestone ─────────────

Map<CapabilityAxis, double> _axesFromMilestoneSequence(SimMilestone m) {
  final out = <CapabilityAxis, double>{};
  Position? chainTo;
  int chainDur = 0;

  void flush() {
    if (chainTo == null) return;
    if (chainTo == Position.throat) {
      out[CapabilityAxis.holdThroatStreak] =
          max(out[CapabilityAxis.holdThroatStreak] ?? 0, chainDur.toDouble());
    } else if (chainTo == Position.full) {
      out[CapabilityAxis.holdFullStreak] =
          max(out[CapabilityAxis.holdFullStreak] ?? 0, chainDur.toDouble());
    }
    chainTo = null;
    chainDur = 0;
  }

  for (final s in m.sequence) {
    final mode = s.mode ?? SessionMode.rhythm;
    if (mode == SessionMode.hold && s.to != null) {
      if (chainTo == s.to) {
        chainDur += s.duration ?? 0;
      } else {
        flush();
        chainTo = s.to;
        chainDur = s.duration ?? 0;
      }
      continue;
    }
    flush();
    switch (mode) {
      case SessionMode.rhythm:
        final to = s.to;
        if (to != null) {
          out[CapabilityAxis.rhythmDepthMax] =
              max(out[CapabilityAxis.rhythmDepthMax] ?? 0, to.index.toDouble());
          final bpm = (s.bpm ?? 80).toDouble();
          if (to.index <= Position.mid.index) {
            out[CapabilityAxis.rhythmBpmCeilShallow] =
                max(out[CapabilityAxis.rhythmBpmCeilShallow] ?? 0, bpm);
          } else if (to == Position.throat) {
            out[CapabilityAxis.rhythmBpmCeilThroat] =
                max(out[CapabilityAxis.rhythmBpmCeilThroat] ?? 0, bpm);
          } else if (to == Position.full) {
            out[CapabilityAxis.rhythmBpmCeilFull] =
                max(out[CapabilityAxis.rhythmBpmCeilFull] ?? 0, bpm);
          }
          // motion_streak ~ durée du step (sans pause)
          out[CapabilityAxis.rhythmMotionStreak] = max(
              out[CapabilityAxis.rhythmMotionStreak] ?? 0,
              (s.duration ?? 0).toDouble());
        }
        break;
      case SessionMode.lick:
        out[CapabilityAxis.lickStreak] = max(
            out[CapabilityAxis.lickStreak] ?? 0, (s.duration ?? 0).toDouble());
        final to = s.to;
        if (to != null) {
          out[CapabilityAxis.lickDepthMax] =
              max(out[CapabilityAxis.lickDepthMax] ?? 0, to.index.toDouble());
        }
        break;
      case SessionMode.biffle:
        final dur = (s.duration ?? 0).toDouble();
        out[CapabilityAxis.biffleStreak] =
            max(out[CapabilityAxis.biffleStreak] ?? 0, dur);
        final bpm = (s.bpm ?? 80).toDouble();
        out[CapabilityAxis.biffleBpmMax] =
            max(out[CapabilityAxis.biffleBpmMax] ?? 0, bpm);
        break;
      case SessionMode.beg:
        final to = s.to;
        if (to == Position.throat) {
          out[CapabilityAxis.holdThroatStreak] = max(
              out[CapabilityAxis.holdThroatStreak] ?? 0,
              (s.duration ?? 0).toDouble());
        } else if (to == Position.full) {
          out[CapabilityAxis.holdFullStreak] = max(
              out[CapabilityAxis.holdFullStreak] ?? 0,
              (s.duration ?? 0).toDouble());
        }
        break;
      case SessionMode.breath:
      case SessionMode.freestyle:
      case SessionMode.hand:
      case SessionMode.hold:
      case SessionMode.suckle:
        // Suckle ne consomme aucun axe capability (geste actif-statique
        // hors palette des records). On le laisse passer sans contribuer.
        break;
    }
  }
  flush();
  return out;
}

// ─── Défis intra-séance ───────────────────────────────────────────────────
//
// Réplique simplifiée de `ChallengeService.buildForSession` + résolution
// d'outcome pondérée par la difficulté du défi (au lieu d'un % fixe).
// Les valeurs (facteur 1.30, table durée par axe, plancher BPM minimize 18)
// sont alignées sur le fix `fix/challenges-calibration-by-axis`.

const double _kChallengeOverloadFactor = 1.30;
const int _kChallengeBpmFloor = 18;
const int _kChallengeTutorialDurationSeconds = 5;

/// Axes éligibles à la surcharge — réplique de `CapabilityClamps.overloadableAxes`.
const Set<CapabilityAxis> _overloadableSimAxes = {
  CapabilityAxis.gorgeApneeStreak,
  CapabilityAxis.gorgeEngagementStreak,
  CapabilityAxis.gorgeCrossingsBpmThroat,
  CapabilityAxis.gorgeCrossingsBpmFull,
  CapabilityAxis.rhythmBpmCeilShallow,
  CapabilityAxis.rhythmBpmCeilThroat,
  CapabilityAxis.rhythmBpmCeilFull,
  CapabilityAxis.rhythmDepthMax,
  CapabilityAxis.rhythmMotionStreak,
  CapabilityAxis.holdThroatStreak,
  CapabilityAxis.holdFullStreak,
  CapabilityAxis.noswallowStreak,
  CapabilityAxis.biffleStreak,
  CapabilityAxis.biffleBpmMax,
};

/// Réplique de `MilestoneService._impliedHoldUnlocksByAxis` — cascade
/// transitive : tenir gorge X s prouve qu'on tient les positions plus
/// shallow X s.
const Map<CapabilityAxis, Set<UnlockKey>> _impliedHoldUnlocksByAxis = {
  CapabilityAxis.holdThroatStreak: {
    UnlockKey.holdHead,
    UnlockKey.holdMid,
    UnlockKey.finalHoldTip,
    UnlockKey.finalHoldHead,
    UnlockKey.finalHoldMid,
  },
  CapabilityAxis.holdFullStreak: {
    UnlockKey.holdHead,
    UnlockKey.holdMid,
    UnlockKey.throatHold,
    UnlockKey.finalHoldTip,
    UnlockKey.finalHoldHead,
    UnlockKey.finalHoldMid,
    UnlockKey.finalHoldThroat,
  },
};

/// Seuil minimum (en secondes) au-dessus duquel un défi sur un axe hold
/// déclenche la cascade transitive. Aligné sur la prod.
const double _transitiveHoldMinReached = 3.0;

/// Plafond pratique d'un axe poussé via défi — borne le compounding
/// `comfort × 1.30` qui sinon explose en 10-15 sessions (le simulateur ne
/// modélise pas la régulation `comfort` ↔ `successRate`, donc le best
/// ratchete à chaque défi). Aligné sur les `absoluteMax` des `axisTargets`
/// des profils existants pour rester comparable.
double _axisChallengeCap(CapabilityAxis axis) {
  switch (axis) {
    case CapabilityAxis.rhythmBpmCeilShallow:
    case CapabilityAxis.rhythmBpmCeilThroat:
      return 180.0;
    case CapabilityAxis.rhythmBpmCeilFull:
      return 165.0;
    case CapabilityAxis.gorgeCrossingsBpmThroat:
      return 165.0;
    case CapabilityAxis.gorgeCrossingsBpmFull:
      return 140.0;
    case CapabilityAxis.biffleBpmMax:
      return 160.0;
    case CapabilityAxis.holdThroatStreak:
      return 40.0;
    case CapabilityAxis.holdFullStreak:
      return 25.0;
    case CapabilityAxis.gorgeApneeStreak:
      return 35.0;
    case CapabilityAxis.gorgeEngagementStreak:
      return 60.0;
    case CapabilityAxis.rhythmMotionStreak:
      return 70.0;
    case CapabilityAxis.effortNoBreathStreak:
      return 90.0;
    case CapabilityAxis.noswallowStreak:
      return 60.0;
    case CapabilityAxis.biffleStreak:
      return 30.0;
    case CapabilityAxis.rhythmDepthMax:
      return (Position.values.length - 1).toDouble();
    default:
      return double.infinity;
  }
}

enum SimChallengeKind { duration, bpm, depthCran }

enum SimChallengeOutcome {
  tutorial,
  skipped,
  fail,
  netSuccess,
  extendedSuccess
}

class SimChallenge {
  final CapabilityAxis axis;
  final SimChallengeKind kind;
  final SessionMode mode;
  final Position? from;
  final Position? to;
  final int threshold;
  final int durationSeconds;
  final double difficulty;
  final SimChallengeOutcome outcome;
  final int extensions;
  final bool isTutorial;
  final bool isExploratory;

  SimChallenge({
    required this.axis,
    required this.kind,
    required this.mode,
    required this.from,
    required this.to,
    required this.threshold,
    required this.durationSeconds,
    required this.difficulty,
    required this.outcome,
    required this.extensions,
    required this.isTutorial,
    required this.isExploratory,
  });

  /// Valeur réellement atteinte (récompense d'extensions incluses). Pour les
  /// axes durée : `threshold + N × extensionSeconds`. Sinon : `threshold`.
  double get reachedValue {
    if (kind != SimChallengeKind.duration) return threshold.toDouble();
    return (threshold + extensions * _extensionSecondsForComfort(threshold))
        .toDouble();
  }

  /// Approximation de la prolongation « JE TIENS ENCORE » — plancher 10 s,
  /// sinon `comfort × 0.30`. Le `comfort` n'étant pas tracé dans le sim, on
  /// dérive du threshold (= comfort × 1.30 → comfort ≈ threshold/1.30).
  static int _extensionSecondsForComfort(int threshold) {
    final comfort = threshold / _kChallengeOverloadFactor;
    final v = (comfort * 0.30).round();
    return v < 10 ? 10 : v;
  }
}

/// Sélection de l'axe défi pour la session — réplique simplifiée de
/// `CapabilityClamps.pickOverloadAxis` : axe pilotant avec donnée (best
/// connu), le plus ancien `lastSeen`, excluant ceux des milestones insérées
/// cette session. Si profil neuf → axe vierge tiré au hasard (exploratoire).
({CapabilityAxis? axis, bool isExploratory}) _pickChallengeAxis({
  required SimState state,
  required Set<CapabilityAxis> exclude,
  required Random rng,
}) {
  final withData = <CapabilityAxis>[];
  final virgin = <CapabilityAxis>[];
  for (final a in _overloadableSimAxes) {
    if (exclude.contains(a)) continue;
    if (state.caps.containsKey(a)) {
      withData.add(a);
    } else {
      virgin.add(a);
    }
  }
  if (withData.isNotEmpty) {
    withData.sort(
        (a, b) => state.caps[a]!.lastSeen.compareTo(state.caps[b]!.lastSeen));
    return (axis: withData.first, isExploratory: false);
  }
  if (virgin.isNotEmpty) {
    return (axis: virgin[rng.nextInt(virgin.length)], isExploratory: true);
  }
  return (axis: null, isExploratory: false);
}

SimChallengeKind _challengeKindOf(CapabilityAxis axis) {
  switch (axis.unit) {
    case CapabilityUnit.seconds:
      return SimChallengeKind.duration;
    case CapabilityUnit.bpm:
      return SimChallengeKind.bpm;
    case CapabilityUnit.depthCran:
      return SimChallengeKind.depthCran;
    case CapabilityUnit.count:
      return SimChallengeKind.duration;
  }
}

SessionMode _challengeModeOf(CapabilityAxis axis) {
  switch (axis) {
    case CapabilityAxis.holdThroatStreak:
    case CapabilityAxis.holdFullStreak:
    case CapabilityAxis.gorgeApneeStreak:
    case CapabilityAxis.gorgeEngagementStreak:
      return SessionMode.hold;
    case CapabilityAxis.biffleStreak:
    case CapabilityAxis.biffleBpmMax:
      return SessionMode.biffle;
    default:
      return SessionMode.rhythm;
  }
}

({Position? from, Position? to}) _challengeFromToOf(CapabilityAxis axis) {
  switch (axis) {
    case CapabilityAxis.holdThroatStreak:
    case CapabilityAxis.gorgeApneeStreak:
    case CapabilityAxis.gorgeEngagementStreak:
      return (from: Position.throat, to: Position.throat);
    case CapabilityAxis.holdFullStreak:
      return (from: Position.full, to: Position.full);
    case CapabilityAxis.rhythmBpmCeilShallow:
      return (from: Position.head, to: Position.mid);
    case CapabilityAxis.rhythmBpmCeilThroat:
    case CapabilityAxis.gorgeCrossingsBpmThroat:
    case CapabilityAxis.rhythmMotionStreak:
      return (from: Position.head, to: Position.throat);
    case CapabilityAxis.rhythmBpmCeilFull:
    case CapabilityAxis.gorgeCrossingsBpmFull:
      return (from: Position.mid, to: Position.full);
    case CapabilityAxis.rhythmDepthMax:
    case CapabilityAxis.noswallowStreak:
      return (from: Position.head, to: Position.throat);
    default:
      return (from: null, to: null);
  }
}

int _challengeDurationFor(
    CapabilityAxis axis, int threshold, SimChallengeKind kind) {
  if (kind == SimChallengeKind.duration) return threshold;
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
    case CapabilityAxis.rhythmDepthMax:
      return 12;
    default:
      return 30;
  }
}

/// Calcule le seuil cible (parité avec `ChallengeService.thresholdFor`).
int _challengeThreshold(
    CapabilityAxis axis, double comfort, SimChallengeKind kind) {
  final isMinimize = axis.recordKind == CapabilityRecordKind.minimize;
  switch (kind) {
    case SimChallengeKind.duration:
    case SimChallengeKind.bpm:
      final raw = isMinimize
          ? comfort / _kChallengeOverloadFactor
          : comfort * _kChallengeOverloadFactor;
      final rounded = raw.round();
      if (kind == SimChallengeKind.bpm && isMinimize) {
        return rounded < _kChallengeBpmFloor ? _kChallengeBpmFloor : rounded;
      }
      return rounded;
    case SimChallengeKind.depthCran:
      final delta = isMinimize ? -1 : 1;
      return (comfort.round() + delta).clamp(0, Position.values.length - 1);
  }
}

/// Difficulté du défi dans [0.20, 0.95]. Pondère le mode/axe (catégorie
/// physiologique) + la profondeur ciblée. Cf. spec révisée par le user.
double _challengeDifficulty(CapabilityAxis axis, Position? from, Position? to) {
  final wAxis = switch (axis) {
    CapabilityAxis.holdFullStreak ||
    CapabilityAxis.rhythmDepthMax ||
    CapabilityAxis.effortNoBreathStreak =>
      0.90,
    CapabilityAxis.rhythmBpmCeilFull ||
    CapabilityAxis.gorgeCrossingsBpmFull ||
    CapabilityAxis.holdThroatStreak ||
    CapabilityAxis.gorgeApneeStreak =>
      0.75,
    CapabilityAxis.rhythmBpmCeilThroat ||
    CapabilityAxis.gorgeCrossingsBpmThroat ||
    CapabilityAxis.rhythmMotionStreak ||
    CapabilityAxis.gorgeEngagementStreak ||
    CapabilityAxis.noswallowStreak =>
      0.60,
    CapabilityAxis.rhythmBpmCeilShallow || CapabilityAxis.biffleBpmMax => 0.45,
    _ => 0.30,
  };
  final fromIdx = from?.index ?? 0;
  final toIdx = to?.index ?? 0;
  final depthFactor = max(fromIdx, toIdx) / (Position.values.length - 1);
  return (wAxis + 0.20 * depthFactor).clamp(0.20, 0.95);
}

/// Tire l'outcome du défi : skip indépendant (rare hors débutante), fail
/// croissant avec `difficulty - skill`, extensions croissantes avec
/// `skill - difficulty`. Tutoriel : forcé à `tutorial` (= 0 extension,
/// implicite net pour les effets).
({SimChallengeOutcome outcome, int extensions}) _resolveChallengeOutcome({
  required double difficulty,
  required double skillLevel,
  required bool isTutorial,
  required double skipProba,
  required Random rng,
}) {
  if (isTutorial) {
    return (outcome: SimChallengeOutcome.tutorial, extensions: 0);
  }
  if (rng.nextDouble() < skipProba) {
    return (outcome: SimChallengeOutcome.skipped, extensions: 0);
  }
  final failP = ((difficulty - skillLevel) * 1.6 + 0.05).clamp(0.02, 0.95);
  if (rng.nextDouble() < failP) {
    return (outcome: SimChallengeOutcome.fail, extensions: 0);
  }
  final expectedExt = ((skillLevel - difficulty) * 8).clamp(0.0, 5.0);
  // Bruit gaussien léger (Box-Muller approché par moyenne uniformes).
  final noise = (rng.nextDouble() + rng.nextDouble() - 1.0) * 0.7;
  final n = (expectedExt + noise).round().clamp(0, 5);
  if (n == 0) {
    return (outcome: SimChallengeOutcome.netSuccess, extensions: 0);
  }
  return (outcome: SimChallengeOutcome.extendedSuccess, extensions: n);
}

/// Construit un défi complet (axe + calibration + outcome) pour la session.
/// `firstChallengeSeen` = `false` pour la 1ʳᵉ séance → tutoriel scripté.
SimChallenge? _generateChallenge({
  required SimState state,
  required SimProfile profile,
  required Set<CapabilityAxis> excludeAxes,
  required bool firstChallengeSeen,
  required Random rng,
}) {
  if (!firstChallengeSeen) {
    // Tutoriel hold throat 5 s.
    return SimChallenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: SimChallengeKind.duration,
      mode: SessionMode.hold,
      from: Position.throat,
      to: Position.throat,
      threshold: _kChallengeTutorialDurationSeconds,
      durationSeconds: _kChallengeTutorialDurationSeconds,
      difficulty: 0.30,
      outcome: SimChallengeOutcome.tutorial,
      extensions: 0,
      isTutorial: true,
      isExploratory: false,
    );
  }
  final pick = _pickChallengeAxis(state: state, exclude: excludeAxes, rng: rng);
  final axis = pick.axis;
  if (axis == null) return null;
  final kind = _challengeKindOf(axis);
  final mode = _challengeModeOf(axis);
  final positions = _challengeFromToOf(axis);
  final int threshold;
  if (pick.isExploratory) {
    // Seuils exploratoires conservatifs (parité approximative avec
    // `Challenge.initialEstimateSecondsForAxis`).
    threshold = switch (axis) {
      CapabilityAxis.holdThroatStreak ||
      CapabilityAxis.holdFullStreak ||
      CapabilityAxis.gorgeApneeStreak ||
      CapabilityAxis.gorgeEngagementStreak =>
        5,
      CapabilityAxis.biffleStreak => 8,
      CapabilityAxis.rhythmMotionStreak => 30,
      CapabilityAxis.effortNoBreathStreak ||
      CapabilityAxis.noswallowStreak =>
        15,
      CapabilityAxis.rhythmBpmCeilShallow ||
      CapabilityAxis.rhythmBpmCeilThroat ||
      CapabilityAxis.rhythmBpmCeilFull ||
      CapabilityAxis.gorgeCrossingsBpmThroat ||
      CapabilityAxis.gorgeCrossingsBpmFull ||
      CapabilityAxis.biffleBpmMax =>
        60,
      CapabilityAxis.rhythmDepthMax => 1,
      _ => 15,
    };
  } else {
    final comfort = state.caps[axis]!.best;
    threshold = _challengeThreshold(axis, comfort, kind);
  }
  final duration = _challengeDurationFor(axis, threshold, kind);
  final difficulty = _challengeDifficulty(axis, positions.from, positions.to);
  // En exploratoire, la difficulté apparente est réduite (seuil initial bas,
  // pas de surcharge × 1.30). Plancher 0.20.
  final adjustedDiff =
      pick.isExploratory ? (difficulty - 0.15).clamp(0.20, 0.95) : difficulty;
  final outcomeRes = _resolveChallengeOutcome(
    difficulty: adjustedDiff,
    skillLevel: profile.currentSkillAt(state.sessionIndex),
    isTutorial: false,
    skipProba: profile.challengeSkipProba,
    rng: rng,
  );
  return SimChallenge(
    axis: axis,
    kind: kind,
    mode: mode,
    from: positions.from,
    to: positions.to,
    threshold: threshold,
    durationSeconds: duration,
    difficulty: adjustedDiff,
    outcome: outcomeRes.outcome,
    extensions: outcomeRes.extensions,
    isTutorial: false,
    isExploratory: pick.isExploratory,
  );
}

/// Acquittement implicite milestone via défi — parité avec
/// `MilestoneService.milestonesAcquittableByChallenge`. Inclut la cascade
/// transitive holds (`hold.throat ⇒ holdHead/holdMid/finalHold*`).
/// Retourne les unlocks gagnés (déjà ajoutés à `state.unlocked`).
List<UnlockKey> _acquitMilestonesViaChallenge({
  required SimChallenge challenge,
  required List<SimMilestone> catalog,
  required SimState state,
  required SimProfile profile,
}) {
  if (challenge.outcome == SimChallengeOutcome.fail ||
      challenge.outcome == SimChallengeOutcome.skipped) {
    return const [];
  }
  final reached = challenge.reachedValue;
  final axis = challenge.axis;
  final minimize = axis.recordKind == CapabilityRecordKind.minimize;
  final liveUnlocks = Set<UnlockKey>.from(state.unlocked);
  final gained = <UnlockKey>[];

  // Passe 1 — milestones avec requiresCapability matchant l'axe + autres caps OK.
  // Parité prod : `matchedAxis` est requis (cf. MilestoneService ligne 814-839)
  // — sinon un défi `biffle.streak` acquittait des milestones hold dont
  // les autres caps étaient déjà satisfaites par le profil.
  var added = true;
  while (added) {
    added = false;
    for (final m in catalog) {
      if (state.completedMilestones.contains(m.id)) continue;
      if (m.requiresCapability.isEmpty) continue;
      if (!m.requires.every(liveUnlocks.contains)) continue;
      var matchedAxis = false;
      var allOk = true;
      for (final req in m.requiresCapability) {
        if (req.axis == axis) {
          matchedAxis = true;
          final ok = minimize ? reached <= req.min : reached >= req.min;
          if (!ok) {
            allOk = false;
            break;
          }
        } else {
          final st = state.caps[req.axis];
          final reqMin = req.axis.recordKind == CapabilityRecordKind.minimize;
          if (st == null || (reqMin ? st.best > req.min : st.best < req.min)) {
            allOk = false;
            break;
          }
        }
      }
      if (!matchedAxis || !allOk) continue;
      state.completedMilestones.add(m.id);
      state.candidacyAge.remove(m.id);
      for (final u in m.unlocks) {
        if (state.unlocked.add(u)) {
          gained.add(u);
          liveUnlocks.add(u);
          state.unlockHistory.add((
            key: u,
            session: state.sessionIndex,
            milestone: '${m.id} (challenge)',
          ));
        }
      }
      added = true;
    }
  }

  // Passe 2 — cascade transitive holds (seuil ≥ 3 s).
  final implied = _impliedHoldUnlocksByAxis[axis];
  if (implied != null && reached >= _transitiveHoldMinReached) {
    added = true;
    while (added) {
      added = false;
      for (final m in catalog) {
        if (state.completedMilestones.contains(m.id)) continue;
        if (m.unlocks.isEmpty) continue;
        if (!m.unlocks.any(implied.contains)) continue;
        if (!m.requires.every(liveUnlocks.contains)) continue;
        // Autres caps (sur d'autres axes que celui du défi) doivent rester satisfaits.
        var otherCapsOk = true;
        for (final req in m.requiresCapability) {
          if (req.axis == axis) continue;
          final st = state.caps[req.axis];
          final reqMin = req.axis.recordKind == CapabilityRecordKind.minimize;
          if (st == null || (reqMin ? st.best > req.min : st.best < req.min)) {
            otherCapsOk = false;
            break;
          }
        }
        if (!otherCapsOk) continue;
        state.completedMilestones.add(m.id);
        state.candidacyAge.remove(m.id);
        for (final u in m.unlocks) {
          if (state.unlocked.add(u)) {
            gained.add(u);
            liveUnlocks.add(u);
            state.unlockHistory.add((
              key: u,
              session: state.sessionIndex,
              milestone: '${m.id} (challenge:transitive)',
            ));
          }
        }
        added = true;
      }
    }
  }
  return gained;
}

/// Résumé compact d'un défi pour la timeline. Ex. `hold.throat × net ×2`.
String _formatChallengeSummary(SimChallenge ch) {
  final axisLabel = ch.axis.storageKey;
  final outcomeLabel = switch (ch.outcome) {
    SimChallengeOutcome.tutorial => 'tut',
    SimChallengeOutcome.skipped => 'skip',
    SimChallengeOutcome.fail => 'fail',
    SimChallengeOutcome.netSuccess => 'net',
    SimChallengeOutcome.extendedSuccess => 'ext×${ch.extensions}',
  };
  final exploratoryMark = ch.isExploratory ? '?' : '';
  return '$axisLabel$exploratoryMark × $outcomeLabel';
}

// ─── Catalogue des profils ────────────────────────────────────────────────
//
// 4 tiers (skillLevel croissant) + 2 spé pathologiques (`fail_prone`,
// `quickie_spammer`) qui restent utiles pour les détecteurs LEVEL-STUCK,
// FEATURE-MISSED et la spirale de fail.
//
// Les tiers ont des allocations différentes pour explorer plusieurs spé
// au fil des sessions (une débutante n'a aucun point ; une experte a 9 pts
// alloués typiques d'une fin de carrière niveau 18+). Le pacing humil/obed
// reste calibré par `milestoneCleanProba` / `failProba` / `encoreProba`
// comme avant, mais le `skillLevel` pilote en plus le rapport au défi
// (cf. `_resolveChallengeOutcome`).

/// Bornage d'un push d'axe — évite que des cibles trop ambitieuses laissent
/// croire qu'une débutante tient 80 s de gorge dès la 1ʳᵉ séance.
double _clampGrowth(double v, double absoluteMax) {
  if (v < 0) return 0;
  return v > absoluteMax ? absoluteMax : v;
}

List<SimProfile> _builtinProfiles() {
  return [
    // ── Tier 1 : débutante ──────────────────────────────────────────────
    SimProfile(
      name: 'debutante',
      description:
          'Découvre la mécanique. 0 pt de spé. Fail ambiant 20 %, milestones '
          'ratées 1 fois sur 3, peut passer un défi (PASSE pendant le breath). '
          'Cibles axes basses — la joueuse tient à peine ce qu\'elle peut.',
      allocation: const {},
      failProba: 0.20,
      encoreProba: 0.05,
      quickieProba: 0.0,
      milestoneCleanProba: 0.65,
      miniPunRate: 0.08,
      sessions: 30,
      skillLevel: 0.20,
      // Apprentissage rapide les premières sessions — atteint ~0.74 après
      // 30 séances (= niveau du tier moyen-avancé).
      skillGrowthPerSession: 0.018,
      challengeSkipProba: 0.10,
      axisTargets: (level, p) => {
        CapabilityAxis.holdThroatStreak: _clampGrowth(0.3 + 0.18 * level, 8),
        CapabilityAxis.holdFullStreak: _clampGrowth(0.1 + 0.10 * level, 5),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(5 + 0.7 * level, 22),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(1.2 + level / 10.0, 3), 3),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(0.3 + 0.15 * level, 6),
        CapabilityAxis.gorgeEngagementStreak: _clampGrowth(2 + 0.6 * level, 25),
      },
    ),
    // ── Tier 2 : moyen ──────────────────────────────────────────────────
    SimProfile(
      name: 'moyen',
      description:
          'Joueuse confirmée hybride. 1-1-1-1-1 (5 pts répartis, dispo à L10). '
          'Fail occasionnel (8 %), milestones clean 90 %. Skill moyen sur les '
          'défis — fail sur les axes durs, ext sur les axes simples.',
      allocation: const {
        SpecBranch.endurance: 1,
        SpecBranch.profondeur: 1,
        SpecBranch.rythmeBiffle: 1,
        SpecBranch.obeissance: 1,
        SpecBranch.sloppy: 1,
      },
      failProba: 0.08,
      encoreProba: 0.30,
      quickieProba: 0.05,
      milestoneCleanProba: 0.90,
      miniPunRate: 0.12,
      sessions: 30,
      skillLevel: 0.50,
      // Progression modérée — atteint ~0.71 après 30 séances.
      skillGrowthPerSession: 0.007,
      axisTargets: (level, p) => {
        CapabilityAxis.holdThroatStreak: _clampGrowth(1 + 0.35 * level, 18),
        CapabilityAxis.holdFullStreak: _clampGrowth(0.3 + 0.22 * level, 12),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(10 + 1.5 * level, 45),
        CapabilityAxis.rhythmDepthMax: _clampGrowth(min(2 + level / 7.0, 4), 4),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(1 + 0.3 * level, 18),
        CapabilityAxis.biffleStreak: _clampGrowth(3 + 0.5 * level, 18),
        CapabilityAxis.rhythmBpmCeilThroat: _clampGrowth(80.0 + 3 * level, 135),
        CapabilityAxis.noswallowStreak: _clampGrowth(2 + 0.5 * level, 20),
        CapabilityAxis.lickStreak: _clampGrowth(10 + 1.0 * level, 35),
      },
    ),
    // ── Tier 3 : avancé ─────────────────────────────────────────────────
    SimProfile(
      name: 'avance',
      description:
          'Carrière mi-haute. 3 endurance + 2 obéissance (5 pts, dispo à L10) — '
          'spé soumise endurante typique. Fail rare (4 %), milestones 94 %, '
          'encore fréquent. Tient les défis durs, ext sur la plupart.',
      allocation: const {
        SpecBranch.endurance: 3,
        SpecBranch.obeissance: 2,
      },
      failProba: 0.04,
      encoreProba: 0.45,
      quickieProba: 0.0,
      milestoneCleanProba: 0.94,
      miniPunRate: 0.14,
      sessions: 30,
      skillLevel: 0.75,
      // Plateau atteint plus tôt — atteint ~0.87 après 30 séances.
      skillGrowthPerSession: 0.004,
      axisTargets: (level, p) => {
        CapabilityAxis.holdThroatStreak: _clampGrowth(
            2 + 0.7 * level + 0.4 * p.branchPts(SpecBranch.endurance), 35),
        CapabilityAxis.holdFullStreak: _clampGrowth(
            0.5 + 0.4 * level + 0.3 * p.branchPts(SpecBranch.endurance), 22),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(2 + 0.5 * level, 28),
        CapabilityAxis.gorgeEngagementStreak: _clampGrowth(6 + 1.2 * level, 60),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(15 + 2.0 * level, 65),
        CapabilityAxis.effortNoBreathStreak: _clampGrowth(18 + 2.5 * level, 80),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(2.0 + level / 6.0, 4), 4),
        CapabilityAxis.rhythmBpmCeilThroat: _clampGrowth(95.0 + 4 * level, 165),
      },
    ),
    // ── Tier 4 : experte ────────────────────────────────────────────────
    SimProfile(
      name: 'experte',
      description:
          'Fin de carrière. 4 profondeur + 3 endurance + 2 rythme (9 pts, dispo '
          'à L18+). Quasi jamais de fail (1 %), milestones 98 %, encore par '
          'défaut. Pousse les axes durs et tient les défis avec extensions ×3-5.',
      allocation: const {
        SpecBranch.profondeur: 4,
        SpecBranch.endurance: 3,
        SpecBranch.rythmeBiffle: 2,
      },
      failProba: 0.01,
      encoreProba: 0.60,
      quickieProba: 0.0,
      milestoneCleanProba: 0.98,
      miniPunRate: 0.18,
      sessions: 30,
      skillLevel: 0.95,
      // Plateau atteint (skillGrowth=0) — pas de progression skill, la
      // joueuse est déjà au sommet de sa marge.
      axisTargets: (level, p) => {
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(3.0 + level / 4.0, 4), 4),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(
            3 + 0.8 * level + 0.4 * p.branchPts(SpecBranch.profondeur), 35),
        CapabilityAxis.gorgeCrossingsBpmThroat: _clampGrowth(
            85 + 5 * level + 1.5 * p.branchPts(SpecBranch.profondeur), 165),
        CapabilityAxis.gorgeCrossingsBpmFull:
            _clampGrowth(75 + 4.0 * level, 140),
        CapabilityAxis.holdThroatStreak: _clampGrowth(
            2 + 0.8 * level + 0.4 * p.branchPts(SpecBranch.endurance), 40),
        CapabilityAxis.holdFullStreak: _clampGrowth(
            1 + 0.5 * level + 0.3 * p.branchPts(SpecBranch.endurance), 25),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(20 + 2.5 * level, 70),
        CapabilityAxis.effortNoBreathStreak: _clampGrowth(25 + 3.0 * level, 90),
        CapabilityAxis.rhythmBpmCeilThroat:
            _clampGrowth(100.0 + 5 * level, 180),
        CapabilityAxis.rhythmBpmCeilFull: _clampGrowth(85.0 + 4 * level, 165),
        CapabilityAxis.biffleStreak: _clampGrowth(5 + 0.6 * level, 25),
        CapabilityAxis.biffleBpmMax: _clampGrowth(95 + 3.5 * level, 160),
      },
    ),
    SimProfile(
      name: 'fail_prone',
      description: 'Fail ambiant 25 %, milestones échouées une fois sur trois. '
          'Abandons fréquents. 2 pts endurance + 2 pts profondeur (ambition vs '
          'réalité).',
      allocation: {
        SpecBranch.endurance: 2,
        SpecBranch.profondeur: 2,
      },
      failProba: 0.25,
      encoreProba: 0.10,
      quickieProba: 0.0,
      milestoneCleanProba: 0.55,
      miniPunRate: 0.10,
      sessions: 30,
      skillLevel: 0.35,
      // Progression freinée par les fails fréquents (atteint ~0.59 à s30).
      skillGrowthPerSession: 0.008,
      challengeSkipProba: 0.05,
      axisTargets: (level, p) => {
        CapabilityAxis.holdThroatStreak: _clampGrowth(0.5 + 0.2 * level, 9),
        CapabilityAxis.holdFullStreak: _clampGrowth(0.2 + 0.15 * level, 6),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(6 + 0.8 * level, 28),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(1.5 + level / 9.0, 3), 3),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(0.5 + 0.2 * level, 8),
      },
    ),
    SimProfile(
      name: 'quickie_spammer',
      description: 'Sessions bâclées en permanence (90 %). Pas de level-up. '
          'Pousse en sprint mais ne consolide pas son `comfort`. 1 pt sloppy '
          '+ 1 pt rythmeBiffle.',
      allocation: {
        SpecBranch.sloppy: 1,
        SpecBranch.rythmeBiffle: 1,
      },
      failProba: 0.08,
      encoreProba: 0.05,
      quickieProba: 0.90,
      milestoneCleanProba: 0.80,
      miniPunRate: 0.14,
      sessions: 30,
      skillLevel: 0.60,
      // Pas de défi en quickie de toute façon (cf. _runProfile : if !isQuickie).
      // Skill quasi-figé (cas marginal des sessions non-quickie, ~10 %).
      skillGrowthPerSession: 0.001,
      axisTargets: (level, p) => {
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(8 + 1.2 * level, 35),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(1.5 + level / 8.0, 3), 3),
        CapabilityAxis.biffleStreak: _clampGrowth(2 + 0.6 * level, 16),
        CapabilityAxis.biffleBpmMax: _clampGrowth(80 + 3.0 * level, 140),
        CapabilityAxis.lickStreak: _clampGrowth(8 + 1.0 * level, 30),
        CapabilityAxis.noswallowStreak: _clampGrowth(1 + 0.3 * level, 10),
        CapabilityAxis.holdThroatStreak: _clampGrowth(0.5 + 0.15 * level, 6),
      },
    ),
  ];
}

// ─── Moteur de simulation ─────────────────────────────────────────────────

class SimResult {
  final SimProfile profile;
  final List<TimelineRow> timeline;
  final SimState finalState;
  final List<String> coherenceIssues;
  // milestones jamais déclenchées (placement, id, raison)
  final List<({String id, String reason})> unreachedMilestones;
  // n° session où chaque seuil d'investissement a été franchi (sessions
  // complétées : 5/10/15/20). Remplace l'ancien `sessionsForLevels`
  // (jalons level) — désormais on suit l'investissement direct.
  final Map<int, int?> sessionsForCompletionMilestones;
  // Catalogue complet (rétention faible — sert à calculer le lag à
  // l'acquisition dans le rendu).
  final List<SimMilestone> catalog;
  SimResult({
    required this.profile,
    required this.timeline,
    required this.finalState,
    required this.coherenceIssues,
    required this.unreachedMilestones,
    required this.sessionsForCompletionMilestones,
    required this.catalog,
  });
}

SimResult _runSim({
  required SimProfile profile,
  required List<SimMilestone> catalog,
  required int seed,
}) {
  final rng = Random(seed);
  final state = SimState();
  final timeline = <TimelineRow>[];
  final sessionsForCompletionMilestones = <int, int?>{
    5: null,
    10: null,
    15: null,
    20: null,
  };

  for (var i = 0; i < profile.sessions; i++) {
    state.sessionIndex = i + 1;
    final duration = _durationForLevel(state.synthLevel);
    // Jalons d'investissement : on note la séance où chaque palier
    // « X sessions terminées » est franchi pour la première fois
    // (5/10/15/20). Calculé en début de session sur l'état d'entrée.
    for (final t in sessionsForCompletionMilestones.keys) {
      if (sessionsForCompletionMilestones[t] == null &&
          state.sessionsCompleted >= t) {
        sessionsForCompletionMilestones[t] = state.sessionIndex;
      }
    }

    // Pick body + final milestones — récupère la queue complète pour
    // pouvoir vieillir les candidates non choisies (cf. aging sort, parité
    // avec `MilestoneService.incrementCandidacyAge`).
    final bodyAll = _allPendingMilestones(
      catalog: catalog,
      state: state,
      profile: profile,
      placement: MilestonePlace.body,
    );
    final bodyM = bodyAll.isEmpty ? null : bodyAll.first;
    // Séances longues (≥ 18 min, level 8+) : 2ᵉ body milestone pour
    // accélérer la consommation du catalogue. `excludeIds` + simulation des
    // unlocks de bodyM évitent doublon et conflit d'ordre pédagogique.
    SimMilestone? bodyM2;
    if (bodyM != null && duration >= 18 * 60) {
      final pool = _allPendingMilestones(
        catalog: catalog,
        state: state,
        profile: profile,
        placement: MilestonePlace.body,
        excludeIds: {bodyM.id},
        extraUnlockedSimulated: bodyM.unlocks.toSet(),
      );
      bodyM2 = pool.isEmpty ? null : pool.first;
    }
    final finalAll = _allPendingMilestones(
      catalog: catalog,
      state: state,
      profile: profile,
      placement: MilestonePlace.finalApotheose,
    );
    final finalM = finalAll.isEmpty ? null : finalAll.first;
    // Vieillit les candidates non choisies : bodyAll moins les bodies
    // effectivement insérés (1 ou 2), plus la queue finalAll moins le 1ᵉʳ.
    final insertedBodyIds = <String>{
      if (bodyM != null) bodyM.id,
      if (bodyM2 != null) bodyM2.id,
    };
    for (final m in bodyAll) {
      if (!insertedBodyIds.contains(m.id)) {
        state.candidacyAge[m.id] = (state.candidacyAge[m.id] ?? 0) + 1;
      }
    }
    for (final m in finalAll.skip(1)) {
      state.candidacyAge[m.id] = (state.candidacyAge[m.id] ?? 0) + 1;
    }

    // Decide outcomes.
    final isQuickie = rng.nextDouble() < profile.quickieProba;
    final ambientFailRoll = rng.nextDouble();
    final hasAmbientFail = ambientFailRoll < profile.failProba;
    var bodyOutcome = 'n/a';
    var body2Outcome = 'n/a';
    var finalOutcome = 'n/a';
    if (bodyM != null) {
      final r = rng.nextDouble();
      if (r < profile.milestoneCleanProba) {
        bodyOutcome = 'clean';
      } else {
        final tail = (r - profile.milestoneCleanProba) /
            max(1e-9, 1.0 - profile.milestoneCleanProba);
        bodyOutcome = tail < 0.6 ? 'fail' : 'abandon';
      }
    }
    if (bodyM2 != null) {
      final r = rng.nextDouble();
      if (r < profile.milestoneCleanProba) {
        body2Outcome = 'clean';
      } else {
        final tail = (r - profile.milestoneCleanProba) /
            max(1e-9, 1.0 - profile.milestoneCleanProba);
        body2Outcome = tail < 0.6 ? 'fail' : 'abandon';
      }
    }
    if (finalM != null) {
      final r = rng.nextDouble();
      // Finals sont moins risqués (la coach pousse à l'apothéose, la
      // joueuse y vient déjà chauffée) ; on prend la même proba clean.
      finalOutcome = r < profile.milestoneCleanProba ? 'clean' : 'fail';
    }
    // Si milestone échouée, ça compte comme un fail ambiant.
    final failsCount = (hasAmbientFail ? 1 : 0) +
        (bodyOutcome == 'fail' || bodyOutcome == 'abandon' ? 1 : 0) +
        (body2Outcome == 'fail' || body2Outcome == 'abandon' ? 1 : 0) +
        (finalOutcome == 'fail' ? 1 : 0);
    final cleanSession = failsCount == 0;
    // « Milestone opportunity missed » (passe « fails plus durs ») : il y a
    // eu un fail ET au moins une milestone candidate était présente cette
    // séance — donc non acquittée. Double le malus humil/obed du fail
    // (parité avec `HumiliationEngine.onFail(milestoneOpportunityMissed:)`).
    final missedMilestone =
        failsCount > 0 && (bodyM != null || bodyM2 != null || finalM != null);
    final failHumilObedMul = missedMilestone ? 2.0 : 1.0;

    // Approximation sessionScore : tick humil ×1 + obed accel, durée minutes.
    final accel = (1.0 + (state.obed / 100.0)).clamp(1.0, 3.0);
    final ticks = duration / 60.0 * accel;
    var sessionScore = ticks * HumiliationEngine.bumpPerInterval;
    // Bumps liés à des holds (très grossier : on regarde la milestone body).
    if (bodyOutcome == 'clean' && bodyM != null) {
      for (final s in bodyM.sequence) {
        if (s.mode == SessionMode.hold && s.to == Position.throat) {
          sessionScore += HumiliationEngine.bumpHoldThroatCompleted;
        } else if (s.mode == SessionMode.hold && s.to == Position.full) {
          sessionScore += HumiliationEngine.bumpHoldFullCompleted;
        }
      }
      sessionScore += HumiliationEngine.bumpMilestoneAcquired;
    }
    if (body2Outcome == 'clean' && bodyM2 != null) {
      for (final s in bodyM2.sequence) {
        if (s.mode == SessionMode.hold && s.to == Position.throat) {
          sessionScore += HumiliationEngine.bumpHoldThroatCompleted;
        } else if (s.mode == SessionMode.hold && s.to == Position.full) {
          sessionScore += HumiliationEngine.bumpHoldFullCompleted;
        }
      }
      sessionScore += HumiliationEngine.bumpMilestoneAcquired;
    }
    // Mini-punitions : ~1 candidat/minute, miniPunRate moyenne ; +2 humil
    // par punition complétée si pas d'abandon.
    final minutes = duration ~/ 60;
    final miniPunHits = profile.miniPunRate * minutes;
    sessionScore += miniPunHits * HumiliationEngine.bumpPunishmentCompleted;
    sessionScore -= failsCount * HumiliationEngine.malusFail * failHumilObedMul;
    if (sessionScore < 0) sessionScore = 0;
    if (sessionScore > HumiliationEngine.sessionCap) {
      sessionScore = HumiliationEngine.sessionCap;
    }

    // Encore en fin de séance.
    final canEncore = state.synthLevel >= 5 &&
        ((state.unlocked.contains(UnlockKey.encore) &&
                (state.humilCareer + sessionScore >= 30 || state.obed >= 50)) ||
            state.obed >= 80);
    final askedEncore = canEncore && rng.nextDouble() < profile.encoreProba;
    final encoresAsked = askedEncore ? 1 : 0;

    // Apply career delta.
    final delta = HumiliationEngine.careerAlpha * sessionScore +
        HumiliationEngine.careerBetaEncore * encoresAsked -
        HumiliationEngine.careerBetaFail * failsCount +
        (cleanSession ? HumiliationEngine.careerGammaClean : 0.0);
    state.humilCareer = max(0, state.humilCareer + delta);

    // Obéissance.
    var obedDelta = (duration / ObedienceEngineConst.tickIntervalSec) *
        ObedienceEngineConst.bumpPerInterval;
    obedDelta += miniPunHits * ObedienceEngineConst.bumpPunishmentCompleted;
    if (cleanSession) obedDelta += ObedienceEngineConst.bumpSessionClean;
    obedDelta -= failsCount * ObedienceEngineConst.malusFail * failHumilObedMul;
    if (bodyOutcome == 'abandon') {
      obedDelta -= ObedienceEngineConst.malusPunishmentAbandoned;
    }
    state.obed = max(0, state.obed + obedDelta);

    // Marque milestones acquittées et collecte unlocks.
    // `MilestoneService.markCompleted(hadFail:)` ignore l'appel si la
    // session a connu un fail — peu importe que le fail soit dans la
    // fenêtre milestone ou ambiant. On reproduit cette règle ici.
    final gained = <UnlockKey>[];
    String? bodyInsertedId;
    String? body2InsertedId;
    String? finalInsertedId;
    if (bodyM != null) {
      bodyInsertedId = bodyM.id;
      if (bodyOutcome == 'clean' && cleanSession) {
        state.completedMilestones.add(bodyM.id);
        state.candidacyAge.remove(bodyM.id);
        for (final u in bodyM.unlocks) {
          if (state.unlocked.add(u)) {
            gained.add(u);
            state.unlockHistory.add((
              key: u,
              session: state.sessionIndex,
              milestone: bodyM.id,
            ));
          }
        }
        // Bonus career +2 par unlock (Phase 4 — l'exploit est une soumission).
        state.humilCareer += bodyM.unlocks.length * 2.0;
      }
    }
    if (bodyM2 != null) {
      body2InsertedId = bodyM2.id;
      if (body2Outcome == 'clean' && cleanSession) {
        state.completedMilestones.add(bodyM2.id);
        state.candidacyAge.remove(bodyM2.id);
        for (final u in bodyM2.unlocks) {
          if (state.unlocked.add(u)) {
            gained.add(u);
            state.unlockHistory.add((
              key: u,
              session: state.sessionIndex,
              milestone: bodyM2.id,
            ));
          }
        }
        state.humilCareer += bodyM2.unlocks.length * 2.0;
      }
    }
    if (finalM != null) {
      finalInsertedId = finalM.id;
      if (finalOutcome == 'clean' && cleanSession) {
        state.completedMilestones.add(finalM.id);
        state.candidacyAge.remove(finalM.id);
        for (final u in finalM.unlocks) {
          if (state.unlocked.add(u)) {
            gained.add(u);
            state.unlockHistory.add((
              key: u,
              session: state.sessionIndex,
              milestone: finalM.id,
            ));
          }
        }
        state.humilCareer += finalM.unlocks.length * 2.0;
      }
    }

    // Met à jour les axes capacité.
    final touched = <CapabilityAxis>{};
    if (cleanSession) {
      // (a) Cibles "naturelles" du profil.
      final profileTargets = profile.axisTargets(state.synthLevel, profile);
      profileTargets.forEach((axis, target) {
        if (isQuickie) {
          // Quickie : best mis à jour mais avec cible un peu plus basse —
          // sprint sans consolidation.
          target *= 0.85;
        }
        _pushBest(state, axis, target, state.sessionIndex);
        touched.add(axis);
      });
      // (b) Axes touchés par les milestones effectivement insérées (clean).
      if (bodyM != null && bodyOutcome == 'clean') {
        _axesFromMilestoneSequence(bodyM).forEach((axis, reached) {
          _pushBest(state, axis, reached, state.sessionIndex);
          touched.add(axis);
        });
      }
      if (bodyM2 != null && body2Outcome == 'clean') {
        _axesFromMilestoneSequence(bodyM2).forEach((axis, reached) {
          _pushBest(state, axis, reached, state.sessionIndex);
          touched.add(axis);
        });
      }
      if (finalM != null && finalOutcome == 'clean') {
        _axesFromMilestoneSequence(finalM).forEach((axis, reached) {
          _pushBest(state, axis, reached, state.sessionIndex);
          touched.add(axis);
        });
      }
    }

    // ─── Défi intra-séance ───────────────────────────────────────────────
    // Hors quickie, on insère un défi sur un axe non couvert par les
    // milestones de la séance. Effets appliqués AVANT le calcul level-up
    // pour que les milestones acquittées via défi (markCompletedViaChallenge
    // + cascade transitive holds) comptent.
    SimChallenge? simChallenge;
    if (!isQuickie) {
      final excludeAxes = <CapabilityAxis>{};
      if (bodyM != null) {
        excludeAxes.addAll(_axesFromMilestoneSequence(bodyM).keys);
      }
      if (bodyM2 != null) {
        excludeAxes.addAll(_axesFromMilestoneSequence(bodyM2).keys);
      }
      if (finalM != null) {
        excludeAxes.addAll(_axesFromMilestoneSequence(finalM).keys);
      }
      simChallenge = _generateChallenge(
        state: state,
        profile: profile,
        excludeAxes: excludeAxes,
        firstChallengeSeen: state.tutorialSeen,
        rng: rng,
      );
      if (simChallenge != null) {
        state.challengeCounts[simChallenge.outcome] =
            (state.challengeCounts[simChallenge.outcome] ?? 0) + 1;
        if (simChallenge.isTutorial) state.tutorialSeen = true;

        final outc = simChallenge.outcome;
        if (outc == SimChallengeOutcome.netSuccess ||
            outc == SimChallengeOutcome.extendedSuccess ||
            outc == SimChallengeOutcome.tutorial) {
          // Bumps humil career (+2 base, +1/extension) + obed (+2 base, +1/extension).
          // Cf. spec § 5.2. Tuto = bump mineur uniquement (pas de +2 base).
          final ext = simChallenge.extensions;
          if (simChallenge.isTutorial) {
            state.humilCareer += 1.0;
            state.obed += 1.0;
          } else {
            state.humilCareer +=
                HumiliationEngine.bumpChallengeNetSuccess + ext * 1.0;
            state.obed += 2.0 + ext * 1.0;
          }

          // raiseCareerFloor : pose le careerScore au palier humil de l'action
          // prouvée — cf. HumiliationEngine.raiseCareerFloor.
          final floor = HumiliationScale.requiredFor(
            mode: simChallenge.mode,
            from: simChallenge.from,
            to: simChallenge.to,
            bpm: simChallenge.kind == SimChallengeKind.bpm
                ? simChallenge.threshold
                : null,
            duration: simChallenge.kind == SimChallengeKind.duration
                ? simChallenge.reachedValue.round()
                : null,
          );
          if (floor > state.humilCareer) state.humilCareer = floor;

          // Push best de l'axe défi via recordChallengeReached. Plafonné
          // par `_axisChallengeCap` pour éviter le compounding 1.30^N que
          // la régulation comfort/successRate (non simulée) borne en prod.
          final cap = _axisChallengeCap(simChallenge.axis);
          final reached =
              simChallenge.reachedValue > cap ? cap : simChallenge.reachedValue;
          _pushBest(state, simChallenge.axis, reached, state.sessionIndex);
          touched.add(simChallenge.axis);
          state.challengePushedBest[simChallenge.axis] =
              max(state.challengePushedBest[simChallenge.axis] ?? 0.0, reached);

          // Acquittement implicite milestone via défi.
          final acquitted = _acquitMilestonesViaChallenge(
            challenge: simChallenge,
            catalog: catalog,
            state: state,
            profile: profile,
          );
          state.challengeUnlocksGained += acquitted.length;
          gained.addAll(acquitted);
        } else if (outc == SimChallengeOutcome.skipped) {
          // PASSE pressé : -3 obed.
          state.obed = max(0, state.obed - 3);
        }
        // fail : soft-cap × 0.92 sur comfort (non simulé), pas de malus.
      }
    }

    // Level-up gaté par milestone (parité avec
    // `CareerProgressService.canLevelUp`) : il faut soit avoir acquitté
    // une milestone candidate au niveau courant cette séance, soit qu'il
    // n'y ait plus aucune candidate au niveau courant (catalogue épuisé
    // — on laisse passer pour ne pas piéger la joueuse).
    //
    // **Re-évaluation POST-finish** : le runtime consulte
    // `MilestoneService.pendingFor(...)` dans `_recordCareerCompletion`
    // avec les scores humil/obed **post-finish** (= ceux que la séance
    // suivante verra au start). Une milestone qui n'était pas candidate
    // au start (humil trop faible) peut le devenir après la chauffe de
    // session + les bonus d'unlock acquis. On reproduit fidèlement en
    // recalculant `bodyAll` ici, plutôt qu'en réutilisant celui du start.
    // Tracking d'investissement post-finish. Aligné sur prod
    // (`StatsService.recordSessionCompleted` incrémente quel que soit
    // l'outcome). Le `synthLevel` dérive automatiquement de
    // `sessionsCompleted` (cf. `SimState.synthLevel`) — plus de
    // « level-up » discret.
    state.sessionsCompleted += 1;
    state.totalSeconds += duration;
    if (cleanSession) {
      state.noFailStreak += 1;
      if (askedEncore) state.encoresAsked += 1;
    } else {
      state.noFailStreak = 0;
    }
    final reachedSynthBefore = timeline.isEmpty ? 1 : timeline.last.synthLevel;
    final synthBumped = state.synthLevel > reachedSynthBefore;

    final outcome = isQuickie
        ? 'quickie${cleanSession ? '+clean' : '+fail'}'
        : (cleanSession
            ? (askedEncore ? 'clean+encore' : 'clean')
            : (bodyOutcome == 'abandon' ? 'abandon' : 'fail'));

    timeline.add(TimelineRow(
      session: state.sessionIndex,
      synthLevel: state.synthLevel,
      sessionsCompleted: state.sessionsCompleted,
      totalSeconds: state.totalSeconds,
      reputation: state.reputation,
      humilCareer: state.humilCareer,
      obed: state.obed,
      unlocksGained: gained,
      milestoneBodyInserted: bodyInsertedId,
      milestoneBody2Inserted: body2InsertedId,
      milestoneFinalInserted: finalInsertedId,
      outcome: outcome,
      axesTouched: touched.toList(),
      synthBumped: synthBumped,
      challengeSummary:
          simChallenge != null ? _formatChallengeSummary(simChallenge) : null,
    ));
  }

  // ── Rapport de cohérence ──────────────────────────────────────────────
  final coherence = <String>[];
  final unreached = <({String id, String reason})>[];

  for (final m in catalog) {
    if (state.completedMilestones.contains(m.id)) continue;
    final reasons = <String>[];
    if (m.minLevel - _branchAdvance(m, profile) > state.synthLevel) {
      reasons.add(
          'level ${state.synthLevel} < min ${m.minLevel - _branchAdvance(m, profile)}');
    }
    if (m.humilRequired > state.humilCareer + _humilTolerance(state.obed)) {
      reasons.add(
          'humil ${state.humilCareer.toStringAsFixed(1)} < req ${m.humilRequired.toStringAsFixed(1)}');
    }
    for (final r in m.requires) {
      if (!state.unlocked.contains(r)) reasons.add('manque ${r.serialized}');
    }
    for (final c in m.requiresCapability) {
      final st = state.caps[c.axis];
      if (st == null) {
        reasons.add('axe ${c.axis.storageKey} jamais touché (min ${c.min})');
      } else {
        final minimize = c.axis.recordKind == CapabilityRecordKind.minimize;
        final ok = minimize ? st.best <= c.min : st.best >= c.min;
        if (!ok) {
          reasons.add('${c.axis.storageKey} best=${st.best.toStringAsFixed(1)} '
              'ne satisfait pas ${minimize ? "≤" : "≥"} ${c.min.toStringAsFixed(1)}');
        }
      }
    }
    unreached.add((id: m.id, reason: reasons.join(' ; ')));
  }

  // (1) Capability gating: milestone dont l'axe n'a jamais été touché.
  for (final u in unreached) {
    final m = catalog.firstWhere((x) => x.id == u.id);
    for (final c in m.requiresCapability) {
      if (!state.caps.containsKey(c.axis)) {
        coherence
            .add('CAP-NEVER  ${m.id} demande ${c.axis.storageKey}≥${c.min}, '
                'axe jamais alimenté par ce profil');
      }
    }
  }

  // (2) Inversion humil : trier les milestones acquises par n° d'acquisition,
  //     puis vérifier que l'humilRequired est globalement monotone — un saut
  //     descendant > 5 sur 2 milestones consécutives signale un palier
  //     "facile" tombé après un "dur".
  final acquiredInOrder = <SimMilestone>[];
  for (final entry in state.unlockHistory) {
    final m = catalog.firstWhere(
      (x) => x.unlocks.contains(entry.key),
      orElse: () => SimMilestone(
        id: '__none__',
        minLevel: 0,
        humilRequired: 0,
        unlocks: const [],
        requires: const [],
        requiresCapability: const [],
        branches: const [],
        placement: MilestonePlace.body,
        sequence: const [],
        durationSeconds: 0,
      ),
    );
    if (m.id != '__none__' &&
        m.placement == MilestonePlace.body &&
        !acquiredInOrder.any((x) => x.id == m.id)) {
      acquiredInOrder.add(m);
    }
  }
  for (var i = 1; i < acquiredInOrder.length; i++) {
    final prev = acquiredInOrder[i - 1];
    final cur = acquiredInOrder[i];
    if (cur.humilRequired + 5 < prev.humilRequired) {
      coherence.add(
          'HUMIL-INV  ${cur.id} (req=${cur.humilRequired.toStringAsFixed(1)}) '
          'acquise après ${prev.id} (req=${prev.humilRequired.toStringAsFixed(1)}) — '
          'palier facile tombé après dur');
    }
  }

  // (3) Sessions non-créditées : ≥ 5 sessions consécutives qui n'ont pas
  //     bumpé `sessionsCompleted` (fails/abandons en chaîne, ou quickies
  //     spammées). Remplace l'ancien LEVEL-STUCK qui n'a plus de sens
  //     depuis que le synthLevel dérive de `sessionsCompleted`.
  var stagnation = 0;
  int? stagnationStartSession;
  int? stagnationLastSessionsCompleted;
  void emitStagnation(int endSession, int sessionsCompleted) {
    if (stagnation >= 5 && stagnationStartSession != null) {
      coherence.add(
          'PROGRESS-STUCK  sessionsCompleted resté à $sessionsCompleted pendant '
          '$stagnation sessions (s$stagnationStartSession → s$endSession)');
    }
    stagnation = 0;
    stagnationStartSession = null;
    stagnationLastSessionsCompleted = null;
  }

  for (var i = 0; i < timeline.length; i++) {
    final r = timeline[i];
    if (stagnationLastSessionsCompleted != null &&
        r.sessionsCompleted == stagnationLastSessionsCompleted) {
      stagnation++;
    } else {
      if (stagnationLastSessionsCompleted != null) {
        emitStagnation(r.session - 1, stagnationLastSessionsCompleted!);
      }
      stagnation = 1;
      stagnationStartSession = r.session;
      stagnationLastSessionsCompleted = r.sessionsCompleted;
    }
  }
  if (timeline.isNotEmpty && stagnationLastSessionsCompleted != null) {
    emitStagnation(timeline.last.session, stagnationLastSessionsCompleted!);
  }
  // (4) Feature-milestones jamais débloquées chez un profil compatible.
  for (final featureId in const [
    'intro_surprise_notifs',
    'intro_fake_breath',
    'intro_freestyle',
    'intro_encore',
  ]) {
    final m = catalog.firstWhere((x) => x.id == featureId,
        orElse: () => SimMilestone(
              id: '__none__',
              minLevel: 0,
              humilRequired: 0,
              unlocks: const [],
              requires: const [],
              requiresCapability: const [],
              branches: const [],
              placement: MilestonePlace.body,
              sequence: const [],
              durationSeconds: 0,
            ));
    if (m.id == '__none__') continue;
    if (state.completedMilestones.contains(featureId)) continue;
    // Profil compatible = niveau atteint + tous les prérequis débloqués.
    final compatible = state.synthLevel >= m.minLevel &&
        m.requires.every(state.unlocked.contains) &&
        _capabilitySatisfied(m, state);
    if (compatible) {
      coherence.add(
          'FEATURE-MISSED  $featureId est éligible (level/requires/caps OK) '
          'mais jamais déclenchée — humilCareer=${state.humilCareer.toStringAsFixed(1)} '
          'req=${m.humilRequired.toStringAsFixed(1)}');
    }
  }

  // (5) Decay potentiel sur axe très investi : axe lié à une spec investie
  //     ≥ 2 pts, lastSeen plus vieux que kDecayAfterSessions (=4).
  const decayWindow = 4;
  final invested = <SpecBranch, List<CapabilityAxis>>{
    SpecBranch.endurance: [
      CapabilityAxis.holdThroatStreak,
      CapabilityAxis.holdFullStreak,
      CapabilityAxis.gorgeEngagementStreak,
      CapabilityAxis.effortNoBreathStreak,
    ],
    SpecBranch.profondeur: [
      CapabilityAxis.rhythmDepthMax,
      CapabilityAxis.gorgeApneeStreak,
      CapabilityAxis.gorgeCrossingsBpmThroat,
      CapabilityAxis.gorgeCrossingsBpmFull,
    ],
    SpecBranch.rythmeBiffle: [
      CapabilityAxis.rhythmMotionStreak,
      CapabilityAxis.rhythmBpmCeilThroat,
      CapabilityAxis.biffleStreak,
      CapabilityAxis.biffleBpmMax,
    ],
    SpecBranch.sloppy: [
      CapabilityAxis.noswallowStreak,
      CapabilityAxis.lickStreak,
    ],
    SpecBranch.obeissance: const [],
  };
  invested.forEach((branch, axes) {
    if (profile.branchPts(branch) < 2) return;
    for (final axis in axes) {
      final st = state.caps[axis];
      if (st == null) {
        coherence.add('AXIS-IDLE  ${axis.storageKey} jamais touché malgré '
            '${profile.branchPts(branch)} pts ${branch.name}');
        continue;
      }
      final gap = state.sessionIndex - st.lastSeen;
      if (gap >= decayWindow) {
        coherence.add('AXIS-DECAY  ${axis.storageKey} non sollicité depuis '
            '$gap sessions (best=${st.best.toStringAsFixed(1)}) — '
            'comfort pourrait décliner alors que ${branch.name} a '
            '${profile.branchPts(branch)} pts');
      }
    }
  });

  return SimResult(
    profile: profile,
    timeline: timeline,
    finalState: state,
    coherenceIssues: coherence,
    unreachedMilestones: unreached,
    sessionsForCompletionMilestones: sessionsForCompletionMilestones,
    catalog: catalog,
  );
}

void _pushBest(
    SimState s, CapabilityAxis axis, double reached, int sessionIdx) {
  final cur = s.caps[axis];
  final minimize = axis.recordKind == CapabilityRecordKind.minimize;
  final accumulate = axis.recordKind == CapabilityRecordKind.accumulate;
  if (cur == null) {
    s.caps[axis] = CapState(reached, sessionIdx);
    return;
  }
  if (accumulate) {
    cur.best += reached;
  } else if (minimize) {
    if (reached < cur.best) cur.best = reached;
  } else {
    if (reached > cur.best) cur.best = reached;
  }
  cur.lastSeen = sessionIdx;
}

/// Réplique des constantes `ObedienceEngine` — l'engine lui-même n'a pas
/// d'effets de bord, mais on évite d'instancier le moteur pour rester
/// dans une logique purement fonctionnelle ici.
class ObedienceEngineConst {
  static const double tickIntervalSec = 120.0;
  static const double bumpPerInterval = 1.0;
  static const double bumpPunishmentCompleted = 2.0;
  static const double bumpSessionClean = 3.0;
  static const double malusFail = 2.0;
  static const double malusPunishmentAbandoned = 5.0;
}

// ─── Rendu ────────────────────────────────────────────────────────────────

String _renderMarkdown(SimResult r) {
  final b = StringBuffer();
  final p = r.profile;
  b.writeln('# ${p.name}');
  b.writeln();
  b.writeln('> ${p.description}');
  b.writeln();
  final alloc =
      SpecBranch.values.map((br) => '${br.name}=${p.branchPts(br)}').join(', ');
  b.writeln('Allocation : $alloc');
  b.writeln();
  b.writeln('Probas : fail=${p.failProba}, encore=${p.encoreProba}, '
      'quickie=${p.quickieProba}, milestone-clean=${p.milestoneCleanProba}');
  b.writeln();

  // Timeline
  b.writeln('## Timeline (${r.timeline.length} sessions)');
  b.writeln();
  b.writeln(
      '| # | sessions | temps | rep | humil | obed | milestone (body / final) | challenge | outcome | unlocks | axes touchés |');
  b.writeln('|---:|---:|---:|---:|---:|---:|---|---|---|---|---|');
  for (final t in r.timeline) {
    final body = t.milestoneBody2Inserted != null
        ? '${t.milestoneBodyInserted ?? '—'} + ${t.milestoneBody2Inserted}'
        : (t.milestoneBodyInserted ?? '—');
    final fin = t.milestoneFinalInserted ?? '—';
    final unlocks = t.unlocksGained.isEmpty
        ? ''
        : t.unlocksGained.map((u) => u.serialized).join(', ');
    final axes = t.axesTouched.map((a) => a.storageKey).toList()..sort();
    final axesStr = axes.isEmpty
        ? ''
        : (axes.length > 4 ? '${axes.take(4).join(", ")}…' : axes.join(', '));
    final mins = (t.totalSeconds / 60).round();
    final timeStr = mins >= 60
        ? '${mins ~/ 60}h${(mins % 60).toString().padLeft(2, '0')}'
        : '${mins}m';
    b.writeln(
        '| ${t.session} | ${t.sessionsCompleted}${t.synthBumped ? "↑" : ""} '
        '| $timeStr | ${t.reputation.toStringAsFixed(0)} '
        '| ${t.humilCareer.toStringAsFixed(1)} | ${t.obed.toStringAsFixed(1)} | '
        '$body / $fin | ${t.challengeSummary ?? '—'} | ${t.outcome} | $unlocks | $axesStr |');
  }
  b.writeln();

  // Récap
  b.writeln('## Récap');
  b.writeln();
  b.write('- Séances pour atteindre ');
  b.writeln(r.sessionsForCompletionMilestones.entries
      .map((e) => '${e.key} compl.=${e.value ?? "—"}')
      .join(', '));
  final finalMins = (r.finalState.totalSeconds / 60).round();
  final finalTime = finalMins >= 60
      ? '${finalMins ~/ 60}h${(finalMins % 60).toString().padLeft(2, '0')}'
      : '${finalMins}m';
  b.writeln('- Sessions complétées : ${r.finalState.sessionsCompleted}');
  b.writeln('- Temps de jeu cumulé : $finalTime');
  b.writeln(
      '- Réputation finale : ${r.finalState.reputation.toStringAsFixed(0)}');
  b.writeln(
      '- Humil career final : ${r.finalState.humilCareer.toStringAsFixed(1)}');
  b.writeln('- Obédiance finale : ${r.finalState.obed.toStringAsFixed(1)}');
  b.writeln('- Unlocks acquis (${r.finalState.unlocked.length}) :');
  for (final h in r.finalState.unlockHistory) {
    b.writeln('  - s${h.session}  ${h.key.serialized}  ← ${h.milestone}');
  }
  if (r.unreachedMilestones.isNotEmpty) {
    b.writeln(
        '- Milestones jamais déclenchées (${r.unreachedMilestones.length}) :');
    for (final u in r.unreachedMilestones) {
      b.writeln('  - ${u.id} — ${u.reason}');
    }
  }
  b.writeln();

  // ─── Défis ─────────────────────────────────────────────────────────────
  final cc = r.finalState.challengeCounts;
  final totalCh = cc.values.fold<int>(0, (a, b) => a + b);
  if (totalCh > 0) {
    b.writeln('## Défis intra-séance');
    b.writeln();
    String pct(int n) =>
        totalCh == 0 ? '—' : '(${(100 * n / totalCh).toStringAsFixed(0)} %)';
    final skillStart = r.profile.skillLevel;
    final skillEnd = r.profile.currentSkillAt(r.timeline.length);
    final skillStr = skillStart == skillEnd
        ? skillStart.toStringAsFixed(2)
        : '${skillStart.toStringAsFixed(2)} → ${skillEnd.toStringAsFixed(2)}';
    b.writeln(
        '- Total : $totalCh défi(s) joué(s) sur ${r.timeline.length} sessions '
        '(skill=$skillStr)');
    b.writeln('- Distribution : '
        'tut=${cc[SimChallengeOutcome.tutorial]} ${pct(cc[SimChallengeOutcome.tutorial] ?? 0)}, '
        'net=${cc[SimChallengeOutcome.netSuccess]} ${pct(cc[SimChallengeOutcome.netSuccess] ?? 0)}, '
        'ext=${cc[SimChallengeOutcome.extendedSuccess]} ${pct(cc[SimChallengeOutcome.extendedSuccess] ?? 0)}, '
        'fail=${cc[SimChallengeOutcome.fail]} ${pct(cc[SimChallengeOutcome.fail] ?? 0)}, '
        'skip=${cc[SimChallengeOutcome.skipped]} ${pct(cc[SimChallengeOutcome.skipped] ?? 0)}');
    if (r.finalState.challengePushedBest.isNotEmpty) {
      final entries = r.finalState.challengePushedBest.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      b.writeln('- Axes records poussés via défi :');
      for (final e in entries) {
        b.writeln('  - ${e.key.storageKey} → ${e.value.toStringAsFixed(1)}');
      }
    }
    if (r.finalState.challengeUnlocksGained > 0) {
      b.writeln('- Unlocks gagnés via défi (cascade incluse) : '
          '${r.finalState.challengeUnlocksGained}');
    }
    b.writeln();
  }

  // Lag à l'acquisition — métrique « overdue ». Pour chaque unlock
  // acquis : delta entre la session d'acquisition et la 1ʳᵉ session où
  // `playerLevel ≥ minLevel - branchAdvance` (= minLevel effectif après
  // avance de spé). Un lag élevé signifie qu'une milestone candidate
  // depuis longtemps est restée à la trappe.
  final byId = {for (final m in r.catalog) m.id: m};
  final lagsByMilestone = <({String id, int lag, int acquired})>[];
  for (final h in r.finalState.unlockHistory) {
    final m = byId[h.milestone];
    if (m == null) continue;
    if (m.placement != MilestonePlace.body) continue;
    final advance = _branchAdvance(m, r.profile);
    final effectiveMin = m.minLevel - advance;
    int? firstReached;
    for (final t in r.timeline) {
      if (t.synthLevel >= effectiveMin) {
        firstReached = t.session;
        break;
      }
    }
    if (firstReached == null) continue;
    final lag = h.session - firstReached;
    lagsByMilestone.add((id: m.id, lag: lag, acquired: h.session));
  }
  if (lagsByMilestone.isNotEmpty) {
    final lags = lagsByMilestone.map((e) => e.lag).toList()..sort();
    final maxLag = lags.last;
    final sum = lags.fold<int>(0, (a, b) => a + b);
    final mean = sum / lags.length;
    final median = lags.length.isOdd
        ? lags[lags.length ~/ 2].toDouble()
        : (lags[lags.length ~/ 2 - 1] + lags[lags.length ~/ 2]) / 2.0;
    final overdueCount =
        lagsByMilestone.where((e) => e.lag >= 5).toList(growable: false);
    // Histogramme : 0 / 1-2 / 3-4 / 5-9 / ≥10. Sert à voir la distribution
    // au-delà du seul max et du seuil overdue ; permet de valider que la
    // règle « overdue d'abord » du prompt 3 raccourcit bien la queue droite.
    var h0 = 0, h12 = 0, h34 = 0, h59 = 0, h10p = 0;
    for (final v in lags) {
      if (v == 0) {
        h0++;
      } else if (v <= 2) {
        h12++;
      } else if (v <= 4) {
        h34++;
      } else if (v <= 9) {
        h59++;
      } else {
        h10p++;
      }
    }
    b.writeln('## Lag à l\'acquisition');
    b.writeln(
        '- max lag (body) : $maxLag session(s) ; milestones avec lag ≥ 5 : '
        '${overdueCount.length}');
    b.writeln('- lag moyen : ${mean.toStringAsFixed(2)} ; médiane : '
        '${median.toStringAsFixed(1)} sur ${lags.length} body acquises');
    b.writeln(
        '- histogramme : 0=$h0 | 1-2=$h12 | 3-4=$h34 | 5-9=$h59 | ≥10=$h10p');
    if (overdueCount.isNotEmpty) {
      for (final e in overdueCount) {
        b.writeln('  - ${e.id} acquise s${e.acquired} (lag ${e.lag})');
      }
    }
    b.writeln();
  }

  // Cohérence
  b.writeln('## Rapport de cohérence');
  if (r.coherenceIssues.isEmpty) {
    b.writeln('Aucune incohérence détectée.');
  } else {
    for (final c in r.coherenceIssues) {
      b.writeln('- $c');
    }
  }
  b.writeln();
  b.writeln('---');
  b.writeln();
  return b.toString();
}

String _renderTsv(SimResult r) {
  final b = StringBuffer();
  b.writeln('# profile\t${r.profile.name}');
  b.writeln('# skill_init\t${r.profile.skillLevel.toStringAsFixed(2)}');
  b.writeln(
      '# skill_growth\t${r.profile.skillGrowthPerSession.toStringAsFixed(4)}');
  b.writeln(
      '# skill_final\t${r.profile.currentSkillAt(r.timeline.length).toStringAsFixed(2)}');
  b.writeln(
      'session\tsessionsCompleted\ttotalSeconds\treputation\thumil\tobed\tbody\tbody2\tfinal\tchallenge\toutcome\tunlocks\taxes');
  for (final t in r.timeline) {
    b.writeln([
      t.session,
      t.sessionsCompleted,
      t.totalSeconds,
      t.reputation.toStringAsFixed(1),
      t.humilCareer.toStringAsFixed(1),
      t.obed.toStringAsFixed(1),
      t.milestoneBodyInserted ?? '',
      t.milestoneBody2Inserted ?? '',
      t.milestoneFinalInserted ?? '',
      t.challengeSummary ?? '',
      t.outcome,
      t.unlocksGained.map((u) => u.serialized).join(','),
      t.axesTouched.map((a) => a.storageKey).join(','),
    ].join('\t'));
  }
  b.writeln('# unreached');
  for (final u in r.unreachedMilestones) {
    b.writeln('${u.id}\t${u.reason}');
  }
  b.writeln('# coherence');
  for (final c in r.coherenceIssues) {
    b.writeln(c);
  }
  return b.toString();
}

// ─── CLI ──────────────────────────────────────────────────────────────────

class _Args {
  final List<String> profiles;
  final int? sessionsOverride;
  final int seed;
  final String format;
  final String? outPath;
  final bool capsTable;
  _Args(this.profiles, this.sessionsOverride, this.seed, this.format,
      this.outPath, this.capsTable);
}

_Args _parseArgs(List<String> argv) {
  final profiles = <String>[];
  int? sessionsOverride;
  var seed = 42;
  var format = 'markdown';
  String? outPath;
  var capsTable = false;
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    String next() {
      if (i + 1 >= argv.length) {
        stderr.writeln('option $a sans valeur');
        exit(2);
      }
      return argv[++i];
    }

    switch (a) {
      case '--profile':
        profiles.addAll(next().split(','));
        break;
      case '--sessions':
        sessionsOverride = int.parse(next());
        break;
      case '--seed':
        seed = int.parse(next());
        break;
      case '--format':
        format = next();
        break;
      case '--out':
        outPath = next();
        break;
      case '--caps-table':
        capsTable = true;
        break;
      case '-h':
      case '--help':
        stdout.writeln('Usage: dart run tools/simulate_career.dart [options]\n'
            '  --profile <a,b,...>    profils à simuler (défaut : tous)\n'
            '  --sessions <N>         override du nombre de sessions par profil\n'
            '  --seed <n>             seed RNG (défaut 42)\n'
            '  --format markdown|tsv  format de sortie (défaut markdown)\n'
            '  --out <path>           fichier de sortie (défaut stdout)\n'
            '  --caps-table           génère un tableau BPM/durée par niveau\n'
            '                         à la place de la simulation\n');
        exit(0);
      default:
        stderr.writeln('option inconnue : $a');
        exit(2);
    }
  }
  return _Args(profiles, sessionsOverride, seed, format, outPath, capsTable);
}

// ─── Tableau analytique BPM / durée par niveau ────────────────────────────
//
// Reproduit les formules de `CareerSessionGenerator._pickFinal` et de la
// phase finish (boosts BPM). Sert à répondre à la question « pour une
// joueuse qui performe, qu'est-ce qu'elle ressent à chaque niveau ? »
// sans avoir à instancier le générateur (qui dépend de flutter/foundation).
//
// Source de vérité :
// - hold throat : `target = clamp(10 + (humilOver/5).floor()*2 + endPts*2, 10, 40)`
//   avec `humilOver = max(0, humilCap - 10)` — cf. career_session_generator.dart §3358.
// - hold full : `target = clamp(10 + (humilOver/8).floor()*3 + endPts*3, 10, 80)`
//   avec `humilOver = max(0, humilCap - 30)` — cf. career_session_generator.dart §3389.
// - BPM cap boosts : hand = `clamp(110 + (level-1)*4, 110, 170)`,
//   rhythm = `clamp(130 + (level-1)*4, 130, 180)` — cf. §1230-1234.
// - maxDepth : level ≤ 2 → mid max ; level 3 → throat ; level 4+ → full
//   — cf. `CareerLevel._maxDepthForLevel`.

int _maxDepthIndexFor(int level) {
  if (level <= 2) return 2;
  if (level <= 3) return 3;
  return 4;
}

int _holdThroatTarget({required double humilCap, required int endPts}) {
  final humilOver = (humilCap - 10) < 0 ? 0.0 : (humilCap - 10);
  final v = 10 + (humilOver / 5).floor() * 2 + endPts * 2;
  return v.clamp(10, 80);
}

int _holdFullTarget({required double humilCap, required int endPts}) {
  final humilOver = (humilCap - 30) < 0 ? 0.0 : (humilCap - 30);
  final v = 10 + (humilOver / 8).floor() * 3 + endPts * 3;
  return v.clamp(10, 80);
}

int _bpmBoostHand(int level) =>
    ((110 + (level - 1) * 4).clamp(110, 300)).toInt();
int _bpmBoostRhythm(int level) =>
    ((130 + (level - 1) * 4).clamp(130, 300)).toInt();

/// Humiliation cap "typique chez quelqu'un qui performe" en fin de séance
/// (`careerScore + sessionScore` à la phase finish). Calé empiriquement sur
/// les valeurs observées pour `purist_endurance` dans la simulation (seed 42) :
/// L5 → ~70, L10 → ~115, L15 → ~160, L20 → ~200.
double _perfHumilCapAtFinish(int level) => 30.0 + level * 8.5;

/// Estimation du `comfort` throat tenu par une joueuse "perf endurance" qui
/// surcharge à chaque séance et réussit (ratchet ↑ ~+12 %/session, cf.
/// `CapabilityRegulator.regulate`). Modélise le clamp `_clampToCapability`
/// qui borne la durée du hold final à `comfort × surcharge`. Paliers
/// milestones :
/// - L6 : `intro_hold_throat_short` tenu 3 s → best=3 → comfort=3.
/// - L8 : `intro_hold_throat_long` tenu 8 s → best=8 → comfort=8.
/// Ratchet entre les paliers : `comfort × 1.12` par session. Capé au plafond
/// dur `_pickFinal` (80 s throat & full depuis relax cap).
double? _estComfortThroat(int level) {
  if (level < 6) return null;
  final base = level < 8 ? 3.0 : 8.0;
  final levelsSinceBump = level < 8 ? (level - 6) : (level - 8);
  final v = base * pow(1.12, levelsSinceBump);
  return v > 80.0 ? 80.0 : v.toDouble();
}

double? _estComfortFull(int level) {
  if (level < 11) return null;
  final base = level < 13 ? 3.0 : 10.0;
  final levelsSinceBump = level < 13 ? (level - 11) : (level - 13);
  final v = base * pow(1.12, levelsSinceBump);
  return v > 80.0 ? 80.0 : v.toDouble();
}

/// Comfort BPM rythme dans la bande superficielle (`to ≤ mid`). Paliers
/// milestones qui établissent le `best` :
/// - L1 : `intro_basics` joue rhythm head→mid à 90 BPM → comfort=90.
/// - L3 : `intro_deeper_basics` pousse à 100 puis 110 → comfort=110.
/// `intro_rhythm_sustained` (L6) joue aussi à 110 BPM mais le ratchet est
/// déjà bien au-delà à ce stade — pas de reset milestone.
/// Ratchet ensuite ~+10 %/session pour une joueuse rythme/biffle.
double _estComfortBpmShallow(int level) {
  final double base;
  final int levelsSinceBump;
  if (level < 3) {
    base = 90;
    levelsSinceBump = level - 1;
  } else {
    base = 110;
    levelsSinceBump = level - 3;
  }
  final v = base * pow(1.10, levelsSinceBump);
  return v > 300.0 ? 300.0 : v.toDouble();
}

/// Comfort BPM rythme dans la bande throat (`to = throat`). Paliers :
/// - L10 : `intro_throat_pulse` joue rhythm head→throat à 80 BPM → comfort=80.
/// - L15 : `intro_rhythm_extreme` pousse à 165 BPM (saut massif) → comfort=165.
/// Avant L10 : pas de donnée (throat-rhythm non débloqué côté `rhythm.depth_max`).
double? _estComfortBpmThroat(int level) {
  if (level < 10) return null;
  final base = level < 15 ? 80.0 : 165.0;
  final levelsSinceBump = level < 15 ? (level - 10) : (level - 15);
  final v = base * pow(1.10, levelsSinceBump);
  return v > 300.0 ? 300.0 : v.toDouble();
}

/// Comfort BPM biffle. Paliers :
/// - L5 : `intro_biffle` joue biffle à 45 BPM → comfort=45 (lent et appliqué,
///   premiers coups de queue).
/// - L9 : `intro_biffle_fast` joue biffle à 140 BPM → comfort=140 (saut).
double? _estComfortBpmBiffle(int level) {
  if (level < 5) return null;
  final base = level < 9 ? 45.0 : 140.0;
  final levelsSinceBump = level < 9 ? (level - 5) : (level - 9);
  final v = base * pow(1.10, levelsSinceBump);
  return v > 300.0 ? 300.0 : v.toDouble();
}

String _renderCapsTable() {
  final b = StringBuffer();
  b.writeln('# Durée holds / BPM boosts par niveau — joueuse "qui performe"');
  b.writeln();
  b.writeln('Toutes les durées sont au moment du **final d\'apothéose**.'
      ' On compare la **valeur effective** (= ce que la joueuse voit) à la'
      ' formule théorique (= plafond `_pickFinal` avant le clamp `comfort`).');
  b.writeln();
  b.writeln('Sources :');
  b.writeln('- Hold throat : `target = clamp(10 + (humilOver/5)·2 + endPts·2,'
      ' 10, 80)` (`career_session_generator.dart` §3358 — cap aligné sur full).');
  b.writeln('- Hold full : `target = clamp(10 + (humilOver/8)·3 + endPts·3,'
      ' 10, 80)` (§3389).');
  b.writeln('- BPM boosts : `hand = clamp(110 + (level-1)·4, 110, 300)`,'
      ' `rhythm = clamp(130 + (level-1)·4, 130, 300)` (§1230-1234 — caps relâchés).');
  b.writeln('- Comfort estimé : ratchet +10 à +12 %/session sur l\'axe poussé'
      ' (`CapabilityRegulator.regulate`). Bumps milestones :'
      ' throat 3 s (L6), 8 s (L8) ; full 3 s (L11), 10 s (L13) ;'
      ' BPM rhythme shallow 90 (L1), 110 (L3) ; BPM rhythme throat 80 (L10),'
      ' 165 (L15) ; BPM biffle 45 (L5), 140 (L9).');
  b.writeln();
  b.writeln('**Hypothèse joueuse perf** : 5 pts endurance, humil mature'
      ' (`humilCap = 30 + level × 8.5`), zéro fail, surcharge réussie à'
      ' chaque séance sur l\'axe poussé. Le `comfort` ratchet vers le haut'
      ' régulièrement.');
  b.writeln();
  b.writeln(
      '| L | durée séance | humilCap | comfort throat (effectif) | formule throat endPts=5 | comfort full (effectif) | formule full endPts=5 | BPM hand | BPM rythme |');
  b.writeln('|---:|---:|---:|---:|---:|---:|---:|---:|---:|');

  for (var l = 1; l <= 25; l++) {
    final humil = _perfHumilCapAtFinish(l);
    final mins = _durationForLevel(l) ~/ 60;
    final cThroat = _estComfortThroat(l);
    final cFull = _estComfortFull(l);
    final theoThroat = _maxDepthIndexFor(l) >= 3
        ? '${_holdThroatTarget(humilCap: humil, endPts: 5)}s'
        : '—';
    final theoFull = _maxDepthIndexFor(l) >= 4
        ? '${_holdFullTarget(humilCap: humil, endPts: 5)}s'
        : '—';
    final effThroat =
        cThroat == null ? '—' : '**${cThroat.toStringAsFixed(1)}s**';
    final effFull = cFull == null ? '—' : '**${cFull.toStringAsFixed(1)}s**';
    b.writeln('| $l | $mins min | ${humil.toStringAsFixed(0)} | '
        '$effThroat | $theoThroat | $effFull | $theoFull | '
        '${_bpmBoostHand(l)} | ${_bpmBoostRhythm(l)} |');
  }
  b.writeln();
  b.writeln('## BPM main loop — comfort effectif par axe');
  b.writeln();
  b.writeln('Le BPM des steps **dans le main loop** est borné par le `comfort`'
      ' de l\'axe correspondant (cf. `_capabilityCapFor` dans le générateur).'
      ' Le BPM boost de la phase finish (colonnes "BPM hand / rythme" ci-dessus)'
      ' est lui borné par le cap niveau, mais celui-ci passe maintenant à 300 —'
      ' c\'est le comfort qui régule en pratique.');
  b.writeln();
  b.writeln(
      '| L | comfort rhythm shallow (head→mid) | comfort rhythm throat (head→throat) | comfort biffle |');
  b.writeln('|---:|---:|---:|---:|');
  for (var l = 1; l <= 25; l++) {
    final shallow = _estComfortBpmShallow(l);
    final throat = _estComfortBpmThroat(l);
    final biffle = _estComfortBpmBiffle(l);
    String fmt(double? v) =>
        v == null ? '—' : '**${v.toStringAsFixed(0)} BPM**';
    b.writeln(
        '| $l | **${shallow.toStringAsFixed(0)} BPM** | ${fmt(throat)} | ${fmt(biffle)} |');
  }
  b.writeln();
  b.writeln('## Lecture');
  b.writeln();
  b.writeln('### Durées vécues (colonnes "effectif" du 1er tableau)');
  b.writeln();
  b.writeln(
      '- **Premier hold throat** = 3 s à L6 (post `intro_hold_throat_short`).'
      ' Reste sous 5 s jusqu\'à L7 inclus.');
  b.writeln('- **Saut L8** : `intro_hold_throat_long` pousse `best` à 8 s →'
      ' comfort = 8 s. Le finale peut tenir ~8 s d\'un coup.');
  b.writeln('- **Throat à L15** : ~18 s seulement. À L20 : ~31 s. Le cap dur'
      ' 80 s est inatteignable dans la progression normale.');
  b.writeln(
      '- **Premier hold full** = 3 s à L11 (post `intro_hold_full_short`).');
  b.writeln(
      '- **Saut L13** : `intro_hold_full_long` → best=10 s → comfort=10 s.');
  b.writeln('- **Full à L20** : ~22 s effectifs. Le cap 80 s n\'est jamais'
      ' atteint sur 25 levels par ce modèle de progression.');
  b.writeln();
  b.writeln('### BPM vécus (2e tableau)');
  b.writeln();
  b.writeln('- **Rhythm shallow** (head→mid) : démarre à 90 BPM dès L1 grâce'
      ' à `intro_basics`, bump à 110 à L3 (`intro_deeper_basics`), puis ratchet'
      ' lent (+10 %/session). À L10 ~177 BPM, L15 ~285 BPM, L17+ capé 300.');
  b.writeln('- **Rhythm throat** (head→throat) : pas avant L10 (gate'
      ' `intro_throat_pulse`). Démarre à 80 BPM, ratchet jusqu\'à `intro_rhythm_extreme`'
      ' à L15 qui pousse à 165 BPM en un saut. Ensuite ratchet continue.');
  b.writeln('- **Biffle** : démarre à 45 BPM à L5 (`intro_biffle`, lent et'
      ' appliqué pour les premiers coups), bump à 140 à L9 (`intro_biffle_fast`,'
      ' saut massif x3), ratchet ensuite.');
  b.writeln();
  b.writeln('### Écart formule vs comfort');
  b.writeln();
  b.writeln('L\'écart entre les colonnes "formule" (qui peut saturer haut) et'
      ' "effectif" (qui suit le comfort) montre que **le système de monitoring'
      ' pilote la valeur vécue** — durée comme BPM. Les caps prod (80 s holds,'
      ' 300 BPM boosts) ne servent que de garde-fous en mode hérité (Custom /'
      ' scénarios sans profil de capacités).');
  b.writeln();
  b.writeln('## Caveats');
  b.writeln();
  b.writeln('- Le modèle ratchet `× 1.10-1.12` suppose **surcharge réussie à'
      ' chaque session**. Une joueuse qui rate ratraperait moins vite : tap-out'
      ' imputé → comfort × 0.85 (cf. `CapabilityRegulator.kRatchetDownFactor`).');
  b.writeln('- Le comfort ne peut **pas dépasser** `reached × 1.05` (ancrage,'
      ' `kRatchetAnchorHeadroom`). En pratique : il faut **vraiment** tenir la'
      ' nouvelle valeur pour que le ratchet la consolide. Le modèle suppose que'
      ' la surcharge proposée est tenue à chaque fois — c\'est optimiste.');
  b.writeln('- La courbe BPM main loop est différente du BPM boost (qui'
      ' lui est borné par le cap niveau, plus le comfort de l\'axe). Le'
      ' boost peut être encore plus haut que le main loop (sprint).');
  return b.toString();
}

void main(List<String> argv) {
  final args = _parseArgs(argv);

  if (args.capsTable) {
    final out = _renderCapsTable();
    if (args.outPath != null) {
      File(args.outPath!).writeAsStringSync(out);
      stderr.writeln('écrit dans ${args.outPath}');
    } else {
      stdout.write(out);
    }
    return;
  }

  final milestonesFile = File('assets/career/milestones.json');
  if (!milestonesFile.existsSync()) {
    stderr.writeln(
        'assets/career/milestones.json absent — lance depuis rhythm_coach/');
    exit(2);
  }
  final catalog = _loadMilestones(milestonesFile);

  final allProfiles = _builtinProfiles();
  var selected = allProfiles;
  if (args.profiles.isNotEmpty) {
    final names = args.profiles.toSet();
    selected = allProfiles.where((p) => names.contains(p.name)).toList();
    if (selected.isEmpty) {
      stderr.writeln(
          'aucun profil reconnu parmi ${allProfiles.map((p) => p.name).join(", ")}');
      exit(2);
    }
  }

  final out = StringBuffer();
  if (args.format == 'markdown') {
    out.writeln('# Simulation carrière BeatBitch');
    out.writeln();
    out.writeln(
        '${catalog.length} milestones, ${selected.length} profil(s), seed=${args.seed}.');
    out.writeln();
  }
  for (final p in selected) {
    final pSessions = args.sessionsOverride != null
        ? SimProfile(
            name: p.name,
            description: p.description,
            allocation: p.allocation,
            failProba: p.failProba,
            encoreProba: p.encoreProba,
            quickieProba: p.quickieProba,
            milestoneCleanProba: p.milestoneCleanProba,
            miniPunRate: p.miniPunRate,
            sessions: args.sessionsOverride!,
            axisTargets: p.axisTargets,
            skillLevel: p.skillLevel,
            skillGrowthPerSession: p.skillGrowthPerSession,
            challengeSkipProba: p.challengeSkipProba,
          )
        : p;
    final r = _runSim(profile: pSessions, catalog: catalog, seed: args.seed);
    out.write(args.format == 'tsv' ? _renderTsv(r) : _renderMarkdown(r));
  }

  if (args.outPath != null) {
    File(args.outPath!).writeAsStringSync(out.toString());
    stderr.writeln('écrit dans ${args.outPath}');
  } else {
    stdout.write(out.toString());
  }
}
