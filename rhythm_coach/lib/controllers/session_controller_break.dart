part of 'session_controller.dart';

// ─── Break scénarisé ──────────────────────────────────────────────────────
//
// Pause active de récup. Le générateur a déjà laissé un *trou d'effort*
// dans l'enveloppe (aucun step entre `break.time` et `break.endTime`) ; le
// runtime se contente de geler le moteur d'effort sur cette fenêtre et de
// jouer une dramaturgie de récup :
//
//   entrée  → pause du beep + phrase « on souffle »
//   pendant → ordres espacés (« bois une gorgée », « respire »…)
//   reprise → application de la nouvelle posture + phrase de changement de
//             pose (ou phrase de reprise neutre), puis le step d'effort posé
//             par le générateur juste après le trou reconfigure le beep.
//
// Contrairement au flow fail, l'horloge `elapsed` continue de tourner : la
// machine est donc pilotée par tick (`_updateBreakPhase`, appelée dans
// `_onTick`), sans flow async. Les extensions Dart ne portant pas de champs,
// l'état vit sur `SessionController`.

extension BreakSequencer on SessionController {
  /// Pilote la machine du break à chaque tick. Entrée dans la fenêtre du
  /// prochain break, énoncé des ordres espacés en cours, sortie à
  /// `break.endTime`. No-op si la session n'a pas de break.
  void _updateBreakPhase() {
    final breaks = _session.breaks;
    if (breaks.isEmpty) return;
    final now = elapsedSeconds;

    if (_breakActive) {
      final b = _activeBreak!;
      if (now >= b.endTime) {
        _exitBreak(b);
      } else {
        _maybeFireBreakOrder();
      }
      return;
    }

    if (_nextBreakIndex >= breaks.length) return;
    final next = breaks[_nextBreakIndex];
    if (now >= next.endTime) {
      // Fenêtre déjà entièrement dépassée (cas dégénéré : saut de timeline,
      // bouton debug). On ne gèle pas après coup — on jette ce break.
      _nextBreakIndex++;
      return;
    }
    if (now >= next.time) {
      _enterBreak(next);
    }
  }

  /// Entrée dans un break : gèle le loop d'effort (pause beep + disarm caméra)
  /// et énonce la phrase d'entrée. `_breakActive` coupe l'accrual d'effort et
  /// les commentaires aléatoires (cf. `_onTick` / `_fireRandomComment`).
  void _enterBreak(ScriptedBreak b) {
    _breakActive = true;
    _activeBreak = b;
    _nextBreakIndex++;
    _breakOrderLastAtSec = elapsedSeconds;
    _breakOrderInterval = _pickBreakOrderInterval();
    _disarmHoldVerifier();
    unawaited(_beep.pause());
    final entry = _phraseBank?.pickBreakEntry(_random);
    if (entry != null) _speakScripted(entry);
    _notify();
  }

  /// Énonce un ordre de break si l'intervalle est écoulé et que le TTS est
  /// libre. Les ordres viennent du pool global `break_orders` (jamais
  /// « tiens/hold/halten » — réservés au pool hold).
  void _maybeFireBreakOrder() {
    final bank = _phraseBank;
    if (bank == null) return;
    final now = elapsedSeconds;
    if (now - _breakOrderLastAtSec < _breakOrderInterval) return;
    if (_tts.isSpeaking) return;
    final order = bank.pickBreakOrder(_random);
    if (order == null) return;
    _breakOrderLastAtSec = now;
    _breakOrderInterval = _pickBreakOrderInterval();
    _speakScripted(order);
  }

  /// Passe la pause en cours : saute la timeline à sa fin et enchaîne sur la
  /// reprise. No-op hors pause.
  void skipBreak() {
    final b = _activeBreak;
    if (!_breakActive || b == null) return;
    final end = Duration(seconds: b.endTime);
    if (elapsed < end) _timelineOffset += end - elapsed;
    _exitBreak(b);
  }

  /// Déclenche le prochain changement de position seul : annonce, coupure du
  /// bip et attente de mise en place. Le step posé à `change.time` relance
  /// l'effort après la validation ; si un saut de timeline l'a déjà consommé,
  /// le changement est abandonné plutôt que de laisser la séance muette.
  void _updatePostureChange() {
    final changes = _session.postureChanges;
    if (_nextPostureChangeIndex >= changes.length) return;
    if (isTimelineFrozen || _failActive) return;
    final change = changes[_nextPostureChangeIndex];
    if (elapsedSeconds < change.time) return;
    _nextPostureChangeIndex++;
    final steps = _session.steps;
    if (_nextStepIndex >= steps.length ||
        steps[_nextStepIndex].time > change.time) {
      return;
    }
    _currentPose = change.pose;
    _disarmHoldVerifier();
    unawaited(_beep.pause());
    final phrase = _phraseBank?.pickPostureChange(change.pose, _random);
    if (phrase != null) _speakScripted(phrase);
    _enterAwaitReady();
  }

  /// Tire un intervalle d'ordre dans [min, max] (cadence irrégulière).
  int _pickBreakOrderInterval() =>
      SessionController._breakOrderMinIntervalSeconds +
      _random.nextInt(SessionController._breakOrderMaxIntervalSeconds -
          SessionController._breakOrderMinIntervalSeconds +
          1);

  /// Sortie d'un break : applique la nouvelle posture, énonce la phrase de
  /// changement de pose (ou de reprise neutre en récup pure), et relâche
  /// `_breakActive`. Le beep n'est PAS restauré ici : `_checkSteps` (appelé
  /// juste après dans `_onTick`) applique le step d'effort que le générateur
  /// a posé à `break.endTime`, ce qui reconfigure et relance le loop à
  /// l'heure ; sa propre phrase attend la fin de la phrase de reprise.
  void _exitBreak(ScriptedBreak b) {
    _breakActive = false;
    _activeBreak = null;
    final newPose = b.newPose;
    if (newPose != null) _currentPose = newPose;
    final bank = _phraseBank;
    final resume = newPose != null
        ? (bank?.pickPostureChange(newPose, _random) ??
            bank?.pickBreakResume(_random))
        : bank?.pickBreakResume(_random);
    if (resume != null) _speakScripted(resume);
    // Gate posture : si le break impose une nouvelle posture
    // physique, on gèle la reprise jusqu'à ce que la joueuse s'y mette (comme
    // le 1er step des milestones posture). `free` = pas de repositionnement,
    // pas de gate.
    if (newPose != null && newPose != Posture.free) {
      _enterAwaitReady();
    }
    _notify();
  }

  /// Met à jour `_currentPose` quand la fenêtre d'une **milestone posture**
  /// est active : la séquence enseigne la pose (« mets-toi à
  /// genoux… ») et l'`unlock` la débloque, mais rien ne posait la pose sur
  /// l'écran de jeu. On la fixe dès l'entrée dans la fenêtre — et on la
  /// **garde** ensuite (le script dit « reste à genoux »), comme un break qui
  /// impose une pose durable. Appelée dans `_onTick` après `_updateBreakPhase`
  /// (fenêtres disjointes) et avant `_checkSteps`.
  void _updateMilestonePose() {
    final id = currentMilestoneIdInWindow;
    if (id == null) return;
    final pose = postureTaughtByMilestone(id);
    if (pose != null && pose != _currentPose) {
      _currentPose = pose;
    }
  }
}
