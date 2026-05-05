import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'debug_score_bar.dart';

/// Barre debug de la jauge d'excitation 0–max. Wrapper léger autour de
/// [DebugScoreBar] avec la palette excitation.
class ExcitationBar extends StatelessWidget {
  final double value;
  final double max;

  const ExcitationBar({
    super.key,
    required this.value,
    this.max = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    return DebugScoreBar(
      label: AppLocalizations.of(context).debugBarLabelExcitation,
      value: value,
      max: max,
      colorForRatio: excitationColorForRatio,
    );
  }
}
