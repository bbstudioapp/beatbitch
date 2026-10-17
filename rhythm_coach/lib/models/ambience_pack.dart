import 'session.dart';

/// Mapping mode → asset d'ambiance. Une entrée absente ou null signifie
/// « silence pour ce mode ». Le pack `none` (vide) coupe toute ambiance.
class AmbiencePack {
  final String id;
  final String name;
  final String? description;

  /// Chemin asset relatif au dossier `assets/` (ex: `audio/ambience/rain.mp3`).
  /// Une valeur null ou absente coupe l'ambiance pour ce mode.
  final Map<SessionMode, String?> tracksByMode;

  /// Variantes tirées au hasard, séparées par palier de profondeur. Un mode
  /// absent d'ici se rabat sur [tracksByMode].
  final Map<SessionMode, AmbienceVariants> variantsByMode;

  /// Clips joués une fois, au moment du chime du final.
  final List<String> climax;

  const AmbiencePack({
    required this.id,
    required this.name,
    this.description,
    required this.tracksByMode,
    this.variantsByMode = const {},
    this.climax = const [],
  });

  /// Pack vide (silence total), toujours disponible en tête de liste.
  static const AmbiencePack none = AmbiencePack(
    id: 'none',
    name: 'Aucune',
    description: 'Pas d\'ambiance — bips et voix uniquement.',
    tracksByMode: {},
  );

  String? assetFor(SessionMode mode) => tracksByMode[mode];

  List<String> candidatesFor(SessionMode mode, {required bool deep}) {
    final variants = variantsByMode[mode];
    if (variants == null) {
      final asset = tracksByMode[mode];
      return asset == null ? const [] : [asset];
    }
    final preferred = deep ? variants.deep : variants.shallow;
    if (preferred.isNotEmpty) return preferred;
    return deep ? variants.shallow : variants.deep;
  }

  /// Une piste s'écrit soit `"fichier.mp3"`, soit une liste de variantes,
  /// soit `{"shallow": ..., "deep": ...}` (chaque palier : fichier ou liste).
  factory AmbiencePack.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as Map?) ?? const {};
    final tracks = <SessionMode, String?>{};
    final variants = <SessionMode, AmbienceVariants>{};
    rawTracks.forEach((key, value) {
      final mode = SessionMode.fromString(key.toString());
      if (value is Map) {
        final v = AmbienceVariants(
          shallow: _assetList(value['shallow']),
          deep: _assetList(value['deep']),
        );
        variants[mode] = v;
        tracks[mode] = [...v.shallow, ...v.deep].firstOrNull;
      } else if (value is List) {
        final list = _assetList(value);
        variants[mode] = AmbienceVariants(shallow: list, deep: list);
        tracks[mode] = list.firstOrNull;
      } else {
        final asset = value?.toString();
        tracks[mode] = (asset == null || asset.isEmpty) ? null : asset;
      }
    });
    return AmbiencePack(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      tracksByMode: tracks,
      variantsByMode: variants,
      climax: _assetList(json['climax']),
    );
  }

  static List<String> _assetList(Object? raw) => switch (raw) {
        final String s when s.isNotEmpty => [s],
        final List l => [
            for (final e in l)
              if (e != null && e.toString().isNotEmpty) e.toString(),
          ],
        _ => const [],
      };
}

class AmbienceVariants {
  final List<String> shallow;
  final List<String> deep;

  const AmbienceVariants({required this.shallow, required this.deep});
}
