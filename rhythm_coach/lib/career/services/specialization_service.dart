import 'package:shared_preferences/shared_preferences.dart';

import '../models/specialization.dart';

/// Persistance des points de spécialisation + règles de gain et respec.
///
/// **Gain** : 1 point tous les 2 niveaux (niv 2 → 1 pt, niv 4 → 2 pts,
/// etc.). Aux niveaux impairs, pas de nouveau point. Niveau 1 = 0 point.
///
/// **Respec** : remet tous les compteurs à 0, applique une pénalité
/// (-1 niveau global), pose un cooldown empêchant un nouveau respec
/// avant 3 jours.
class SpecializationService {
  static const String _kPointsPrefix = 'specialization.points.';
  static const String _kLastRespec = 'specialization.last_respec_ms';
  static const String _kRespecCount = 'specialization.respec_count';

  /// Cooldown en heures entre deux respecs.
  static const int respecCooldownHours = 72;

  /// Nombre total de points de spé acquis à un niveau global donné.
  static int totalPointsForLevel(int level) {
    if (level < 2) return 0;
    return level ~/ 2;
  }

  Future<SpecializationAllocation> load() async {
    final prefs = await SharedPreferences.getInstance();
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
  /// a été fait, false sinon.
  Future<bool> invest(SpecializationBranch branch, int globalLevel) async {
    final alloc = await load();
    final cap = totalPointsForLevel(globalLevel);
    if (alloc.totalSpent >= cap) return false;
    final prefs = await SharedPreferences.getInstance();
    final newValue = alloc.pointsIn(branch) + 1;
    await prefs.setInt('$_kPointsPrefix${branch.name}', newValue);
    return true;
  }

  /// Combien de points disponibles à dépenser au niveau global donné.
  Future<int> availablePoints(int globalLevel) async {
    final alloc = await load();
    final cap = totalPointsForLevel(globalLevel);
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
  }
}
