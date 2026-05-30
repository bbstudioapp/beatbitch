import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/posture.dart';
import '../theme/app_theme.dart';

/// Indicateur de posture imposée (issue #77) : silhouette schématique + label
/// localisé, affiché en permanence pendant la séance dès qu'une posture est
/// imposée (`pose != Posture.free`). Pas d'asset binaire — la silhouette est
/// peinte par [_PostureSilhouettePainter] (picto léger in-repo, cohérent avec
/// la politique « pas de binaires lourds, ceux-là restent dans le repo »).
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
            child: CustomPaint(
              painter: _PostureSilhouettePainter(
                pose: pose,
                color: AppTheme.textPrimary,
              ),
            ),
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
}

/// Peint une silhouette humaine schématique selon la posture. Traits épais à
/// bouts ronds (effet silhouette) sur un canvas normalisé. Volontairement
/// minimal : le label porte le sens, la silhouette donne le repère visuel
/// immédiat (téléphone posé sur le côté, lecture d'un coup d'œil).
class _PostureSilhouettePainter extends CustomPainter {
  final Posture pose;
  final Color color;

  _PostureSilhouettePainter({required this.pose, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.11;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final headR = w * 0.12;

    // Helpers en coordonnées normalisées (0..1) → pixels.
    Offset p(double x, double y) => Offset(x * w, y * h);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(p(x1, y1), p(x2, y2), paint);
    void head(double x, double y) =>
        canvas.drawCircle(p(x, y), headR, headPaint);

    switch (pose) {
      case Posture.standing:
        head(0.5, 0.16);
        line(0.5, 0.26, 0.5, 0.62); // tronc
        line(0.5, 0.36, 0.30, 0.52); // bras g
        line(0.5, 0.36, 0.70, 0.52); // bras d
        line(0.5, 0.62, 0.38, 0.92); // jambe g
        line(0.5, 0.62, 0.62, 0.92); // jambe d
      case Posture.sitting:
        head(0.40, 0.18);
        line(0.40, 0.28, 0.40, 0.58); // tronc
        line(0.40, 0.58, 0.74, 0.58); // cuisses (horizontales)
        line(0.74, 0.58, 0.74, 0.90); // tibias (verticaux)
        line(0.40, 0.40, 0.60, 0.54); // bras posé sur la cuisse
      case Posture.kneeling:
        head(0.5, 0.22);
        line(0.5, 0.31, 0.5, 0.60); // tronc
        line(0.5, 0.42, 0.32, 0.56); // bras g
        line(0.5, 0.42, 0.68, 0.56); // bras d
        line(0.5, 0.60, 0.5, 0.82); // cuisses (verticales)
        line(0.5, 0.82, 0.78, 0.82); // tibias au sol
      case Posture.allFours:
        head(0.18, 0.40);
        line(0.26, 0.42, 0.78, 0.42); // dos horizontal
        line(0.34, 0.42, 0.34, 0.84); // bras
        line(0.72, 0.42, 0.72, 0.84); // jambe
        line(0.50, 0.42, 0.50, 0.84); // appui central
      case Posture.onBack:
        head(0.16, 0.52);
        line(0.24, 0.56, 0.84, 0.56); // corps allongé
        line(0.50, 0.56, 0.62, 0.74); // genou replié
        line(0.62, 0.74, 0.74, 0.74); // pied au sol
        line(0.84, 0.56, 0.92, 0.62); // jambe tendue
      case Posture.free:
        // Pose libre : ligne ondulée neutre (jamais affichée par
        // PostureIndicator, qui ne se monte que pour pose != free — rendu
        // défensif au cas où).
        head(0.5, 0.20);
        line(0.5, 0.30, 0.5, 0.70);
    }
  }

  @override
  bool shouldRepaint(_PostureSilhouettePainter old) =>
      old.pose != pose || old.color != color;
}
