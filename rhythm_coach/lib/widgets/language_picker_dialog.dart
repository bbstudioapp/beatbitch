import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../l10n/enum_labels.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Sélecteur de langue affiché au premier lancement quand la langue du
/// téléphone n'est pas supportée — on ne devine pas, on demande. Non
/// dismissible : il faut choisir (la locale active provisoire est
/// [kFallbackLocale], donc tout l'écran est dans cette langue tant qu'on
/// n'a pas choisi). Taper une langue persiste le choix via
/// [LocaleService.setLocale] et ferme la boîte.
class LanguagePickerDialog extends StatelessWidget {
  const LanguagePickerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LanguagePickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final activeCode = LocaleService.instance.current.languageCode;
    return AlertDialog(
      title: Text(t.languagePickerTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.languagePickerBody,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          for (final locale in kSupportedLocales)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language, color: AppTheme.accent),
              title: Text(localizedLanguageName(context, locale)),
              trailing: locale.languageCode == activeCode
                  ? const Icon(Icons.check, color: AppTheme.accent, size: 20)
                  : null,
              onTap: () async {
                await LocaleService.instance.setLocale(locale);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

/// Boîte de dialogue (non bloquante : un refus est ok) proposée à l'écran
/// d'accueil quand une langue ajoutée dans une version ultérieure correspond
/// désormais à la locale système. Renvoie `true` si l'utilisatrice veut
/// basculer, `false`/`null` sinon. Voir [LocaleService.pendingNewLocaleOffer].
class NewLocaleOfferDialog extends StatelessWidget {
  final Locale offered;

  const NewLocaleOfferDialog({super.key, required this.offered});

  static Future<bool?> show(BuildContext context, Locale offered) {
    return showDialog<bool>(
      context: context,
      builder: (_) => NewLocaleOfferDialog(offered: offered),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name = localizedLanguageName(context, offered);
    return AlertDialog(
      title: Text(t.languageNewlyAvailableTitle(name)),
      content: Text(t.languageNewlyAvailableBody(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.languageNewlyAvailableKeep),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.languageNewlyAvailableSwitch(name)),
        ),
      ],
    );
  }
}
