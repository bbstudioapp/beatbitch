import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../services/locale_service.dart';
import '../models/coach.dart';
import '../models/coach_catalog.dart';

/// Charge les coachs depuis deux types de fichiers :
///
/// - `assets/career/coaches/<coach.id>.json` — **préférences gameplay**
///   indépendantes de la langue (name, archetype, tier, isPrincipal,
///   specialties, requirements).
/// - `assets/career/coaches/<coach.id>_<lang>.json` — **contenu localisé**
///   (title, publicBio, phrases, nicknames).
///
/// Pipeline pour chaque coach :
/// 1. Part de la définition codée (`CoachCatalog.defaults`).
/// 2. Applique les préférences globales si le fichier existe.
/// 3. Applique le pack langue demandé ; fallback sur `_fr.json` si la
///    langue demandée manque ; sinon laisse vide (les phrases retomberont
///    sur la PhraseBank globale via `Coach.toPhraseBank`).
///
/// Aucune exception ne remonte : un asset manquant est traité comme
/// "rien à overrider", l'app reste utilisable.
class CoachLoader {
  static const String _dir = 'assets/career/coaches';

  Future<List<Coach>> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final futures = CoachCatalog.defaults
        .map((c) => _loadOne(c, lang))
        .toList(growable: false);
    final merged = await Future.wait(futures);
    return List.unmodifiable(merged);
  }

  Future<Coach> _loadOne(Coach coach, String lang) async {
    var resolved = coach;

    // 1. Meta globale (langue-indépendante).
    final meta = await _tryLoadMeta(coach.id);
    if (meta != null) resolved = resolved.withMeta(meta);

    // 2. Pack localisé (phrases + title/bio + nicknames).
    final pack = await _tryLoadPack(coach.id, lang) ??
        (lang == 'fr' ? null : await _tryLoadPack(coach.id, 'fr'));
    if (pack != null) resolved = resolved.withPhrases(pack);

    return resolved;
  }

  Future<CoachMeta?> _tryLoadMeta(String coachId) async {
    final path = '$_dir/$coachId.json';
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      return CoachMeta.fromJson(data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            'CoachLoader: pas de meta global pour $coachId ($path) — $e');
      }
      return null;
    }
  }

  Future<CoachPhrasePack?> _tryLoadPack(String coachId, String lang) async {
    final path = '$_dir/${coachId}_$lang.json';
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      return CoachPhrasePack.fromJson(data);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('CoachLoader: pas de pack pour $coachId/$lang ($path) — $e');
      }
      return null;
    }
  }
}
