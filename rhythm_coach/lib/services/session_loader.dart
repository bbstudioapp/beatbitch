import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/session.dart';
import 'bundled_assets.dart' as bundled;
import 'locale_service.dart';

class SessionLoader {
  SessionLoader({Future<bool> Function(String assetKey)? isAssetBundled})
      : _isAssetBundled = isAssetBundled ?? bundled.isAssetBundled;

  final Future<bool> Function(String assetKey) _isAssetBundled;

  static const List<String> _assetPaths = [
    'assets/sessions/session_tutorial.json',
    'assets/sessions/session_initiation.json',
    'assets/sessions/session_intense.json',
    'assets/sessions/session_advanced_demo.json',
    'assets/sessions/session_tutorial_en.json',
    'assets/sessions/session_initiation_en.json',
    'assets/sessions/session_intense_en.json',
    'assets/sessions/session_advanced_demo_en.json',
    'assets/sessions/session_tutorial_de.json',
    'assets/sessions/session_initiation_de.json',
    'assets/sessions/session_intense_de.json',
    'assets/sessions/session_advanced_demo_de.json',
    'assets/sessions/session_tutorial_es.json',
    'assets/sessions/session_initiation_es.json',
    'assets/sessions/session_intense_es.json',
    'assets/sessions/session_advanced_demo_es.json',
  ];

  /// Charge toutes les sessions intégrées et filtre par locale active.
  /// Si aucune locale ne correspond, retourne le sous-ensemble en `fr` à titre
  /// de fallback pour ne pas livrer une liste vide à l'écran d'accueil.
  Future<List<Session>> loadAll({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final all = <Session>[];
    for (final path in _assetPaths) {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      final session = Session.fromJson(data);
      // Le morceau est hors dépôt : sans lui la séance ne se joue pas.
      final music = session.music;
      if (music != null && !await _isAssetBundled('assets/${music.asset}')) {
        continue;
      }
      all.add(session);
    }
    final matching = all.where((s) => s.lang == lang).toList();
    if (matching.isNotEmpty) return matching;
    if (kDebugMode) {
      debugPrint(
        '[SessionLoader] aucune session pour lang=$lang — fallback fr',
      );
    }
    return all.where((s) => s.lang == 'fr').toList();
  }
}
