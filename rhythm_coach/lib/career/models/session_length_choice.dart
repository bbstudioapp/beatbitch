/// Palier de durée d'une séance carrière. Sélecteur UX qui pilote la
/// durée + le nombre total d'events à insérer (body milestones + défis
/// intercalés, compensables : si une milestone manque, un défi prend le
/// relais). Cf. roadmap Phase 19.
///
/// | Palier  | Durée   | Body max | Total events |
/// |---------|---------|----------|--------------|
/// | bachee  | ~6 min  | 0        | 1            |
/// | courte  | ~12 min | 1        | 2            |
/// | moyenne | ~25 min | 2        | 3            |
/// | longue  | ~45 min | 2        | 4            |
///
/// Le nombre effectif de défis est calculé après avoir su combien de
/// body milestones sont effectivement insérables (catalogue pending) :
/// `nbChallenges = totalEvents - bodyInserted`. Quand le catalogue est
/// épuisé, les défis comblent (jusqu'à 4 défis en longue).
///
/// La bâclée garde son nom et reste portée par le flag `quickie` pour
/// l'intensityFloor (0.65) ; la durée 6 min est l'alignement de ce
/// palier sur le mécanisme existant.
enum SessionLengthChoice {
  bachee(durationSeconds: 360, maxBodyMilestones: 0, totalEvents: 1),
  courte(durationSeconds: 720, maxBodyMilestones: 1, totalEvents: 2),
  moyenne(durationSeconds: 1500, maxBodyMilestones: 2, totalEvents: 3),
  longue(durationSeconds: 2700, maxBodyMilestones: 2, totalEvents: 4);

  const SessionLengthChoice({
    required this.durationSeconds,
    required this.maxBodyMilestones,
    required this.totalEvents,
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

  /// Nombre total cible d'« events » par séance (1/2/3/4 selon palier).
  /// Le nombre de défis effectivement insérés = `totalEvents - body
  /// insérés` (compensation : un défi remplace une milestone absente).
  final int totalEvents;

  /// Calcule le nombre de défis à insérer en fonction du nombre de body
  /// milestones effectivement disponibles. Plancher à 0.
  int targetChallengesFor(int insertedBodies) {
    final n = totalEvents - insertedBodies;
    return n < 0 ? 0 : n;
  }
}
