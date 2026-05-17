// Fichier part de `career_session_generator.dart` — modèle d'endurance pure.
//
// Regroupe les fonctions sans état d'instance qui calculent comment chaque
// step consomme ou régénère l'endurance (`stamina` 0..100). Tirées hors du
// fichier principal pour deux raisons :
// 1. La courbe `delta(...)` est dense (8 modes × règles par profondeur,
//    BPM et amplitude) et mérite son propre point d'entrée pour la review.
// 2. Toutes les méthodes sont **statiques + pures** — elles ne dépendent que
//    de leurs arguments. Pas de bénéfice à les laisser sur l'instance, et
//    de futurs tests unitaires dédiés sont triviaux à écrire.
//
// Restent côté instance dans le fichier principal :
//   * `_config.pts` / `_config.scaleDuration` — tissent `_config.spec` à travers la pondération
//     des modes, lectures éparpillées dans tout le générateur.

part of 'career_session_generator.dart';

/// Modèle d'endurance procédural : delta par mode/profondeur/BPM/durée,
/// plafond [max], helpers de remplissage de profil.
///
/// Toutes les méthodes sont statiques et pures. Le test unitaire de
/// référence vit dans `test/career_stamina_model_test.dart`.
class StaminaModel {
  /// Plafond de la jauge — l'endurance est clampée à cette valeur en haut,
  /// mais peut descendre en négatif (dette d'endurance) pour signaler au
  /// caller qu'un sas breath est nécessaire avant le step suivant.
  ///
  /// Nommé `cap` plutôt que `max` pour éviter toute ambiguïté avec la
  /// fonction `max` de `dart:math` qui est aussi importée dans la library.
  static const double cap = 100.0;

  /// Interpolation linéaire bornée. `t.clamp(0, 1)` pour qu'un dépassement
  /// (cf. cap effectif des progressions de boost) ne sorte pas de [a, b].
  static double lerp(double a, double b, double t) =>
      a + (b - a) * t.clamp(0.0, 1.0);

  /// Profondeur effective d'un step (1..5) prenant le max de `from` / `to`.
  /// `null` est traité comme `tip` (idx 0). Sert au calcul du coût stamina,
  /// **pas** au gating humil (qui a sa propre table d'index dans
  /// `HumiliationScale`).
  static double positionDepth(Position? from, Position? to) {
    final fIdx = from?.index ?? 0;
    final tIdx = to?.index ?? fIdx;
    return (max(fIdx, tIdx) + 1).toDouble();
  }

  /// Remplit le profil stamina sur l'intervalle `[from, from + count)` avec
  /// une **rampe linéaire** entre [valueStart] (stamina au début du step) et
  /// [valueEnd] (stamina à la fin, après application du delta du step).
  ///
  /// Sans cette interpolation, l'affichage debug montre une valeur unique
  /// pour toute la durée du step, ce qui est trompeur — un breath de 12 s
  /// affichait 70 % d'endurance pendant 12 s alors qu'il démarre justement
  /// quand on est en déficit (stamina < 0). La rampe permet de voir la
  /// chute pendant un step rythmique et la remontée pendant un breath /
  /// recovery, ce qui colle à l'intuition de l'utilisatrice.
  ///
  /// Compatibilité : si [valueStart] est omis, on retombe sur le comportement
  /// historique (valeur constante). Conservé pour les séquences milestone
  /// où on ne calcule pas la valeur de départ.
  static void fillProfile(
    List<double> profile,
    int from,
    int count,
    double valueEnd, {
    double? valueStart,
  }) {
    final end = min(profile.length, from + count);
    final start = max(0, from);
    if (start >= end) return;
    final span = end - start;
    if (valueStart == null || span <= 1) {
      for (var i = start; i < end; i++) {
        profile[i] = valueEnd;
      }
      return;
    }
    // Rampe linéaire : profile[start] = valueStart, profile[end-1] = valueEnd.
    final dx = (valueEnd - valueStart) / (span - 1);
    for (var i = 0; i < span; i++) {
      profile[start + i] = valueStart + dx * i;
    }
  }

  /// Variante « brute » du delta endurance : retourne le coût (négatif) ou
  /// le gain (positif) sans clamp, pour pouvoir détecter un déficit projeté
  /// (= dette d'endurance qu'il faut combler par un breath, cf. D3 du plan).
  ///
  /// Dispatch polymorphique : chaque mode a sa règle dans
  /// `_modeRulesRegistry` (cf. `career_session_generator_mode_rules.dart`).
  /// Comptabilité endurance : modes effort consomment, modes respi régénèrent
  /// (multiplicateur qui monte avec `progress`), freestyle est neutre.
  static double delta(
    StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) =>
      _modeRulesRegistry[draft.mode]!.delta(draft, progress, cfg);

  /// Applique [delta] à `stamina`, en plafonnant à [cap].
  ///
  /// **Pas de plancher bas** — on autorise une dette d'endurance qui sera
  /// comblée par le sas breath conditionnel (cf. `_buildBreathRecovery`).
  /// Les bas niveaux ne descendaient jamais sous 90 à cause d'un ancien
  /// clamp à 0 combiné aux faibles deltas — le sas breath ne se déclenchait
  /// alors quasiment jamais.
  static double apply(
    double stamina,
    StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) {
    final next = stamina + delta(draft, progress, cfg);
    return next > cap ? cap : next;
  }
}
