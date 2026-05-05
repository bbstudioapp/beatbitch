import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/session.dart';
import '../models/session_step.dart';
import 'locale_service.dart';

/// Charge la liste des commentaires aléatoires + leurs paramètres de cadence
/// depuis `assets/random_comments.json` (FR) ou `assets/random_comments_<lang>.json`.
///
/// Chaque entrée `comments[]` peut être :
/// - une simple chaîne `"phrase"` (applicable partout, fallback)
/// - un objet `{text, modes?, min_bpm?, min_depth?}` filtré par contexte
///   pour ne sortir que dans la situation correspondante (cf. C1 du plan).
class RandomCommentsLoader {
  static const String _assetPathDefault = 'assets/random_comments.json';

  Future<RandomCommentsBundle> load({Locale? locale}) async {
    final lang = (locale ?? LocaleService.instance.current).languageCode;
    final path = _resolvePath(lang);
    final raw = await rootBundle.loadString(path);
    final data = json.decode(raw) as Map<String, dynamic>;

    final declared = (data['lang'] as String?) ?? 'fr';
    if (declared != lang && kDebugMode) {
      debugPrint(
        '[RandomCommentsLoader] $path déclare lang=$declared mais locale demandée=$lang',
      );
    }

    final raws = (data['comments'] as List<dynamic>? ?? const []);
    final comments = raws
        .map(RandomComment.fromJson)
        .where((c) => c.text.trim().isNotEmpty)
        .toList();
    return RandomCommentsBundle(
      comments: comments,
      minIntervalSeconds:
          (data['min_interval_seconds'] as num?)?.toInt() ?? 20,
      maxIntervalSeconds:
          (data['max_interval_seconds'] as num?)?.toInt() ?? 45,
      scriptedCooldownSeconds:
          (data['scripted_cooldown_seconds'] as num?)?.toInt() ?? 4,
    );
  }

  String _resolvePath(String lang) {
    if (lang == 'fr') return _assetPathDefault;
    return 'assets/random_comments_$lang.json';
  }
}

/// Un commentaire random et ses contraintes optionnelles d'apparition.
class RandomComment {
  final String text;

  /// Si non null : ne sort que si le mode courant est dans la liste.
  final List<SessionMode>? modes;

  /// Si non null : ne sort que si le BPM courant >= seuil.
  final int? minBpm;

  /// Si non null : ne sort que si la profondeur courante (to ?? from) est
  /// au moins aussi profonde que ce seuil.
  final Position? minDepth;

  const RandomComment({
    required this.text,
    this.modes,
    this.minBpm,
    this.minDepth,
  });

  /// Accepte deux formats sérialisés : string simple ou objet avec filtres.
  factory RandomComment.fromJson(dynamic raw) {
    if (raw is String) return RandomComment(text: raw);
    if (raw is Map<String, dynamic>) {
      final modesRaw = raw['modes'] as List<dynamic>?;
      final modes = modesRaw
          ?.map((e) => SessionMode.fromString(e as String))
          .whereType<SessionMode>()
          .toList();
      return RandomComment(
        text: (raw['text'] as String?) ?? '',
        modes: modes != null && modes.isNotEmpty ? modes : null,
        minBpm: (raw['min_bpm'] as num?)?.toInt(),
        minDepth: Position.fromString(raw['min_depth'] as String?),
      );
    }
    return const RandomComment(text: '');
  }

  /// Vrai si ce commentaire s'applique au contexte courant.
  bool matches({
    required SessionMode mode,
    int? bpm,
    Position? depth,
  }) {
    if (modes != null && !modes!.contains(mode)) return false;
    if (minBpm != null && (bpm == null || bpm < minBpm!)) return false;
    if (minDepth != null) {
      if (depth == null || depth.index < minDepth!.index) return false;
    }
    return true;
  }
}

class RandomCommentsBundle {
  /// Liste des phrases candidates avec leurs filtres optionnels.
  final List<RandomComment> comments;

  /// Délai minimum entre deux commentaires aléatoires (secondes).
  final int minIntervalSeconds;

  /// Délai maximum entre deux commentaires aléatoires (secondes).
  /// Le délai effectif est tiré uniformément dans [min, max].
  final int maxIntervalSeconds;

  /// Si une phrase scriptée a été dite il y a moins de N secondes, on
  /// reporte le commentaire aléatoire pour ne pas chevaucher.
  final int scriptedCooldownSeconds;

  const RandomCommentsBundle({
    required this.comments,
    required this.minIntervalSeconds,
    required this.maxIntervalSeconds,
    required this.scriptedCooldownSeconds,
  });

  bool get isEmpty => comments.isEmpty;

  /// Tire une phrase aléatoire compatible avec le contexte courant. Si
  /// aucune phrase contextuelle ne match, fallback sur les phrases sans
  /// filtre (= phrases applicables partout). Si rien du tout, retourne null.
  String? pickFor({
    required SessionMode mode,
    int? bpm,
    Position? depth,
    required Random rng,
  }) {
    final matching = comments
        .where((c) => c.matches(mode: mode, bpm: bpm, depth: depth))
        .toList();
    if (matching.isNotEmpty) {
      return matching[rng.nextInt(matching.length)].text;
    }
    final fallback = comments
        .where((c) => c.modes == null && c.minBpm == null && c.minDepth == null)
        .toList();
    if (fallback.isEmpty) return null;
    return fallback[rng.nextInt(fallback.length)].text;
  }
}
