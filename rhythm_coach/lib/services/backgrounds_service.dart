import 'dart:math';

import 'package:flutter/foundation.dart';

import 'backgrounds_loader.dart';

/// Contexte de session passé à `BackgroundsService.pickForContext`. Chaque
/// champ correspond à une catégorie du `BackgroundTagVocabulary`. Un champ
/// `null` signifie « pas d'info » — toute entrée qui porte un tag de cette
/// catégorie sera disqualifiée (un fond marqué `final` ne s'affiche pas
/// hors de la phase finale).
@immutable
class BackgroundContext {
  final String? mode;
  final String? position;
  final String? coach;
  final String? phase;

  const BackgroundContext({this.mode, this.position, this.coach, this.phase});

  bool get isEmpty =>
      mode == null && position == null && coach == null && phase == null;

  String? valueFor(BackgroundTagCategory cat) => switch (cat) {
        BackgroundTagCategory.mode => mode,
        BackgroundTagCategory.position => position,
        BackgroundTagCategory.coach => coach,
        BackgroundTagCategory.phase => phase,
      };
}

/// Singleton qui pilote le fond média de l'écran de jeu.
///
/// **Modes de mise à jour** :
/// - `setById(id)` : override explicite (consommé par `step.background`).
/// - `pickForContext(ctx)` : sélection priorisée — score = nombre de
///   catégories de tags qui matchent le contexte. Une entrée taguée dans
///   une catégorie *inconnue* du contexte (ex : `lick` pendant un rhythm)
///   est disqualifiée. Si aucune entrée taguée ne match, on tombe sur les
///   entrées sans tags (pool historique).
/// - `pickRandom()` : fallback historique — pioche au hasard hors entrée
///   courante, sans considérer les tags.
/// - `clear()` : retire le fond courant (le widget retombe sur le
///   placeholder animé).
///
/// **État** : `current` est un `ValueNotifier<BackgroundEntry?>` que le
/// widget `SessionBackground` écoute. Pas de stream — un seul observateur
/// (l'écran de jeu actif), pas besoin de broadcast.
class BackgroundsService {
  BackgroundsService._();

  static final BackgroundsService instance = BackgroundsService._();

  final ValueNotifier<BackgroundEntry?> current =
      ValueNotifier<BackgroundEntry?>(null);

  BackgroundsBundle _bundle = BackgroundsBundle.empty;
  final Random _rng = Random();

  /// Charge ou recharge le catalogue. Appelé une fois au démarrage de
  /// l'app, idempotent.
  void setBundle(BackgroundsBundle bundle) {
    _bundle = bundle;
    // Si l'entrée courante n'existe plus dans le nouveau bundle, on la
    // clear pour ne pas pointer vers un id orphelin.
    final cur = current.value;
    if (cur != null && _bundle.byId(cur.id) == null) {
      current.value = null;
    }
  }

  bool get hasEntries => _bundle.entries.isNotEmpty;

  /// Override explicite par id (typiquement appelé par `SessionController`
  /// quand un step a `background: "..."`). No-op si l'id est inconnu —
  /// on ne casse pas la session pour un asset manquant, on garde le fond
  /// courant.
  void setById(String id) {
    final entry = _bundle.byId(id);
    if (entry == null) return;
    current.value = entry;
  }

  /// Sélection priorisée par tags du nom de fichier. Pour chaque entrée :
  /// 1. Si elle porte au moins un tag dans une catégorie pour laquelle le
  ///    contexte n'a *aucune* valeur attendue (ex : tag `final` hors phase
  ///    finale, tag `lick` hors mode lick) → disqualifiée.
  /// 2. Sinon, son score est le nombre de catégories pour lesquelles le
  ///    contexte a une valeur ET cette valeur figure dans les tags de
  ///    l'entrée.
  ///
  /// Le bucket de plus haut score gagne. À score égal, tirage aléatoire
  /// (anti-doublon immédiat avec l'entrée courante). Si aucune entrée
  /// taguée ne match, on retombe sur le pool des entrées sans tags
  /// (`pickRandom` filtré). Si même ce pool est vide, on retombe sur le
  /// `pickRandom` historique (entrées taguées comprises) — mieux vaut un
  /// fond inadapté que pas de fond du tout quand le catalogue est entiè-
  /// rement tagué.
  void pickForContext(BackgroundContext ctx) {
    final entries = _bundle.entries;
    if (entries.isEmpty) return;
    if (ctx.isEmpty) {
      pickRandom();
      return;
    }
    var bestScore = -1;
    final byScore = <int, List<BackgroundEntry>>{};
    final untagged = <BackgroundEntry>[];
    for (final e in entries) {
      if (!e.hasTags) {
        untagged.add(e);
        continue;
      }
      final score = _scoreEntry(e, ctx);
      if (score < 0) continue;
      byScore.putIfAbsent(score, () => <BackgroundEntry>[]).add(e);
      if (score > bestScore) bestScore = score;
    }
    final tagged = bestScore > 0
        ? (byScore[bestScore] ?? const <BackgroundEntry>[])
        : const <BackgroundEntry>[];
    if (tagged.isNotEmpty) {
      _setExcluding(tagged);
      return;
    }
    if (untagged.isNotEmpty) {
      _setExcluding(untagged);
      return;
    }
    // Tout le catalogue est tagué mais aucun ne match : on retombe sur
    // un random global plutôt que de figer le fond.
    pickRandom();
  }

  static int _scoreEntry(BackgroundEntry e, BackgroundContext ctx) {
    var score = 0;
    for (final cat in BackgroundTagCategory.values) {
      final entryTags = e.tagsByCategory[cat];
      if (entryTags == null || entryTags.isEmpty) continue;
      final wanted = ctx.valueFor(cat);
      // Catégorie présente sur l'entrée mais absente du contexte → fond
      // hors-sujet (ex: tag `final` en pleine session). Mismatch sur la
      // valeur attendue → idem (`lick` pendant un rhythm). Disqualifié.
      if (wanted == null) return -1;
      if (!entryTags.contains(wanted)) return -1;
      score += 1;
    }
    return score;
  }

  void _setExcluding(List<BackgroundEntry> candidates) {
    if (candidates.isEmpty) return;
    if (candidates.length == 1) {
      current.value = candidates.first;
      return;
    }
    final cur = current.value;
    final idx = cur == null ? -1 : candidates.indexOf(cur);
    if (idx < 0) {
      current.value = candidates[_rng.nextInt(candidates.length)];
      return;
    }
    final draw = _rng.nextInt(candidates.length - 1);
    final pick = draw >= idx ? draw + 1 : draw;
    current.value = candidates[pick];
  }

  /// Pioche aléatoire **différente** de l'entrée courante (anti-doublon
  /// immédiat). Conservée pour les call sites qui n'ont pas de contexte
  /// (ex : reset, debug) et comme fallback de `pickForContext`. Si le
  /// bundle a une seule entrée, on retombe forcément dessus ; si le
  /// bundle est vide, no-op (le widget reste sur son placeholder animé).
  void pickRandom() {
    final n = _bundle.entries.length;
    if (n == 0) return;
    if (n == 1) {
      current.value = _bundle.entries.first;
      return;
    }
    final cur = current.value;
    final curIdx = cur == null ? -1 : _bundle.entries.indexOf(cur);
    if (curIdx < 0) {
      current.value = _bundle.entries[_rng.nextInt(n)];
      return;
    }
    // Tire dans [0, n-1] en excluant curIdx. Astuce : tirer dans
    // [0, n-2] et décaler de 1 si on tombe sur curIdx ou plus haut.
    final draw = _rng.nextInt(n - 1);
    final pick = draw >= curIdx ? draw + 1 : draw;
    current.value = _bundle.entries[pick];
  }

  /// Reset complet (sortie de session, retour au placeholder).
  void clear() {
    current.value = null;
  }

  @visibleForTesting
  void debugResetForTest() {
    _bundle = BackgroundsBundle.empty;
    current.value = null;
  }
}
