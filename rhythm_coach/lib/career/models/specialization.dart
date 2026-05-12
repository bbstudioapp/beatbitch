import 'package:flutter/material.dart';

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

/// Métadonnées affichables d'une branche : libellé + description courte
/// + icône d'illustration. Centralisé ici pour partager entre écran de
/// répartition et l'éventuel écran profil.
class SpecializationBranchMeta {
  final SpecializationBranch branch;
  final String label;
  final String description;
  final IconData icon;

  const SpecializationBranchMeta({
    required this.branch,
    required this.label,
    required this.description,
    required this.icon,
  });

  static const List<SpecializationBranchMeta> all = [
    SpecializationBranchMeta(
      branch: SpecializationBranch.endurance,
      label: 'Endurance',
      description: 'Tenir longtemps. Plus de holds, durées rallongées.',
      icon: Icons.fitness_center,
    ),
    SpecializationBranchMeta(
      branch: SpecializationBranch.profondeur,
      label: 'Profondeur',
      description: 'Aller chercher loin. Biais throat / full.',
      icon: Icons.south,
    ),
    SpecializationBranchMeta(
      branch: SpecializationBranch.rythmeBiffle,
      label: 'Rythme & Biffle',
      description: 'BPM élevés, coups de queue plus fréquents.',
      icon: Icons.bolt,
    ),
    SpecializationBranchMeta(
      branch: SpecializationBranch.obeissance,
      label: 'Obéissance',
      description: 'Beg insistants, supplique soutenue.',
      icon: Icons.volunteer_activism,
    ),
    SpecializationBranchMeta(
      branch: SpecializationBranch.sloppy,
      label: 'Sloppy',
      description: 'Lick humide, biffle bas, plus de bave.',
      icon: Icons.water_drop,
    ),
  ];

  static SpecializationBranchMeta forBranch(SpecializationBranch b) =>
      all.firstWhere((m) => m.branch == b);
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
