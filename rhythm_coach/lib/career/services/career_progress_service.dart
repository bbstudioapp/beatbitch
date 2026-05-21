import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_length_choice.dart';

/// Persiste l'état de progression du mode Carrière entre lancements de l'app.
///
/// Phase 19.12 : le concept de `maxLevel` est retiré du flux. La
/// progression de la joueuse est désormais portée par :
/// - les sessions complétées (`getCompletedSessions`)
/// - le temps cumulé (`StatsService.getTotalSeconds`)
/// - le profil de capacités (`CapabilityProfile`)
/// - les milestones acquittées (`MilestoneService`)
///
/// `recordSessionCompleted()` ne fait plus que tracker la session ;
/// l'avancement de tier coach se fait via
/// `CoachService.syncFromTotalSeconds`, la difficulté via
/// `CareerDifficultyResolver.resolveForCareer`, etc.
class CareerProgressService {
  static const String _kCompleted = 'career.completed_sessions';
  static const String _kIncludeHand = 'career.include_hand';
  static const String _kLastLengthChoice = 'career.last_length_choice';

  /// Clés legacy conservées pour la lecture (rétrocompat des exports
  /// diagnostic) — plus aucune écriture côté code Phase 19.12+.
  static const String _kLegacyMaxLevel = 'career.max_level';
  static const String _kLegacyLastLevel = 'career.last_level';

  CareerProgressService();

  Future<int> getCompletedSessions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kCompleted) ?? 0;
  }

  /// Incrémente le compteur de sessions complétées (Phase 19.12 : plus
  /// de notion de level-up, juste un tracking d'investissement).
  Future<void> recordSessionCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = (prefs.getInt(_kCompleted) ?? 0) + 1;
    await prefs.setInt(_kCompleted, completed);
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

  /// Dernier palier de durée choisi via le picker UI (Phase 19.4). Stocké
  /// par le nom de l'enum pour rester lisible et résilient à un
  /// renommage. Défaut = `courte` (palier le plus représentatif pour une
  /// première séance).
  Future<SessionLengthChoice> getLastLengthChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastLengthChoice);
    if (raw == null) return SessionLengthChoice.courte;
    for (final c in SessionLengthChoice.values) {
      if (c.name == raw) return c;
    }
    return SessionLengthChoice.courte;
  }

  Future<void> setLastLengthChoice(SessionLengthChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastLengthChoice, choice.name);
  }

  /// Efface la progression carrière (compteurs + dernier choix de durée).
  /// On préserve le toggle `includeHand` qui est une préférence d'UI,
  /// pas un compteur. Purge aussi les clés legacy `max_level` et
  /// `last_level` (Phase 19.12 — plus consultées par le code).
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCompleted);
    await prefs.remove(_kLastLengthChoice);
    await prefs.remove(_kLegacyMaxLevel);
    await prefs.remove(_kLegacyLastLevel);
  }
}
