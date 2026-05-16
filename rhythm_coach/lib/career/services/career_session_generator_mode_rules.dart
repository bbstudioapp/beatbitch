// Fichier part de `career_session_generator.dart` — contrat « ModeRules ».
//
// Objectif : remplacer progressivement les gros `switch (draft.mode)`
// éparpillés (stamina, humiliation gates, capability clamp, dispatch
// difficulté…) par un dispatch polymorphique. Un fichier par mode (à
// terme), chacun posant ses règles locales, le générateur n'orchestre
// plus que la cascade commune.
//
// Migration **incrémentale** : pour chaque méthode ajoutée au contrat,
// on fournit une implémentation par défaut, puis on migre mode par mode.
// Tant qu'un mode n'a pas override, le switch historique reste autoritaire.
//
// Migrations livrées :
//   * `delta` — calcul du Δ endurance (cf. `_StaminaModel.delta`).
//
// Migrations en cours :
//   * `unlockKeyFor` — gate UnlockKey requis pour qu'un draft soit jouable
//     en mode carrière (cf. `_HumiliationGates.unlockKeyFor`).

part of 'career_session_generator.dart';

/// Règles d'un mode pour le calcul du `delta` d'endurance et le mapping
/// `_StepDraft → UnlockKey?`.
///
/// Pure : aucun accès à l'état d'instance du générateur, tout est passé
/// via les arguments. Les helpers numériques partagés vivent côté
/// `_StaminaModel` (`positionDepth`, `lerp`).
abstract class _ModeRules {
  const _ModeRules();

  /// Coût (négatif) ou regen (positif) d'endurance pour le step.
  double delta(_StepDraft draft, double progress, CareerLevel cfg);

  /// Clé d'unlock requise pour qu'un step de ce mode soit jouable en mode
  /// carrière, ou `null` quand le step est dans le socle de base (pas de
  /// gate explicite).
  ///
  /// Override par défaut `null` — la migration depuis le switch de
  /// `_HumiliationGates.unlockKeyFor` se fait mode par mode, un mode non
  /// migré n'aura pas encore d'override ici et continuera à être servi
  /// par le switch historique.
  ///
  /// Convention `_isUnlocked` (hors interface ici, mais appliquée par le
  /// caller) : `unlockedKeys.isEmpty` = mode hérité, aucun gating. Cette
  /// méthode ne tient pas compte de cette convention — elle retourne
  /// toujours la clé mécanique.
  UnlockKey? unlockKeyFor(_StepDraft draft) => null;
}

/// Règles `breath` : toujours regen. Vitesse 2.8 stamina/s — règle de
/// design : un breath doit être plus court que les steps d'action qu'il
/// sépare, sinon la dramaturgie ressemble à « action / longue pause /
/// action / longue pause ». À 2.8/s, 8 s rendent ~22 stamina, ce qui
/// couvre un step rythme moyen (~20 de coût) et permet d'enchaîner.
class _BreathRules extends _ModeRules {
  const _BreathRules();

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
/// ni vraie regen). Toujours gaté par `freestyle` (palier d'intro
/// `intro_freestyle` au niveau 7).
class _FreestyleRules extends _ModeRules {
  const _FreestyleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) => 0.0;

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) => UnlockKey.freestyle;
}

/// Règles `suckle` : aspiration / téter. La bouche bosse sans aller-retour.
/// Coût par seconde modéré, plus marqué sur head (zone sensible → pompage
/// actif) que sur balls (sloppy soumis mais peu intense musculairement).
/// On modélise sur `_holdCostPerSec` de StaminaEngine en l'ajustant :
/// head ≈ 60 % d'un hold mid, balls ≈ 30 % (moins d'effort de la bouche,
/// plus de l'humil).
class _SuckleRules extends _ModeRules {
  const _SuckleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final pos = draft.to ?? draft.from;
    if (pos == Position.head) return -0.30 * dur;
    if (pos == Position.balls) return -0.15 * dur;
    return 0.0;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    // Suckle hors balls (filtré ailleurs) → forcément head. Gating
    // dédié, indépendant de la profondeur générique (suckle head n'est
    // pas une généralisation de hold head — c'est un geste explicite à
    // introduire pédagogiquement par sa propre milestone).
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.suckleBalls;
    }
    return UnlockKey.suckleHead;
  }
}

/// Règles `hand` : effort modéré côté endurance (la bouche se repose, mais
/// la main travaille). On consomme moins que rhythm équivalent.
class _HandRules extends _ModeRules {
  const _HandRules();

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
class _BiffleRules extends _ModeRules {
  const _BiffleRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final bpm = (draft.bpm ?? 80).toDouble();
    final depth = _StaminaModel.positionDepth(draft.from, draft.to);
    return -(bpm / 100.0) * depth * dur / 3.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) =>
      (draft.bpm ?? 0) > 100 ? UnlockKey.biffleFast : UnlockKey.biffleBasic;
}

/// Règles `lick` : BPM ≤ 60 = vraie récup vocale (regen), au-delà = effort
/// léger (consommation modérée, plus de regen).
class _LickRules extends _ModeRules {
  const _LickRules();

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

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.lickBalls;
    }
    // Lick X→full nécessite la milestone `intro_lick_full`. Sinon, lick
    // from=tip (toutes amplitudes ≤ throat) est du socle de base.
    if (draft.to == Position.full) return UnlockKey.lickFull;
    return null;
  }
}

/// Règles `hold` : coût pur lié à la profondeur tenue (`to`). Convention
/// uniforme hold/beg : la position tenue est dans `to`.
class _HoldRules extends _ModeRules {
  const _HoldRules();

  @override
  double delta(_StepDraft draft, double progress, CareerLevel cfg) {
    final dur = draft.duration ?? 0;
    final depth = _StaminaModel.positionDepth(draft.to, draft.to);
    return -depth * dur / 2.5;
  }

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.holdBalls;
    }
    // Convention : hold/beg portent leur position dans `to`. Les holds
    // tip/head sont du socle de base (pas de clé) ; mid+ sont gatés.
    final to = draft.to;
    if (to == null || to == Position.tip || to == Position.head) return null;
    if (to == Position.mid) return UnlockKey.holdMidShort;
    final dur = draft.duration ?? 0;
    if (to == Position.throat) {
      return dur > 10 ? UnlockKey.throatHoldLong : UnlockKey.throatHoldShort;
    }
    if (to == Position.full) {
      return dur > 10 ? UnlockKey.fullHoldLong : UnlockKey.fullHoldShort;
    }
    return null;
  }
}

/// Règles `beg` : convention uniforme hold/beg, la position tenue est dans
/// `to`. Sans `to` ou `to = head` → assimilé à du repos vocal (regen). Avec
/// `to = mid/throat/full` → coût comme un hold à cette profondeur (la
/// position doit être tenue pendant la supplique).
class _BegRules extends _ModeRules {
  const _BegRules();

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

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return UnlockKey.begBalls;
    }
    // Convention : hold/beg portent leur position dans `to`.
    if (draft.to == null) return UnlockKey.begLibre;
    if (draft.to == Position.full) return UnlockKey.begFull;
    // Toute supplique avec position tenue (head/mid/throat) reste gated
    // par begThroat (palier niveau 14). Avant ça, seule la supplique
    // libre (to=null) doit apparaître. Évite que le générateur produise
    // des beg head/mid après l'unlock de begLibre alors qu'aucune
    // milestone ne les a explicitement introduits.
    return UnlockKey.begThroat;
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
class _RhythmRules extends _ModeRules {
  const _RhythmRules();

  @override
  UnlockKey? unlockKeyFor(_StepDraft draft) {
    // Rhythm n'a pas de variante balls valide (les modes-incompatibles
    // balls sont filtrés en amont par `_HumiliationGates.isUnlocked`).
    // Pour rester strictement isomorphe au switch historique on retourne
    // null si touchesBalls — le filtre amont coupe avant.
    if (draft.from == Position.balls || draft.to == Position.balls) {
      return null;
    }
    if (draft.to == Position.full) return UnlockKey.fullPulse;
    if (draft.to == Position.throat) return UnlockKey.throatPulse;
    if (draft.to == Position.mid) return UnlockKey.rhythmMidBasic;
    // Rythme superficiel (tip→head) = socle de base, pas de clé.
    if ((draft.bpm ?? 0) >= 160) return UnlockKey.rhythmExtreme;
    return null;
  }

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
final Map<SessionMode, _ModeRules> _modeRulesRegistry = {
  SessionMode.rhythm: const _RhythmRules(),
  SessionMode.lick: const _LickRules(),
  SessionMode.hold: const _HoldRules(),
  SessionMode.biffle: const _BiffleRules(),
  SessionMode.beg: const _BegRules(),
  SessionMode.hand: const _HandRules(),
  SessionMode.breath: const _BreathRules(),
  SessionMode.freestyle: const _FreestyleRules(),
  SessionMode.suckle: const _SuckleRules(),
};
