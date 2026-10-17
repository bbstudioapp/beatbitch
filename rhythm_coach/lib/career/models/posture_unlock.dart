import '../../models/posture.dart';
import 'unlock_key.dart';

/// Pont entre le modèle [Posture] (`lib/models/`, sans dépendance carrière) et
/// l'enum carrière [UnlockKey]. Vit côté `career/` pour ne pas faire dépendre
/// `models/` de `career/` (cf. `Posture.unlockKey`, qui renvoie une `String`).
///
/// Le `switch` explicite référence chaque `UnlockKey.posture*` littéralement —
/// requis par l'invariant `test/milestone_unlock_invariants_test.dart` (scan
/// textuel `UnlockKey.<name>` dans `/lib`) une fois les milestones
/// `intro_posture_*` ajoutées au catalogue.
extension PostureUnlock on Posture {
  /// Clé d'unlock carrière de cette posture, ou `null` pour [Posture.free]
  /// (toujours disponible, sans milestone).
  UnlockKey? get unlockKeyEnum => switch (this) {
        Posture.free => null,
        Posture.sitting => UnlockKey.postureSitting,
        Posture.standing => UnlockKey.postureStanding,
        Posture.kneeling => UnlockKey.postureKneeling,
        Posture.allFours => UnlockKey.postureAllFours,
        Posture.onBack => UnlockKey.postureOnBack,
      };
}

/// Postures que l'utilisatrice peut se voir imposer, compte tenu des unlocks
/// acquis. [Posture.free] est toujours incluse (jamais débloquée). L'ordre
/// suit `Posture.values` (déterministe). Sert au tirage de la posture d'intro
/// et des postures de break.
List<Posture> availablePostures(Set<UnlockKey> unlockedKeys) => [
      Posture.free,
      for (final p in Posture.values)
        if (p != Posture.free && unlockedKeys.contains(p.unlockKeyEnum)) p,
    ];

/// Posture enseignée par une milestone `intro_posture_*`, `null` pour toute
/// autre milestone. Suit la convention d'id de `assets/career/milestones.json`.
Posture? postureTaughtByMilestone(String? milestoneId) {
  const prefix = 'intro_posture_';
  if (milestoneId == null || !milestoneId.startsWith(prefix)) return null;
  final pose = Posture.fromString(milestoneId.substring(prefix.length));
  return pose == Posture.free ? null : pose;
}
