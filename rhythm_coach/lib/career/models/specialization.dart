/// Cinq branches de spécialisation. Le joueur investit des points dans
/// une ou plusieurs branches pour signaler au générateur procédural ce
/// dans quoi il/elle s'estime « bon ». Le générateur s'en sert pour
/// pondérer les candidats de step et adapter les paramètres (BPM,
/// profondeur, durées).
///
/// Note : la branche `resilience` historique a été retirée — l'endurance
/// couvre déjà « tenir quand c'est dur », et les mini-punitions inopinées
/// sont désormais pilotées par la personnalité du coach
/// (`Coach.miniPunishmentRate`), pas par une branche de spé. Les points
/// investis dans `resilience` par une joueuse existante sont automatiquement
/// reversés au pool libre (cf. `SpecializationService.load`).
///
/// **Pure-Dart** (pas d'import `package:flutter`) pour rester consommable
/// depuis les outils `dart run` standalone (`tools/simulate_career.dart`).
/// Les métadonnées UI (libellé, description, icône) vivent dans
/// `specialization_meta.dart`.
library;

enum SpecializationBranch {
  /// Tenir longtemps : durées de step allongées, plus de holds.
  endurance,

  /// Aller chercher loin : biais throat/full, holds profonds.
  profondeur,

  /// BPM élevés et coups de queue (biffle).
  rythmeBiffle,

  /// Phases beg insistantes / pleurnicheries vocales.
  obeissance,

  /// Lick humide, biffle bas, drool — moins de discipline, plus de bave.
  sloppy,
}

/// État immuable d'allocation des points sur les 5 branches. Un score 0
/// par branche par défaut. La somme des `points.values` ne peut pas
/// dépasser le total disponible (cf. `SpecializationService`).
class SpecializationAllocation {
  final Map<SpecializationBranch, int> points;

  /// Timestamp epoch ms du dernier respec, ou null jamais respeccé.
  /// Sert au cooldown de respec.
  final int? lastRespecMs;

  const SpecializationAllocation({
    required this.points,
    required this.lastRespecMs,
  });

  factory SpecializationAllocation.empty() {
    return SpecializationAllocation(
      points: {for (final b in SpecializationBranch.values) b: 0},
      lastRespecMs: null,
    );
  }

  int pointsIn(SpecializationBranch b) => points[b] ?? 0;

  int get totalSpent => points.values.fold<int>(0, (acc, v) => acc + v);

  SpecializationAllocation copyWith({
    Map<SpecializationBranch, int>? points,
    int? lastRespecMs,
    bool clearLastRespec = false,
  }) {
    return SpecializationAllocation(
      points: points ?? this.points,
      lastRespecMs:
          clearLastRespec ? null : (lastRespecMs ?? this.lastRespecMs),
    );
  }
}
