import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/session.dart';
import 'locale_service.dart';

class SessionLoader {
  static const List<String> _assetPaths = [
    'assets/sessions/session_tutorial.json',
    'assets/sessions/session_initiation.json',
    'assets/sessions/session_intense.json',
    'assets/sessions/session_advanced_demo.json',
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
      all.add(Session.fromJson(data));
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
