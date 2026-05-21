/// Palier de durée d'une séance carrière. Sélecteur UX qui pilote la
/// durée + le nombre cible d'events insérés (body milestones + défis
/// intercalés). Cf. roadmap Phase 19.
///
/// | Palier  | Durée   | Body max | Défis cible | Total events |
/// |---------|---------|----------|-------------|--------------|
/// | bachee  | ~6 min  | 0        | 1           | 1            |
/// | courte  | ~12 min | 1        | 1           | 2            |
/// | moyenne | ~25 min | 2        | 1           | 3            |
/// | longue  | ~45 min | 2        | 2           | 4            |
///
/// Le total est un cible : si le catalogue de milestones est épuisé ou
/// que les défis sont désactivés, le compte effectif descend.
///
/// La bâclée garde son nom et reste portée par le flag `quickie` pour
/// l'intensityFloor (0.65) ; la durée 6 min est l'alignement de ce
/// palier sur le mécanisme existant.
enum SessionLengthChoice {
  bachee(durationSeconds: 360, maxBodyMilestones: 0, targetChallenges: 1),
  courte(durationSeconds: 720, maxBodyMilestones: 1, targetChallenges: 1),
  moyenne(durationSeconds: 1500, maxBodyMilestones: 2, targetChallenges: 1),
  longue(durationSeconds: 2700, maxBodyMilestones: 2, targetChallenges: 2);

  const SessionLengthChoice({
    required this.durationSeconds,
    required this.maxBodyMilestones,
    required this.targetChallenges,
  });

  /// Durée nominale du palier en secondes. Passée telle quelle au
  /// générateur — peut être surchargée explicitement via le paramètre
  /// `durationSeconds` (priorité plus haute, cas debug / surprise).
  final int durationSeconds;

  /// Nombre maximum de body milestones à insérer pour ce palier (la
  /// disponibilité réelle dépend du catalogue / pending). Phase 19.5 :
  /// 0 pour bâclée (express, pas de pédagogie), 1 pour courte, 2 pour
  /// moyenne/longue.
  final int maxBodyMilestones;

  /// Nombre cible de défis intra-séance à intercaler pour ce palier
  /// (sous réserve que le toggle soit activé et qu'il reste des axes
  /// candidats). Total visé d'« events » par séance : `maxBodyMilestones
  /// + targetChallenges` = 1/2/3/4 selon palier.
  final int targetChallenges;
}
