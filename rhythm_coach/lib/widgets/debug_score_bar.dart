import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Barre debug générique : label fixe à gauche (~64 px), barre à fraction
/// au centre, valeur numérique à droite. La couleur de remplissage est
/// décidée par [colorForRatio] (ratio = value / max, clampé).
class DebugScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color Function(double ratio) colorForRatio;

  const DebugScoreBar({
    super.key,
    required this.label,
    required this.value,
    required this.colorForRatio,
    this.max = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    final safeMax = max <= 0 ? 1.0 : max;
    final ratio = (value / safeMax).clamp(0.0, 1.0);
    final color = colorForRatio(ratio);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
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
            width: 64,
            child: Text(
              '${value.round()}/${max.round()}',
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
}

/// Palette « excitation » : rose pâle → rouge → blanc à 100 %.
Color excitationColorForRatio(double ratio) {
  if (ratio >= 1.0) return Colors.white;
  if (ratio >= 0.75) return const Color(0xFFEF5350);
  if (ratio >= 0.50) return const Color(0xFFFFA726);
  if (ratio >= 0.25) return Colors.amber;
  return const Color(0xFFF8BBD0);
}

/// Palette « humiliation » : violet doux → magenta → rouge sombre.
Color humiliationColorForRatio(double ratio) {
  if (ratio >= 0.75) return const Color(0xFFB71C1C);
  if (ratio >= 0.50) return const Color(0xFFC2185B);
  if (ratio >= 0.25) return const Color(0xFF8E24AA);
  return const Color(0xFFCE93D8);
}

/// Palette « obéissance » : rouge si bas (rebelle), vert si haut (docile).
Color obedienceColorForRatio(double ratio) {
  if (ratio >= 0.90) return const Color(0xFF66BB6A);
  if (ratio >= 0.75) return const Color(0xFFAED581);
  if (ratio >= 0.50) return Colors.amber;
  if (ratio >= 0.25) return const Color(0xFFFFA726);
  return const Color(0xFFEF5350);
}
