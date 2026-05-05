import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Bandeau ambre rappelant que la session en cours n'avancera pas le palier.
/// À afficher en tête de l'écran Carrière et dans `SessionScreen` quand le
/// coach actif n'est pas le Principal du palier courant.
class FreeTrainingBanner extends StatelessWidget {
  final String coachName;
  final String? principalName;
  final VoidCallback? onSwitchToPrincipal;

  const FreeTrainingBanner({
    super.key,
    required this.coachName,
    this.principalName,
    this.onSwitchToPrincipal,
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
          const Icon(Icons.tune, color: _amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.coachFreeTrainingBannerTitle(coachName),
                  style: const TextStyle(
                    color: _amber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  principalName != null
                      ? t.coachFreeTrainingBannerBodyWithPrincipal(
                          principalName!)
                      : t.coachFreeTrainingBannerBodyNoPrincipal,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onSwitchToPrincipal != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onSwitchToPrincipal,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(t.coachFreeTrainingBannerSwitchAction,
                  style: const TextStyle(fontSize: 11, letterSpacing: 1)),
            ),
          ],
        ],
      ),
    );
  }
}
