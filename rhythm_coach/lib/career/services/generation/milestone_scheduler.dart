// Library autonome — orchestration de l'insertion des milestones
// **body** dans la séance.
//
// `generate()` reçoit jusqu'à 2 milestones body (`insertedBodies`) +
// éventuellement une milestone finale (`finalMilestone`, gérée à
// part). Chaque body milestone vise une **fenêtre** `[minInsert,
// maxInsert]` avec une `targetTime` cible (par défaut 30 % / 65 % de
// la durée pour la 1ʳᵉ / 2ᵉ). Le générateur ouvre l'insertion dès que
// `time` atteint la target, ou en urgence dès que `time >= maxInsert`
// (pour ne pas la louper si la chauffe traîne).
//
// Ce scheduler porte tout l'état + les 3 points d'entrée de la boucle :
//   * [insertIntroReplacement] — cas spécial où la milestone unique
//     a `insertAtMinSeconds <= 0` et joue le rôle de step #0.
//   * [tryInsertAt] — phase 1 du main loop : insère si la fenêtre
//     est ouverte au tps courant, sinon null.
//   * [insertAllRemaining] — drain post-loop : force l'insertion
//     de toute pending non encore posée (cas sessions très courtes
//     ou genUntil bas qui n'ont pas atteint la fenêtre).
//
// Le bookkeeping `bodyStartTime` / `bodyDurationSeconds` (1ʳᵉ et 2ᵉ)
// est exposé en getters, consommé par `_assembleResult` côté caller.
//
// Sortie du `part of 'career_session_generator.dart'` historique en
// D.PR6 du plan de refacto. Les 2 dépendances d'instance (mutation de
// `_state.unlockedKeys` + appel à `_pushMilestoneSequence`) sont
// threadées par référence et callback au constructeur.

import 'dart:math';

import '../../models/level_milestone.dart';
import 'generation_context.dart';
import 'session_runtime_state.dart';

/// Signature du callback `pushMilestoneSequence` : émet la séquence
/// d'une milestone au temps courant, retourne `(newTime, newStamina)`.
/// L'implémentation vit côté `CareerSessionGenerator`
/// (`_pushMilestoneSequence`) — le scheduler ne réimplémente pas la
/// logique d'émission, il décide juste **quand** déclencher.
typedef PushMilestoneSequence = ({int time, double stamina}) Function(
  GenerationContext ctx, {
  required LevelMilestone milestone,
  required int time,
  required double stamina,
});

/// État mutable d'une milestone body en attente d'insertion dans la séance.
/// Le scheduler traite la liste dans l'ordre — chaque insertion repousse
/// la `minInsert` de la suivante pour conserver un buffer ≥ 60 s.
class _PendingMilestoneInsert {
  final LevelMilestone milestone;
  int minInsert;
  int maxInsert;
  int targetTime;
  bool inserted = false;

  _PendingMilestoneInsert({
    required this.milestone,
    required this.minInsert,
    required this.maxInsert,
    required this.targetTime,
  });
}

/// Orchestre l'insertion des milestones body dans `generate()`. Construit
/// une fois en début de séance, consommé par 3 points d'entrée (intro
/// replacement / main loop phase 1 / post-loop drain).
///
/// Mute le state du générateur en injectant les unlocks acquis dans
/// `state.unlockedKeys` après chaque insertion. Tient aussi le
/// bookkeeping `bodyStartTime` / `bodyDurationSeconds` consommé par
/// `_assembleResult` côté caller.
class MilestoneScheduler {
  final SessionRuntimeState _state;
  final PushMilestoneSequence _pushMilestoneSequence;
  final List<_PendingMilestoneInsert> _pending;

  /// Instant de démarrage de la 1ʳᵉ milestone body acquittée
  /// (`null` tant qu'aucune n'a été posée). Consommé par `_assembleResult`
  /// pour exposer la fenêtre milestone côté `SessionController`.
  int? bodyStartTime;

  /// Durée de la 1ʳᵉ milestone body acquittée.
  int? bodyDurationSeconds;

  /// Instant de démarrage de la 2ᵉ milestone body acquittée (sessions
  /// longues uniquement, cf. `career_screen.dart`).
  int? secondBodyStartTime;

  /// Durée de la 2ᵉ milestone body acquittée.
  int? secondBodyDurationSeconds;

  MilestoneScheduler._(this._state, this._pushMilestoneSequence, this._pending);

  /// Construit le scheduler depuis la liste `insertedBodies`. Pré-calcule
  /// `[minInsert, maxInsert]` + `targetTime` par milestone selon les
  /// fractions par défaut (0.30 / 0.40 pour la 1ʳᵉ, 0.65 / 0.75 pour la
  /// 2ᵉ), surchargeables via `m.insertAtMinSeconds` / `m.insertAtMaxSeconds`.
  factory MilestoneScheduler.fromBodies({
    required SessionRuntimeState state,
    required PushMilestoneSequence pushMilestoneSequence,
    required List<LevelMilestone> bodies,
    required int effectiveDuration,
  }) {
    final pending = <_PendingMilestoneInsert>[];
    for (var i = 0; i < bodies.length; i++) {
      final m = bodies[i];
      final defaultMaxFraction = i == 0 ? 0.40 : 0.75;
      final defaultTargetFraction = i == 0 ? 0.30 : 0.65;
      final maxInsert = m.insertAtMaxSeconds ??
          (effectiveDuration * defaultMaxFraction).round();
      final minInsert = m.insertAtMinSeconds ?? 60;
      final target = (effectiveDuration * defaultTargetFraction).round();
      pending.add(_PendingMilestoneInsert(
        milestone: m,
        minInsert: minInsert,
        maxInsert: maxInsert,
        targetTime: target.clamp(minInsert, maxInsert),
      ));
    }
    return MilestoneScheduler._(state, pushMilestoneSequence, pending);
  }

  /// Cas spécial : la **seule** milestone body acquittée a
  /// `insertAtMinSeconds <= 0` et doit donc remplacer le step #0
  /// d'intro classique. Incompatible avec deux body milestones
  /// (deux à t=0 n'a pas de sens).
  bool get replacesIntro =>
      _pending.length == 1 && _pending.first.minInsert <= 0;

  /// Insère la 1ʳᵉ pending en remplacement du step #0. Le caller doit
  /// avoir vérifié [replacesIntro]. Idempotent (no-op si déjà posée).
  ({int time, double stamina}) insertIntroReplacement(
    GenerationContext ctx, {
    required int time,
    required double stamina,
  }) {
    return _insertAt(ctx, 0, time: time, stamina: stamina);
  }

  /// Phase 1 du main loop : insère la prochaine milestone si `time`
  /// a atteint sa `targetTime` OU sa `maxInsert` (urgence). Renvoie
  /// `null` quand aucune insertion n'est due (laisser la boucle main
  /// continuer son tirage normal).
  ({int time, double stamina})? tryInsertAt(
    GenerationContext ctx, {
    required int time,
    required double stamina,
  }) {
    final nextIdx = _nextPendingIndex();
    if (nextIdx < 0) return null;
    final p = _pending[nextIdx];
    if (time < p.targetTime && time < p.maxInsert) return null;
    return _insertAt(ctx, nextIdx, time: time, stamina: stamina);
  }

  /// Drain post-loop : force l'insertion de toute pending non encore
  /// posée. Cas rare (sessions courtes / `genUntil` faible après le
  /// first step) — on ne veut pas perdre une milestone silencieusement.
  ({int time, double stamina}) insertAllRemaining(
    GenerationContext ctx, {
    required int time,
    required double stamina,
  }) {
    for (var idx = 0; idx < _pending.length; idx++) {
      if (!_pending[idx].inserted) {
        final r = _insertAt(ctx, idx, time: time, stamina: stamina);
        time = r.time;
        stamina = r.stamina;
      }
    }
    return (time: time, stamina: stamina);
  }

  /// Index de la prochaine pending non encore posée (−1 si tout est
  /// fait). Scan linéaire sur ≤ 2 éléments — pas de structure plus
  /// élaborée nécessaire.
  int _nextPendingIndex() {
    for (var idx = 0; idx < _pending.length; idx++) {
      if (!_pending[idx].inserted) return idx;
    }
    return -1;
  }

  /// Cœur d'insertion partagé par les 3 entry points. Marque la pending
  /// posée, pousse la séquence via [_pushMilestoneSequence], met à jour
  /// le bookkeeping `bodyStartTime` / `bodyDurationSeconds`, étend les
  /// unlocks dans `_state.unlockedKeys`, et recale le `minInsert` de
  /// la pending suivante (buffer ≥ 60 s).
  ({int time, double stamina}) _insertAt(
    GenerationContext ctx,
    int index, {
    required int time,
    required double stamina,
  }) {
    final p = _pending[index];
    if (p.inserted) return (time: time, stamina: stamina);
    p.inserted = true;
    final startedAt = time;
    final result = _pushMilestoneSequence(
      ctx,
      milestone: p.milestone,
      time: time,
      stamina: stamina,
    );
    time = result.time;
    stamina = result.stamina;
    if (index == 0) {
      bodyStartTime = startedAt;
      bodyDurationSeconds = p.milestone.durationSeconds;
    } else {
      secondBodyStartTime = startedAt;
      secondBodyDurationSeconds = p.milestone.durationSeconds;
    }
    // Réutilisation post-acquittement : les unlocks de la milestone
    // deviennent disponibles pour les steps générés APRÈS la séquence
    // (corps restant, pré-finisher, boosts, final). On suppose succès au
    // runtime — sur fail la session est replanifiée par le contrôleur, ce
    // qui régénère un set d'unlocks cohérent.
    if (p.milestone.unlocks.isNotEmpty) {
      _state.unlockedKeys = {
        ..._state.unlockedKeys,
        ...p.milestone.unlocks,
      };
    }
    // Recale le min de la prochaine pending : `m.endTime + 60s` buffer
    // (sinon les 2 séquences pédagogiques s'enchaînent sans souffle).
    if (index + 1 < _pending.length) {
      final nextMin = time + 60;
      final next = _pending[index + 1];
      next.minInsert = max(next.minInsert, nextMin);
      // Si le buffer pousse au-delà du maxInsert de la 2ᵉ, on le repousse
      // pour laisser l'insertion se faire (relâchement plutôt que skip).
      if (next.minInsert > next.maxInsert) {
        next.maxInsert = next.minInsert + p.milestone.durationSeconds;
      }
      next.targetTime = next.targetTime.clamp(next.minInsert, next.maxInsert);
    }
    return (time: time, stamina: stamina);
  }
}
