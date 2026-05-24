import 'package:shared_preferences/shared_preferences.dart';

import '../models/specialization.dart';

/// Persistance des points de spécialisation + règles de gain et respec.
///
/// **Gain** (retour playtest 0.6) : basé sur le temps cumulé.
/// 1ᵉʳ point à 5 min, puis delta +5 min entre chaque point suivant
/// (5, 15, 30, 50, 1 h 15 …). Cf. [totalPointsForSeconds] pour la
/// formule et la table de seuils.
///
/// **Respec** : remet tous les compteurs à 0, pose un cooldown
/// empêchant un nouveau respec avant 3 jours. Plus de pénalité de
/// niveau global (concept retiré en Phase 19.12).
class SpecializationService {
  static const String _kPointsPrefix = 'specialization.points.';
  static const String _kLastRespec = 'specialization.last_respec_ms';
  static const String _kRespecCount = 'specialization.respec_count';

  /// File d'attente FIFO de branches à « mettre en vitrine » dans les
  /// séances suivantes. Chaque appel à [invest] empile la branche
  /// concernée ; la prochaine séance qui peut honorer la tête de file
  /// (= une milestone candidate touche cette branche) la consomme. But :
  /// rendre immédiatement visible l'effet d'un point dépensé, sinon les
  /// 5 pts spé d'une joueuse expérimentée passent inaperçus face à
  /// l'aging des autres branches. Stockée en CSV de `branch.name`.
  static const String _kPendingShowcase = 'specialization.pending_showcase';

  /// Cooldown en heures entre deux respecs.
  static const int respecCooldownHours = 72;

  /// Nombre total de points de spé acquis pour un investissement temps
  /// cumulé donné (retour playtest 0.6 — l'attribution se base désormais
  /// sur le temps passé, pas le nombre de sessions, parce que la durée
  /// du contenu joué reflète mieux l'investissement réel que le compteur
  /// de sessions, surtout avec les paliers Bâclée/Courte/Moyenne/Longue
  /// très contrastés).
  ///
  /// Cadence : 1ᵉʳ point à 5 min, puis le delta entre 2 points augmente
  /// de 5 min à chaque fois (5, +10, +15, +20, +25 …). Seuil cumulé pour
  /// le n-ième point : `2.5 × n × (n+1)` minutes = `n × (n+1) × 150`
  /// secondes.
  ///
  /// | n | seuil    |
  /// |---|----------|
  /// | 1 |  5 min   |
  /// | 2 | 15 min   |
  /// | 3 | 30 min   |
  /// | 4 | 50 min   |
  /// | 5 | 1 h 15   |
  /// | 6 | 1 h 45   |
  /// | 7 | 2 h 20   |
  /// | 8 | 3 h      |
  static int totalPointsForSeconds(int totalSeconds) {
    if (totalSeconds < 300) return 0;
    var n = 0;
    while (totalSeconds >= (n + 1) * (n + 2) * 150) {
      n++;
    }
    return n;
  }

  /// Clé legacy : points investis dans l'ancienne branche `resilience`
  /// (retirée). On la nettoie au chargement — comme elle n'est plus
  /// sommée dans `totalSpent`, les points qu'elle portait redeviennent
  /// automatiquement disponibles (la bannière « points de spé à
  /// réattribuer » s'affiche d'elle-même).
  static const String _kLegacyResiliencePoints = '${_kPointsPrefix}resilience';

  Future<SpecializationAllocation> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_kLegacyResiliencePoints)) {
      await prefs.remove(_kLegacyResiliencePoints);
    }
    final points = <SpecializationBranch, int>{};
    for (final b in SpecializationBranch.values) {
      points[b] = prefs.getInt('$_kPointsPrefix${b.name}') ?? 0;
    }
    return SpecializationAllocation(
      points: points,
      lastRespecMs: prefs.getInt(_kLastRespec),
    );
  }

  /// Investit un point dans [branch]. Vérifie qu'il reste des points
  /// disponibles compte tenu du niveau global. Retourne true si l'invest
  /// a été fait, false sinon. Empile aussi [branch] dans la file
  /// [pendingShowcase] : la prochaine séance qui peut honorer ce point
  /// (= au moins une milestone candidate touche cette branche) sera
  /// biaisée pour la mettre en vitrine. Voir [peekShowcase] /
  /// [consumeShowcase].
  Future<bool> invest(SpecializationBranch branch, int totalSeconds) async {
    final alloc = await load();
    final cap = totalPointsForSeconds(totalSeconds);
    if (alloc.totalSpent >= cap) return false;
    final prefs = await SharedPreferences.getInstance();
    final newValue = alloc.pointsIn(branch) + 1;
    await prefs.setInt('$_kPointsPrefix${branch.name}', newValue);
    final queue = await pendingShowcase();
    queue.add(branch);
    await _writeShowcase(prefs, queue);
    return true;
  }

  /// File d'attente FIFO des branches à mettre en vitrine (lecture).
  /// Vide quand aucun point n'attend d'être honoré.
  Future<List<SpecializationBranch>> pendingShowcase() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingShowcase) ?? '';
    if (raw.isEmpty) return <SpecializationBranch>[];
    return raw
        .split(',')
        .map(_branchFromName)
        .whereType<SpecializationBranch>()
        .toList();
  }

  /// Tête de file ou `null` si la file est vide. Lecture seule —
  /// utiliser [consumeShowcase] pour la retirer après l'avoir honorée.
  Future<SpecializationBranch?> peekShowcase() async {
    final queue = await pendingShowcase();
    return queue.isEmpty ? null : queue.first;
  }

  /// Retire la première occurrence de [branch] dans la file. Appelé
  /// par le call site (career_screen) une fois qu'il a constaté qu'une
  /// milestone effectivement insérée touche cette branche. Si [branch]
  /// n'est pas dans la file, no-op (la dette a déjà été consommée ou
  /// la séance n'a pas pu l'honorer).
  Future<void> consumeShowcase(SpecializationBranch branch) async {
    final queue = await pendingShowcase();
    final idx = queue.indexOf(branch);
    if (idx < 0) return;
    queue.removeAt(idx);
    final prefs = await SharedPreferences.getInstance();
    await _writeShowcase(prefs, queue);
  }

  static SpecializationBranch? _branchFromName(String name) {
    for (final b in SpecializationBranch.values) {
      if (b.name == name) return b;
    }
    return null; // tolérance : silencieux si une branche disparaît
  }

  static Future<void> _writeShowcase(
    SharedPreferences prefs,
    List<SpecializationBranch> queue,
  ) async {
    if (queue.isEmpty) {
      await prefs.remove(_kPendingShowcase);
    } else {
      await prefs.setString(
        _kPendingShowcase,
        queue.map((b) => b.name).join(','),
      );
    }
  }

  /// Combien de points disponibles à dépenser pour un temps cumulé
  /// donné (retour playtest 0.6 — cadence basée sur le temps, cf.
  /// [totalPointsForSeconds]).
  Future<int> availablePoints(int totalSeconds) async {
    final alloc = await load();
    final cap = totalPointsForSeconds(totalSeconds);
    return (cap - alloc.totalSpent).clamp(0, cap);
  }

  /// Vrai si le respec est autorisé (cooldown écoulé).
  Future<bool> canRespec() async {
    final alloc = await load();
    final last = alloc.lastRespecMs;
    if (last == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - last;
    return diff >= respecCooldownHours * 3600 * 1000;
  }

  /// Heures restantes avant que respec soit à nouveau possible. Retourne
  /// 0 si déjà autorisé.
  Future<int> respecCooldownRemainingHours() async {
    final alloc = await load();
    final last = alloc.lastRespecMs;
    if (last == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = respecCooldownHours * 3600 * 1000 - (now - last);
    if (remainingMs <= 0) return 0;
    return (remainingMs / (3600 * 1000)).ceil();
  }

  /// Effectue un respec : remet tous les points à zéro, fixe l'horodatage,
  /// déduit la pénalité globale (gérée côté CareerProgressService par
  /// l'appelant — ce service ne connaît pas le compteur de niveau global).
  /// Retourne le nouvel `SpecializationAllocation` après reset.
  Future<SpecializationAllocation> respec() async {
    final prefs = await SharedPreferences.getInstance();
    for (final b in SpecializationBranch.values) {
      await prefs.setInt('$_kPointsPrefix${b.name}', 0);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_kLastRespec, now);
    await prefs.setInt(
      _kRespecCount,
      (prefs.getInt(_kRespecCount) ?? 0) + 1,
    );
    // Respec rebat les cartes — la file showcase est obsolète.
    await prefs.remove(_kPendingShowcase);
    return SpecializationAllocation(
      points: {for (final b in SpecializationBranch.values) b: 0},
      lastRespecMs: now,
    );
  }

  /// Nombre cumulé de respecs effectués. Sert à pénaliser le score de
  /// réputation.
  Future<int> respecCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRespecCount) ?? 0;
  }

  /// Efface tous les points investis, le compteur de respec et le
  /// timestamp du dernier respec. Utilisé par le reset profil.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final b in SpecializationBranch.values) {
      await prefs.remove('$_kPointsPrefix${b.name}');
    }
    await prefs.remove(_kLastRespec);
    await prefs.remove(_kRespecCount);
    await prefs.remove(_kPendingShowcase);
  }
}
