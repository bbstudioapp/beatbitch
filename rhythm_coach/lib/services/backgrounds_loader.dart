import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Type d'un média de fond. Pas de vidéo en V1 (cf. CLAUDE.md backlog).
enum BackgroundMediaType {
  image,
  gif;

  static BackgroundMediaType? fromString(String? raw) {
    if (raw == null) return null;
    return switch (raw.toLowerCase()) {
      'image' => BackgroundMediaType.image,
      'gif' => BackgroundMediaType.gif,
      _ => null,
    };
  }
}

/// Une entrée du catalogue de fonds. Référence un asset par `id` + `path`.
/// Pas de tags en V1 — on rotate uniformément. Cf. CLAUDE.md backlog
/// pour le retour des tags si une segmentation par thème devient utile.
class BackgroundEntry {
  final String id;
  final BackgroundMediaType type;
  final String path;

  const BackgroundEntry({
    required this.id,
    required this.type,
    required this.path,
  });

  factory BackgroundEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final type = BackgroundMediaType.fromString(json['type'] as String?);
    final path = json['path'];
    if (id is! String || type == null || path is! String) {
      throw FormatException(
          'BackgroundEntry: id/type/path invalides (reçu: $json)');
    }
    return BackgroundEntry(id: id, type: type, path: path);
  }
}

/// Bundle chargé depuis `assets/backgrounds.json`. Liste vide → fallback
/// gracieux côté `BackgroundsService` (le widget retombe sur le dégradé
/// animé placeholder).
class BackgroundsBundle {
  final List<BackgroundEntry> entries;

  const BackgroundsBundle({required this.entries});

  static const empty = BackgroundsBundle(entries: []);

  BackgroundEntry? byId(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }
}

class BackgroundsLoader {
  static const String _assetPath = 'assets/backgrounds.json';

  Future<BackgroundsBundle> load() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final data = json.decode(raw) as Map<String, dynamic>;
      final list = (data['backgrounds'] as List<dynamic>? ?? const [])
          .map((e) => BackgroundEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return BackgroundsBundle(entries: list);
    } catch (_) {
      // Fichier absent / invalide : on retourne un bundle vide pour que le
      // widget tombe sur son fallback animé sans planter la session.
      return BackgroundsBundle.empty;
    }
  }
}
