// Library autonome — helpers de construction de drafts spécialisés.
//
// Regroupe les builders d'instance qui consomment l'état du générateur
// (`_state`, `_config`, `_rng`, `_rules`) pour assembler un `StepDraft`
// d'un type particulier (breath recovery, fake breath, swallow order,
// mini-vague, recovery, first step, post-final, post-wave breath).
// La plupart sont des thin delegates aux rules — la rule mode-specific
// décide de la durée / des positions, les builders ne gèrent que les
// pré-conditions d'éligibilité + l'invocation polymorphique.
//
// Sortis du fichier principal en D.PR8-partielle du plan de refacto
// (`~/beatbitch_refacto_phase_d.md`). Approche pragmatique : on extrait
// les helpers qui ont des dépendances stables (`state`/`config`/
// `rng`/`rules`) ; les méthodes d'émission qui muent le ctx restent
// dans `CareerSessionGenerator` (couplage trop fort à externaliser).

import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_step.dart';
import '../../models/career_level.dart';
import '../../models/phrase_bank.dart';
import '../../models/unlock_key.dart';
import 'mode_picker.dart';
import 'mode_rules.dart';
import 'session_config.dart';
import 'session_runtime_state.dart';
import 'step_draft.dart';

/// Callback de tirage de phrase contextualisée. Pointe sur
/// `_pickPhrase(bank, mode, tier)` côté générateur ; threadé en argument
/// pour [StepBuilders.maybeBuildFakeBreath] qui sélectionne lui-même
/// son texte. Évite de threader `state.lastText` + le rng auxiliaire
/// dans une 2e voie.
typedef PickPhrase = String Function(
    PhraseBank bank, SessionMode mode, String tier);

/// Callback de filtrage humiliation cascade. Pointe sur
/// `_enforceHumiliationRequired(draft, humilCap)` côté générateur.
/// Threadé pour [StepBuilders.buildMiniWave] qui filtre chaque step
/// de la vague brute avant émission.
typedef EnforceHumiliationRequired = StepDraft Function(
    StepDraft draft, double humilCap);

/// Callback de bornage capacité. Pointe sur
/// `_clampToCapability(draft)` côté générateur (= 2ᵉ enveloppe
/// profondeur / BPM / durée).
typedef ClampToCapability = StepDraft Function(StepDraft draft);

/// Callback de gating unlock d'un draft. Pointe sur `_isUnlocked(draft)`
/// côté générateur (qui adapte `HumiliationGates.isUnlocked` avec
/// `_config.anatomy`, `_state.unlockedKeys`, `_rules`).
typedef IsUnlocked = bool Function(StepDraft draft);

/// Constructeurs de drafts d'instance. Instancié une fois par
/// `generate()` après que `_state` / `_config` / `_capClamps` sont
/// posés, partagé avec les helpers d'émission de la chaîne main loop +
/// finish phase.
class StepBuilders {
  StepBuilders({
    required this.config,
    required this.state,
    required this.rng,
    required this.rules,
    required this.facade,
    required this.enforceHumiliationRequired,
    required this.clampToCapability,
    required this.isUnlocked,
  })  : _breathMode = _resolveRole(rules, ModeSemanticRole.breath),
        _postWaveBreathMode =
            _resolveRole(rules, ModeSemanticRole.postWaveBreath),
        _swallowOrderMode = _resolveRole(rules, ModeSemanticRole.swallowOrder),
        _miniWaveCoreMode = _resolveRole(rules, ModeSemanticRole.miniWaveCore),
        _recoveryDegradeFallbackMode =
            _resolveRole(rules, ModeSemanticRole.recoveryDegradeFallback);

  final SessionConfig config;
  final SessionRuntimeState state;
  final Random rng;
  final Map<SessionMode, ModeRules> rules;
  final GenFacadeSurface facade;
  final EnforceHumiliationRequired enforceHumiliationRequired;
  final ClampToCapability clampToCapability;
  final IsUnlocked isUnlocked;

  /// Modes résolus une fois à la construction pour éviter d'itérer le
  /// registre à chaque appel.
  final SessionMode _breathMode;
  final SessionMode _postWaveBreathMode;
  final SessionMode _swallowOrderMode;
  final SessionMode _miniWaveCoreMode;
  final SessionMode _recoveryDegradeFallbackMode;

  /// Résolution de rôle — itère le registre, retourne le 1er mode qui
  /// déclare le rôle. Dupliqué depuis `_resolveModeForRole` /
  /// `DifficultyDispatch._resolveRole` (couplage minimal entre
  /// libraries autonomes).
  static SessionMode _resolveRole(
    Map<SessionMode, ModeRules> rules,
    ModeSemanticRole role,
  ) {
    for (final entry in rules.entries) {
      if (entry.value.roles.contains(role)) return entry.key;
    }
    throw StateError(
      'ModeSemanticRole.$role : aucun mode du registry ne le déclare',
    );
  }

  /// Construit le **breath de recovery** standard (déficit d'endurance
  /// projeté). Délégué au mode qui porte le rôle `breath` (cf. B.PR7) ;
  /// la rule décide de la durée (deficit + buffer, fenêtre [4, 12]).
  /// La rule retourne toujours un draft non-null pour ce rôle, donc le
  /// `!` est sûr.
  StepDraft buildBreathRecovery(
    double deficit,
    double progress,
    CareerLevel cfg,
  ) {
    return rules[_breathMode]!.buildBreathRecovery(BreathRecoveryCtx(
      deficit: deficit,
      progress: progress,
      cfg: cfg,
    ))!;
  }

  /// Construit la **pause longue post-vague** : breath dédié dimensionné
  /// pour viser ~95 stamina, fenêtre [12, 20] s. Délégué au mode qui
  /// porte le rôle `postWaveBreath` (cf. B.PR7). Retourne `null` si
  /// `remainingSeconds < 12` (pas assez de place avant le finish).
  StepDraft? buildPostWaveBreath(
    double stamina,
    double progress,
    CareerLevel cfg,
    int remainingSeconds,
  ) {
    return rules[_postWaveBreathMode]!.buildPostWaveBreath(PostWaveBreathCtx(
      stamina: stamina,
      progress: progress,
      cfg: cfg,
      remainingSeconds: remainingSeconds,
    ));
  }

  /// Construit éventuellement un **fake breath** (2-3 s) après un step
  /// intense, pour effet de surprise dramaturgique. Conditions
  /// cumulatives :
  /// - `_state.unlockedKeys.isEmpty` (mode hérité) OU `fakeBreath`
  ///   débloqué ;
  /// - marge `genUntil - time >= 30` ;
  /// - `currentStamina >= 30` (sinon un vrai breath a déjà été inséré) ;
  /// - dernier step émis « intense » selon la rule
  ///   (`isIntenseForFakeBreath`) ;
  /// - dé 25 %.
  ///
  /// Retourne `null` si une condition manque. Sinon `(draft, text)` —
  /// la phrase est tirée via le callback [pickPhrase] (tier
  /// `fake_breath`, fallback `hard`).
  ({StepDraft draft, String text})? maybeBuildFakeBreath({
    required StepDraft lastEmitted,
    required double currentStamina,
    required int time,
    required int genUntil,
    required PhraseBank bank,
    required PickPhrase pickPhrase,
  }) {
    // Convention `_state.unlockedKeys.isEmpty` = mode hérité (Custom /
    // scénarios / debug) : pas de gating, le mécanisme reste actif. En
    // carrière le déblocage passe par la milestone `intro_fake_breath`
    // qui accorde la clé `fakeBreath`.
    if (state.unlockedKeys.isNotEmpty &&
        !state.unlockedKeys.contains(UnlockKey.fakeBreath)) {
      return null;
    }
    if (genUntil - time < 30) return null; // pas trop près du finish
    if (currentStamina < 30) return null; // déjà en dette, vrai breath plus bas
    if (!rules[lastEmitted.mode]!.isIntenseForFakeBreath(lastEmitted)) {
      return null;
    }
    if (rng.nextDouble() >= 0.25) return null;
    // Construction du draft déléguée à la rule (cf. B.PR7). 2-3 s,
    // peanuts face au coût d'un step intense ~25-40. La rule retourne
    // toujours un draft non-null pour ce rôle, donc le `!` est sûr.
    final draft = rules[_breathMode]!.buildFakeBreath(FakeBreathCtx(rng: rng))!;
    // Phrase : on tire d'abord dans le tier `fake_breath` (phrases
    // taquines). Fallback sur `hard` si la bank n'a pas encore le pool
    // dédié — au moins le ton reste sec/dominateur, pas une phrase
    // douce qui casse la surprise.
    var text = pickPhrase(bank, _breathMode, 'fake_breath');
    if (text.isEmpty) {
      text = pickPhrase(bank, _breathMode, 'hard');
    }
    return (draft: draft, text: text);
  }

  /// Construit éventuellement un step **swallow_order** : beg libre court
  /// (5-7 s) qui matérialise l'ordre coach « avale tout » quand la sim
  /// salive sature. Conditions cumulatives :
  /// - `_state.salivaSim.value >= 80` (marge 10 sous le seuil overflow) ;
  /// - cooldown 90 s depuis `_state.lastSwallowOrderAt` ;
  /// - marge `genUntil - time >= 60` ;
  /// - `begLibre` débloqué.
  ///
  /// Retourne `null` si une condition manque. Sinon délègue à la rule
  /// qui porte le rôle `swallowOrder` (cf. B.PR6).
  StepDraft? maybeBuildSwallowOrder(int time, int genUntil) {
    if (state.salivaSim.value < 80.0) return null;
    if (time - state.lastSwallowOrderAt < 90) return null;
    if (genUntil - time < 60) return null;
    if (!state.unlockedKeys.contains(UnlockKey.begLibre)) return null;
    return rules[_swallowOrderMode]!.buildSwallowOrder(SwallowCtx(rng: rng));
  }

  /// Construit la séquence de la mini-vague : 2 à 3 steps rythmés à BPM
  /// montant, chacun à profondeur progressive (head→mid puis head→mid
  /// puis head→throat si débloqué). Variations de `to` choisies pour
  /// ne pas trigger le détecteur de pattern plat
  /// (`_patternBuffer.wouldBeFlat`) et pour matérialiser la montée à
  /// l'oreille (BPMs espacés de 20).
  ///
  /// Chaque step est filtré par [enforceHumiliationRequired] avec le
  /// `humilCap` courant : si la vague propose un step trop humiliant,
  /// il dégrade vers du plus doux automatiquement (ex throat → mid).
  /// Si après dégradation un step duplique le précédent, il est skip
  /// plutôt que re-poussé — la vague peut donc se réduire à 2 steps
  /// en pratique. La séquence brute est déléguée au mode qui porte
  /// le rôle `miniWaveCore` (cf. B.PR5).
  List<StepDraft> buildMiniWave(double humilCap) {
    final hasThroat = state.unlockedKeys.contains(UnlockKey.throatHoldShort) ||
        config.maxDepthIndex >= Position.throat.index;
    final raw = rules[_miniWaveCoreMode]!
            .buildMiniWaveSegment(MiniWaveCtx(hasThroat: hasThroat)) ??
        const <StepDraft>[];
    final out = <StepDraft>[];
    Position? prevTo;
    int? prevBpm;
    for (final s in raw) {
      final filtered = enforceHumiliationRequired(s, humilCap);
      // Skip si la dégradation rend ce step identique au précédent
      // (mêmes from/to/bpm) — la vague compresserait sinon en plat.
      if (filtered.to == prevTo && filtered.bpm == prevBpm) continue;
      out.add(filtered);
      prevTo = filtered.to;
      prevBpm = filtered.bpm;
    }
    // Garde au minimum 2 steps : si la cascade a tout aplati (cas humil
    // très basse en début de niveau 5), on retombe sur les 2 premiers
    // steps de `raw` sans filtre humil, qui sont volontairement modérés
    // (head→mid 100/120 — req mécanique très basse). On les borne quand
    // même au profil de capacités.
    if (out.length < 2) {
      return raw.take(2).map(clampToCapability).toList();
    }
    return out;
  }

  /// Tirage d'un step « respi active » : mode parmi les `ModeRules`
  /// qui opt-in à `isRecoveryCandidate`, BPM ≤ 60 pour déclencher la
  /// regen d'endurance. Le mode `breath` n'est plus tiré ici — il est
  /// inséré strictement sur déficit d'endurance projeté via
  /// [buildBreathRecovery], pas comme une option d'humeur générale.
  ///
  /// Orchestration mode-agnostic : collecte les candidats via le
  /// registry, applique les filtres communs (dose Custom, friction de
  /// continuité), délègue l'assemblage à la rule retenue. La logique
  /// mode-specific (durée, gating unlock, choix de position) vit dans
  /// `ModeRules.isRecoveryCandidate` / `buildRecovery`.
  ///
  /// Si le draft tiré échoue le gating unlock (mode pas encore
  /// débloqué), on dégrade en `tip → head` sur le mode
  /// `recoveryDegradeFallback` — dramaturgie hardcodée (positions
  /// imposées), seul le mode est mappable via le rôle. Cf. C.PR5.
  StepDraft buildRecoveryStep() {
    final bpm = 45 + rng.nextInt(14); // [45, 58]
    final dur = 10 + rng.nextInt(9); // [10, 18]
    // Convention `state.unlockedKeys.isEmpty` = mode hérité : pas de
    // gating, tous les modes opt-in passent par défaut.
    final avail = RecoveryAvailability(
      heritage: state.unlockedKeys.isEmpty,
      unlockedKeys: state.unlockedKeys,
      includeHand: config.includeHand,
    );
    final candidates = <SessionMode>[
      for (final entry in rules.entries)
        if (entry.value.isRecoveryCandidate(avail)) entry.key,
    ];
    // Exclusions Custom (dose `none`) : la recovery ne doit pas
    // ramener un mode que la joueuse a explicitement banni. Si tout
    // est exclu, on retombe sur `recoveryDegradeFallback` (lick
    // historique).
    candidates.removeWhere(config.isModeForbidden);
    if (candidates.isEmpty) candidates.add(_recoveryDegradeFallbackMode);
    final pool =
        ModePicker.filterRepeated(candidates, state.lastMode, rules: rules);
    // Tirage pondéré pour que la friction de continuité par type
    // s'applique aussi à la recovery (sans ça, une recovery uniforme
    // repousse souvent langue/libre alors que la séance vient juste
    // de quitter bouche).
    final mode = ModePicker.pickWeighted(
      pool,
      spec: config.spec,
      coachWeights: config.coachModeWeights,
      continuity: state.continuitySnapshot(),
      rng: rng,
      rules: rules,
    );
    final draft = rules[mode]!.buildRecovery(RecoveryCtx(
      gen: facade,
      bpm: bpm,
      duration: dur,
    ));
    // Gating unlock : si le mode/draft tiré n'est pas encore débloqué
    // (ex : biffle avant niveau 5, beg libre avant niveau 3,
    // freestyle avant niveau 4), on dégrade.
    if (!isUnlocked(draft)) {
      return StepDraft(
        mode: _recoveryDegradeFallbackMode,
        bpm: bpm,
        from: Position.tip,
        to: Position.head,
        duration: dur,
      );
    }
    return draft;
  }
}
