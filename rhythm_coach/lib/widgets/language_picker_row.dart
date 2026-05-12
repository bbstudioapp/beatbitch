import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

/// Sélecteur de langue compact (icône globe + dropdown). Lit/écrit la locale
/// active via [LocaleService] et se reconstruit quand elle change. Désactivé
/// tant qu'une seule locale est supportée. Libellés via [localizedLanguageName]
/// (« Français » / « English » / « Deutsch »…). Utilisé par l'écran Profil ;
/// c'est l'échappatoire universelle au choix de langue (le sélecteur de
/// premier lancement et l'offre « disponible en X » sont des canaux à part).
class LanguagePickerRow extends StatelessWidget {
  const LanguagePickerRow({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocaleService.instance,
      builder: (context, _) {
        final current = LocaleService.instance.current;
        final value =
            kSupportedLocales.any((l) => l.languageCode == current.languageCode)
                ? current.languageCode
                : kSupportedLocales.first.languageCode;
        final disabled = kSupportedLocales.length <= 1;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.language, color: AppTheme.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  onChanged: disabled
                      ? null
                      : (code) async {
                          if (code == null) return;
                          await LocaleService.instance.setLocale(Locale(code));
                        },
                  items: [
                    for (final l in kSupportedLocales)
                      DropdownMenuItem(
                        value: l.languageCode,
                        child: Text(
                          localizedLanguageName(context, l),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
