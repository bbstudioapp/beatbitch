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
      minIntervalSeconds: (data['min_interval_seconds'] as num?)?.toInt() ?? 20,
      maxIntervalSeconds: (data['max_interval_seconds'] as num?)?.toInt() ?? 45,
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

  /// Si non null : ne sort que si le BPM courant <= seuil. Permet de
  /// réserver une phrase calme (« doucement », « prends ton temps ») à un
  /// rythme bas, sans qu'elle tombe en plein sprint à 140 BPM.
  final int? maxBpm;

  /// Si non null : ne sort que si la profondeur courante (to ?? from) est
  /// au moins aussi profonde que ce seuil.
  final Position? minDepth;

  /// Si non null : ne sort que si la profondeur courante (to ?? from) est
  /// au plus aussi profonde que ce seuil. Permet de réserver une phrase
  /// du type « respire par le nez » à un hold pas trop profond, où la
  /// respiration nasale reste possible.
  final Position? maxDepth;

  /// Si non vide : la phrase n'est candidate que si **toutes** ces clés
  /// d'unlock (au format `UnlockKey.serialized`) sont acquises pour la
  /// session courante. Permet de scoper un sous-pool de phrases à une
  /// compétence : les phrases « bave / déborde / saliva pleine » ne
  /// sortent qu'une fois `sloppy_drool_basic` acquis, donnant à la
  /// joueuse un retour audible que sa milestone vient de changer le jeu.
  final List<String> requiresUnlock;

  const RandomComment({
    required this.text,
    this.modes,
    this.minBpm,
    this.maxBpm,
    this.minDepth,
    this.maxDepth,
    this.requiresUnlock = const [],
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
      final unlockRaw = raw['requires_unlock'];
      final requiresUnlock = <String>[];
      if (unlockRaw is String && unlockRaw.isNotEmpty) {
        requiresUnlock.add(unlockRaw);
      } else if (unlockRaw is List) {
        for (final v in unlockRaw) {
          if (v is String && v.isNotEmpty) requiresUnlock.add(v);
        }
      }
      return RandomComment(
        text: (raw['text'] as String?) ?? '',
        modes: modes != null && modes.isNotEmpty ? modes : null,
        minBpm: (raw['min_bpm'] as num?)?.toInt(),
        maxBpm: (raw['max_bpm'] as num?)?.toInt(),
        minDepth: Position.fromString(raw['min_depth'] as String?),
        maxDepth: Position.fromString(raw['max_depth'] as String?),
        requiresUnlock: requiresUnlock,
      );
    }
    return const RandomComment(text: '');
  }

  /// Vrai si ce commentaire s'applique au contexte courant ET que tous
  /// ses [requiresUnlock] sont satisfaits par [unlockedKeys].
  bool matches({
    required SessionMode mode,
    int? bpm,
    Position? depth,
    Set<String> unlockedKeys = const {},
  }) {
    if (modes != null && !modes!.contains(mode)) return false;
    if (minBpm != null && (bpm == null || bpm < minBpm!)) return false;
    if (maxBpm != null && bpm != null && bpm > maxBpm!) return false;
    if (minDepth != null) {
      if (depth == null || depth.index < minDepth!.index) return false;
    }
    if (maxDepth != null && depth != null && depth.index > maxDepth!.index) {
      return false;
    }
    for (final k in requiresUnlock) {
      if (!unlockedKeys.contains(k)) return false;
    }
    return true;
  }

  /// Vrai si la phrase n'a aucun filtre contextuel (mode/bpm/depth) et que
  /// ses prérequis d'unlock sont satisfaits — sert de fallback dans
  /// `pickFor` quand aucune phrase contextuelle ne match.
  bool isContextlessFor(Set<String> unlockedKeys) {
    if (modes != null ||
        minBpm != null ||
        maxBpm != null ||
        minDepth != null ||
        maxDepth != null) {
      return false;
    }
    for (final k in requiresUnlock) {
      if (!unlockedKeys.contains(k)) return false;
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
  /// filtre (= phrases applicables partout) — toujours filtrées par les
  /// `requires_unlock` éventuels. Si rien du tout, retourne null.
  ///
  /// [unlockedKeys] = compétences acquises pour la session courante (au
  /// format `UnlockKey.serialized`). Une phrase avec `requires_unlock`
  /// non couvert est exclue. Set vide = mode hérité (équivalent V1, sans
  /// scope par compétence).
  String? pickFor({
    required SessionMode mode,
    int? bpm,
    Position? depth,
    required Random rng,
    Set<String> unlockedKeys = const {},
  }) {
    final matching = comments
        .where((c) => c.matches(
              mode: mode,
              bpm: bpm,
              depth: depth,
              unlockedKeys: unlockedKeys,
            ))
        .toList();
    if (matching.isNotEmpty) {
      return matching[rng.nextInt(matching.length)].text;
    }
    final fallback =
        comments.where((c) => c.isContextlessFor(unlockedKeys)).toList();
    if (fallback.isEmpty) return null;
    return fallback[rng.nextInt(fallback.length)].text;
  }
}
