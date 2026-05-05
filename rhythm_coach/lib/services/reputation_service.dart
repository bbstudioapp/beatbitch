import '../career/services/career_progress_service.dart';
import '../career/services/specialization_service.dart';
import 'stats_service.dart';

/// Score numérique unique qui agrège niveau global + stats clés. Pensé
/// pour servir de teaser de progression (affiché dans l'écran Profil)
/// et de base au futur classement online anonyme. Volontairement simple
/// — à ajuster une fois qu'on aura quelques utilisateurs et un sens du
/// barème pertinent.
///
/// Formule (validée 2026-05-03) :
///
/// ```
/// rep = niveau_max × 100
///     + sessions_completées × 5
///     + sessions_no_fail_streak × 3
///     + max_hold_full_atomic × 2
///     + total_throatfucks × 0.5
///     + encores_demandés × 10
///     − respecs × 50
/// ```
class ReputationService {
  final StatsService _stats;
  final CareerProgressService _career;
  final SpecializationService _spec;

  ReputationService({
    StatsService? stats,
    CareerProgressService? career,
    SpecializationService? spec,
  })  : _stats = stats ?? StatsService(),
        _career = career ?? CareerProgressService(),
        _spec = spec ?? SpecializationService();

  Future<ReputationSnapshot> snapshot() async {
    final results = await Future.wait([
      _stats.snapshot(),
      _career.getMaxLevel(),
      _spec.respecCount(),
    ]);
    final s = results[0] as StatsSnapshot;
    final maxLevel = results[1] as int;
    final respecs = results[2] as int;

    final score = maxLevel * 100 +
        s.sessionsCompleted * 5 +
        s.sessionsNoFailStreak * 3 +
        s.maxHoldFullAtomic * 2 +
        (s.throatfucks * 0.5).round() +
        s.encoresAsked * 10 -
        respecs * 50;

    return ReputationSnapshot(
      score: score,
      maxLevel: maxLevel,
      stats: s,
      respecCount: respecs,
    );
  }
}

class ReputationSnapshot {
  final int score;
  final int maxLevel;
  final StatsSnapshot stats;
  final int respecCount;

  const ReputationSnapshot({
    required this.score,
    required this.maxLevel,
    required this.stats,
    required this.respecCount,
  });
}
