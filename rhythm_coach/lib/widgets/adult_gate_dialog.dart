import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/adult_consent_service.dart';
import '../theme/app_theme.dart';

/// Dialog 18+ non-skippable affiché au premier mount de
/// `ModeSelectionScreen` quand `AdultConsentService.isAccepted == false`.
/// Pas de barrier dismissible : seule l'action « J'accepte » sort. Le
/// bouton « Quitter » ferme l'app via `SystemNavigator.pop`.
class AdultGateDialog extends StatelessWidget {
  const AdultGateDialog({super.key});

  /// Affiche le dialog et persiste l'acceptation. Retourne `true` si
  /// l'utilisatrice a accepté, `false` sinon (devrait être inatteignable
  /// puisque « Quitter » ferme l'app, mais on garde la sortie défensive).
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AdultGateDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: AppTheme.accent.withValues(alpha: 0.3),
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppTheme.accent, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.adultGateTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            t.adultGateBody,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
            onPressed: () async {
              await SystemNavigator.pop();
            },
            child: Text(t.adultGateLeave),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () async {
              await AdultConsentService.instance.accept();
              if (context.mounted) Navigator.of(context).pop(true);
            },
            child: Text(
              t.adultGateAccept,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
