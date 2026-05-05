import 'dart:math';

/// Configuration de difficulté d'un niveau de carrière. Calculée
/// analytiquement à partir du numéro de niveau (pas de table figée).
class CareerLevel {
  /// Numéro du niveau (1 = débutant).
  final int level;

  /// Borne haute absolue de la fenêtre de tirage (`diff ∈ [0, 1]`).
  /// Plus le niveau monte, plus le dé peut atteindre des valeurs élevées.
  final double maxDifficultyCap;

  /// Multiplicateur de régénération d'endurance au début d'une séance
  /// (à `t = 0`). Reste autour de 1.0 quel que soit le niveau.
  final double regenStartMultiplier;

  /// Multiplicateur de régénération en fin de séance (à `t = duration`).
  /// Augmente avec le niveau : plus on est avancé, plus la récup s'accélère
  /// vers la fin → moins de temps réel passé en récup, plus d'effort enchaîné.
  final double regenEndMultiplier;

  /// Durée nominale d'une séance à ce niveau, en secondes. Couple
  /// difficulté/endurance avec durée — niveau 1 court, niveau 15+ long.
  final int durationSeconds;

  /// Titre affichable du niveau (peut être partagé entre plusieurs niveaux
  /// consécutifs).
  final String title;

  /// Profondeur maximale autorisée pour les rhythm/hold à ce niveau.
  /// Niveau 1 : interdit throat et full. Au-delà : full possible.
  final int maxDepthIndex;

  /// Probabilité de tomber sur throat/full quand le tirage l'autorise
  /// (rhythm + hold). Permet de raréfier au niveau 2 sans bannir.
  final double deepProbability;

  /// Plafond d'excitation atteignable à ce niveau. Sert à la fois de
  /// `maxValue` du moteur d'excitation (clamp haut) et de `max` de la
  /// barre UI. Adapté au niveau pour qu'il reste atteignable sans BPM
  /// élevés ni profondeur ouverte (interdits aux bas niveaux). Niveau 1
  /// = 70, niveau 6+ = 100. Le mode encore monte cette valeur de +20.
  final double excitationTarget;

  /// Cible **minimale** que les boosts visent en phase finish. Découplée
  /// du `excitationTarget` (max UI) : permet à un finish de monter au-delà
  /// du minimum si la dynamique le permet, mais garantit qu'on atteint au
  /// moins ce seuil avant de basculer sur le final. De base 90 ; plus bas
  /// aux premiers niveaux pour que le finish soit toujours bouclable.
  /// Si `minFinal > excitationTarget`, le moteur ne peut pas atteindre
  /// minFinal (clampé par maxValue) — c'est OK, les boosts s'arrêtent
  /// après `minBoosts` et le finish reste lisible.
  final double minFinal;

  const CareerLevel({
    required this.level,
    required this.maxDifficultyCap,
    required this.regenStartMultiplier,
    required this.regenEndMultiplier,
    required this.durationSeconds,
    required this.title,
    required this.maxDepthIndex,
    required this.deepProbability,
    required this.excitationTarget,
    required this.minFinal,
  });

  /// Déduit la config d'un niveau N. Niveau 1 = doux et permissif ;
  /// chaque niveau ajoute ~5 points de plafond et accélère la récup en fin
  /// de séance. Plafonné à 1.0 / 3.0.
  factory CareerLevel.forLevel(int n) {
    final level = max(1, n);
    final cap = min(0.20 + 0.05 * level, 1.0);
    final regenEnd = min(1.2 + 0.15 * level, 3.0);
    return CareerLevel(
      level: level,
      maxDifficultyCap: cap,
      regenStartMultiplier: 1.0,
      regenEndMultiplier: regenEnd,
      durationSeconds: _durationForLevel(level),
      title: _titleForLevel(level),
      maxDepthIndex: _maxDepthForLevel(level),
      deepProbability: _deepProbabilityForLevel(level),
      excitationTarget: _excitationTargetForLevel(level),
      minFinal: _minFinalForLevel(level),
    );
  }

  /// Plafond d'excitation atteignable côté moteur : toujours 100. La
  /// progression par niveau passe désormais uniquement par `minFinal` (la
  /// barre UI plafonne à minFinal pour donner l'impression d'atteindre
  /// l'objectif), pas par un cap engine artificiellement bas. Le mode
  /// encore ajoute +20 par-dessus (= 120).
  static double _excitationTargetForLevel(int level) => 100.0;

  /// Seuil minimal d'excitation que les boosts doivent atteindre pour
  /// boucler le finish. Sert également de **plafond visuel** de la barre
  /// (cf. `excitationBarMax` côté SessionScreen) : la barre fait le plein
  /// quand l'excitation atteint minFinal, même si le moteur peut grimper
  /// plus haut. Une débutante voit donc sa jauge se remplir « à temps »
  /// sans qu'on bride la physique sous-jacente.
  static double _minFinalForLevel(int level) {
    if (level <= 1) return 50.0;
    if (level <= 2) return 65.0;
    if (level <= 3) return 70.0;
    if (level <= 5) return 80.0;
    return 90.0;
  }

  /// Mapping niveau → durée. Couple progression et endurance : un niveau
  /// 1 ne dure pas 30 min, un niveau 15 demande de tenir longtemps.
  static int _durationForLevel(int level) {
    if (level <= 2) return 5 * 60;
    if (level <= 4) return 8 * 60;
    if (level <= 7) return 12 * 60;
    if (level <= 10) return 18 * 60;
    if (level <= 14) return 25 * 60;
    if (level <= 17) return 35 * 60;
    return 45 * 60;
  }

  /// Titres figés par paliers (doublons consécutifs assumés).
  static String _titleForLevel(int level) {
    if (level <= 2) return 'Débutante';
    if (level <= 4) return 'Apprentie Suceuse';
    if (level <= 6) return 'Petite Salope Confirmée';
    if (level <= 8) return 'Bouche à Pipe';
    if (level == 9) return 'Avaleuse';
    if (level <= 12) return 'Throat Queen';
    if (level <= 14) return 'Reine du Sloppy';
    if (level <= 17) return 'Trou à Bite Officiel';
    if (level <= 19) return 'Vide-Couilles Pro';
    return 'Reine des Putes';
  }

  /// Profondeur max autorisée (index de Position) pour rhythm + hold :
  /// niveaux 1-2 plafonnent à `mid` (2), niveau 3 ouvre throat (3),
  /// niveau 4+ ouvre full (4).
  static int _maxDepthForLevel(int level) {
    if (level <= 2) return 2; // mid max — pas de throat/full
    if (level <= 3) return 3; // throat possible, full encore interdit
    return 4; // full ouvert
  }

  /// Probabilité de réellement tirer une position profonde (throat ou full)
  /// quand le niveau l'autorise. 0 jusqu'au niveau 3 inclus : throat est
  /// ouvert au niveau 3 (`maxDepthIndex = 3`) MAIS uniquement dans la
  /// phase finish (boosts + finisher), pas dans le main loop — sinon
  /// l'utilisatrice voit un step head→throat sans aucune prépa avant.
  /// À partir du niveau 4 (full ouvert), throat/full peuvent apparaître
  /// dans le main loop.
  static double _deepProbabilityForLevel(int level) {
    if (level <= 3) return 0.0;
    if (level <= 5) return 0.30;
    if (level <= 8) return 0.55;
    return 0.80;
  }
}
