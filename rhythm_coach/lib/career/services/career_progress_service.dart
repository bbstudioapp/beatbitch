import 'package:shared_preferences/shared_preferences.dart';

/// Persiste l'état de progression du mode Carrière entre lancements de l'app.
///
/// La progression de niveau est **gatée par les milestones** depuis la passe
/// « level-up gaté » : `recordSessionCompleted(levelUp:)` reste l'API d'écriture,
/// mais le caller doit calculer `levelUp` via [canLevelUp] qui exige soit
/// l'acquittement d'une milestone candidate au niveau courant, soit l'absence
/// de candidate (catalogue épuisé pour ce niveau — on laisse passer pour ne
/// pas piéger la joueuse). Les milestones elles-mêmes sont sélectionnées
/// par `MilestoneService.pendingFor` (humiliation + obédiance + minLevel +
/// requiresCapability).
class CareerProgressService {
  static const String _kMaxLevel = 'career.max_level';
  static const String _kLastLevel = 'career.last_level';
  static const String _kCompleted = 'career.completed_sessions';
  static const String _kIncludeHand = 'career.include_hand';

  CareerProgressService();

  Future<int> getMaxLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kMaxLevel) ?? 1;
  }

  Future<int> getLastChosenLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastLevel);
    if (last != null) return last;
    return prefs.getInt(_kMaxLevel) ?? 1;
  }

  Future<int> getCompletedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCompleted) ?? 0;
  }

  Future<void> setLastChosenLevel(int level) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastLevel, level);
  }

  /// Décide si la session qui vient de finir autorise un level-up.
  ///
  /// Règle (« level-up gaté par milestone ») :
  /// - session clean (pas de fail) **et** non bâclée — sinon faux d'office.
  /// - et soit une milestone candidate au niveau courant a été acquittée
  ///   cette séance, soit aucune n'était plus candidate (catalogue épuisé
  ///   au niveau courant — on laisse passer pour ne pas piéger la joueuse).
  ///
  /// Le caller reste responsable du check « niveau de la session ≥ max
  /// actuel » et de la cohérence coach (`coachAdvancesTier`) — ils
  /// n'appartiennent pas à la mécanique milestone↔niveau.
  bool canLevelUp({
    required bool cleanSession,
    required bool isQuickie,
    required bool milestoneAcquittedThisSession,
    required bool hasPendingAtCurrentLevel,
  }) {
    if (!cleanSession) return false;
    if (isQuickie) return false;
    return milestoneAcquittedThisSession || !hasPendingAtCurrentLevel;
  }

  /// Incrémente le compteur de sessions complétées. Bump le niveau max
  /// uniquement si [levelUp] est vrai.
  ///
  /// La règle de level-up est décidée par l'appelant via [canLevelUp] :
  /// session **standard** (pas bâclée), au niveau max, **sans fail**, et
  /// soit une milestone candidate au niveau courant a été acquittée, soit
  /// le catalogue est épuisé à ce niveau. Toute autre complétion
  /// (en dessous du max, bâclée, avec fail, ou milestone candidate ratée)
  /// est comptabilisée mais ne débloque pas de palier.
  Future<void> recordSessionCompleted({required bool levelUp}) async {
    final prefs = await SharedPreferences.getInstance();
    final completed = (prefs.getInt(_kCompleted) ?? 0) + 1;
    await prefs.setInt(_kCompleted, completed);
    if (levelUp) {
      final currentMax = prefs.getInt(_kMaxLevel) ?? 1;
      final newMax = currentMax + 1;
      await prefs.setInt(_kMaxLevel, newMax);
      await prefs.setInt(_kLastLevel, newMax);
    }
  }

  /// Toggle « inclure la stimulation main » dans le générateur.
  /// Désactivé → le générateur exclut aussi les coups de queue (biffle),
  /// puisque biffle implique de tenir avec la main.
  Future<bool> getIncludeHand() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIncludeHand) ?? true;
  }

  Future<void> setIncludeHand(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIncludeHand, value);
  }

  /// Bump le niveau max sans toucher au compteur de sessions complétées.
  /// Utilisé par l'action « Supplier » pour débloquer un palier supérieur
  /// en cours de séance. Retourne le nouveau max.
  Future<int> bumpMaxLevel({int amount = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final newMax = (prefs.getInt(_kMaxLevel) ?? 1) + amount;
    await prefs.setInt(_kMaxLevel, newMax);
    return newMax;
  }

  /// Décrémente le niveau max (jamais sous 1). Utilisé comme pénalité
  /// de respec dans le système de spécialisation. Retourne le nouveau max.
  Future<int> decrementMaxLevel({int amount = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kMaxLevel) ?? 1;
    final newMax = (current - amount).clamp(1, current);
    await prefs.setInt(_kMaxLevel, newMax);
    // Si le dernier choisi dépassait le nouveau max, on le rabat.
    final last = prefs.getInt(_kLastLevel);
    if (last != null && last > newMax) {
      await prefs.setInt(_kLastLevel, newMax);
    }
    return newMax;
  }

  /// Efface la progression carrière (niveau max, dernier choisi, sessions
  /// complétées). On préserve le toggle `includeHand` qui est une
  /// préférence d'UI, pas un compteur.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMaxLevel);
    await prefs.remove(_kLastLevel);
    await prefs.remove(_kCompleted);
  }
}
