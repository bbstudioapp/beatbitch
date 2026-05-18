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
import '../../models/career_level.dart';
import '../../models/phrase_bank.dart';
import '../../models/unlock_key.dart';
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
  })  : _breathMode = _resolveRole(rules, ModeSemanticRole.breath),
        _postWaveBreathMode =
            _resolveRole(rules, ModeSemanticRole.postWaveBreath),
        _swallowOrderMode = _resolveRole(rules, ModeSemanticRole.swallowOrder);

  final SessionConfig config;
  final SessionRuntimeState state;
  final Random rng;
  final Map<SessionMode, ModeRules> rules;

  /// Modes résolus une fois à la construction pour éviter d'itérer le
  /// registre à chaque appel.
  final SessionMode _breathMode;
  final SessionMode _postWaveBreathMode;
  final SessionMode _swallowOrderMode;

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
}
