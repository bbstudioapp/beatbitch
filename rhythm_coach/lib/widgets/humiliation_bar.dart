import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'debug_score_bar.dart';

/// Barre debug du score d'humiliation. Pas de cap théorique : le score
/// peut dépasser 100 sur les longues carrières. Le `max` affiché s'adapte
/// dynamiquement par paliers de 50 (100, 150, 200…) pour que la barre
/// reste lisible même au-delà.
class HumiliationBar extends StatelessWidget {
  final double value;

  const HumiliationBar({
    super.key,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final dynamicMax = _stepUpMax(value);
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelHumiliation,
      value: value,
      max: dynamicMax,
      colorForRatio: humiliationColorForRatio,
    );
  }

  /// Plus petit multiple de 50 ≥ value, minimum 100.
  double _stepUpMax(double v) {
    if (v <= 100) return 100;
    return ((v / 50).ceil() * 50).toDouble();
  }
}
