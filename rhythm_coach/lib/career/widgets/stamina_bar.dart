import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Overlay debug : barre horizontale qui montre l'endurance.
///
/// Affichage à deux niveaux (cf. E1 du plan) :
/// - **Live** : valeur courante du `StaminaEngine`, mise à jour à chaque
///   beat / tick. Représente la vraie endurance restante.
/// - **Ghost** : projection du générateur (`profile[seconde]`), affichée
///   en pointillé en filigrane pour comparer ce qui était prévu vs ce
///   qu'on a réellement consommé.
///
/// Pas affichée par défaut — branchée sur le toggle
/// `DebugSettingsService.showStaminaBar`.
class StaminaBar extends StatelessWidget {
  /// Valeur live courante (0..100). Si null, on retombe sur la projection.
  final double? liveValue;

  /// Profil projeté seconde par seconde (calculé à la génération).
  final List<double> profile;

  /// Seconde courante de la session (clamp safe).
  final int currentSecond;

  const StaminaBar({
    super.key,
    required this.profile,
    required this.currentSecond,
    this.liveValue,
  });

  @override
  Widget build(BuildContext context) {
    final projected = profile.isEmpty
        ? 0.0
        : profile[currentSecond.clamp(0, profile.length - 1)];
    final value = liveValue ?? projected;
    final ratio = (value / 100.0).clamp(0.0, 1.0);
    final ghostRatio = (projected / 100.0).clamp(0.0, 1.0);
    final color = _colorForRatio(ratio);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 64,
            child: Text(
              'STAMINA',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Ghost : projection théorique du générateur, en filigrane.
                FractionallySizedBox(
                  widthFactor: ghostRatio,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.textMuted.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Live : barre pleine de la valeur courante.
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForRatio(double ratio) {
    if (ratio > 0.6) return Colors.greenAccent;
    if (ratio > 0.3) return Colors.amber;
    return const Color(0xFFEF5350);
  }
}
