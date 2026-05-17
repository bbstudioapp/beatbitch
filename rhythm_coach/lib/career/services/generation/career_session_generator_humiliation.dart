// Fichier part de `career_session_generator.dart` — gating humiliation
// + unlocks + lubrification.
//
// Toutes les méthodes sont statiques. Les fonctions purement liées au
// `StepDraft` (mapping unlock-key, descente d'un cran, deepestOf) n'ont
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
  /// Dispatch polymorphique : chaque mode porte sa propre logique dans
  /// `_*Rules.unlockKeyFor` (cf. `career_session_generator_mode_rules.dart`),
  /// y compris la gestion des variantes balls (lickBalls / holdBalls /
  /// begBalls / suckleBalls). Les modes-incompatibles balls
  /// (rhythm / hand / biffle) sont déjà filtrés par [isUnlocked] avant
  /// d'arriver ici.
  ///
  /// Convention `_isUnlocked` (hors interface ici, mais appliquée par le
  /// caller) : `unlockedKeys.isEmpty` = mode hérité, aucun gating. Cette
  /// fonction ne tient pas compte de cette convention — elle retourne
  /// toujours la clé mécanique.
  static UnlockKey? unlockKeyFor(
    StepDraft d, {
    required Map<SessionMode, ModeRules> rules,
  }) =>
      rules[d.mode]!.unlockKeyFor(d);

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
    StepDraft d, {
    required AnatomyProfile anatomy,
    required Set<UnlockKey> unlockedKeys,
    required Map<SessionMode, ModeRules> rules,
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
    final key = unlockKeyFor(d, rules: rules);
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
  static double lubricationCapDelta(StepDraft d, double saliva) {
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

  /// Une étape de dégradation. Chaque mode porte sa propre stratégie
  /// dans `_*Rules.tryDegrade` (cf. `career_session_generator_mode_rules.dart`) :
  /// hold raccourcit puis baisse `to`, beg baisse `to` puis repli libre,
  /// rhythm/lick/hand cascade desc-to → desc-from (+ cap BPM pour rhythm),
  /// biffle cap BPM puis se transforme en lick. Quand toutes les rules
  /// retournent `null`, on retombe sur le fallback ultime ci-dessous.
  ///
  /// **Garde-fou from < to** porté par les helpers `tryDescendToWithGuard`
  /// (cf. mode rules) : la descente de `to` saute l'étape si elle
  /// ferait collision avec `from` (head→mid → head→head interdit).
  static StepDraft stepDownOne(
    StepDraft d, {
    required Map<SessionMode, ModeRules> rules,
  }) {
    final degraded = rules[d.mode]!.tryDegrade(d);
    if (degraded != null) return degraded;
    // Fallback ultime : lick tip→head — le geste le plus doux qu'on
    // puisse poser sans contrainte d'unlock (toujours disponible).
    return StepDraft(
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
  static StepDraft enforceRequired(
    StepDraft draft,
    double available, {
    required StepDraft Function(StepDraft) clampToCapability,
    required AnatomyProfile anatomy,
    required Set<UnlockKey> unlockedKeys,
    required double saliva,
    required Map<SessionMode, ModeRules> rules,
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
          isUnlocked(current,
              anatomy: anatomy, unlockedKeys: unlockedKeys, rules: rules)) {
        return current;
      }
      current = stepDownOne(current, rules: rules);
    }
    return StepDraft(
      mode: SessionMode.lick,
      bpm: 60,
      from: Position.tip,
      to: Position.head,
      duration: draft.duration ?? 12,
    );
  }
}
