import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart' show rootBundle;

import '../models/ambience_pack.dart';
import 'locale_service.dart';

class AmbiencePackLoader {
  static const String _assetPathDefault = 'assets/ambience_packs.json';

  Future<List<AmbiencePack>> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final path =
        lang == 'fr' ? _assetPathDefault : 'assets/ambience_packs_$lang.json';
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw) as Map<String, dynamic>;
      final packs = (data['packs'] as List<dynamic>? ?? const [])
          .map((p) => AmbiencePack.fromJson(p as Map<String, dynamic>))
          .toList();
      // Toujours injecter le pack `none` en première position.
      return [AmbiencePack.none, ...packs];
    } catch (_) {
      // Fichier absent ou invalide → on retourne au moins le pack vide
      // pour que l'UI reste cohérente.
      return const [AmbiencePack.none];
    }
  }
}
