// Fichier part de `career_session_generator.dart` — pickers de position
// pour les modes à amplitude / hold / beg / suckle.
//
// Regroupe les tirages géographiques (from/to, position de hold, position
// de beg, position du pré-finisher) + les calculs de plafond profondeur
// dérivés des milestones acquittées (`milestoneHoldCeilingIdx`,
// `milestoneRhythmCeilingIdx`) + le samplers générique `sampleSimplex3`.
//
// Tous bundlés dans `_PositionPickers` (value object immuable), pattern
// identique à `CapabilityClamps` et `FinalPicker` : les méthodes
// s'appellent entre elles et partagent le même état (8 fields), passer
// chaque field à chaque appel rendrait les signatures illisibles.

part of 'career_session_generator.dart';

/// Pickers de position : profondeurs des holds/beg/finisher, tirages de
/// couple from/to par mode, samplers RNG. Immuable : le générateur en
/// construit un par appel à `generate()` / `generatePunishment()` après
/// que `_capClamps` est posé.
class _PositionPickers {
  /// Snapshot de la config de séance. On y lit `maxDepthIndex`,
  /// `deepProbability`, `humiliationCareer`, `spec`, `coachModeWeights`,
  /// `anatomy` — figés au début de `generate()`.
  final SessionConfig config;

  /// Unlocks acquittés par milestones. Convention héritée :
  /// `unlockedKeys.isEmpty` = pas de gating milestone, on retombe sur le
  /// cap de niveau.
  final Set<UnlockKey> unlockedKeys;

  final Random rng;

  const _PositionPickers({
    required this.config,
    required this.unlockedKeys,
    required this.rng,
  });

  int _pts(SpecializationBranch b) => config.spec.pointsIn(b);

  bool _isModeForbidden(SessionMode m) => config.isModeForbidden(m);

  bool _isUnlocked(StepDraft d) => _HumiliationGates.isUnlocked(
        d,
        anatomy: config.anatomy,
        unlockedKeys: unlockedKeys,
      );

  /// Templates `(beg, chainAction)` pour la palette [maybePickBegWithChain].
  /// La durée du beg est l'enveloppe : pour un beg libre on l'écrase par
  /// `baseDuration` clampé entre les deux bornes définies ici (utilisé
  /// comme min/max). Pour un beg ancré (`to != null`), on garde tel quel.
  static const List<(StepDraft, StepDraft)> begChainTemplates = [
    // Beg libre + rhythm tip→head 80 BPM 18 s.
    (
      StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      StepDraft(
        mode: SessionMode.rhythm,
        bpm: 80,
        from: Position.tip,
        to: Position.head,
        duration: 18,
      ),
    ),
    // Beg libre + lick tip→head 70 BPM 14 s.
    (
      StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 10,
      ),
      StepDraft(
        mode: SessionMode.lick,
        bpm: 70,
        from: Position.tip,
        to: Position.head,
        duration: 14,
      ),
    ),
    // Beg libre + hold head 6 s.
    (
      StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: null,
        duration: 12,
      ),
      StepDraft(
        mode: SessionMode.hold,
        bpm: null,
        from: null,
        to: Position.head,
        duration: 6,
      ),
    ),
    // Beg head + lick head→mid 65 BPM 12 s — profil obéissance avancée
    // (gated par begThroat car beg to non-null).
    (
      StepDraft(
        mode: SessionMode.beg,
        bpm: null,
        from: null,
        to: Position.head,
        duration: 8,
      ),
      StepDraft(
        mode: SessionMode.lick,
        bpm: 65,
        from: Position.head,
        to: Position.mid,
        duration: 12,
      ),
    ),
  ];

  /// Profondeur max débloquée pour un hold, basée sur les milestones :
  /// fullHoldShort > throatHoldShort > holdMidShort > head (socle de
  /// base). Capée aussi par [maxDepthIndex] (cohérence niveau).
  ///
  /// Sémantique design : « le seul hold qui a du sens est le plus profond
  /// que tu sais tenir ». Aller moins profond perd le côté narratif —
  /// l'utilisatrice qui sait tenir gorge n'a aucune raison de tenir mid
  /// pendant une session normale, c'est juste de la baisse arbitraire.
  /// Les holds tip/head n'ont pas de clé (socle ouvert par
  /// `intro_basics`) → en carrière sans milestone hold acquise, le
  /// plancher est `head`.
  int milestoneHoldCeilingIdx() {
    final int milestoneCap;
    if (unlockedKeys.contains(UnlockKey.fullHoldShort)) {
      milestoneCap = Position.full.index;
    } else if (unlockedKeys.contains(UnlockKey.throatHoldShort)) {
      milestoneCap = Position.throat.index;
    } else if (unlockedKeys.contains(UnlockKey.holdMidShort)) {
      milestoneCap = Position.mid.index;
    } else if (unlockedKeys.isEmpty) {
      // Hérité (mode démo / scénario non-carrière) : on retombe sur le cap
      // de niveau. Évite que le mode démo se fige sur head.
      milestoneCap = config.maxDepthIndex;
    } else {
      // Carrière, socle de base : head est le hold le plus profond libre.
      milestoneCap = Position.head.index;
    }
    return min(milestoneCap, config.maxDepthIndex);
  }

  /// Cap de profondeur autorisé pour les modes rythmés (rhythm/hand) en
  /// `to`, basé sur les milestones effectivement acquittées :
  /// - `fullPulse` (intro_full_pulse) → full ouvert
  /// - `throatPulse` (intro_throat_pulse) → throat ouvert
  /// - sinon → plafond mid (la joueuse n'a pas encore appris la profondeur)
  ///
  /// Capé aussi par [maxDepthIndex] en sécurité (cohérence niveau).
  /// Indépendant du niveau : c'est l'acquittement de la milestone qui
  /// débloque, pas le passage de palier.
  int milestoneRhythmCeilingIdx() {
    final int milestoneCap;
    if (unlockedKeys.contains(UnlockKey.fullPulse)) {
      milestoneCap = Position.full.index;
    } else if (unlockedKeys.contains(UnlockKey.throatPulse)) {
      milestoneCap = Position.throat.index;
    } else {
      milestoneCap = Position.mid.index;
    }
    return min(milestoneCap, config.maxDepthIndex);
  }

  /// Choix de la position d'un hold. Règle : on ne tient **que la
  /// profondeur max débloquée**. Si full est ouverte, on tire entre throat
  /// et full (ampScore + spé profondeur biaisent vers full). Si throat est
  /// le max, on ne tient que throat — pas de retour à mid arbitraire. Au
  /// tout début (mid max), on tient mid.
  Position pickHoldPosition(double ampScore) {
    final ceilingIdx = milestoneHoldCeilingIdx();
    final depthPts = _pts(SpecializationBranch.profondeur);
    // Cas full ouvert : choix throat / full pondéré par ampScore + spé.
    if (ceilingIdx >= Position.full.index) {
      final adjusted = (ampScore + 0.10 * depthPts).clamp(0.0, 1.0);
      final boostedFullProb =
          (config.deepProbability + 0.10 * depthPts).clamp(0.0, 1.0);
      // Plus ampScore est haut, plus on penche full ; mais on respecte
      // aussi `deepProbability` du niveau pour ne pas spammer du full dès
      // le palier d'ouverture.
      final wantsFull = adjusted >= 0.55 && rng.nextDouble() < boostedFullProb;
      return wantsFull ? Position.full : Position.throat;
    }
    // Cap inférieur ou égal à throat : on tient strictement le max.
    return Position.values[ceilingIdx];
  }

  /// Choix de la position du pré-finisher (transition rythmée juste avant
  /// les boosts, bas niveaux). Le cap suit [milestoneRhythmCeilingIdx]
  /// — gating par milestones acquittées, jamais par niveau seul.
  Position pickFinisherPosition() {
    final ceilingIdx = milestoneRhythmCeilingIdx();
    if (ceilingIdx <= Position.mid.index) return Position.mid;
    if (ceilingIdx == Position.throat.index) {
      // throatPulse acquis : 30% mid (variété) / 70% throat.
      return rng.nextDouble() < 0.30 ? Position.mid : Position.throat;
    }
    // ceilingIdx == full → fullPulse acquis : tirage parmi mid/throat/full.
    final r = rng.nextDouble();
    if (r < 0.30) return Position.mid;
    if (r < 0.70) return Position.throat;
    return Position.full;
  }

  /// Choix de la position d'un beg selon ampScore. Retourne null pour
  /// `ampScore < 0.40` → beg libre (sans position). Sinon : mid → throat
  /// → full. Jamais head ou tip (pas de sens : un beg léger doit être
  /// libre, ancrer la position de tenue ne commence qu'à mid).
  Position? pickBegPosition(double ampScore) {
    if (ampScore < 0.40) return null;
    if (ampScore < 0.65) return Position.mid;
    if (ampScore < 0.85) return Position.throat;
    return Position.full;
  }

  /// Tire un couple (from, to) tel que `from.index < to.index` strictement.
  ///
  /// `ampScore = 0` → head→mid (baseline). `ampScore = 1` → tip→full ou
  /// mid→full. Garantit la contrainte from < to.
  ///
  /// Choix de design : `from = head` est la baseline, `from = tip` reste
  /// possible mais minoritaire (~15%) — sinon on se retrouve avec une
  /// majorité de tip→head en début de session, alors que la position de
  /// référence pour la coach est head.
  /// [capByDepth] = true → ceiling et probabilité de profondeur appliqués
  /// (rythme : la profondeur est gated par milestone). false → toutes
  /// profondeurs autorisées (lick : la langue n'a pas de tension de
  /// profondeur ; le filtre se fait en aval via `_isUnlocked` quand `to`
  /// requiert une milestone, ex: `lick_full`).
  (Position, Position) sampleFromTo(double ampScore, {bool capByDepth = true}) {
    final clamped = ampScore.clamp(0.0, 1.0);
    // Min mid (idx 2) au lieu de head (idx 1) : l'amplitude minimale est
    // head→mid, pas tip→head.
    final ceiling = capByDepth ? config.maxDepthIndex.clamp(2, 4) : 4;
    var deepestIdx = StaminaModel.lerp(2.0, ceiling.toDouble(), clamped)
        .round()
        .clamp(2, ceiling);
    // Bonus Profondeur (spé) : remonte la probabilité de profond, dans la
    // limite du plafond du tirage.
    final depthPts = _pts(SpecializationBranch.profondeur);
    final effectiveDeepProb = capByDepth ? config.deepProbability : 1.0;
    final boostedDeepProb =
        (effectiveDeepProb + 0.08 * depthPts).clamp(0.0, 1.0);
    // Si le tirage demande une position profonde (≥ throat) mais que la
    // probabilité ne le permet pas, on rabat sur mid.
    if (deepestIdx >= 3 && rng.nextDouble() >= boostedDeepProb) {
      deepestIdx = 2;
    }
    final int shallowestIdx;
    if (deepestIdx >= 3 && rng.nextDouble() < 0.15) {
      // ~15% : tip pour les amplitudes pleines (tip→full marque bien).
      shallowestIdx = 0;
    } else {
      // Sinon : head ou plus profond (jamais tip), uniforme entre les
      // positions admissibles.
      shallowestIdx = 1 + rng.nextInt(deepestIdx - 1);
    }
    return (
      Position.values[shallowestIdx],
      Position.values[deepestIdx],
    );
  }

  /// Tirage spécifique au mode hand. **Une seule variation** en standalone :
  /// `head→throat`. La main enveloppe la base de la verge ; aller plus haut
  /// que les lèvres (= head) n'a pas de sens anatomique, et la varier sur
  /// 3-4 amplitudes brouillait la lecture acoustique sans gain dramaturgique.
  /// Le BPM (60–180, choisi par `bpmScore`) reste le levier de variété.
  ///
  /// `ampScore` est ignoré ici — la variation viendra des futurs combos
  /// hand+rhythm où `from` du hand s'aligne sur le `from` du rhythm
  /// (ex. rhythm mid→throat → hand mid→throat, parce que la main ne peut
  /// pas être plus haut que les lèvres pendant le combo).
  (Position, Position) sampleFromToForHand(double ampScore) {
    return (Position.head, Position.throat);
  }

  /// Tirage spécifique au mode lick. Tant que `humiliationCareer < 2`, le
  /// lick reste sur tip→head (l'utilisatrice n'a pas encore appris à
  /// lécher plus profond). À partir de 2, toutes les amplitudes sont
  /// autorisées sans cap niveau — la langue n'a pas de tension de
  /// profondeur (`capByDepth: false`). Si le tirage tombe sur to=full
  /// sans la milestone `lick_full`, le filtre `_isUnlocked` en cascade
  /// dégrade.
  (Position, Position) sampleFromToForLick(double ampScore) {
    if (config.humiliationCareer < 2.0) {
      return (Position.tip, Position.head);
    }
    return sampleFromTo(ampScore, capByDepth: false);
  }

  /// Tire un point uniforme sur le simplexe 3D (a + b + c = 1, tous > 0).
  /// Méthode des "barres de Dirichlet" : 2 cuts uniformes dans [0,1] triés
  /// délimitent 3 segments.
  (double, double, double) sampleSimplex3() {
    final a = rng.nextDouble();
    final b = rng.nextDouble();
    final lo = min(a, b);
    final hi = max(a, b);
    return (lo, hi - lo, 1.0 - hi);
  }

  /// Tente de transformer un beg simple en beg + action enchaînée
  /// (« dis X et continue à me sucer »). Retourne `null` quand aucun
  /// template ne passe les unlocks ou quand le tirage aléatoire l'emporte.
  /// Probabilité 0.20 → 0.60 selon l'obéissance investie.
  ///
  /// **Palette V1** (gating naturel par `_isUnlocked` sur les composants) :
  /// 1. beg libre 12 s + rhythm tip→head 80 BPM 18 s
  /// 2. beg libre 10 s + lick tip→head 70 BPM 14 s
  /// 3. beg libre 12 s + hold head 6 s
  /// 4. beg head 8 s + lick head→mid 65 BPM 12 s (gated begThroat)
  ///
  /// Le tirage est uniforme parmi les templates dont les deux composants
  /// passent `_isUnlocked`. `null` si aucun ne passe.
  StepDraft? maybePickBegWithChain({
    required Position? to,
    required int obPts,
  }) {
    // Pour V1, on n'attache une chain que sur un beg libre (to == null).
    // Les beg avec position tenue (mid/throat/full) sont déjà mécaniquement
    // chargés, on ne veut pas y greffer une seconde action en plus.
    if (to != null) return null;
    final probability = 0.20 + 0.05 * obPts;
    if (rng.nextDouble() > probability.clamp(0.20, 0.60)) return null;

    final holdCeilingIdx = milestoneHoldCeilingIdx();
    final candidates = <(StepDraft, StepDraft)>[];
    for (final tpl in begChainTemplates) {
      // Si le chainNext est un hold à profondeur sous le palier de hold
      // débloqué par milestones, on filtre — un hold tip/head qui suit
      // un beg alors qu'on maîtrise mid est une régression. On NE le
      // promote pas en silence (durée 6 s d'un template tip/head ne
      // tient pas une bouchée à throat ou full) — on retire juste le
      // template du tirage.
      final chain = tpl.$2;
      if (chain.mode == SessionMode.hold &&
          chain.to != null &&
          chain.to!.index < holdCeilingIdx) {
        continue;
      }
      if (!_isUnlocked(tpl.$1) || !_isUnlocked(tpl.$2)) continue;
      // Custom (dose `none`) : on ne propose pas un beg-with-chain dont la
      // suite est sur un mode banni. Le beg en lui-même est aussi gaté (si
      // beg=none, le tirage de beg ne sera pas atteint en amont, mais on
      // re-check ici pour rester explicite).
      if (_isModeForbidden(tpl.$1.mode)) continue;
      if (_isModeForbidden(tpl.$2.mode)) continue;
      candidates.add(tpl);
    }
    if (candidates.isEmpty) return null;
    final pick = candidates[rng.nextInt(candidates.length)];
    return StepDraft(
      mode: pick.$1.mode,
      bpm: pick.$1.bpm,
      from: pick.$1.from,
      to: pick.$1.to,
      duration: pick.$1.duration,
      chainNext: pick.$2,
    );
  }
}
