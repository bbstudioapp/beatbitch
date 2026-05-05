import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/punishment.dart';
import 'locale_service.dart';

/// Charge la liste des phrases de fail + des punitions depuis un seul JSON.
/// Tout est groupé dans `assets/punishments.json` pour faciliter la
/// modification du contenu sans toucher au code.
///
/// Pour le multi-langue, le fichier porte une clé top-level `lang`. À terme,
/// il y aura un fichier par locale (`punishments_fr.json`, `punishments_en.json`)
/// — pour l'instant on garde le path historique et on valide le `lang`.
class PunishmentLoader {
  static const String _assetPathDefault = 'assets/punishments.json';

  Future<PunishmentBundle> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final path = _resolvePath(lang);
    final raw = await rootBundle.loadString(path);
    final data = json.decode(raw) as Map<String, dynamic>;

    final declared = (data['lang'] as String?) ?? 'fr';
    if (declared != lang && kDebugMode) {
      debugPrint(
        '[PunishmentLoader] $path déclare lang=$declared mais locale demandée=$lang',
      );
    }

    final phrases = (data['fail_phrases'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    final punishments = (data['punishments'] as List<dynamic>? ?? const [])
        .map((e) => Punishment.fromJson(e as Map<String, dynamic>))
        .toList();

    return PunishmentBundle(failPhrases: phrases, punishments: punishments);
  }

  String _resolvePath(String lang) {
    // Convention future : assets/punishments_<lang>.json. Si absent (cas FR
    // historique), on retombe sur assets/punishments.json.
    if (lang == 'fr') return _assetPathDefault;
    return 'assets/punishments_$lang.json';
  }
}

class PunishmentBundle {
  final List<String> failPhrases;
  final List<Punishment> punishments;

  const PunishmentBundle({
    required this.failPhrases,
    required this.punishments,
  });

  bool get isEmpty => failPhrases.isEmpty || punishments.isEmpty;
}
