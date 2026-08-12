import 'dart:math';

/// Palier de durée d'une séance carrière. Sélecteur UX qui pilote la
/// durée + le nombre total d'events à insérer (body milestones + défis
/// intercalés, compensables : si une milestone manque, un défi prend le
/// relais). Cf. roadmap Phase 19.
///
/// | Palier    | Durée      | Body max | Total events |
/// |-----------|------------|----------|--------------|
/// | bachee    | ~6 min     | 0        | 1            |
/// | courte    | ~12 min    | 1        | 2            |
/// | moyenne   | ~25 min    | 2        | 3            |
/// | longue    | ~45 min    | 2        | 4            |
/// | aleatoire | surprise   | —        | —            |
///
/// Le nombre effectif de défis est calculé après avoir su combien de
/// body milestones sont effectivement insérables (catalogue pending) :
/// `nbChallenges = totalEvents - bodyInserted`. Quand le catalogue est
/// épuisé, les défis comblent (jusqu'à 4 défis en longue).
///
/// La bâclée garde son nom et reste portée par le flag `quickie` pour
/// l'intensityFloor (0.65) ; la durée 6 min est l'alignement de ce
/// palier sur le mécanisme existant.
///
/// `aleatoire` est un **méta-choix** : ses champs `durationSeconds` /
/// `maxBodyMilestones` / `totalEvents` sont des sentinelles (0) qui ne
/// doivent **jamais** être lus tels quels. L'appelant doit résoudre la
/// valeur effective via [resolveAleatoireIfNeeded] juste avant d'utiliser
/// les champs en aval (la bâclée est volontairement exclue du tirage :
/// l'esprit du palier est « surprise sur la longueur », pas « surprise
/// sur le format intensité maximale »).
/// Part de la durée annoncée que les défis d'une séance peuvent au plus
/// **ajouter**, tous défis confondus. Le temps des défis s'ajoute au format
/// choisi (c'est ce que l'écran de sélection annonce), mais sans borne un
/// seul défi d'endurance dépassait le format entier : l'ampleur d'un défi
/// « durée » vaut `comfort × kChallengeOverloadFactor` et `comfort` ne fait
/// que monter avec la pratique — contrairement aux défis de vitesse (bornés
/// par le BPM max du moteur) et de profondeur (bornés par le nombre de
/// crans). Une Bâclée annoncée 6 min en durait 58 sur un profil très
/// entraîné.
///
/// `0.5` : assez haut pour qu'un défi reste un vrai effort sur les formats
/// longs (5 min 37 sur une Longue), assez bas pour qu'une séance ne double
/// jamais la durée qu'elle annonce.
const double kChallengesShareOfFormat = 0.5;

enum SessionLengthChoice {
  bachee(durationSeconds: 360, maxBodyMilestones: 0, totalEvents: 1),
  courte(durationSeconds: 720, maxBodyMilestones: 1, totalEvents: 2),
  moyenne(durationSeconds: 1500, maxBodyMilestones: 2, totalEvents: 3),
  longue(durationSeconds: 2700, maxBodyMilestones: 2, totalEvents: 4),
  aleatoire(durationSeconds: 0, maxBodyMilestones: 0, totalEvents: 0);

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

  /// Durée maximale d'un défi sur ce palier : la part [kChallengesShareOfFormat]
  /// de la durée annoncée, divisée par le nombre d'événements que le palier
  /// planifie. Comme `targetChallengesFor(...) <= totalEvents`, la somme des
  /// défis d'une séance ne peut jamais dépasser cette part — quel que soit
  /// l'état du catalogue de milestones.
  ///
  /// Sentinelle `aleatoire` : `totalEvents` y vaut 0, la lecture lève. Comme
  /// les autres champs du palier, à résoudre via [resolveAleatoireIfNeeded]
  /// avant usage.
  int get maxChallengeDurationSeconds =>
      (durationSeconds * kChallengesShareOfFormat).round() ~/ totalEvents;

  /// Calcule le nombre de défis à insérer en fonction du nombre de body
  /// milestones effectivement disponibles. Plancher à 0.
  int targetChallengesFor(int insertedBodies) {
    final n = totalEvents - insertedBodies;
    return n < 0 ? 0 : n;
  }

  /// Si [this] est [SessionLengthChoice.aleatoire], tire une longueur
  /// effective parmi [aleatoireDrawPool] et la retourne. Sinon retourne
  /// `this` inchangé. Idempotent sur les valeurs non-aléatoires.
  SessionLengthChoice resolveAleatoireIfNeeded(Random rng) {
    if (this != SessionLengthChoice.aleatoire) return this;
    return aleatoireDrawPool[rng.nextInt(aleatoireDrawPool.length)];
  }

  /// Pool de durées effectives quand `aleatoire` est tiré. Volontairement
  /// sans la bâclée — cf. doc de [SessionLengthChoice.aleatoire].
  static const aleatoireDrawPool = <SessionLengthChoice>[
    SessionLengthChoice.courte,
    SessionLengthChoice.moyenne,
    SessionLengthChoice.longue,
  ];
}
