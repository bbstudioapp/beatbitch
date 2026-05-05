/// Familles de badges. Chacune a sa propre métrique source dans
/// [StatsSnapshot] et ses propres seuils par palier.
enum BadgeFamily {
  marathonien,
  throatQueen,
  ironLungs,
  toutTerrain,
  sansBroncher,
  reguliere,
  jamaisRassasiee,
  videCouilles,
  // Badges sur la dramaturgie de fin de séance (final + post-final).
  // Comptés dans `SessionController._finish` quand la session se termine
  // sans fail, en lisant le mode du step final et du step post-final.
  /// Final mode `hold` (toutes profondeurs) — la sauce reste dans la bouche.
  bouchePleine,
  /// Final mode `biffle` — la sauce gicle sur le visage.
  repeinte,
  /// Final mode `lick` — langue dehors, la coach jouit dessus.
  gobeuse,
  /// Post-final mode `lick` — nettoyer après, lécher le sperme qui coule.
  nettoyeuse,
  /// Post-final mode `beg` — supplique imposée après l'orgasme.
  suppliante,
}

/// Paliers d'un badge. Order = niveau croissant. `none` = pas encore
/// débloqué (en-dessous du seuil bronze).
enum BadgeTier {
  none,
  bronze,
  silver,
  gold,
  platinium;

  String get label => switch (this) {
        BadgeTier.none => '—',
        BadgeTier.bronze => 'Bronze',
        BadgeTier.silver => 'Argent',
        BadgeTier.gold => 'Or',
        BadgeTier.platinium => 'Platine',
      };
}

/// Définition d'une famille de badge : nom affichable + grille des seuils
/// par palier. Le tier est dérivé d'une valeur courante via [tierFor].
class BadgeDefinition {
  final BadgeFamily family;
  final String displayName;
  final String unitLabel;
  final List<int> thresholds; // [bronze, silver, gold, platinium]

  const BadgeDefinition({
    required this.family,
    required this.displayName,
    required this.unitLabel,
    required this.thresholds,
  });

  BadgeTier tierFor(int value) {
    if (value >= thresholds[3]) return BadgeTier.platinium;
    if (value >= thresholds[2]) return BadgeTier.gold;
    if (value >= thresholds[1]) return BadgeTier.silver;
    if (value >= thresholds[0]) return BadgeTier.bronze;
    return BadgeTier.none;
  }

  /// Seuil du prochain palier au-delà du tier courant, ou null si déjà
  /// platinium. Utile pour afficher la progression vers le palier suivant.
  int? nextThresholdAfter(BadgeTier tier) {
    final idx = switch (tier) {
      BadgeTier.none => 0,
      BadgeTier.bronze => 1,
      BadgeTier.silver => 2,
      BadgeTier.gold => 3,
      BadgeTier.platinium => null,
    };
    return idx == null ? null : thresholds[idx];
  }

  /// Catalogue figé des badges. Seuils choisis pour donner une montée
  /// régulière sans frustrer une utilisatrice débutante (bronze accessible
  /// après 1-2 séances, platinium = objectif long terme).
  static const List<BadgeDefinition> catalog = [
    BadgeDefinition(
      family: BadgeFamily.marathonien,
      displayName: 'Marathonienne',
      unitLabel: 'minutes cumulées',
      // 30 min, 2h, 8h, 24h
      thresholds: [1800, 7200, 28800, 86400],
    ),
    BadgeDefinition(
      family: BadgeFamily.throatQueen,
      displayName: 'Throat Queen',
      unitLabel: 'throatfucks cumulés',
      thresholds: [200, 1000, 5000, 20000],
    ),
    BadgeDefinition(
      family: BadgeFamily.ironLungs,
      displayName: 'Iron Lungs',
      unitLabel: 'secondes du plus long hold full',
      thresholds: [10, 20, 35, 60],
    ),
    BadgeDefinition(
      family: BadgeFamily.toutTerrain,
      displayName: 'Tout-terrain',
      unitLabel: 'modes différents utilisés',
      // 8 modes au total : on récompense la progression de découverte
      thresholds: [3, 5, 7, 8],
    ),
    BadgeDefinition(
      family: BadgeFamily.sansBroncher,
      displayName: 'Sans broncher',
      unitLabel: 'séances complètes consécutives sans fail',
      thresholds: [1, 5, 15, 50],
    ),
    BadgeDefinition(
      family: BadgeFamily.reguliere,
      displayName: 'Régulière',
      unitLabel: 'jours consécutifs avec séance',
      thresholds: [3, 7, 30, 100],
    ),
    BadgeDefinition(
      family: BadgeFamily.jamaisRassasiee,
      displayName: 'Jamais rassasiée',
      unitLabel: 'fois où tu as redemandé "encore"',
      thresholds: [1, 5, 20, 50],
    ),
    BadgeDefinition(
      family: BadgeFamily.videCouilles,
      displayName: 'Vide-Couilles',
      unitLabel: 'sessions bâclées terminées',
      thresholds: [3, 10, 30, 100],
    ),
    BadgeDefinition(
      family: BadgeFamily.bouchePleine,
      displayName: 'Bouche pleine',
      unitLabel: 'finals dans la bouche',
      thresholds: [3, 15, 50, 150],
    ),
    BadgeDefinition(
      family: BadgeFamily.repeinte,
      displayName: 'Repeinte',
      unitLabel: 'finals sur le visage',
      thresholds: [3, 15, 50, 150],
    ),
    BadgeDefinition(
      family: BadgeFamily.gobeuse,
      displayName: 'Gobeuse',
      unitLabel: 'finals sur la langue',
      thresholds: [3, 15, 50, 150],
    ),
    BadgeDefinition(
      family: BadgeFamily.nettoyeuse,
      displayName: 'Nettoyeuse',
      unitLabel: 'post-finals à lécher',
      thresholds: [3, 15, 50, 150],
    ),
    BadgeDefinition(
      family: BadgeFamily.suppliante,
      displayName: 'Suppliante',
      unitLabel: 'suppliques post-orgasme',
      thresholds: [3, 15, 50, 150],
    ),
  ];

  static BadgeDefinition forFamily(BadgeFamily f) =>
      catalog.firstWhere((d) => d.family == f);
}

/// État courant d'un badge : sa définition + le palier atteint + la
/// valeur source. Utilisé par l'écran badges et l'annonce TTS.
class BadgeState {
  final BadgeDefinition definition;
  final BadgeTier tier;
  final int value;

  const BadgeState({
    required this.definition,
    required this.tier,
    required this.value,
  });

  int? get nextThreshold => definition.nextThresholdAfter(tier);
}
