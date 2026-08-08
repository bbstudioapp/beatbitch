import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_export_service.dart';
import '../theme/app_theme.dart';
import 'export_delivery.dart';

/// Ouvre la feuille de partage des **seuls** réglages de voix.
///
/// Elle est proposée depuis le bloc voix du Profil, pas depuis la section
/// DIAGNOSTIC : celle-ci est associée au dépannage (« quelque chose ne va
/// pas »), alors qu'ici on demande une contribution à quelqu'un qui vient
/// justement de régler ses voix. Le geste et le lieu doivent coïncider.
Future<void> showCoachVoiceShareSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CoachVoiceShareSheet(),
  );
}

/// Feuille de partage : elle affiche le fichier **en entier** avant de
/// proposer de l'envoyer.
///
/// Ce n'est pas un ornement. Sur cette app, l'export complet contient ce
/// qu'une personne a de plus intime sur son téléphone ; proposer d'en
/// envoyer un autre demande de prouver, pas d'affirmer, qu'il ne contient
/// que des voix. Le fichier est court par construction — il tient à l'écran,
/// donc on le montre plutôt que de le résumer. Le bouton d'envoi reste
/// inerte tant que le contenu n'est pas affiché : on n'envoie jamais ce
/// qu'on n'a pas montré.
class _CoachVoiceShareSheet extends StatefulWidget {
  const _CoachVoiceShareSheet();

  @override
  State<_CoachVoiceShareSheet> createState() => _CoachVoiceShareSheetState();
}

class _CoachVoiceShareSheetState extends State<_CoachVoiceShareSheet> {
  DiagnosticExportService? _service;
  String? _json;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final svc = await DiagnosticExportService.create();
      final raw = svc.buildVoiceShareJson();
      if (!mounted) return;
      setState(() {
        _service = svc;
        _json = raw;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _send() async {
    final svc = _service;
    final raw = _json;
    if (_sending || svc == null || raw == null) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      final outcome = await deliverExportFile(
        bytes: Uint8List.fromList(utf8.encode(raw)),
        filename: svc.voiceShareFilename(),
        subject: t.coachVoiceShareSubject,
      );
      if (!mounted) return;
      if (outcome == ExportDeliveryOutcome.cancelled) {
        // Save dialog desktop refermée : on rend la main sans snackbar
        // trompeuse, la feuille reste ouverte pour réessayer.
        setState(() => _sending = false);
        return;
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(outcome == ExportDeliveryOutcome.saved
              ? t.profileDiagnosticSavedSnackbar
              : t.profileDiagnosticShareSnackbar),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text(t.profileDiagnosticErrorSnackbar(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final raw = _json;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.coachVoiceShareSheetTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.coachVoiceSharePurpose,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.coachVoiceShareContentLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // La prévisualisation cède la hauteur qui manque plutôt que de
            // faire déborder la feuille : elle a son propre scroll, le texte
            // du dessus n'en a pas.
            Flexible(child: _ContentPreview(json: raw, error: _error)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: Text(t.profileDiagnosticCancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    // Inerte tant que le contenu n'est pas sous les yeux.
                    onPressed: (_sending || raw == null) ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: Text(exportDeliveryButtonLabel(context)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Le fichier tel qu'il sera envoyé, sélectionnable et scrollable. Hauteur
/// bornée pour que les boutons restent atteignables sans scroller la
/// feuille entière — le contenu, lui, n'est jamais tronqué.
class _ContentPreview extends StatelessWidget {
  final String? json;
  final String? error;

  const _ContentPreview({required this.json, required this.error});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final body = json;
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textMuted.withValues(alpha: 0.2)),
      ),
      child: error != null
          ? Text(
              t.profileDiagnosticErrorSnackbar(error!),
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            )
          : body == null
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    body,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
    );
  }
}
