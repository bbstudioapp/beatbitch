import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'debug_score_bar.dart';

/// Barre debug du score d'obéissance. Score persistant entre sessions,
/// démarre à 0, sans borne haute. Le `max` affiché s'adapte dynamiquement
/// par paliers de 50 (100, 150, 200…) pour rester lisible au-delà de 100.
class ObedienceBar extends StatelessWidget {
  final double value;

  const ObedienceBar({
    super.key,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final dynamicMax = _stepUpMax(value);
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelObedience,
      value: value,
      max: dynamicMax,
      colorForRatio: obedienceColorForRatio,
    );
  }

  /// Plus petit multiple de 50 ≥ value, minimum 100.
  double _stepUpMax(double v) {
    if (v <= 100) return 100;
    return ((v / 50).ceil() * 50).toDouble();
  }
}
