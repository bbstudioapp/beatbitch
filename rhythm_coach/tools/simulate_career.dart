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
/// Usage : `dart run tools/simulate_career.dart [--profile <name>] [--sessions
/// <N>] [--seed <n>] [--format markdown|tsv] [--out <path>]` depuis
/// `rhythm_coach/`. Sans `--profile`, tourne sur tous les profils embarqués.
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
  });

  int branchPts(SpecBranch b) => allocation[b] ?? 0;
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
  int level = 1;
  int sessionIndex = 0;
  Set<UnlockKey> unlocked = <UnlockKey>{};
  Set<String> completedMilestones = <String>{};
  Map<CapabilityAxis, CapState> caps = <CapabilityAxis, CapState>{};
  // Compteur de candidature (id milestone → sessions où elle est candidate
  // mais non sélectionnée). Cf. `MilestoneService.incrementCandidacyAge`.
  Map<String, int> candidacyAge = <String, int>{};
  // ordre d'acquisition des unlocks (clé → n° session)
  List<({UnlockKey key, int session, String milestone})> unlockHistory = [];
}

// ─── Enregistrement timeline ──────────────────────────────────────────────

class TimelineRow {
  final int session;
  final int level;
  final double humilCareer;
  final double obed;
  final List<UnlockKey> unlocksGained;
  final String? milestoneBodyInserted;
  final String? milestoneBody2Inserted;
  final String? milestoneFinalInserted;
  final String outcome; // clean / fail / abandon / encore / quickie
  final List<CapabilityAxis> axesTouched;
  final bool levelUp;

  TimelineRow({
    required this.session,
    required this.level,
    required this.humilCareer,
    required this.obed,
    required this.unlocksGained,
    required this.milestoneBodyInserted,
    this.milestoneBody2Inserted,
    required this.milestoneFinalInserted,
    required this.outcome,
    required this.axesTouched,
    required this.levelUp,
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
      .where((m) => (m.minLevel - _branchAdvance(m, profile)) <= state.level)
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
  candidates.sort((a, b) {
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
        break;
    }
  }
  flush();
  return out;
}

// ─── Catalogue des 6 profils ──────────────────────────────────────────────

/// Bornage d'un push d'axe — évite que des cibles trop ambitieuses laissent
/// croire qu'une débutante tient 80 s de gorge dès la 1ʳᵉ séance.
double _clampGrowth(double v, double absoluteMax) {
  if (v < 0) return 0;
  return v > absoluteMax ? absoluteMax : v;
}

List<SimProfile> _builtinProfiles() {
  return [
    SimProfile(
      name: 'purist_endurance',
      description: 'Durée et tenues : holds throat/full longs, motion streak '
          'régulier. Zéro fail volontaire. Aucune bâclée. 5 pts endurance.',
      allocation: {
        SpecBranch.endurance: 5,
      },
      failProba: 0.02,
      encoreProba: 0.40,
      quickieProba: 0.0,
      milestoneCleanProba: 0.96,
      miniPunRate: 0.10,
      sessions: 30,
      axisTargets: (level, p) => {
        CapabilityAxis.holdThroatStreak: _clampGrowth(
            1.5 + 0.6 * level + 0.4 * p.branchPts(SpecBranch.endurance), 35),
        CapabilityAxis.holdFullStreak: _clampGrowth(
            0.5 + 0.35 * level + 0.3 * p.branchPts(SpecBranch.endurance), 22),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(2 + 0.4 * level, 28),
        CapabilityAxis.gorgeEngagementStreak: _clampGrowth(5 + 1.0 * level, 60),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(15 + 2.0 * level, 70),
        CapabilityAxis.effortNoBreathStreak: _clampGrowth(20 + 3.0 * level, 90),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(2.0 + level / 6.0, 4), 4),
      },
    ),
    SimProfile(
      name: 'profondeur_brutale',
      description: 'Va chercher loin et vite. Pousse rhythm depth + apnée + '
          'BPM throat. Quelques fails sur les pushes (10 %). 4 pts profondeur '
          '+ 1 pt rythmeBiffle.',
      allocation: {
        SpecBranch.profondeur: 4,
        SpecBranch.rythmeBiffle: 1,
      },
      failProba: 0.10,
      encoreProba: 0.25,
      quickieProba: 0.05,
      milestoneCleanProba: 0.85,
      miniPunRate: 0.18,
      sessions: 30,
      axisTargets: (level, p) => {
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(2.5 + level / 5.0, 4), 4),
        CapabilityAxis.gorgeApneeStreak: _clampGrowth(
            2 + 0.6 * level + 0.4 * p.branchPts(SpecBranch.profondeur), 35),
        CapabilityAxis.gorgeCrossingsBpmThroat: _clampGrowth(
            80 + 4 * level + 1.5 * p.branchPts(SpecBranch.profondeur), 165),
        CapabilityAxis.gorgeCrossingsBpmFull:
            _clampGrowth(70 + 3.0 * level, 140),
        CapabilityAxis.gorgeCrossingsLifetime: 5.0 + level.toDouble(),
        CapabilityAxis.rhythmBpmCeilThroat: _clampGrowth(90.0 + 5 * level, 180),
        CapabilityAxis.rhythmBpmCeilFull: _clampGrowth(80.0 + 4 * level, 160),
        CapabilityAxis.holdThroatStreak: _clampGrowth(1 + 0.4 * level, 22),
        CapabilityAxis.holdFullStreak: _clampGrowth(0.5 + 0.3 * level, 18),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(12 + 1.5 * level, 55),
      },
    ),
    SimProfile(
      name: 'sloppy_obeissante',
      description: 'Beg + lick humide + noswallow. Peu de fail. 3 pts sloppy '
          '+ 2 pts obéissance.',
      allocation: {
        SpecBranch.sloppy: 3,
        SpecBranch.obeissance: 2,
      },
      failProba: 0.04,
      encoreProba: 0.50,
      quickieProba: 0.0,
      milestoneCleanProba: 0.92,
      miniPunRate: 0.14,
      sessions: 30,
      axisTargets: (level, p) => {
        CapabilityAxis.noswallowStreak: _clampGrowth(
            3 + 1.0 * level + 0.5 * p.branchPts(SpecBranch.sloppy), 60),
        CapabilityAxis.lickStreak: _clampGrowth(
            15 + 2.5 * level + 1.0 * p.branchPts(SpecBranch.sloppy), 70),
        CapabilityAxis.lickDepthMax: _clampGrowth(min(1.5 + level / 6.0, 4), 4),
        CapabilityAxis.rhythmMotionStreak: _clampGrowth(10 + 1.5 * level, 50),
        CapabilityAxis.rhythmDepthMax:
            _clampGrowth(min(1.5 + level / 8.0, 3), 3),
        CapabilityAxis.holdThroatStreak: _clampGrowth(0.5 + 0.25 * level, 12),
      },
    ),
    SimProfile(
      name: 'hybride_prudente',
      description: 'Allocation 1-1-1-1-1, valeurs modérées partout. Très peu '
          'de fail. Profil "tortue qui finit la course".',
      allocation: {
        SpecBranch.endurance: 1,
        SpecBranch.profondeur: 1,
        SpecBranch.rythmeBiffle: 1,
        SpecBranch.obeissance: 1,
        SpecBranch.sloppy: 1,
      },
      failProba: 0.03,
      encoreProba: 0.20,
      quickieProba: 0.05,
      milestoneCleanProba: 0.94,
      miniPunRate: 0.10,
      sessions: 30,
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
  // n° session pour atteindre L5, L10, L15, L20 (ou null si jamais atteint)
  final Map<int, int?> sessionsForLevels;
  SimResult({
    required this.profile,
    required this.timeline,
    required this.finalState,
    required this.coherenceIssues,
    required this.unreachedMilestones,
    required this.sessionsForLevels,
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
  final sessionsForLevels = <int, int?>{5: null, 10: null, 15: null, 20: null};

  for (var i = 0; i < profile.sessions; i++) {
    state.sessionIndex = i + 1;
    final duration = _durationForLevel(state.level);

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
    sessionScore -= failsCount * HumiliationEngine.malusFail; // approximation
    if (sessionScore < 0) sessionScore = 0;
    if (sessionScore > HumiliationEngine.sessionCap) {
      sessionScore = HumiliationEngine.sessionCap;
    }

    // Encore en fin de séance.
    final canEncore = state.level >= 5 &&
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
    obedDelta -= failsCount * ObedienceEngineConst.malusFail;
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
      final profileTargets = profile.axisTargets(state.level, profile);
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

    // Level-up : session terminée sans fail, hors bâclée, à `level` courant.
    // Le simulateur considère le `level` courant = max level (pas de jeu
    // sous-niveau dans le simulateur).
    var leveledUp = false;
    if (cleanSession && !isQuickie) {
      state.level += 1;
      leveledUp = true;
      for (final t in sessionsForLevels.keys) {
        if (sessionsForLevels[t] == null && state.level >= t) {
          sessionsForLevels[t] = state.sessionIndex;
        }
      }
    }

    final outcome = isQuickie
        ? 'quickie${cleanSession ? '+clean' : '+fail'}'
        : (cleanSession
            ? (askedEncore ? 'clean+encore' : 'clean')
            : (bodyOutcome == 'abandon' ? 'abandon' : 'fail'));

    timeline.add(TimelineRow(
      session: state.sessionIndex,
      level: state.level,
      humilCareer: state.humilCareer,
      obed: state.obed,
      unlocksGained: gained,
      milestoneBodyInserted: bodyInsertedId,
      milestoneBody2Inserted: body2InsertedId,
      milestoneFinalInserted: finalInsertedId,
      outcome: outcome,
      axesTouched: touched.toList(),
      levelUp: leveledUp,
    ));
  }

  // ── Rapport de cohérence ──────────────────────────────────────────────
  final coherence = <String>[];
  final unreached = <({String id, String reason})>[];

  for (final m in catalog) {
    if (state.completedMilestones.contains(m.id)) continue;
    final reasons = <String>[];
    if (m.minLevel - _branchAdvance(m, profile) > state.level) {
      reasons.add(
          'level ${state.level} < min ${m.minLevel - _branchAdvance(m, profile)}');
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

  // (3) Palier de niveau bloqué : level a stagné ≥ 5 sessions consécutives.
  //     Un cluster de stagnation produit 1 entrée (pas 1 par session).
  var stagnation = 0;
  int? stagnationStartSession;
  void emitStagnation(int endSession, int level) {
    if (stagnation >= 5 && stagnationStartSession != null) {
      coherence.add('LEVEL-STUCK  niveau $level pendant $stagnation sessions '
          '(s$stagnationStartSession → s$endSession)');
    }
    stagnation = 0;
    stagnationStartSession = null;
  }

  for (var i = 0; i < timeline.length; i++) {
    final r = timeline[i];
    if (!r.levelUp) {
      stagnation++;
      stagnationStartSession ??= r.session;
    } else {
      emitStagnation(r.session - 1, r.level - 1);
    }
  }
  if (timeline.isNotEmpty) {
    emitStagnation(timeline.last.session, timeline.last.level);
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
    final compatible = state.level >= m.minLevel &&
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
    sessionsForLevels: sessionsForLevels,
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
      '| # | lvl | humil | obed | milestone (body / final) | outcome | unlocks | axes touchés |');
  b.writeln('|---:|---:|---:|---:|---|---|---|---|');
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
    b.writeln('| ${t.session} | ${t.level}${t.levelUp ? "↑" : ""} | '
        '${t.humilCareer.toStringAsFixed(1)} | ${t.obed.toStringAsFixed(1)} | '
        '$body / $fin | ${t.outcome} | $unlocks | $axesStr |');
  }
  b.writeln();

  // Récap
  b.writeln('## Récap');
  b.writeln();
  b.write('- Sessions pour atteindre le niveau ');
  b.writeln(r.sessionsForLevels.entries
      .map((e) => 'L${e.key}=${e.value ?? "—"}')
      .join(', '));
  b.writeln('- Niveau final : ${r.finalState.level}');
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
  b.writeln(
      'session\tlevel\thumil\tobed\tbody\tbody2\tfinal\toutcome\tunlocks\taxes');
  for (final t in r.timeline) {
    b.writeln([
      t.session,
      t.level,
      t.humilCareer.toStringAsFixed(1),
      t.obed.toStringAsFixed(1),
      t.milestoneBodyInserted ?? '',
      t.milestoneBody2Inserted ?? '',
      t.milestoneFinalInserted ?? '',
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
  _Args(this.profiles, this.sessionsOverride, this.seed, this.format,
      this.outPath);
}

_Args _parseArgs(List<String> argv) {
  final profiles = <String>[];
  int? sessionsOverride;
  var seed = 42;
  var format = 'markdown';
  String? outPath;
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
      case '-h':
      case '--help':
        stdout.writeln('Usage: dart run tools/simulate_career.dart [options]\n'
            '  --profile <a,b,...>    profils à simuler (défaut : tous)\n'
            '  --sessions <N>         override du nombre de sessions par profil\n'
            '  --seed <n>             seed RNG (défaut 42)\n'
            '  --format markdown|tsv  format de sortie (défaut markdown)\n'
            '  --out <path>           fichier de sortie (défaut stdout)\n');
        exit(0);
      default:
        stderr.writeln('option inconnue : $a');
        exit(2);
    }
  }
  return _Args(profiles, sessionsOverride, seed, format, outPath);
}

void main(List<String> argv) {
  final args = _parseArgs(argv);

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
