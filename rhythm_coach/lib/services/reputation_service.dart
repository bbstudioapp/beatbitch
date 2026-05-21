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
      tier: ReputationTier.tierFor(score),
    );
  }
}

class ReputationSnapshot {
  final int score;
  final int maxLevel;
  final StatsSnapshot stats;
  final int respecCount;

  /// Palier honorifique dérivé du [score] (Phase 19.11). Sert à
  /// afficher un titre nommé en plus du score numérique.
  final ReputationTier tier;

  const ReputationSnapshot({
    required this.score,
    required this.maxLevel,
    required this.stats,
    required this.respecCount,
    required this.tier,
  });
}

/// Palier honorifique de ré-pute-ation (Phase 19.11). Pas de gating
/// fonctionnel — c'est purement un titre d'identité affiché côté UI.
/// Calibration : voir [ReputationTier.tierFor]. Les seuils sont
/// volontairement larges pour que la progression soit ressentie sur
/// plusieurs sessions (et pas à chaque encore demandée).
enum ReputationTier {
  /// 0 → 149 — la nouvelle, encore en exploration.
  bonneEleve(minScore: 0),

  /// 150 → 399 — quelques sessions, sait ce qu'elle aime.
  petiteSuceuse(minScore: 150),

  /// 400 → 899 — pratique régulière, technique en place.
  suceuseConfirmee(minScore: 400),

  /// 900 → 1799 — installée, reconnue par ses coachs.
  puteReconnue(minScore: 900),

  /// 1800 → 3499 — palier sérieux, score à 3 chiffres bien tassé.
  puteConsacree(minScore: 1800),

  /// 3500 → 5999 — ancienne du game, expérience visible.
  reineDesSuceuses(minScore: 3500),

  /// 6000+ — sommet honorifique, score à 4 chiffres.
  reineDesPutes(minScore: 6000);

  const ReputationTier({required this.minScore});

  /// Score minimum requis pour atteindre ce palier (borne basse incluse).
  final int minScore;

  /// Renvoie le palier dérivé d'un score brut. Le mapping est monotone :
  /// score plus haut ⇔ palier ≥ (jamais de régression à score égal).
  static ReputationTier tierFor(int score) {
    var best = ReputationTier.bonneEleve;
    for (final t in ReputationTier.values) {
      if (score >= t.minScore) best = t;
    }
    return best;
  }
}
