import 'package:shared_preferences/shared_preferences.dart';

import '../models/badge.dart';
import 'stats_service.dart';

/// Calcule l'état des badges à partir d'un [StatsSnapshot], et détecte
/// les nouveaux paliers débloqués depuis le dernier check (utilisé par
/// le SessionController pour annoncer le déblocage en TTS).
class BadgeService {
  static const String _kPrefix = 'badge.tier.';

  Future<List<BadgeState>> currentStates(StatsSnapshot snap) async {
    return [
      for (final def in BadgeDefinition.catalog)
        BadgeState(
          definition: def,
          tier: def.tierFor(_valueFor(def.family, snap)),
          value: _valueFor(def.family, snap),
        ),
    ];
  }

  /// Compare l'état actuel à l'état persisté la dernière fois. Met à jour
  /// la persistance et retourne la liste des nouveaux déblocages (un par
  /// passage de palier, possiblement plusieurs si on saute des paliers).
  Future<List<BadgeUnlock>> reconcileAndDetectUnlocks(
    StatsSnapshot snap,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final unlocks = <BadgeUnlock>[];
    for (final def in BadgeDefinition.catalog) {
      final value = _valueFor(def.family, snap);
      final newTier = def.tierFor(value);
      final key = _kPrefix + def.family.name;
      final stored = BadgeTier.values[(prefs.getInt(key) ?? 0)];
      if (newTier.index > stored.index) {
        // On annonce le palier le plus haut atteint, pas chaque palier
        // intermédiaire (évite « bronze, argent, or » à l'enchaîné).
        unlocks.add(BadgeUnlock(definition: def, tier: newTier));
        await prefs.setInt(key, newTier.index);
      }
    }
    return unlocks;
  }

  int _valueFor(BadgeFamily f, StatsSnapshot snap) => switch (f) {
        BadgeFamily.marathonien => snap.totalSeconds,
        BadgeFamily.throatQueen => snap.throatfucks,
        BadgeFamily.ironLungs => snap.maxHoldFullAtomic,
        BadgeFamily.toutTerrain => snap.distinctModesUsed,
        BadgeFamily.sansBroncher => snap.sessionsNoFailStreak,
        BadgeFamily.reguliere => snap.dailyStreak,
        BadgeFamily.jamaisRassasiee => snap.encoresAsked,
        BadgeFamily.videCouilles => snap.quickiesCompleted,
      };

  /// Efface l'état persisté des paliers — utilisé par le reset profil.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final def in BadgeDefinition.catalog) {
      await prefs.remove(_kPrefix + def.family.name);
    }
  }
}

class BadgeUnlock {
  final BadgeDefinition definition;
  final BadgeTier tier;

  const BadgeUnlock({required this.definition, required this.tier});

  /// Phrase TTS d'annonce, neutre et factuelle (la coach garde son ton
  /// salace pour le reste). Format intentionnellement court, lu pendant
  /// l'animation de fin de séance.
  String announcement() {
    return 'Badge débloqué : ${definition.displayName}, palier ${tier.label}.';
  }
}
