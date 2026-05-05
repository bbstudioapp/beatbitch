import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Bandeau ambre signalant qu'il reste des points de spécialisation à
/// dépenser. Affiché en tête de `CareerScreen` (avant le sélecteur de
/// niveau) et sur l'écran de fin de session quand un point vient d'être
/// gagné. L'utilisatrice ne peut pas oublier ses points en quittant
/// l'app — la prochaine ouverture les lui rappellera.
class FreeSpecPointsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onAllocate;

  const FreeSpecPointsBanner({
    super.key,
    required this.count,
    required this.onAllocate,
  });

  static const Color _amber = Color(0xFFE8B33A);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star, color: _amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.specPointsBannerTitle(count),
                  style: const TextStyle(
                    color: _amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.specPointsBannerSubtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAllocate,
            style: TextButton.styleFrom(
              foregroundColor: _amber,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            child: Text(t.specPointsBannerCta),
          ),
        ],
      ),
    );
  }
}
