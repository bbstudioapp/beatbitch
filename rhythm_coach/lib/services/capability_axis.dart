/// Catalogue des axes du **profil de capacités** (mode carrière uniquement).
///
/// Le profil de capacités est une 2ᵉ enveloppe de difficulté, orthogonale à
/// l'humiliation/obéissance : un faisceau de compteurs par « pratique »
/// (profondeur, apnée, franchissement de gorge, vitesse BPM, salive,
/// souffle…) qui mesure ce que la joueuse a *prouvé* tenir.
///
/// **Phase 1 — télémétrie pure** : on enregistre `best` (record propre) et on
/// pose `comfort = best` naïvement ; aucun pilotage du générateur n'en
/// dépend encore. Les phases suivantes ajoutent le gating, puis la surcharge
/// autorégulée. Ce fichier reste purement déclaratif — la classification
/// « état d'une seconde → quels axes alimentés » vit dans
/// `capability_tracker.dart`.
///
/// Spec complète : doc local `~/beatbitch_career_capability_profile.md`.
library;

/// Unité d'un axe — pilote uniquement le formatage à l'affichage.
enum CapabilityUnit {
  /// Durée en secondes (streaks d'endurance / d'engagement).
  seconds,

  /// Battements par minute (fenêtres BPM, records de vitesse).
  bpm,

  /// Cran de profondeur 0..4 (`tip`=0 … `full`=4).
  depthCran,

  /// Compteur entier (franchissements cumulés).
  count,
}

/// Sens dans lequel `best` évolue.
enum CapabilityRecordKind {
  /// Record qui monte : `best = max(best, atteint)` (la plupart des axes).
  maximize,

  /// Record qui descend : `best = min(best, atteint)` — planchers BPM
  /// (« lent & maîtrisé ») et dose mini de souffle.
  minimize,

  /// Somme cumulée toutes sessions : `best += atteint` — franchissements
  /// lifetime (matière à badge / classement).
  accumulate,
}

/// Les axes du profil. Chaque entrée porte sa clé de persistance (préfixée
/// `cap.` dans `shared_preferences`), son unité d'affichage, son sens de
/// record, et un flag `pilotant` (= un futur étage du générateur lira son
/// `comfort` — informatif en Phase 1).
enum CapabilityAxis {
  // ── Modèle « gorge » ──────────────────────────────────────────────────
  /// Apnée max : plus longue séquence airless cumulée cross-mode
  /// (hold/beg ≥ throat, ou rhythm/lick stroke `throat↔full`). Gate strict.
  gorgeApneeStreak('gorge.apnee_streak', CapabilityUnit.seconds,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Engagement gorge max : plus longue séquence où « la gorge est en jeu »
  /// (hold/beg ≥ throat, ou rhythm/lick `to ≥ throat`), même avec des
  /// fenêtres d'air entre les coups. Gate permissif.
  gorgeEngagementStreak('gorge.engagement_streak', CapabilityUnit.seconds,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// BPM max tenu ≥ N s sur un pattern franchissant (`from ≤ mid, to ≥ throat`)
  /// dont le point bas est `throat`.
  gorgeCrossingsBpmThroat('gorge.crossings_pm.throat', CapabilityUnit.bpm,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Idem, point bas `full` (franchissement plus profond, plus dur).
  gorgeCrossingsBpmFull('gorge.crossings_pm.full', CapabilityUnit.bpm,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Cumul de franchissements de gorge toutes sessions. Enregistré seulement.
  gorgeCrossingsLifetime('gorge.crossings_lifetime', CapabilityUnit.count,
      CapabilityRecordKind.accumulate,
      pilotant: false),

  // ── Fenêtres BPM rhythm par bande de profondeur de `to` ───────────────
  /// Bande `to ≤ mid` — plafond (BPM le plus rapide tenu ≥ N s). Ratchet ↑.
  rhythmBpmCeilShallow('rhythm.bpm_ceil.shallow', CapabilityUnit.bpm,
      CapabilityRecordKind.maximize,
      pilotant: true),
  rhythmBpmCeilThroat('rhythm.bpm_ceil.throat', CapabilityUnit.bpm,
      CapabilityRecordKind.maximize,
      pilotant: true),
  rhythmBpmCeilFull(
      'rhythm.bpm_ceil.full', CapabilityUnit.bpm, CapabilityRecordKind.maximize,
      pilotant: true),

  /// Bande `to ≤ mid` — plancher (BPM le plus lent tenu ≥ N s). Ratchet ↓ —
  /// l'axe « lent & maîtrisé ».
  rhythmBpmFloorShallow('rhythm.bpm_floor.shallow', CapabilityUnit.bpm,
      CapabilityRecordKind.minimize,
      pilotant: true),
  rhythmBpmFloorThroat('rhythm.bpm_floor.throat', CapabilityUnit.bpm,
      CapabilityRecordKind.minimize,
      pilotant: true),
  rhythmBpmFloorFull('rhythm.bpm_floor.full', CapabilityUnit.bpm,
      CapabilityRecordKind.minimize,
      pilotant: true),

  // ── Axes rythme ───────────────────────────────────────────────────────
  /// Cran de `to` le plus profond tenu ≥ N s en rhythm. Ratchet par cran.
  rhythmDepthMax('rhythm.depth_max', CapabilityUnit.depthCran,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Mouvement rythmé ininterrompu (rhythm **ou** lick ; hand exclu).
  /// Cassé par hold/beg/breath/freestyle/hand/fail. Remplacera le cap fixe
  /// `_capRhythmConsecutive` (60 s) par une valeur par joueuse.
  rhythmMotionStreak('rhythm.motion_streak', CapabilityUnit.seconds,
      CapabilityRecordKind.maximize,
      pilotant: true),

  // ── Tenues (hold + beg-avec-position) ─────────────────────────────────
  /// Hold/beg tenu exactement à `throat`, cumule hold/beg/hold.
  holdThroatStreak('hold.throat.streak', CapabilityUnit.seconds,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Hold/beg tenu exactement à `full` (migration de
  /// `StatsService.maxHoldFullAtomic`).
  holdFullStreak(
      'hold.full.streak', CapabilityUnit.seconds, CapabilityRecordKind.maximize,
      pilotant: true),

  // ── Salive ────────────────────────────────────────────────────────────
  /// `swallowMode == forbidden` en continu. Cassé par fenêtre autorisée /
  /// fail. Un `best` ne compte que si aucun débordement n'a eu lieu pendant
  /// le streak.
  noswallowStreak(
      'noswallow.streak', CapabilityUnit.seconds, CapabilityRecordKind.maximize,
      pilotant: true),

  // ── Biffle ────────────────────────────────────────────────────────────
  biffleStreak(
      'biffle.streak', CapabilityUnit.seconds, CapabilityRecordKind.maximize,
      pilotant: true),
  biffleBpmMax(
      'biffle.bpm_max', CapabilityUnit.bpm, CapabilityRecordKind.maximize,
      pilotant: true),

  // ── Économie du souffle ───────────────────────────────────────────────
  /// Temps d'effort sans step `breath`. Cassé par `breath`, fail.
  effortNoBreathStreak('effort.no_breath_streak', CapabilityUnit.seconds,
      CapabilityRecordKind.maximize,
      pilotant: true),

  /// Plus courte durée de `breath` après laquelle elle a repris sans fail
  /// immédiat. À minimiser. Bornera par le bas la durée des sas générés.
  breathMinDose(
      'breath.min_dose', CapabilityUnit.seconds, CapabilityRecordKind.minimize,
      pilotant: true),

  // ── Enregistrés seulement (profil / classement / tuning futur) ────────
  /// Cran de `to` le plus profond tenu ≥ N s en lick.
  lickDepthMax(
      'lick.depth_max', CapabilityUnit.depthCran, CapabilityRecordKind.maximize,
      pilotant: false),

  /// Lick ininterrompu (distinct de `rhythm.motion_streak` qui couvre
  /// rhythm+lick).
  lickStreak(
      'lick.streak', CapabilityUnit.seconds, CapabilityRecordKind.maximize,
      pilotant: false),

  /// Plus longue phase hand ininterrompue. Pur compteur d'endurance — ne
  /// sert qu'à éventuellement *rallonger* les phases hand, jamais à les
  /// durcir (cf. « hand n'est jamais un levier de difficulté »).
  handStreak(
      'hand.streak', CapabilityUnit.seconds, CapabilityRecordKind.maximize,
      pilotant: false);

  const CapabilityAxis(
    this.storageKey,
    this.unit,
    this.recordKind, {
    required this.pilotant,
  });

  /// Suffixe stable utilisé dans les clés `shared_preferences`
  /// (`cap.<storageKey>.best` / `.comfort` / `.sr` / `.seen`).
  final String storageKey;
  final CapabilityUnit unit;
  final CapabilityRecordKind recordKind;

  /// `true` si un étage du générateur lit (ou lira) le `comfort` de cet axe
  /// pour borner / surcharger. Informatif tant qu'on est en Phase 1.
  final bool pilotant;

  /// Axes affichés dans le panneau « Capacités » du ProfileScreen (ordre
  /// éditorial). Aujourd'hui = tous, mais on garde le point d'extension.
  static List<CapabilityAxis> get displayOrder => values;
}
