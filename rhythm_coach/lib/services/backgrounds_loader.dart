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

/// Catégories de tags qu'un fichier peut porter dans son nom. Vocabulaire
/// fermé : tout segment du basename qui n'appartient à aucune catégorie
/// fait partie de l'`id`, pas des tags. Cela permet à l'`id` de contenir
/// des `_` sans casser le parsing.
enum BackgroundTagCategory { mode, position, coach, phase }

/// Vocabulaire de tags reconnus dans les noms de fichiers de fond.
///
/// Chaque tag appartient à une seule catégorie (mode | position | coach |
/// phase). Le parser remonte les segments du basename depuis la droite tant
/// qu'ils appartiennent à ce vocabulaire ; au premier inconnu il s'arrête
/// et le reste est l'`id` brut du média.
///
/// Modèle de scoring côté `BackgroundsService` :
/// - chaque catégorie présente dans les tags de l'entrée doit matcher le
///   contexte de la session, sinon l'entrée est disqualifiée (un fond
///   tagué `lick` n'apparaîtra pas pendant un step `rhythm`).
/// - le score est le nombre de catégories matchées ; à score égal, tirage
///   aléatoire ; à score 0 (entrée sans tag), fallback random historique.
class BackgroundTagVocabulary {
  static const Map<String, BackgroundTagCategory> _byTag = {
    // SessionMode.values.map((m) => m.name) — gardé en miroir manuel pour
    // ne pas dépendre du fichier models/ depuis le loader.
    'rhythm': BackgroundTagCategory.mode,
    'lick': BackgroundTagCategory.mode,
    'biffle': BackgroundTagCategory.mode,
    'hold': BackgroundTagCategory.mode,
    'breath': BackgroundTagCategory.mode,
    'beg': BackgroundTagCategory.mode,
    'freestyle': BackgroundTagCategory.mode,
    'hand': BackgroundTagCategory.mode,
    // Position.values.map((p) => p.name)
    'tip': BackgroundTagCategory.position,
    'head': BackgroundTagCategory.position,
    'mid': BackgroundTagCategory.position,
    'throat': BackgroundTagCategory.position,
    'full': BackgroundTagCategory.position,
    'balls': BackgroundTagCategory.position,
    // Coachs : nom court (suffixe de `coach_NN_<name>`).
    'lina': BackgroundTagCategory.coach,
    'helene': BackgroundTagCategory.coach,
    'jade': BackgroundTagCategory.coach,
    'morgan': BackgroundTagCategory.coach,
    'victoria': BackgroundTagCategory.coach,
    'nyx': BackgroundTagCategory.coach,
    // Phases dramaturgiques. `final` = le step `finale_chime` ;
    // `post-final` = ce qui vient après (giclées résiduelles, MERCI).
    'final': BackgroundTagCategory.phase,
    'post-final': BackgroundTagCategory.phase,
  };

  static BackgroundTagCategory? categorize(String tag) => _byTag[tag];

  static bool isKnown(String tag) => _byTag.containsKey(tag);
}

/// Une entrée du catalogue de fonds. L'`id` est dérivé du nom de fichier
/// (sans extension) — stable tant que le fichier garde son nom, ne dépend
/// pas de la position dans la liste.
///
/// Les `tags` sont les segments suffixes du basename qui appartiennent au
/// `BackgroundTagVocabulary`. Exemple : `clip01_lina_throat.png` →
/// `id = "clip01"`, `tags = {lina, throat}`, `tagsByCategory = {coach:
/// {lina}, position: {throat}}`. Si aucun tag n'est détecté, l'`id` reste
/// le basename complet et `tags` est vide — comportement V0 préservé pour
/// les fonds historiques sans suffixe.
class BackgroundEntry {
  final String id;
  final BackgroundMediaType type;
  final String path;
  final Set<String> tags;
  final Map<BackgroundTagCategory, Set<String>> tagsByCategory;

  const BackgroundEntry({
    required this.id,
    required this.type,
    required this.path,
    this.tags = const {},
    this.tagsByCategory = const {},
  });

  bool get hasTags => tags.isNotEmpty;
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
          .map(parseEntry)
          .whereType<BackgroundEntry>()
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return BackgroundsBundle(entries: entries);
    } catch (_) {
      return BackgroundsBundle.empty;
    }
  }

  /// Exposé pour les tests : convertit un asset path en `BackgroundEntry`
  /// (ou `null` si l'extension ou le chemin ne sont pas valides). Garde
  /// la même logique de parsing que la passe `load()`.
  static BackgroundEntry? parseEntry(String assetPath) {
    if (!assetPath.startsWith(_prefix)) return null;
    final filename = assetPath.substring(_prefix.length);
    if (filename.isEmpty || filename.contains('/')) return null;
    final dotIdx = filename.lastIndexOf('.');
    if (dotIdx <= 0 || dotIdx == filename.length - 1) return null;
    final ext = filename.substring(dotIdx + 1).toLowerCase();
    if (!_supportedExtensions.contains(ext)) return null;
    final basename = filename.substring(0, dotIdx);
    final parsed = _splitIdAndTags(basename);
    return BackgroundEntry(
      id: parsed.id,
      type: BackgroundMediaType.fromExtension(ext),
      path: assetPath,
      tags: parsed.tags,
      tagsByCategory: parsed.byCategory,
    );
  }

  /// Sépare `basename` en `id` + `tags` : on remonte les segments depuis
  /// la droite tant qu'ils sont dans le vocabulaire. Au premier segment
  /// inconnu, le reste à gauche (joint par `_`) est l'`id`. Permet aux
  /// id de contenir des `_` sans casser le parsing — un fichier historique
  /// `porngif-d242ee.png` sans suffixe reste `id = "porngif-d242ee"`,
  /// `tags = {}`.
  static _IdAndTags _splitIdAndTags(String basename) {
    final parts = basename.split('_');
    if (parts.length < 2) {
      return _IdAndTags(id: basename, tags: const {}, byCategory: const {});
    }
    final tags = <String>{};
    final byCategory = <BackgroundTagCategory, Set<String>>{};
    var cut = parts.length;
    for (var i = parts.length - 1; i >= 1; i--) {
      // i >= 1 : on garde au moins un segment pour l'id.
      final seg = parts[i].toLowerCase();
      final cat = BackgroundTagVocabulary.categorize(seg);
      if (cat == null) break;
      tags.add(seg);
      byCategory.putIfAbsent(cat, () => <String>{}).add(seg);
      cut = i;
    }
    if (cut == parts.length) {
      return _IdAndTags(id: basename, tags: const {}, byCategory: const {});
    }
    final id = parts.sublist(0, cut).join('_');
    return _IdAndTags(id: id, tags: tags, byCategory: byCategory);
  }
}

class _IdAndTags {
  final String id;
  final Set<String> tags;
  final Map<BackgroundTagCategory, Set<String>> byCategory;
  const _IdAndTags({
    required this.id,
    required this.tags,
    required this.byCategory,
  });
}
