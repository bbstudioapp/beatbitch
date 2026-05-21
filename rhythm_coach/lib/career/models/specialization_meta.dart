import 'package:flutter/material.dart';

import 'specialization.dart';

/// Métadonnées affichables d'une branche de spécialisation — libellé,
/// description courte, icône. Centralisé hors de `specialization.dart`
/// (qui doit rester pure-Dart pour être consommable depuis les outils
/// `dart run` standalone — `tools/simulate_career.dart`). Convention
/// alignée avec `enum_labels.dart` : l'enum nu reste pure, l'habillage UI
/// (icons, libellés localisés) vit dans un fichier dédié qui importe
/// Flutter / l10n.
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
