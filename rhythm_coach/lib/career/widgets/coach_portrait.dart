import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/coach.dart';

/// Affiche le portrait d'un coach (`coach.portraitAsset`).
///
/// Repli gracieux sur une initiale stylisée si l'asset est absent ou ne
/// charge pas — coach sans portrait, ou bundle d'assets allégé. Même esprit
/// que `SessionBackground` côté arrière-plans : la fonctionnalité ne casse
/// jamais si l'image manque.
///
/// Les portraits livrés ont un ratio source 2:3 (512×768) ; par défaut le
/// widget rend une vignette verticale de cette proportion. Fournir [width]
/// pour forcer un cadrage différent (l'image est alors recadrée en
/// `BoxFit.cover`).
///
/// Décoratif : l'identité du coach est déjà annoncée par le texte qui
/// l'accompagne, donc l'image est exclue de l'arbre sémantique.
class CoachPortrait extends StatelessWidget {
  final Coach coach;

  /// Hauteur en logical px. La largeur vaut `height * 2 / 3` si [width] est
  /// omis (ratio source des portraits livrés).
  final double height;
  final double? width;

  /// Arrondi des coins. `null` = `BorderRadius.circular(12)`.
  final BorderRadius? borderRadius;

  /// Couleur d'accent du repli (cadre + initiale). `null` = `AppTheme.accent`.
  final Color? accent;

  const CoachPortrait({
    super.key,
    required this.coach,
    this.height = 96,
    this.width,
    this.borderRadius,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final w = width ?? height * 2 / 3;
    final radius = borderRadius ?? BorderRadius.circular(12);
    final accentColor = accent ?? AppTheme.accent;

    final fallback = _PortraitFallback(
      initial: coach.name.trim().isEmpty
          ? '?'
          : coach.name.trim().substring(0, 1).toUpperCase(),
      accent: accentColor,
      width: w,
      height: height,
      radius: radius,
    );

    final asset = coach.portraitAsset;
    if (asset == null) return fallback;

    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        asset,
        width: w,
        height: height,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _PortraitFallback extends StatelessWidget {
  final String initial;
  final Color accent;
  final double width;
  final double height;
  final BorderRadius radius;

  const _PortraitFallback({
    required this.initial,
    required this.accent,
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: radius,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        initial,
        style: TextStyle(
          // L'initiale s'adapte un peu à la taille de la vignette.
          fontSize: (height * 0.4).clamp(14.0, 40.0),
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }
}
