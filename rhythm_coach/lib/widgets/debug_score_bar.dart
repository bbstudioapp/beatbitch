import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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

/// Palette « humiliation » : violet doux → magenta → rouge sombre.
Color humiliationColorForRatio(double ratio) {
  if (ratio >= 0.75) return const Color(0xFFB71C1C);
  if (ratio >= 0.50) return const Color(0xFFC2185B);
  if (ratio >= 0.25) return const Color(0xFF8E24AA);
  return const Color(0xFFCE93D8);
}

/// Palette « salive » : transparent → bleu pâle → cyan → bleu profond, et
/// rouge sombre au-dessus du seuil de débordement (90 %) pour signaler la
/// saturation. Quand la jauge atteint 100 % ça déborde, on veut le rendre
/// visible d'un coup d'œil.
Color salivaColorForRatio(double ratio) {
  if (ratio >= 1.0) return const Color(0xFF7B1FA2);
  if (ratio >= 0.90) return const Color(0xFF1976D2);
  if (ratio >= 0.60) return const Color(0xFF29B6F6);
  if (ratio >= 0.30) return const Color(0xFF81D4FA);
  return const Color(0xFFB3E5FC);
}

/// Palette « obéissance » : rouge si bas (rebelle), vert si haut (docile).
Color obedienceColorForRatio(double ratio) {
  if (ratio >= 0.90) return const Color(0xFF66BB6A);
  if (ratio >= 0.75) return const Color(0xFFAED581);
  if (ratio >= 0.50) return Colors.amber;
  if (ratio >= 0.25) return const Color(0xFFFFA726);
  return const Color(0xFFEF5350);
}

/// Plus petit multiple de 50 ≥ value, minimum 100. Utilisé pour les jauges
/// sans borne haute (humiliation, obédiance) qui doivent rester lisibles
/// même au-delà de 100.
double _dynamicMaxStep50(double v) {
  if (v <= 100) return 100;
  return ((v / 50).ceil() * 50).toDouble();
}

/// Barre debug du score d'humiliation. Pas de cap théorique : le score
/// peut dépasser 100 sur les longues carrières. `max` adapté par paliers
/// de 50 (100, 150, 200…).
class HumiliationBar extends StatelessWidget {
  final double value;

  const HumiliationBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelHumiliation,
      value: value,
      max: _dynamicMaxStep50(value),
      colorForRatio: humiliationColorForRatio,
    );
  }
}

/// Barre debug de la jauge de salive 0–max. Le `max` est dynamique selon
/// les compétences sloppy acquises (60 défaut, 100 si `sloppyDroolBasic`,
/// +20 si `sloppyDroolDeep`).
class SalivaBar extends StatelessWidget {
  final double value;
  final double max;

  const SalivaBar({
    super.key,
    required this.value,
    this.max = 60.0,
  });

  @override
  Widget build(BuildContext context) {
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelSaliva,
      value: value,
      max: max,
      colorForRatio: salivaColorForRatio,
    );
  }
}

/// Barre debug du score d'obéissance. Score persistant entre sessions,
/// démarre à 0, sans borne haute. `max` adapté par paliers de 50.
class ObedienceBar extends StatelessWidget {
  final double value;

  const ObedienceBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelObedience,
      value: value,
      max: _dynamicMaxStep50(value),
      colorForRatio: obedienceColorForRatio,
    );
  }
}
