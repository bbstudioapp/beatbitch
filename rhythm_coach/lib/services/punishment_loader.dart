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
    final (raw, resolvedLang) = await _loadWithFallback(lang);
    final data = json.decode(raw) as Map<String, dynamic>;

    final declared = (data['lang'] as String?) ?? 'fr';
    if (declared != lang && kDebugMode) {
      debugPrint(
        '[PunishmentLoader] lang=$lang demandée → chargé lang=$resolvedLang (déclaré=$declared)',
      );
    }

    final phrases = (data['fail_phrases'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList();

    final swallowPhrases =
        (data['fail_phrases_swallow'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();

    final punishments = (data['punishments'] as List<dynamic>? ?? const [])
        .map((e) => Punishment.fromJson(e as Map<String, dynamic>))
        .toList();

    return PunishmentBundle(
      failPhrases: phrases,
      failPhrasesSwallow: swallowPhrases,
      punishments: punishments,
    );
  }

  String _resolvePath(String lang) {
    // Convention future : assets/punishments_<lang>.json. Si absent (cas FR
    // historique), on retombe sur assets/punishments.json.
    if (lang == 'fr') return _assetPathDefault;
    return 'assets/punishments_$lang.json';
  }

  /// Cascade `_<lang>.json` → `_en.json` → `_fr.json`. Permet d'ajouter une
  /// locale (UI traduite) avant d'avoir traduit le contenu éditorial.
  Future<(String raw, String lang)> _loadWithFallback(String lang) async {
    for (final candidate in <String>{lang, 'en', 'fr'}) {
      try {
        final raw = await rootBundle.loadString(_resolvePath(candidate));
        return (raw, candidate);
      } catch (_) {
        continue;
      }
    }
    throw StateError(
        'Aucun fichier punishments trouvé (essayé: $lang, en, fr)');
  }
}

class PunishmentBundle {
  final List<String> failPhrases;

  /// Phrases de fail dédiées à la transgression du toggle de déglutition
  /// (la salope a avalé alors que la coach l'avait interdit). Pool tiré
  /// uniquement quand `swallowMode == forbidden` au moment du fail. Si
  /// vide, on retombe sur [failPhrases] pour ne pas casser la session.
  final List<String> failPhrasesSwallow;

  final List<Punishment> punishments;

  const PunishmentBundle({
    required this.failPhrases,
    this.failPhrasesSwallow = const [],
    required this.punishments,
  });

  bool get isEmpty => failPhrases.isEmpty || punishments.isEmpty;
}
