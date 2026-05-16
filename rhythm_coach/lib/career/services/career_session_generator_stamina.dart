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
//   * `_pts` / `_scaleDuration` — tissent `_spec` à travers la pondération
//     des modes, lectures éparpillées dans tout le générateur.

part of 'career_session_generator.dart';

/// Modèle d'endurance procédural : delta par mode/profondeur/BPM/durée,
/// plafond [max], helpers de remplissage de profil.
///
/// Toutes les méthodes sont statiques et pures. Le test unitaire de
/// référence vit dans `test/career_stamina_model_test.dart`.
class _StaminaModel {
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
  /// Comptabilité endurance : modes effort consomment (taux ~doublés par
  /// rapport à la v1, qui descendait beaucoup trop lentement), modes respi
  /// ≤ 60 BPM régénèrent (multiplicateur qui monte avec `progress`),
  /// au-dessus c'est neutre.
  static double delta(
    _StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) {
    final dur = draft.duration ?? 0;
    var next = 0.0;
    switch (draft.mode) {
      case SessionMode.rhythm:
        final bpm = (draft.bpm ?? 60).toDouble();
        final depth = positionDepth(draft.from, draft.to);
        // Multiplicateur de coût accentué dès que `to` atteint mid
        // (idx 2). Sur les bas niveaux, c'est la profondeur où on tient
        // le rythme la plus longtemps, et l'endurance ne descendait
        // quasiment pas — ajout d'un coup de fatigue plus marqué.
        // to=mid: ×1.45, to=throat: ×1.30, to=full: ×1.15.
        final toIdx = (draft.to ?? draft.from)?.index ?? 0;
        final depthMul = toIdx >= Position.full.index
            ? 1.15
            : toIdx >= Position.throat.index
                ? 1.30
                : toIdx >= Position.mid.index
                    ? 1.45
                    : 1.0;
        // Bénéfice respiration : un step à grande amplitude (ex tip→full,
        // mid→throat) laisse une fenêtre de respi au creux du va-et-vient.
        // À l'inverse, un step throat/full ou throat/throat = pas de
        // respiration, coût plein. À haute vitesse, le bénéfice s'évanouit
        // (la respi n'a plus le temps de s'installer entre deux beats).
        // Formule : amplitudeFactor ∈ [0,1] = (toIdx - fromIdx) / 4
        //          bpmFactor ∈ [0,1] = clamp((100-bpm)/40, 0, 1)
        //          respiBenefit = amplitudeFactor × bpmFactor × 0.40
        // → tip→full 60bpm : −40 % de coût
        // → mid→full 60bpm : −20 %
        // → throat→full 60bpm : −10 %
        // → mid→full 100bpm : 0 % (BPM trop haut)
        final fromIdx = (draft.from)?.index ?? toIdx;
        final amplitude = (toIdx - fromIdx).clamp(0, 4);
        final amplitudeFactor = amplitude / 4.0;
        final respiBpmFactor = ((100.0 - bpm) / 40.0).clamp(0.0, 1.0);
        final respiBenefit = amplitudeFactor * respiBpmFactor * 0.40;
        final costFactor = (1.0 - respiBenefit).clamp(0.6, 1.0);
        next -= (bpm / 100.0) * depth * dur * depthMul * costFactor / 3.0;
      case SessionMode.hold:
        // Convention uniforme : hold/beg portent leur position dans `to`.
        final depth = positionDepth(draft.to, draft.to);
        next -= depth * dur / 2.5;
      case SessionMode.biffle:
        // Biffle = effort soutenu (la fille encaisse), conso entre rythme
        // et hold, modulée par la profondeur.
        final bpm = (draft.bpm ?? 80).toDouble();
        final depth = positionDepth(draft.from, draft.to);
        next -= (bpm / 100.0) * depth * dur / 3.5;
      case SessionMode.beg:
        // Convention uniforme : hold/beg portent leur position dans `to`.
        // Sans `to` ou `to = head` → assimilé à du repos vocal (regen).
        // Avec `to = mid/throat/full` → coût comme un hold à cette
        // profondeur (la position doit être tenue pendant la supplique).
        final to = draft.to;
        if (to == null || to == Position.head) {
          final regen = lerp(
            cfg.regenStartMultiplier,
            cfg.regenEndMultiplier,
            progress,
          );
          next += dur * 1.0 * regen;
        } else {
          final depth = positionDepth(to, to);
          next -= depth * dur / 2.5;
        }
      case SessionMode.lick:
        final bpm = draft.bpm ?? 60;
        if (bpm <= 60) {
          // Lick lent = vraie récup vocale.
          final regen = lerp(
            cfg.regenStartMultiplier,
            cfg.regenEndMultiplier,
            progress,
          );
          next += dur * 1.2 * regen;
        } else {
          // Lick plus vite = effort léger, on ne récupère plus et on
          // s'épuise un peu.
          final depth = positionDepth(draft.from, draft.to);
          next -= depth * dur / 8.0;
        }
      case SessionMode.breath:
        // Toujours regen : breath n'est jamais un step d'effort. Vitesse
        // poussée à 2.8 stamina/s — règle de design : un breath doit être
        // plus court que les steps d'action qu'il sépare, sinon la
        // dramaturgie ressemble à « action / longue pause / action /
        // longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui couvre
        // un step rythme moyen (~20 de coût) et permet d'enchaîner.
        final regen = lerp(
          cfg.regenStartMultiplier,
          cfg.regenEndMultiplier,
          progress,
        );
        next += dur * 2.8 * regen;
      case SessionMode.hand:
        // Hand = effort modéré côté endurance (la bouche se repose, mais
        // la main travaille). On consomme moins que rhythm équivalent.
        final bpm = (draft.bpm ?? 80).toDouble();
        final depth = positionDepth(draft.from, draft.to);
        next -= (bpm / 100.0) * depth * dur / 6.0;
      case SessionMode.freestyle:
        // Phase libre : neutre côté endurance (ni effort ni vraie regen).
        break;
      case SessionMode.suckle:
        // Aspiration / téter : la bouche bosse sans aller-retour. Coût
        // par seconde modéré, plus marqué sur head (zone sensible →
        // pompage actif) que sur balls (sloppy soumis mais peu intense
        // musculairement). On modélise sur `_holdCostPerSec` de
        // StaminaEngine en l'ajustant : head ≈ 60 % d'un hold mid, balls
        // ≈ 30 % (moins d'effort de la bouche, plus de l'humil).
        final pos = draft.to ?? draft.from;
        if (pos == Position.head) {
          next -= 0.30 * dur;
        } else if (pos == Position.balls) {
          next -= 0.15 * dur;
        }
    }
    return next;
  }

  /// Applique [delta] à `stamina`, en plafonnant à [cap].
  ///
  /// **Pas de plancher bas** — on autorise une dette d'endurance qui sera
  /// comblée par le sas breath conditionnel (cf. `_buildBreathRecovery`).
  /// Les bas niveaux ne descendaient jamais sous 90 à cause d'un ancien
  /// clamp à 0 combiné aux faibles deltas — le sas breath ne se déclenchait
  /// alors quasiment jamais.
  static double apply(
    double stamina,
    _StepDraft draft,
    double progress,
    CareerLevel cfg,
  ) {
    final next = stamina + delta(draft, progress, cfg);
    return next > cap ? cap : next;
  }
}
