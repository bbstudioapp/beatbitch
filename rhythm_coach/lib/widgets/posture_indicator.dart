import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/posture.dart';
import '../theme/app_theme.dart';

/// Indicateur de posture imposée (issue #77) : silhouette + label localisé,
/// affiché en permanence pendant la séance dès qu'une posture est imposée
/// (`pose != Posture.free`). La silhouette est un PNG monochrome
/// (`assets/postures/<pose>.png`, teinté au runtime via `BlendMode.srcIn`) —
/// asset SFW léger conservé dans le repo (pas d'externalisation R2, contrairement
/// aux portraits de coach).
///
/// Cf. spec `specs/scripted_breaks.md` § UI. La pose change uniquement à
/// l'intro et aux breaks ; cet indicateur reflète `SessionController.currentPose`.
class PostureIndicator extends StatelessWidget {
  final Posture pose;

  /// Taille de la silhouette (carrée). Le label s'aligne dessous.
  final double size;

  const PostureIndicator({super.key, required this.pose, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: _buildSilhouette(),
          ),
          const SizedBox(width: 10),
          Text(
            pose.localizedLabel(context).toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Silhouette PNG teintée à `textPrimary` (blanc → couleur via `srcIn`, qui
  /// respecte l'alpha détouré). `free` n'a pas d'asset — l'indicateur ne se
  /// monte de toute façon que pour `pose != free`, rendu défensif au cas où.
  Widget _buildSilhouette() {
    if (pose == Posture.free) return const SizedBox.shrink();
    return Image.asset(
      'assets/postures/${pose.serialized}.png',
      width: size,
      height: size,
      color: AppTheme.textPrimary,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
