import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/diagnostic_import_service.dart';
import '../theme/app_theme.dart';

/// Section **debug uniquement** (montée sous `if (kDebugMode)` dans
/// `SoundDemoScreen`) : charge un profil pré-fabriqué depuis
/// `assets/debug/profiles/` via [DiagnosticImportService], pour tester une
/// feature sans rejouer toutes les sessions.
///
/// Chaque profil écrase l'état persisté (déterministe) puis demande un
/// **redémarrage** — les services lisent les prefs au boot.
///
/// Textes FR en dur, assumé : outil de dev jamais compilé en release
/// (`kDebugMode`), hors périmètre i18n.
class DebugProfilesSection extends StatefulWidget {
  const DebugProfilesSection({super.key});

  @override
  State<DebugProfilesSection> createState() => _DebugProfilesSectionState();
}

class _DebugProfilesSectionState extends State<DebugProfilesSection> {
  bool _busy = false;

  // (fichier sous assets/debug/profiles/, libellé affiché).
  static const List<(String, String)> _profiles = [
    ('reset', 'Reset — profil vierge'),
    ('posture_sitting_ready', 'Posture assise — à débloquer'),
    ('posture_standing_ready', 'Posture debout — à débloquer'),
    ('posture_kneeling_ready', 'Posture à genoux — à débloquer'),
    ('posture_all_fours_ready', 'Posture à quatre pattes — à débloquer'),
    ('posture_on_back_ready', 'Posture sur le dos — à débloquer'),
    ('mi_carriere_profondeur', 'Mi-carrière profondeur (niv 8)'),
    ('pro', 'Pro (niv 18, tout débloqué)'),
    ('mon_profil_reel', 'Mon profil réel (avant reset)'),
  ];

  Future<void> _load(String file, String label) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Charger ce profil ?'),
        content: Text(
          '« $label »\n\nÇa écrase TOUT ton état actuel (progression, '
          'capacités, milestones…) et demande un redémarrage de l\'app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Charger'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final raw =
          await rootBundle.loadString('assets/debug/profiles/$file.json');
      final payload = json.decode(raw) as Map<String, dynamic>;
      final svc = await DiagnosticImportService.create();
      await svc.apply(payload);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Profil chargé'),
          content: Text(
            '« $label » appliqué.\n\nFerme et relance l\'app pour que les '
            'services rechargent l\'état.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Plus tard'),
            ),
            const FilledButton(
              onPressed: SystemNavigator.pop,
              child: Text('Fermer l\'app'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec du chargement : $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.science, color: AppTheme.accent, size: 18),
            const SizedBox(width: 8),
            Text(
              'PROFILS DEBUG',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: AppTheme.accent.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Charge un état pré-fabriqué (écrase tout, redémarrage requis). '
            'Debug uniquement.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ),
        for (final (file, label) in _profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: _busy ? null : () => _load(file, label),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.4)),
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              child: Text(label, textAlign: TextAlign.left),
            ),
          ),
      ],
    );
  }
}
