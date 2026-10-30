import 'package:flutter/services.dart' show AssetManifest, rootBundle;

enum BackgroundMediaType {
  image,
  gif;

  static BackgroundMediaType fromExtension(String ext) {
    return ext.toLowerCase() == 'gif'
        ? BackgroundMediaType.gif
        : BackgroundMediaType.image;
  }
}

enum BackgroundTagCategory {
  mode,
  position,
  coach,
  phase,
  tier,
  viewpoint,
  moment,
}

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
    'suckle': BackgroundTagCategory.mode,
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
    'lilith': BackgroundTagCategory.coach,
    'marc': BackgroundTagCategory.coach,
    // Phases dramaturgiques. `final` = le step `finale_chime` ;
    // `post-final` = ce qui vient après (giclées résiduelles, MERCI).
    'final': BackgroundTagCategory.phase,
    'post-final': BackgroundTagCategory.phase,
    'fail': BackgroundTagCategory.phase,
    'challenge': BackgroundTagCategory.phase,
    // Paliers de nudité : `nu1` = seins nus, `nu2` = nue. Sans tag = lingerie.
    'nu1': BackgroundTagCategory.tier,
    'nu2': BackgroundTagCategory.tier,
    // Scène vue par la joueuse, commune à toutes les coachs.
    'pov': BackgroundTagCategory.viewpoint,
    // Moments de jeu : `play` = le fil de l'acte, quel que soit le geste.
    'play': BackgroundTagCategory.moment,
    'punish': BackgroundTagCategory.moment,
    'milestone': BackgroundTagCategory.moment,
  };

  static BackgroundTagCategory? categorize(String tag) => _byTag[tag];

  static bool isKnown(String tag) => _byTag.containsKey(tag);
}

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

  String? get tier => tagsByCategory[BackgroundTagCategory.tier]?.first;

  // Le pack nomme ses fonds d'intro `<coach>-pack[-nuN]-intro-…` : pas de tag.
  bool get isIntro => id.contains('-intro-');

  bool get isPov => tags.contains('pov');

  bool get isMilestone => tags.contains('milestone');

  // Le pack nomme ses transitions sans tag propre : palier + coach seuls.
  bool get isTierTransition =>
      tier != null &&
      !isIntro &&
      tagsByCategory.keys.every((c) =>
          c == BackgroundTagCategory.coach || c == BackgroundTagCategory.tier);
}

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

  static _IdAndTags _splitIdAndTags(String basename) {
    final parts = basename.split('_');
    if (parts.length < 2) {
      return _IdAndTags(id: basename, tags: const {}, byCategory: const {});
    }
    final tags = <String>{};
    final byCategory = <BackgroundTagCategory, Set<String>>{};
    var cut = parts.length;
    for (var i = parts.length - 1; i >= 1; i--) {
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
