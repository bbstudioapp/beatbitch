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

  const AmbiencePack({
    required this.id,
    required this.name,
    this.description,
    required this.tracksByMode,
  });

  /// Pack vide (silence total), toujours disponible en tête de liste.
  static const AmbiencePack none = AmbiencePack(
    id: 'none',
    name: 'Aucune',
    description: 'Pas d\'ambiance — bips et voix uniquement.',
    tracksByMode: {},
  );

  String? assetFor(SessionMode mode) => tracksByMode[mode];

  factory AmbiencePack.fromJson(Map<String, dynamic> json) {
    final rawTracks = (json['tracks'] as Map?) ?? const {};
    final tracks = <SessionMode, String?>{};
    rawTracks.forEach((key, value) {
      final mode = SessionMode.fromString(key.toString());
      final asset = value?.toString();
      tracks[mode] = (asset == null || asset.isEmpty) ? null : asset;
    });
    return AmbiencePack(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      tracksByMode: tracks,
    );
  }
}
