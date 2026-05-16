// Fichier part de `career_session_generator.dart` — gating humiliation
// + unlocks + lubrification.
//
// Toutes les méthodes sont statiques. Les fonctions purement liées au
// `_StepDraft` (mapping unlock-key, descente d'un cran, deepestOf) n'ont
// aucun état d'instance. Celles qui consultent un thermomètre persistent
// reçoivent l'état requis en paramètres explicites :
//   * `isUnlocked` ← `anatomy` + `unlockedKeys`
//   * `finalUnlocked` ← `unlockedKeys`
//   * `lubricationCapDelta` ← projection salive
//   * `enforceRequired` ← `available` (humil cap), `anatomy`, `unlockedKeys`,
//     `saliva`, + un callback `clampToCapability` pour appliquer la 2ᵉ
//     enveloppe (qui reste côté instance car elle consulte `_capProfile`).
//
// Les adapteurs d'instance (préfixés `_`) du fichier principal injectent
// le contexte courant pour garder les call sites brefs (un seul argument
// au lieu de quatre).

part of 'career_session_generator.dart';

/// Gating humiliation et unlocks : mapping draft → clé requise, vérification
/// d'éligibilité, descente d'un cran, et cascade
/// d'`enforceHumiliationRequired` qui dégrade un draft jusqu'à acceptation.
///
/// Aucun état mutable. Toutes les méthodes sont statiques + pures (modulo
/// les arguments injectés par le caller).
class _HumiliationGates {
  /// Map un step vers la `UnlockKey` requise pour qu'il soit jouable en
  /// mode carrière. Retourne `null` quand le step est dans le socle de
  /// base (pas de gate explicite).
  ///
  /// Convention `_isUnlocked` (hors instance ici, mais appliquée par le
  /// caller) : `unlockedKeys.isEmpty` = mode hérité, aucun gating. Cette
  /// fonction ne tient pas compte de cette convention — elle retourne
  /// toujours la clé mécanique.
  static UnlockKey? unlockKeyFor(_StepDraft d) {
    // Balls : zone latérale, gating dédié (`lickBalls`/`holdBalls`/`begBalls`)
    // qui prime sur les clés génériques de profondeur. Le filtre anatomy +
    // modes-incompatibles vit dans [isUnlocked] (rhythm/hand/biffle balls
    // sont déjà rejetés en amont) — ici on suppose que la zone est légitime
    // pour le mode courant.
    final touchesBalls = d.from == Position.balls || d.to == Position.balls;
    if (touchesBalls) {
      switch (d.mode) {
        case SessionMode.lick:
          return UnlockKey.lickBalls;
        case SessionMode.hold:
          return UnlockKey.holdBalls;
        case SessionMode.beg:
          return UnlockKey.begBalls;
        case SessionMode.suckle:
          // Aspiration sur les couilles : gating dédié + filtre anatomy
          // côté MilestoneService (le générateur a déjà rejeté `suckle to:balls`
          // si `hasBalls=false`).
          return UnlockKey.suckleBalls;
        default:
          return null;
      }
    }
    switch (d.mode) {
      case SessionMode.hold:
        // Convention : hold/beg portent leur position dans `to`. Les holds
        // tip/head sont du socle de base (pas de clé) ; mid+ sont gatés.
        final to = d.to;
        if (to == null || to == Position.tip || to == Position.head) {
          return null;
        }
        if (to == Position.mid) return UnlockKey.holdMidShort;
        final dur = d.duration ?? 0;
        if (to == Position.throat) {
          return dur > 10
              ? UnlockKey.throatHoldLong
              : UnlockKey.throatHoldShort;
        }
        if (to == Position.full) {
          return dur > 10 ? UnlockKey.fullHoldLong : UnlockKey.fullHoldShort;
        }
        return null;
      case SessionMode.rhythm:
        if (d.to == Position.full) return UnlockKey.fullPulse;
        if (d.to == Position.throat) return UnlockKey.throatPulse;
        if (d.to == Position.mid) return UnlockKey.rhythmMidBasic;
        // Rythme superficiel (tip→head) = socle de base, pas de clé.
        if ((d.bpm ?? 0) >= 160) return UnlockKey.rhythmExtreme;
        return null;
      case SessionMode.biffle:
        return (d.bpm ?? 0) > 100
            ? UnlockKey.biffleFast
            : UnlockKey.biffleBasic;
      case SessionMode.freestyle:
        return UnlockKey.freestyle;
      case SessionMode.beg:
        // Convention : hold/beg portent leur position dans `to`.
        if (d.to == null) return UnlockKey.begLibre;
        if (d.to == Position.full) return UnlockKey.begFull;
        // Toute supplique avec position tenue (head/mid/throat) reste
        // gated par begThroat (palier niveau 14). Avant ça, seule la
        // supplique libre (to=null) doit apparaître. Évite que le
        // générateur produise des beg head/mid après l'unlock de
        // begLibre alors qu'aucun milestone ne les a explicitement
        // introduits.
        return UnlockKey.begThroat;
      case SessionMode.lick:
        // Lick X→full nécessite la milestone `intro_lick_full`. Sinon, lick
        // from=tip (toutes amplitudes ≤ throat) est du socle de base.
        if (d.to == Position.full) return UnlockKey.lickFull;
        return null;
      case SessionMode.hand:
        return null;
      case SessionMode.breath:
        return null;
      case SessionMode.suckle:
        // Suckle hors balls (filtré au-dessus) → forcément head. Gating
        // dédié, indépendant de la profondeur générique (suckle head n'est
        // pas une généralisation de hold head — c'est un geste explicite
        // à introduire pédagogiquement par sa propre milestone).
        return UnlockKey.suckleHead;
    }
  }

  /// Position la plus profonde du couple (a, b). `null` est traité comme
  /// « non spécifié » et l'autre l'emporte.
  static Position? deepestOf(Position? a, Position? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  /// Vrai si [d] n'est pas gaté par une `UnlockKey` ou si la clé requise
  /// est dans [unlockedKeys].
  ///
  /// **Convention `unlockedKeys.isEmpty` = mode hérité** : aucun gating
  /// appliqué. Sert aux scénarios hors carrière (sessions JSON statiques,
  /// tests) qui n'ont pas de chaîne milestones à consulter — sans cette
  /// convention, un `generate(...)` sans `unlockedKeys` deviendrait
  /// injouable (cascade systématique sur la baseline). Les call sites
  /// carrière passent toujours un set non vide (au minimum les unlocks
  /// d'`intro_basics` après le niveau 1).
  ///
  /// **Prérequis transverse `begLibre`** : « beg libre » signifie « bouche
  /// libre, supplique facile ». Toutes les autres formes de beg (avec
  /// `from` = position tenue) sont mécaniquement plus dures (la bouche
  /// reste sur la position pendant la supplique). On les bloque donc tant
  /// que `begLibre` n'est pas acquise — elle reste la fondation pédagogique.
  static bool isUnlocked(
    _StepDraft d, {
    required AnatomyProfile anatomy,
    required Set<UnlockKey> unlockedKeys,
  }) {
    // Anatomy gate (toujours actif, même en mode hérité) : la zone balls
    // n'est pas dans le setup → aucun step jouable dessus.
    final touchesBalls = d.from == Position.balls || d.to == Position.balls;
    if (touchesBalls && !anatomy.hasBalls) return false;
    // Modes-incompatibles : balls n'est pertinent que pour lick / hold /
    // beg (zone à lécher / aspirer / supplier-en-tenant). Pas de pompage
    // rythmé sur les couilles — gating structurel indépendant du contexte
    // (anatomy, milestone, mode hérité ou non).
    if (touchesBalls &&
        (d.mode == SessionMode.rhythm ||
            d.mode == SessionMode.hand ||
            d.mode == SessionMode.biffle)) {
      return false;
    }
    // Suckle : positions valides = `head` et `balls`. Toute autre cible
    // (tip / mid / throat / full) est structurellement rejetée — l'action
    // n'a pas de sens sur ces zones (aspiration sur la verge profonde =
    // hold, pas suckle ; aspiration sur le bout = lick tip). Filtre actif
    // même en mode hérité pour rester cohérent en Custom et scénarios JSON.
    if (d.mode == SessionMode.suckle) {
      final target = d.to ?? d.from;
      if (target != Position.head && target != Position.balls) return false;
    }
    if (unlockedKeys.isEmpty) return true;
    if (d.mode == SessionMode.beg &&
        !unlockedKeys.contains(UnlockKey.begLibre)) {
      return false;
    }
    final key = unlockKeyFor(d);
    return key == null || unlockedKeys.contains(key);
  }

  /// Vrai si la gate `UnlockKey?` d'un final candidat est accessible :
  /// soit `null` (final libre), soit présente dans [unlockedKeys], soit
  /// [unlockedKeys] est vide (= **mode hérité**, cf. la convention
  /// documentée sur [isUnlocked] : Custom, scénarios JSON, tests — pas de
  /// gating milestone). Sans ce dernier cas, Custom filtrerait *tous* les
  /// finals gated et retomberait systématiquement sur la baseline hand
  /// (cf. issue #43 : Custom Extrême se terminait toujours par un
  /// « branler »).
  ///
  /// Distinct de [isUnlocked] parce qu'un final est gaté par sa propre
  /// clé `finalXxx` dédiée — pas par la clé du composant. Ex : un final
  /// `hold mid` est gaté par `finalHoldMid` (sa milestone d'introduction
  /// dédiée), pas par `holdMidShort` qui couvre l'usage en corps de séance.
  static bool finalUnlocked(UnlockKey? key, Set<UnlockKey> unlockedKeys) =>
      key == null || unlockedKeys.isEmpty || unlockedKeys.contains(key);

  /// Retourne un offset au cap d'humiliation selon la lubrification
  /// projetée par la simulation salive. S'applique uniquement aux actions
  /// qui sollicitent une pénétration profonde (rhythm/lick/hold avec
  /// deepest ≥ throat).
  /// - saliva < 25 → -5 (sec, l'action coûte plus cher)
  /// - saliva ≥ 60 → +3 (humide, on peut pousser un peu plus)
  /// - sinon : 0
  static double lubricationCapDelta(_StepDraft d, double saliva) {
    final deepest = deepestOf(d.from, d.to);
    final needsLube = (d.mode == SessionMode.rhythm ||
            d.mode == SessionMode.lick ||
            d.mode == SessionMode.hold) &&
        deepest != null &&
        deepest.index >= Position.throat.index;
    if (!needsLube) return 0.0;
    if (saliva < 25.0) return -5.0;
    if (saliva >= 60.0) return 3.0;
    return 0.0;
  }

  /// Stratégie de dégradation : raccourcir un hold long, baisser `to` d'un
  /// cran, sinon `from`, sinon ramener un BPM rapide à 80, sinon
  /// transformer en mode plus doux.
  ///
  /// **Garde-fou from < to** : la descente de `to` saute l'étape si elle
  /// ferait collision avec `from` (head→mid → head→head interdit). Dans
  /// ce cas on passe directement à descendre `from`.
  static _StepDraft stepDownOne(_StepDraft d) {
    // Hold throat/full long → raccourcir d'abord (la durée pèse beaucoup
    // sur l'humiliation requise, la position reste contractuelle).
    if (d.mode == SessionMode.hold &&
        (d.to == Position.throat || d.to == Position.full) &&
        (d.duration ?? 0) > 5) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: d.from,
        to: d.to,
        duration: max(2, (d.duration ?? 0) ~/ 2),
      );
    }
    // Hold/beg : descendre `to` (la position tenue) d'un cran avant
    // d'aller plus loin.
    final isHoldLike = d.mode == SessionMode.hold || d.mode == SessionMode.beg;
    if (isHoldLike && d.to != null && d.to!.index > Position.tip.index) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: d.from,
        to: Position.values[d.to!.index - 1],
        duration: d.duration,
      );
    }
    if (d.to != null && d.to!.index > Position.head.index) {
      final newToIdx = d.to!.index - 1;
      // Skip si la descente collisionne avec `from` (cas typique :
      // head→mid → head→head interdit). On passe à descendre `from`.
      final fromIdx = d.from?.index ?? -1;
      if (newToIdx > fromIdx) {
        return _StepDraft(
          mode: d.mode,
          bpm: d.bpm,
          from: d.from,
          to: Position.values[newToIdx],
          duration: d.duration,
        );
      }
    }
    if (d.from != null && d.from!.index > Position.tip.index) {
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: Position.values[d.from!.index - 1],
        to: d.to,
        duration: d.duration,
      );
    }
    if ((d.mode == SessionMode.rhythm || d.mode == SessionMode.biffle) &&
        (d.bpm ?? 0) > 80) {
      return _StepDraft(
        mode: d.mode,
        bpm: 80,
        from: d.from,
        to: d.to,
        duration: d.duration,
      );
    }
    if (d.mode == SessionMode.biffle) {
      return _StepDraft(
        mode: SessionMode.lick,
        bpm: d.bpm ?? 60,
        from: d.from ?? Position.tip,
        to: d.to ?? Position.head,
        duration: d.duration,
      );
    }
    if (d.mode == SessionMode.beg && d.to != null) {
      // Beg avec position tenue → repli sur beg libre.
      return _StepDraft(
        mode: d.mode,
        bpm: d.bpm,
        from: null,
        to: null,
        duration: d.duration,
      );
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: 60,
      from: Position.tip,
      to: Position.head,
      duration: d.duration ?? 12,
    );
  }

  /// Si l'humiliation requise par [draft] dépasse [available], OU si la
  /// clé d'unlock requise n'est pas acquittée, dégrade progressivement
  /// (baisse profondeur, BPM, durée de hold, change de mode pour quelque
  /// chose de plus doux) jusqu'à acceptation. Fallback ultime sur un
  /// lick tip→head.
  ///
  /// Le callback [clampToCapability] applique la 2ᵉ enveloppe (profil de
  /// capacités) — il reste côté instance car il dépend de `_capProfile`,
  /// `_capCeilings`, `_overloadAxis` et `_overloadFactor` qui sont des
  /// snapshots de la session courante. La cascade ne fait que dégrader
  /// après le clamp initial, donc le clamp n'est appelé qu'une fois en
  /// tête de boucle.
  static _StepDraft enforceRequired(
    _StepDraft draft,
    double available, {
    required _StepDraft Function(_StepDraft) clampToCapability,
    required AnatomyProfile anatomy,
    required Set<UnlockKey> unlockedKeys,
    required double saliva,
  }) {
    // 2ᵉ enveloppe : on borne d'abord aux capacités prouvées (profondeur /
    // BPM / durée), puis la cascade humiliation ne fait que dégrader plus —
    // baisser `to`/`bpm`/`duration` ne peut jamais re-violer le cap capacité.
    var current = clampToCapability(draft);
    for (var i = 0; i < 12; i++) {
      final r = HumiliationScale.requiredFor(
        mode: current.mode,
        from: current.from,
        to: current.to,
        bpm: current.bpm,
        duration: current.duration,
      );
      // Lubrification : la salive projetée module le cap pour les actions
      // qui exigent un fond lubrifié (throat/full). Sous-lubrifié → cap
      // réduit (l'action est dégradée plus probablement). Bien lubrifié →
      // cap augmenté (la coach peut pousser plus loin).
      final lubeDelta = lubricationCapDelta(current, saliva);
      final effectiveAvailable = available + lubeDelta;
      if (r <= effectiveAvailable &&
          isUnlocked(current, anatomy: anatomy, unlockedKeys: unlockedKeys)) {
        return current;
      }
      current = stepDownOne(current);
    }
    return _StepDraft(
      mode: SessionMode.lick,
      bpm: 60,
      from: Position.tip,
      to: Position.head,
      duration: draft.duration ?? 12,
    );
  }
}
