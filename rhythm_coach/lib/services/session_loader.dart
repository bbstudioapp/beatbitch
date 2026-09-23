import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import '../models/session.dart';
import 'locale_service.dart';

class SessionLoader {
  /// [isAssetBundled] reçoit la clé complète de l'asset (`assets/...`). Le
  /// défaut interroge l'`AssetManifest` : lire le fichier lui-même chargerait
  /// le morceau entier en mémoire pour un simple test de présence.
  SessionLoader({Future<bool> Function(String assetKey)? isAssetBundled})
      : _isAssetBundled = isAssetBundled ?? _manifestContains;

  final Future<bool> Function(String assetKey) _isAssetBundled;

  static Set<String>? _manifestKeys;

  static Future<bool> _manifestContains(String assetKey) async {
    try {
      _manifestKeys ??= (await AssetManifest.loadFromAssetBundle(rootBundle))
          .listAssets()
          .toSet();
      return _manifestKeys!.contains(assetKey);
    } catch (_) {
      return false;
    }
  }

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
    'assets/sessions/session_montee_puissance.json',
    'assets/sessions/session_montee_puissance_en.json',
    'assets/sessions/session_montee_puissance_de.json',
    'assets/sessions/session_montee_puissance_es.json',
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
