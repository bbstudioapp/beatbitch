import 'package:file_saver/file_saver.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';

/// Acheminement d'un fichier produit par l'app vers l'extérieur, partagé par
/// les deux exports du Profil : le diagnostic complet et les seuls réglages
/// de voix. Ils diffèrent par ce qu'ils contiennent, pas par la façon dont
/// le fichier sort de l'appareil — et un correctif de plateforme doit valoir
/// pour les deux.
enum ExportDeliveryOutcome { shared, saved, cancelled }

/// Achemine le fichier selon la plateforme :
/// - **Web** : `file_saver.saveFile` (download blob via navigateur — la seule
///   API qui marche sans accès au filesystem).
/// - **Android / iOS** : `share_plus` (intent système → mail, messagerie, etc.).
/// - **Desktop (Linux / Windows / macOS / Fuchsia)** : `file_selector` pour
///   ouvrir un save dialog GTK/Win/AppKit, puis `XFile.saveTo` pour écrire.
///   Volontairement **pas** `file_saver.saveAs` : son implémentation Linux
///   throw `UnimplementedError` (la méthode n'est livrée que sur Android).
Future<ExportDeliveryOutcome> deliverExportFile({
  required Uint8List bytes,
  required String filename,
  required String subject,
}) async {
  if (kIsWeb) {
    await FileSaver.instance.saveFile(
      name: filename.replaceAll('.json', ''),
      bytes: bytes,
      fileExtension: 'json',
      mimeType: MimeType.json,
    );
    return ExportDeliveryOutcome.saved;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'application/json',
              name: filename,
            ),
          ],
          subject: subject,
          fileNameOverrides: [filename],
        ),
      );
      return ExportDeliveryOutcome.shared;
    case TargetPlatform.linux:
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'JSON',
            extensions: <String>['json'],
            mimeTypes: <String>['application/json'],
          ),
        ],
      );
      if (location == null) return ExportDeliveryOutcome.cancelled;
      await XFile.fromData(
        bytes,
        mimeType: 'application/json',
        name: filename,
      ).saveTo(location.path);
      return ExportDeliveryOutcome.saved;
  }
}

/// Libellé du bouton d'envoi, aligné sur ce que la plateforme va réellement
/// faire : partager (mobile), enregistrer (desktop), télécharger (web).
String exportDeliveryButtonLabel(BuildContext context) {
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
