// Fichier part de `career_session_generator.dart` — contrat « ModeRules ».
//
// Objectif : remplacer progressivement les gros `switch (draft.mode)`
// éparpillés (stamina, humiliation gates, capability clamp, dispatch
// difficulté…) par un dispatch polymorphique. Un fichier par mode, chacun
// posant sa règle locale, le générateur n'orchestre plus que la cascade
// commune.
//
// Migration **incrémentale** : tant qu'un mode n'a pas son `_ModeRules`
// enregistré, l'ancien switch reste autoritaire. La migration mode par
// mode permet de checker les tests à chaque étape sans bigbang.
//
// Étape en cours : `staminaDelta` (la plus pure — aucune dépendance à
// l'état d'instance du générateur).

part of 'career_session_generator.dart';

/// Règles d'un mode pour le calcul du `delta` d'endurance.
///
/// Pure : aucun accès à l'état d'instance du générateur, tout est passé
/// via [draft] / [progress] / [cfg]. Les helpers numériques partagés
/// vivent côté `_StaminaModel` (`positionDepth`, `lerp`).
abstract class _ModeStaminaRules {
  /// Coût (négatif) ou regen (positif) d'endurance pour le step.
  double delta(_StepDraft draft, double progress, CareerLevel cfg);
}

/// Règles `breath` : toujours regen. Vitesse 2.8 stamina/s — règle de
/// design : un breath doit être plus court que les steps d'action qu'il
/// sépare, sinon la dramaturgie ressemble à « action / longue pause /
/// action / longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui
/// couvre un step rythme moyen (~20 de coût) et permet d'enchaîner.
class _BreathStaminaRules implements _ModeStaminaRules {
  const _BreathStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final regen = _StaminaModel.lerp(
      cfg.regenStartMultiplier,
      cfg.regenEndMultiplier,
      progress,
    );
    return dur * 2.8 * regen;
  }
}

/// Règles `freestyle` : phase libre, neutre côté endurance (ni effort
/// ni vraie regen).
class _FreestyleStaminaRules implements _ModeStaminaRules {
  const _FreestyleStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) => 0.0;
}

/// Règles `suckle` : aspiration / téter. La bouche bosse sans aller-retour.
/// Coût par seconde modéré, plus marqué sur head (zone sensible → pompage
/// actif) que sur balls (sloppy soumis mais peu intense musculairement).
/// On modélise sur `_holdCostPerSec` de StaminaEngine en l'ajustant :
/// head ≈ 60 % d'un hold mid, balls ≈ 30 % (moins d'effort de la bouche,
/// plus de l'humil).
class _SuckleStaminaRules implements _ModeStaminaRules {
  const _SuckleStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final pos = draft.to ?? draft.from;
    if (pos == Position.head) return -0.30 * dur;
    if (pos == Position.balls) return -0.15 * dur;
    return 0.0;
  }
}

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class _HandStaminaRules implements _ModeStaminaRules {
  const _HandStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 6.0;
  }
}

/// Règles `biffle` : effort soutenu (la fille encaisse), conso entre
/// rythme et hold, modulée par la profondeur.
class _BiffleStaminaRules implements _ModeStaminaRules {
  const _BiffleStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 3.5;
  }
}

/// Règles `lick` : BPM ≤ 60 = vraie récup vocale (regen), au-delà = effort
/// léger (consommation modérée, plus de regen).
class _LickStaminaRules implements _ModeStaminaRules {
  const _LickStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = draft.bpm ?? 60;
    if (bpm <= 60) {
      final regen = _StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.2 * regen;
    }
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -depth * dur / 8.0;
  }
}

/// Règles `hold` : coût pur lié à la profondeur tenue (`to`). Convention
/// uniforme hold/beg : la position tenue est dans `to`.
class _HoldStaminaRules implements _ModeStaminaRules {
  const _HoldStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final depth = _StaminaModel.positionDepth(draft.to, draft.to);
    return -depth * dur / 2.5;
  }
}

/// Règles `beg` : convention uniforme hold/beg, la position tenue est dans
/// `to`. Sans `to` ou `to = head` → assimilé à du repos vocal (regen). Avec
/// `to = mid/throat/full` → coût comme un hold à cette profondeur (la
/// position doit être tenue pendant la supplique).
class _BegStaminaRules implements _ModeStaminaRules {
  const _BegStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final to = draft.to;
    if (to == null || to == Position.head) {
      final regen = _StaminaModel.lerp(
        cfg.regenStartMultiplier,
        cfg.regenEndMultiplier,
        progress,
      );
      return dur * 1.0 * regen;
    }
    final depth = _StaminaModel.positionDepth(to, to);
    return -depth * dur / 2.5;
  }
}

/// Règles `rhythm` : coût modulé par profondeur cible (mid pèse le plus :
/// c'est la zone où on tient le rythme le plus longtemps), atténué par le
/// bénéfice de respiration au creux du va-et-vient (qui s'évanouit à haute
/// vitesse).
///
/// Multiplicateurs de coût accentués dès que `to` atteint mid (idx 2).
/// to=mid: ×1.45, to=throat: ×1.30, to=full: ×1.15.
///
/// Bénéfice respi : un step à grande amplitude (tip→full, mid→throat)
/// laisse une fenêtre de respi. À l'inverse, throat/full ou throat/throat
/// = pas de respi, coût plein. Formule :
///   `amplitudeFactor ∈ [0,1] = (toIdx − fromIdx) / 4`
///   `bpmFactor ∈ [0,1] = clamp((100 − bpm) / 40, 0, 1)`
///   `respiBenefit = amplitudeFactor × bpmFactor × 0.40`
/// → tip→full 60 bpm : −40 % de coût
/// → mid→full 60 bpm : −20 %
/// → throat→full 60 bpm : −10 %
/// → mid→full 100 bpm : 0 % (BPM trop haut)
class _RhythmStaminaRules implements _ModeStaminaRules {
  const _RhythmStaminaRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 60).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    final toIdx = (draft.to ?? draft.from)?.index ?? 0;
    final depthMul = toIdx >= Position.full.index
        ? 1.15
        : toIdx >= Position.throat.index
            ? 1.30
            : toIdx >= Position.mid.index
                ? 1.45
                : 1.0;
    final fromIdx = draft.from?.index ?? toIdx;
    final amplitude = (toIdx - fromIdx).clamp(0, 4);
    final amplitudeFactor = amplitude / 4.0;
    final respiBpmFactor = ((100.0 - bpm) / 40.0).clamp(0.0, 1.0);
    final respiBenefit = amplitudeFactor * respiBpmFactor * 0.40;
    final costFactor = (1.0 - respiBenefit).clamp(0.6, 1.0);
    return -(bpm / 100.0) * depth * dur * depthMul * costFactor / 3.0;
  }
}

/// Registry des règles par mode. La migration `staminaDelta` est terminée :
/// les 9 modes sont couverts, le switch de `_StaminaModel.delta` n'est plus
/// qu'un dispatch unique vers ce registry (cf. la méthode `delta`).
final Map<SessionMode, _ModeStaminaRules> _modeStaminaRulesRegistry = {
  SessionMode.rhythm: const _RhythmStaminaRules(),
  SessionMode.lick: const _LickStaminaRules(),
  SessionMode.hold: const _HoldStaminaRules(),
  SessionMode.biffle: const _BiffleStaminaRules(),
  SessionMode.beg: const _BegStaminaRules(),
  SessionMode.hand: const _HandStaminaRules(),
  SessionMode.breath: const _BreathStaminaRules(),
  SessionMode.freestyle: const _FreestyleStaminaRules(),
  SessionMode.suckle: const _SuckleStaminaRules(),
};
