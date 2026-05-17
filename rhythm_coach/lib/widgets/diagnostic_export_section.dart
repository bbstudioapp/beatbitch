import 'dart:convert';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_export_service.dart';
import '../theme/app_theme.dart';

/// Section DIAGNOSTIC de l'écran Profil : bouton qui ouvre une bottom sheet
/// de confirmation, à partir de laquelle la joueuse peut partager ou
/// enregistrer un export JSON de son profil.
///
/// L'export n'est jamais déclenché automatiquement et ne sort jamais de
/// l'appareil tant que la joueuse n'a pas appuyé elle-même sur Partager /
/// Enregistrer / Télécharger.
class DiagnosticExportSection extends StatelessWidget {
  const DiagnosticExportSection({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.profileDiagnosticDescription,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openSheet(context),
                icon: const Icon(Icons.ios_share),
                label: Text(t.profileDiagnosticExportButton),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                    color: AppTheme.accent.withValues(alpha: 0.6),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => const _ExportConfirmSheet(),
    );
  }
}

class _ExportConfirmSheet extends StatefulWidget {
  const _ExportConfirmSheet();

  @override
  State<_ExportConfirmSheet> createState() => _ExportConfirmSheetState();
}

class _ExportConfirmSheetState extends State<_ExportConfirmSheet> {
  bool _includeNicknames = false;
  bool _running = false;

  Future<void> _doExport() async {
    if (_running) return;
    setState(() => _running = true);
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    try {
      final svc = await DiagnosticExportService.create();
      final options =
          DiagnosticExportOptions(includeNicknames: _includeNicknames);
      final raw = svc.buildJson(options);
      final filename = svc.defaultFilename();
      final bytes = Uint8List.fromList(utf8.encode(raw));

      final outcome = await _deliver(
        bytes: bytes,
        filename: filename,
        subject: t.profileDiagnosticShareSubject,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(outcome == _DeliverOutcome.saved
              ? t.profileDiagnosticSavedSnackbar
              : t.profileDiagnosticShareSnackbar),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(t.profileDiagnosticErrorSnackbar(e.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final shareLabel = _shareButtonLabelFor(context);
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
              t.profileDiagnosticSheetTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t.profileDiagnosticSheetIntro,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _IncludedItem(t.profileDiagnosticItemCareer),
            _IncludedItem(t.profileDiagnosticItemStats),
            _IncludedItem(t.profileDiagnosticItemCapabilities),
            _IncludedItem(t.profileDiagnosticItemAnatomy),
            _IncludedItem(t.profileDiagnosticItemPreferences),
            _IncludedItem(t.profileDiagnosticItemBadges),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                t.profileDiagnosticIncludeNicknames,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                t.profileDiagnosticIncludeNicknamesSubtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
              value: _includeNicknames,
              onChanged: _running
                  ? null
                  : (v) => setState(() => _includeNicknames = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _running ? null : () => Navigator.of(context).pop(),
                    child: Text(t.profileDiagnosticCancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _running ? null : _doExport,
                    icon: _running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share, size: 18),
                    label: Text(shareLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shareButtonLabelFor(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (kIsWeb) return t.profileDiagnosticDownloadButton;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return t.profileDiagnosticShareButton;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        return t.profileDiagnosticSaveButton;
    }
  }
}

enum _DeliverOutcome { shared, saved }

/// Achemine le fichier selon la plateforme. Sur Android/iOS on passe par le
/// partage natif (`share_plus`), sur desktop on ouvre un save dialog
/// (`file_saver.saveAs`), sur web on déclenche le download blob
/// (`file_saver.saveFile`).
Future<_DeliverOutcome> _deliver({
  required Uint8List bytes,
  required String filename,
  required String subject,
}) async {
  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: filename.replaceAll('.json', ''),
      bytes: bytes,
      ext: 'json',
      mimeType: MimeType.json,
    );
    return _DeliverOutcome.saved;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/json',
            name: filename,
          ),
        ],
        subject: subject,
        fileNameOverrides: [filename],
      );
      return _DeliverOutcome.shared;
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      await FileSaver.instance.saveAs(
        name: filename.replaceAll('.json', ''),
        bytes: bytes,
        ext: 'json',
        mimeType: MimeType.json,
      );
      return _DeliverOutcome.saved;
  }
}

class _IncludedItem extends StatelessWidget {
  final String text;
  const _IncludedItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(Icons.check, size: 14, color: AppTheme.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
