import 'dart:math' show min;

import '../../models/session.dart' show SessionMode;
import '../../services/locale_service.dart';
import 'specialization.dart';

/// Niveau de difficulté global d'une session custom. Pilote le niveau
/// « virtuel » passé au générateur (donc `maxDifficultyCap`,
/// `deepProbability`, `boostsCount`, `regenEndMultiplier`) ainsi qu'un
/// plancher d'intensité (`intensityFloor`) appliqué dès le début de séance.
enum CustomDifficulty { facile, normal, difficile, extreme }

/// Dosage de la quantité d'un mode dans la session générée. Mappé sur le
/// multiplicateur de poids du générateur (`coachModeWeights`). `none`
/// exclut mécaniquement le mode du tirage.
enum ModeDose { none, rare, normal, frequent }

/// Configuration d'une session du mode « Custom » : durée (ou non-stop),
/// coach (ou voix par défaut), dosage par mode, difficulté globale, biais
/// d'axes (allocation de spécialisation virtuelle), profondeur maximale.
/// Sérialisable pour être sauvegardée et rechargée (cf. [CustomConfigService]).
class CustomSessionConfig {
  /// Niveaux « virtuels » de base par difficulté (paliers carrière). Le
  /// niveau ne sert qu'à dériver `maxDifficultyCap` / `deepProbability` /
  /// `boostsCount` / `regenEndMultiplier` — la durée est toujours surchargée
  /// par [durationSeconds] ou [cycleDurationSeconds].
  static const Map<CustomDifficulty, int> _baseLevel = {
    CustomDifficulty.facile: 2,
    CustomDifficulty.normal: 6,
    CustomDifficulty.difficile: 11,
    CustomDifficulty.extreme: 18,
  };

  static const Map<CustomDifficulty, double?> _intensityFloor = {
    CustomDifficulty.facile: null,
    CustomDifficulty.normal: null,
    CustomDifficulty.difficile: 0.25,
    CustomDifficulty.extreme: 0.45,
  };

  static const Map<ModeDose, double> _doseWeight = {
    ModeDose.none: 0.0,
    ModeDose.rare: 0.4,
    ModeDose.normal: 1.0,
    ModeDose.frequent: 2.2,
  };

  /// Bornes du curseur de durée (session simple) et du curseur de durée de
  /// cycle (non-stop), en secondes.
  static const int minDurationSeconds = 3 * 60;
  static const int maxDurationSeconds = 60 * 60;
  static const int minCycleDurationSeconds = 5 * 60;
  static const int maxCycleDurationSeconds = 20 * 60;

  /// Points max investissables par branche d'axe.
  static const int maxAxisPoints = 5;

  /// Modes « bouche » : au moins l'un d'eux doit rester actif (≥ `rare`),
  /// sinon le générateur n'a plus de candidat à tirer dans la phase de
  /// chauffe. Le garde-fou est appliqué côté éditeur.
  static const Set<SessionMode> mouthModes = {
    SessionMode.rhythm,
    SessionMode.lick,
    SessionMode.hold,
  };

  /// Modes proposés au dosage dans l'éditeur. On exclut uniquement `breath` :
  /// c'est un mode de récup, jamais tiré comme step d'effort — le « doser »
  /// n'aurait aucun sens (et fausserait la lecture de la difficulté).
  /// `freestyle` reste proposé (même s'il n'apparaît qu'après sa milestone
  /// en carrière — en custom où tout est débloqué, son poids compte dès que
  /// le générateur le tirera).
  static const List<SessionMode> dosableModes = [
    SessionMode.rhythm,
    SessionMode.lick,
    SessionMode.hold,
    SessionMode.beg,
    SessionMode.biffle,
    SessionMode.hand,
    SessionMode.freestyle,
  ];

  final String id;
  final String name;

  /// Durée totale (session simple). Null si [nonStop].
  final int? durationSeconds;

  /// Mode sans fin : enchaîne des cycles complets (boosts + final + chime),
  /// puis régénère le cycle suivant automatiquement.
  final bool nonStop;

  /// Durée d'un cycle quand [nonStop]. Ignoré sinon.
  final int cycleDurationSeconds;

  /// En non-stop : chaque cycle monte d'un cran (niveau virtuel +2,
  /// `encoreChainIndex` +1). Sans effet hors non-stop.
  final bool progressiveDifficulty;

  /// Id du coach (cf. `CoachService.coaches`). Null = voix par défaut
  /// (pas de coach : PhraseBank globale + voix TTS système, pas de preset).
  final String? coachId;

  /// Dosage par mode. Les 8 modes sont toujours présents après [defaults] /
  /// [fromJson] (clé absente ⇒ `normal`).
  final Map<SessionMode, ModeDose> doses;

  final CustomDifficulty difficulty;

  /// Points d'axes (allocation de spécialisation virtuelle). 0..[maxAxisPoints]
  /// par branche. N'affecte pas la vraie allocation de carrière.
  final Map<SpecializationBranch, int> axes;

  final bool includeHand;

  /// Plafond de profondeur (index dans `Position` : 0 = tip … 4 = full)
  /// pour les modes rhythm/hold.
  final int maxDepthIndex;

  /// Code langue au moment de la sauvegarde (utilisé pour le nom de session
  /// et un éventuel filtrage futur).
  final String lang;

  const CustomSessionConfig({
    required this.id,
    required this.name,
    required this.durationSeconds,
    required this.nonStop,
    required this.cycleDurationSeconds,
    required this.progressiveDifficulty,
    required this.coachId,
    required this.doses,
    required this.difficulty,
    required this.axes,
    required this.includeHand,
    required this.maxDepthIndex,
    required this.lang,
  });

  factory CustomSessionConfig.defaults({String? id}) {
    return CustomSessionConfig(
      id: id ?? newId(),
      name: '',
      durationSeconds: 12 * 60,
      nonStop: false,
      cycleDurationSeconds: 10 * 60,
      progressiveDifficulty: false,
      coachId: null,
      doses: {for (final m in SessionMode.values) m: ModeDose.normal},
      difficulty: CustomDifficulty.normal,
      axes: {for (final b in SpecializationBranch.values) b: 0},
      includeHand: true,
      maxDepthIndex: 4,
      lang: LocaleService.instance.languageCode,
    );
  }

  static String newId() => 'custom_${DateTime.now().millisecondsSinceEpoch}';

  CustomSessionConfig copyWith({
    String? id,
    String? name,
    int? durationSeconds,
    bool? nonStop,
    int? cycleDurationSeconds,
    bool? progressiveDifficulty,
    String? coachId,
    bool clearCoachId = false,
    Map<SessionMode, ModeDose>? doses,
    CustomDifficulty? difficulty,
    Map<SpecializationBranch, int>? axes,
    bool? includeHand,
    int? maxDepthIndex,
    String? lang,
  }) {
    return CustomSessionConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      nonStop: nonStop ?? this.nonStop,
      cycleDurationSeconds: cycleDurationSeconds ?? this.cycleDurationSeconds,
      progressiveDifficulty:
          progressiveDifficulty ?? this.progressiveDifficulty,
      coachId: clearCoachId ? null : (coachId ?? this.coachId),
      doses: doses ?? this.doses,
      difficulty: difficulty ?? this.difficulty,
      axes: axes ?? this.axes,
      includeHand: includeHand ?? this.includeHand,
      maxDepthIndex: maxDepthIndex ?? this.maxDepthIndex,
      lang: lang ?? this.lang,
    );
  }

  // ─── Résolution vers les paramètres du générateur ──────────────────────

  /// Multiplicateurs de poids par mode passés à `generate(coachModeWeights:)`.
  Map<SessionMode, double> resolveCoachModeWeights() {
    return {
      for (final entry in doses.entries)
        entry.key: _doseWeight[entry.value] ?? 1.0,
    };
  }

  /// Allocation de spécialisation « virtuelle » passée à
  /// `generate(specialization:)`. N'est jamais persistée côté carrière.
  SpecializationAllocation resolveSpecialization() {
    return SpecializationAllocation(
      points: {for (final b in SpecializationBranch.values) b: (axes[b] ?? 0)},
      lastRespecMs: null,
    );
  }

  /// Niveau « virtuel » passé à `generate(level:)`. En non-stop progressif,
  /// monte de +2 par cycle (capé à +12).
  int resolveVirtualLevel({int cycleIndex = 0}) {
    final base = _baseLevel[difficulty] ?? 6;
    final bump =
        (nonStop && progressiveDifficulty) ? min(cycleIndex * 2, 12) : 0;
    return base + bump;
  }

  /// Plancher d'intensité passé à `generate(intensityFloor:)`. Null = pas de
  /// plancher (comportement par défaut du générateur).
  double? resolveIntensityFloor() => _intensityFloor[difficulty];

  /// Cran d'encore passé à `generate(encoreChainIndex:)`. En non-stop
  /// progressif, vaut `cycleIndex` (capé à 6 pour éviter des finishs absurdes).
  int resolveEncoreChainIndex({int cycleIndex = 0}) {
    if (!nonStop || !progressiveDifficulty) return 0;
    return min(cycleIndex, 6);
  }

  /// Durée d'une session/cycle effective à passer à `generate(durationSeconds:)`.
  int resolveDurationSeconds() =>
      nonStop ? cycleDurationSeconds : (durationSeconds ?? 12 * 60);

  /// `includeHand` dérivé du dosage : on inclut main/biffle dès que l'un des
  /// deux n'est pas réglé sur « Aucun ». Le champ [includeHand] persisté
  /// reste là pour compat mais n'est plus exposé dans l'éditeur — les doses
  /// hand/biffle sont la source de vérité.
  bool get resolveIncludeHand =>
      (doses[SessionMode.hand] ?? ModeDose.normal) != ModeDose.none ||
      (doses[SessionMode.biffle] ?? ModeDose.normal) != ModeDose.none;

  // ─── Sérialisation ─────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lang': lang,
        if (!nonStop && durationSeconds != null)
          'duration_seconds': durationSeconds,
        'non_stop': nonStop,
        'cycle_duration_seconds': cycleDurationSeconds,
        'progressive_difficulty': progressiveDifficulty,
        if (coachId != null) 'coach_id': coachId,
        'difficulty': difficulty.name,
        'include_hand': includeHand,
        'max_depth_index': maxDepthIndex,
        'doses': {
          for (final entry in doses.entries)
            entry.key.serialized: entry.value.name,
        },
        'axes': {
          for (final entry in axes.entries)
            if (entry.value > 0) entry.key.name: entry.value,
        },
      };

  factory CustomSessionConfig.fromJson(Map<String, dynamic> json) {
    ModeDose parseDose(Object? raw) {
      final s = raw is String ? raw : '';
      return ModeDose.values.firstWhere(
        (d) => d.name == s,
        orElse: () => ModeDose.normal,
      );
    }

    CustomDifficulty parseDifficulty(Object? raw) {
      final s = raw is String ? raw : '';
      return CustomDifficulty.values.firstWhere(
        (d) => d.name == s,
        orElse: () => CustomDifficulty.normal,
      );
    }

    SpecializationBranch? parseBranch(String raw) {
      for (final b in SpecializationBranch.values) {
        if (b.name == raw) return b;
      }
      return null;
    }

    final dosesJson =
        (json['doses'] as Map?)?.cast<String, dynamic>() ?? const {};
    final doses = <SessionMode, ModeDose>{
      for (final m in SessionMode.values) m: parseDose(dosesJson[m.serialized]),
    };

    final axesJson =
        (json['axes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final axes = <SpecializationBranch, int>{
      for (final b in SpecializationBranch.values) b: 0,
    };
    for (final entry in axesJson.entries) {
      final b = parseBranch(entry.key);
      if (b == null) continue;
      final v = entry.value;
      if (v is num) axes[b] = v.toInt().clamp(0, maxAxisPoints);
    }

    final nonStop = json['non_stop'] as bool? ?? false;
    final rawDuration = json['duration_seconds'];
    final duration = rawDuration is num ? rawDuration.toInt() : null;
    final rawCycle = json['cycle_duration_seconds'];
    final cycle = rawCycle is num ? rawCycle.toInt() : 10 * 60;
    final rawDepth = json['max_depth_index'];
    final depth = rawDepth is num ? rawDepth.toInt().clamp(0, 4) : 4;

    return CustomSessionConfig(
      id: json['id'] as String? ?? newId(),
      name: json['name'] as String? ?? '',
      durationSeconds: nonStop ? null : (duration ?? 12 * 60),
      nonStop: nonStop,
      cycleDurationSeconds: cycle.clamp(
        minCycleDurationSeconds,
        maxCycleDurationSeconds,
      ),
      progressiveDifficulty: json['progressive_difficulty'] as bool? ?? false,
      coachId: json['coach_id'] as String?,
      doses: doses,
      difficulty: parseDifficulty(json['difficulty']),
      axes: axes,
      includeHand: json['include_hand'] as bool? ?? true,
      maxDepthIndex: depth,
      lang: json['lang'] as String? ?? LocaleService.instance.languageCode,
    );
  }
}
