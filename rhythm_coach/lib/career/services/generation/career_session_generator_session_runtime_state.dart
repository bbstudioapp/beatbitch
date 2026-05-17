// Fichier part de `career_session_generator.dart` — value object
// mutable `_SessionRuntimeState` : état muté pendant une séance.
//
// Pendant l'exécution de `generate()`, le générateur tient un
// scratchpad de compteurs / derniers émis / cooldowns / simulation
// salive qui est lu et muté à chaque step poussé. Ces ~13 fields
// vivaient sur l'instance du générateur ; ils sont désormais regroupés
// dans ce value object mutable, posé en début de chaque `generate()`
// / `generatePunishment()`.
//
// Pendant que `_SessionConfig` est **immuable** (inputs figés de la
// séance), `_SessionRuntimeState` est **mutable par contrat** — c'est
// le moteur de la boucle main. Les call sites externes (rules,
// dispatcher, trackers) lisent toujours via `gen._foo` grâce à des
// getters d'adapteur ; les mutations sont locales au générateur.
//
// `unlockedKeys` vit ici (et pas dans `_SessionConfig`) parce qu'il est
// **étendu** en cours de séance : quand une milestone est acquittée,
// ses unlocks rejoignent l'ensemble pour les steps suivants.
//
// Sous-systèmes runtime déjà extraits **séparément** (pas dans ce state) :
//   * `_RhythmChainTracker` — sait gérer sa propre vie (reset + onStepPushed).
//   * `_RhythmicPatternBuffer` — idem (clear + record).
// Ils restent des objets autonomes du générateur ; ce state regroupe
// juste les fields plats.

part of 'career_session_generator.dart';

/// État muté pendant une séance — scratchpad de la boucle `generate()`.
/// Posé une fois en début de `generate()` / `generatePunishment()` via
/// `_SessionRuntimeState.fresh(rng:)`, puis muté à chaque step poussé.
///
/// Champs publics et mutables par convention : le générateur les lit/écrit
/// directement, les call sites externes y accèdent via les getters
/// d'adapteur sur le générateur.
class _SessionRuntimeState {
  _SessionRuntimeState._({
    required this.nextMiniWaveAt,
    required this.salivaSim,
  });

  /// Construit un state initial pour une nouvelle séance. Les valeurs
  /// reflètent l'ancien bloc de reset au début de `generate()` :
  ///   * `nextMiniWaveAt` ∈ [240, 300] s (première mini-vague entre 4 et
  ///     5 min — laisse l'intro / chauffe se dérouler sans rupture).
  ///   * `lastSwallowOrderAt = -120` : laisse passer un premier ordre
  ///     swallow dès la fin de la rampe initiale si la salive monte vite.
  ///   * `salivaSim` : nouvelle instance reset.
  ///   * Tous les autres : valeurs « rien-encore-poussé » (null / 0 / '').
  ///   * `unlockedKeys` : vide par défaut (le caller met le set reçu en
  ///     param après `fresh()`).
  factory _SessionRuntimeState.fresh({required Random rng}) {
    return _SessionRuntimeState._(
      nextMiniWaveAt: 240 + rng.nextInt(61),
      salivaSim: SalivaEngine()..reset(),
    );
  }

  // ─── Cooldowns d'insertions (pacing) ─────────────────────────────────────

  /// `time` (en secondes) à partir duquel une **mini-vague** peut être
  /// insérée dans la boucle main. Cf. `_shouldEmitMiniWave` pour les
  /// conditions cumulatives. Une vague émise repousse à `time + 6-7 min`.
  /// Vise à casser la diagonale d'intensité unique du début au finish sur
  /// les sessions longues — 1 à 3 mini-vagues sur une session de 25-45 min.
  int nextMiniWaveAt;

  /// `time` du dernier ordre de déglutition forcé (`swallow_order`).
  /// Sert au cooldown 90 s entre deux ordres : sans ça, une joueuse spé
  /// sloppy avec lick à fond sature en permanence et le coach radoterait
  /// « avale » toutes les 30 s.
  int lastSwallowOrderAt = -120;

  // ─── Continuité par mode / type ──────────────────────────────────────────

  /// Dernier mode poussé dans la séance, pour éviter qu'un même mode
  /// (breath, beg, …) se déclenche deux steps d'affilé.
  SessionMode? lastMode;

  /// Type effectif du dernier step poussé (= cluster sémantique :
  /// bouche / langue / libre-main). Sert à forcer une continuité par
  /// type sur plusieurs steps consécutifs.
  ///
  /// Les steps `transit` (breath / freestyle) sont des parenthèses
  /// transparentes : ils ne touchent ni `lastType` ni `stepsInLastType`,
  /// pour qu'un breath de récup au milieu d'une série bouche n'efface pas
  /// la continuité.
  _StepType? lastType;
  int stepsInLastType = 0;

  /// Nombre de steps **consécutifs** posés en dehors du type `bouche`.
  /// Reset à 0 dès qu'un step bouche est poussé. Sert à imposer un cap
  /// dur sur la durée d'une excursion hors bouche : passé un certain
  /// nombre de steps cumulés (peu importe que ce soit langue ou
  /// libre-main), on force le retour à bouche.
  ///
  /// Distinct de `stepsInLastType` qui reset à chaque changement de type
  /// — ce compteur-là tient sur tout l'écart bouche → bouche.
  int stepsOutsideBouche = 0;

  // ─── Anti-répétition (BPM / amplitude / texte) ───────────────────────────

  /// Dernière phrase TTS poussée, pour éviter de répéter la même phrase
  /// scriptée d'un step à l'autre.
  String lastText = '';

  /// Dernier BPM appliqué à un step (rhythm/lick/biffle/hand). Sert à
  /// forcer la variété : un nouveau BPM trop proche du précédent est
  /// décalé de 18–30 BPM par `_BpmPacing.diversifyBpm`.
  int? lastBpm;

  /// Dernier couple (from, to) appliqué pour les modes à amplitude
  /// (rhythm/lick/hand/biffle). Sert à forcer une variation de profondeur
  /// quand le step suivant tombe sur exactement la même paire.
  Position? lastFrom;
  Position? lastTo;

  // ─── Simulation salive ───────────────────────────────────────────────────
  // Mime le runtime `SalivaEngine` pour anticiper les ordres de déglutition
  // au moment du draft.

  /// Simulateur de salive utilisé pendant la génération. Mime le
  /// comportement du `SalivaEngine` runtime : production par mode/position,
  /// auto-déglutition au-dessus de 75. Sert à projeter la lubrification
  /// au moment du draft d'un step throat/full (cf. Phase 4). En V1 le
  /// SwallowMode est assumé `allowed`.
  SalivaEngine salivaSim;

  /// Compteur de secondes consommées par la simulation salive (mute en
  /// parallèle de `salivaSim` via `_advanceSalivaSim`).
  int salivaSimSecond = 0;

  // ─── Gating étendu en cours de séance ────────────────────────────────────

  /// Set des `UnlockKey` débloquées au moment où le step suivant est
  /// généré. Une action dont la clé n'est pas dedans est rejetée par
  /// `_isUnlocked` et dégradée par `_stepDownOne`. Vide = aucune clé
  /// requise (mode héritage).
  ///
  /// **Mutable en cours de séance** : quand une milestone est acquittée
  /// par un step scripté, ses unlocks rejoignent l'ensemble — les steps
  /// suivants en bénéficient immédiatement. C'est cette extension qui
  /// justifie la présence du field dans le **state** plutôt que dans
  /// `_SessionConfig` (qui est immuable).
  Set<UnlockKey> unlockedKeys = const {};

  // ─── Méthodes dérivées (mutations / lectures purement state) ─────────────

  /// Met à jour la continuité par type après un step poussé :
  ///   * `lastType` / `stepsInLastType` (incrémenté si même type que le
  ///     précédent, sinon nouveau cluster).
  ///   * `stepsOutsideBouche` (reset à 0 sur bouche, incrémenté sinon).
  ///
  /// Les steps `transit` (breath / freestyle) sont une parenthèse
  /// transparente : ils ne touchent à rien (un breath de récup au milieu
  /// d'une série rythmée ne doit pas remettre le compteur à zéro).
  void recordContinuity(_StepType type) {
    if (type == _StepType.transit) return;
    if (type == _StepType.bouche) {
      stepsOutsideBouche = 0;
    } else {
      stepsOutsideBouche++;
    }
    if (type == lastType) {
      stepsInLastType++;
    } else {
      lastType = type;
      stepsInLastType = 1;
    }
  }

  /// Capture l'état mutable de continuité (lasts + compteurs) pour le
  /// passer au picker statique [`_ModePicker.pickWeighted`]. Reconstruit
  /// à chaque pick — 4 lectures de fields, cheap.
  _ModeContinuityState continuitySnapshot() => _ModeContinuityState(
        lastType: lastType,
        stepsInLastType: stepsInLastType,
        stepsOutsideBouche: stepsOutsideBouche,
        lastMode: lastMode,
      );

  /// Met à jour l'état « dernier *action* step émis » à partir du draft
  /// qu'on vient d'émettre : `lastMode`, `lastText`, `lastFrom`, `lastTo`.
  /// Inclut explicitement les positions (y compris `null` pour
  /// breath/biffle/beg-sans-from) — les call sites comptent dessus pour
  /// la diversification d'amplitude au tour suivant.
  ///
  /// `lastBpm` n'est **pas** touché : à mettre à jour explicitement au
  /// call site (`_state.lastBpm = d.bpm ?? _state.lastBpm`) quand le
  /// `_BpmPacing.diversifyBpm` du prochain tour doit comparer contre ce
  /// step (intro, mini-vague). Pour les sous-segments de
  /// `_diversifyLongSegment` et le `chainNext`, on veut au contraire que
  /// `lastBpm` reste celui de l'**outer** step — ne rien faire ici donne
  /// la bonne sémantique.
  void recordLastAction(_StepDraft d, String text) {
    lastMode = d.mode;
    lastText = text;
    lastFrom = d.from;
    lastTo = d.to;
  }

  /// Met à jour l'état « dernier step émis » pour une **parenthèse
  /// transit** (breath / fakeBreath / swallow-beg / pré-finisher / boost
  /// / final / post-final) : `lastMode` + `lastText` seulement.
  /// `lastBpm` / `lastFrom` / `lastTo` sont **préservés** — le prochain
  /// action step compare bien contre le dernier *action* step, pas
  /// contre la parenthèse. Les boosts mettent à jour `lastBpm` à part
  /// au call site (cf. doc de [recordLastAction]).
  void recordLastTransit(SessionMode mode, String text) {
    lastMode = mode;
    lastText = text;
  }

  /// Avance la simulation salive pour la durée d'un draft : un tick par
  /// seconde, en propageant `salivaSimSecond` qui sert d'index temporel
  /// à `SalivaEngine.onTickSecond`. Mute `salivaSim` (via `onTickSecond`)
  /// et `salivaSimSecond`. No-op si `draft.duration` ≤ 0.
  void advanceSalivaSim(_StepDraft draft) {
    final dur = draft.duration ?? 0;
    if (dur <= 0) return;
    for (var s = 0; s < dur; s++) {
      salivaSim.onTickSecond(
        mode: draft.mode,
        from: draft.from,
        to: draft.to,
        swallowMode: SwallowMode.allowed,
        elapsedSecond: salivaSimSecond,
      );
      salivaSimSecond++;
    }
  }
}
