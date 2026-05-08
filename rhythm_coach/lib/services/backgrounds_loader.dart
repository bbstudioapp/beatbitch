import 'package:flutter/services.dart' show AssetManifest, rootBundle;

/// Type d'un média de fond. Pas de vidéo en V1 (cf. CLAUDE.md backlog).
enum BackgroundMediaType {
  image,
  gif;

  static BackgroundMediaType fromExtension(String ext) {
    return ext.toLowerCase() == 'gif'
        ? BackgroundMediaType.gif
        : BackgroundMediaType.image;
  }
}

/// Une entrée du catalogue de fonds. L'`id` est dérivé du nom de fichier
/// (sans extension) — stable tant que le fichier garde son nom, ne dépend
/// pas de la position dans la liste.
class BackgroundEntry {
  final String id;
  final BackgroundMediaType type;
  final String path;

  const BackgroundEntry({
    required this.id,
    required this.type,
    required this.path,
  });
}

/// Bundle des fonds bundlés dans l'APK. Liste vide → fallback gracieux côté
/// `BackgroundsService` (le widget retombe sur le dégradé animé placeholder).
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

/// Source des fonds : scan de l'`AssetManifest` Flutter au runtime, filtré
/// sur le dossier `assets/backgrounds/`. Pas de fichier JSON statique à
/// maintenir : la liste suit ce qui est réellement bundlé dans l'APK.
///
/// Les binaires (gifs/images) ne sont **pas** versionnés dans le dépôt git —
/// ils sont rapatriés depuis un canal externe avant `flutter build`. Si le
/// dossier est vide à la build, le bundle est vide et le widget tombe sur
/// son dégradé animé sans planter.
class BackgroundsLoader {
  static const String _prefix = 'assets/backgrounds/';
  static const Set<String> _supportedExtensions = {
    'gif',
    'png',
    'jpg',
    'jpeg',
    'webp',
  };

  Future<BackgroundsBundle> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final entries = manifest
          .listAssets()
          .where((p) => p.startsWith(_prefix))
          .map(_entryFor)
          .whereType<BackgroundEntry>()
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return BackgroundsBundle(entries: entries);
    } catch (_) {
      return BackgroundsBundle.empty;
    }
  }

  static BackgroundEntry? _entryFor(String assetPath) {
    final filename = assetPath.substring(_prefix.length);
    if (filename.isEmpty || filename.contains('/')) return null;
    final dotIdx = filename.lastIndexOf('.');
    if (dotIdx <= 0 || dotIdx == filename.length - 1) return null;
    final ext = filename.substring(dotIdx + 1).toLowerCase();
    if (!_supportedExtensions.contains(ext)) return null;
    final id = filename.substring(0, dotIdx);
    return BackgroundEntry(
      id: id,
      type: BackgroundMediaType.fromExtension(ext),
      path: assetPath,
    );
  }
}
