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
  final String? tier;

  const BackgroundContext({
    this.mode,
    this.position,
    this.coach,
    this.phase,
    this.tier,
  });

  bool get isEmpty =>
      mode == null &&
      position == null &&
      coach == null &&
      phase == null &&
      tier == null;

  String? valueFor(BackgroundTagCategory cat) => switch (cat) {
        BackgroundTagCategory.mode => mode,
        BackgroundTagCategory.position => position,
        BackgroundTagCategory.coach => coach,
        BackgroundTagCategory.phase => phase,
        BackgroundTagCategory.tier => tier,
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

  static const List<String> _tierNames = ['nu1', 'nu2'];
  static int _rankOf(String? tier) => _tierNames.indexOf(tier ?? '') + 1;
  static String? _nameOf(int rank) => rank == 0 ? null : _tierNames[rank - 1];

  Set<String> _tieredCoaches = const {};
  int _tierRank = 0;
  final List<BackgroundEntry> _transitions = [];
  BackgroundContext? _afterTransitions;

  void _resetTiers() {
    _tierRank = 0;
    _transitions.clear();
    _afterTransitions = null;
  }

  /// Charge ou recharge le catalogue. Appelé une fois au démarrage de
  /// l'app, idempotent.
  void setBundle(BackgroundsBundle bundle) {
    _bundle = bundle;
    _tieredCoaches = {
      for (final e in bundle.entries)
        if (e.tier != null) ...?e.tagsByCategory[BackgroundTagCategory.coach],
    };
    _resetTiers();
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
    if (_bundle.entries.isEmpty) return;
    // Seul un coach qui a des fonds de palier en reçoit ; le palier atteint
    // ne redescend pas en cours de séance.
    final tiered = ctx.coach != null && _tieredCoaches.contains(ctx.coach);
    final before = _tierRank;
    if (tiered) _tierRank = max(_tierRank, _rankOf(ctx.tier));
    final effective = BackgroundContext(
      mode: ctx.mode,
      position: ctx.position,
      coach: ctx.coach,
      phase: ctx.phase,
      tier: tiered ? _nameOf(_tierRank) : null,
    );
    final wasPlaying = _transitions.isNotEmpty;
    for (var r = before + 1; r <= _tierRank; r++) {
      final strip = _transitionTo(ctx.coach, r);
      if (strip != null) _transitions.add(strip);
    }
    if (_transitions.isNotEmpty) {
      _afterTransitions = effective;
      if (!wasPlaying) current.value = _transitions.first;
      return;
    }
    _pick(effective);
  }

  /// Fin de lecture d'une transition (signalée par le widget). Enchaîne la
  /// suivante, ou le fond du dernier contexte demandé. Ignorée si [entry]
  /// n'est pas la transition à l'écran.
  void transitionFinished(BackgroundEntry entry) {
    if (_transitions.isEmpty || _transitions.first.id != entry.id) return;
    _transitions.removeAt(0);
    if (_transitions.isNotEmpty) {
      current.value = _transitions.first;
      return;
    }
    final ctx = _afterTransitions;
    _afterTransitions = null;
    if (ctx != null) _pick(ctx);
  }

  /// Fond de la phase d'échec, au palier atteint. Faux, fond courant gardé,
  /// si le coach n'a aucun fond `fail`.
  bool pickFail(String? coach) {
    final tiered = coach != null && _tieredCoaches.contains(coach);
    final best = _rank(
      BackgroundContext(
        coach: coach,
        phase: 'fail',
        tier: tiered ? _nameOf(_tierRank) : null,
      ),
      where: (e) => e.tags.contains('fail'),
    ).best;
    if (best.isEmpty) return false;
    _transitions.clear();
    _afterTransitions = null;
    _setExcluding(best);
    return true;
  }

  BackgroundEntry? _transitionTo(String? coach, int rank) {
    final candidates = _bundle.entries
        .where((e) =>
            e.isTierTransition &&
            e.tier == _nameOf(rank) &&
            (e.tagsByCategory[BackgroundTagCategory.coach]?.contains(coach) ??
                false))
        .toList();
    return candidates.isEmpty
        ? null
        : candidates[_rng.nextInt(candidates.length)];
  }

  void _pick(BackgroundContext ctx) {
    if (ctx.isEmpty) {
      pickRandom();
      return;
    }
    final ranked = _rank(ctx);
    if (ranked.best.isNotEmpty) {
      _setExcluding(ranked.best);
      return;
    }
    if (ranked.untagged.isNotEmpty) {
      _setExcluding(ranked.untagged);
      return;
    }
    // Tout le catalogue est tagué mais aucun ne match : on retombe sur
    // un random global plutôt que de figer le fond.
    pickRandom();
  }

  ({List<BackgroundEntry> best, List<BackgroundEntry> untagged}) _rank(
    BackgroundContext ctx, {
    bool Function(BackgroundEntry)? where,
  }) {
    var bestScore = -1;
    final byScore = <int, List<BackgroundEntry>>{};
    final untagged = <BackgroundEntry>[];
    for (final e in _bundle.entries) {
      if (e.isTierTransition || (where != null && !where(e))) continue;
      if (!e.hasTags) {
        untagged.add(e);
        continue;
      }
      final score = _scoreEntry(e, ctx);
      if (score < 0) continue;
      byScore.putIfAbsent(score, () => <BackgroundEntry>[]).add(e);
      if (score > bestScore) bestScore = score;
    }
    return (
      best: bestScore > 0
          ? (byScore[bestScore] ?? const <BackgroundEntry>[])
          : const <BackgroundEntry>[],
      untagged: untagged,
    );
  }

  static int _scoreEntry(BackgroundEntry e, BackgroundContext ctx) {
    // Un contexte à palier exclut la lingerie (entrées sans tag de palier).
    if (ctx.tier != null && e.tier == null) return -1;
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
      // Une phase l'emporte sur un mode : le final est une tenue, les deux
      // fonds seraient à égalité.
      score += cat == BackgroundTagCategory.phase ? 2 : 1;
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
    final pool = _bundle.entries.where((e) => !e.isTierTransition).toList();
    final n = pool.length;
    if (n == 0) return;
    if (n == 1) {
      current.value = pool.first;
      return;
    }
    final cur = current.value;
    final curIdx = cur == null ? -1 : pool.indexOf(cur);
    if (curIdx < 0) {
      current.value = pool[_rng.nextInt(n)];
      return;
    }
    // Tire dans [0, n-1] en excluant curIdx. Astuce : tirer dans
    // [0, n-2] et décaler de 1 si on tombe sur curIdx ou plus haut.
    final draw = _rng.nextInt(n - 1);
    final pick = draw >= curIdx ? draw + 1 : draw;
    current.value = pool[pick];
  }

  /// Reset complet (sortie de session, retour au placeholder).
  void clear() {
    current.value = null;
    _resetTiers();
  }

  @visibleForTesting
  void debugResetForTest() {
    _bundle = BackgroundsBundle.empty;
    _tieredCoaches = const {};
    current.value = null;
    _resetTiers();
  }
}
