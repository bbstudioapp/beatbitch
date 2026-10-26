part of 'session_controller.dart';

// Les champs d'état et `buildPostChallengeRegenSession` restent sur la
// classe : une extension Dart ne porte ni champ d'instance ni membre statique.

extension CareerHooksOrchestrator on SessionController {
  bool get hasPendingBadges => _pendingBadgeUnlocks.isNotEmpty;

  /// Suppose `CapabilityTracker.onFail()` déjà appelé (`sessionCeilings` à jour).
  String? _tapoutPhraseOrNull() {
    final tracker = _capabilityTracker;
    final profile = _capabilityProfile;
    final bank = _phraseBank;
    if (tracker == null || profile == null || bank == null) return null;
    final axis =
        CapabilityRegulator.attributeTapOut(tracker.sessionCeilings, profile);
    if (axis == null) return null;
    if (_random.nextDouble() >=
        CapabilityRegulator.progressPhraseChanceForLevel(_careerLevel)) {
      return null;
    }
    final phrase = bank.pickProgressPhrase(axis.storageKey, 'tapout', _random);
    return (phrase != null && phrase.isNotEmpty) ? phrase : null;
  }

  CapabilityAxis? _detectCapabilityRecord(SessionCapabilityReport? report) {
    if (report == null || _hadFailThisSession) return null;
    final axis = _capabilityOverloadAxis;
    final profile = _capabilityProfile;
    if (axis == null || profile == null) return null;
    if (!axis.pilotant || axis.recordKind != CapabilityRecordKind.maximize) {
      return null;
    }
    final reached = report.reached[axis];
    if (reached == null) return null;
    final before = profile.bestOf(axis);
    return (before == null || reached > before) ? axis : null;
  }

  Future<void> revealBadgeUnlocks() async {
    if (_pendingBadgeUnlocks.isEmpty) return;
    final unlocks = _pendingBadgeUnlocks;
    _pendingBadgeUnlocks = const [];
    _sessionBadgeUnlocks = unlocks;
    _notify();
    final l10n = _appLocalizations;
    if (l10n == null) return;
    for (final u in unlocks) {
      if (_released) break;
      await _tts.speak(u.announcement(l10n));
    }
  }

  /// `upcomingSession.steps[*].time` partent de 0 : la méthode les rebase.
  Future<void> requestUpgrade({
    required SessionStep insistentBeg,
    required Session upcomingSession,
    bool useMe = false,
  }) async {
    if (_state != SessionState.running) return;

    final start = elapsedSeconds;
    if (useMe) {
      _useMeActive = true;
      _useMeStartedPlayed = playedElapsed;
    }

    _session = SessionController.buildUpgradedSession(
      previous: _session,
      upcoming: upcomingSession,
      insistentBeg: insistentBeg,
      start: start,
      useMe: useMe,
    );

    // Borné : le ticker tourne, un canal TTS muet laisserait `_onTick` lire la
    // nouvelle `_session` avec l'ancien `_nextStepIndex`.
    await _stopTtsBounded();
    _dropPendingSpeech();

    _nextStepIndex = 0;
    _lastConfigStep = null;
    // `breaks` vide fait sortir `_updateBreakPhase` tôt : sans cette clôture,
    // `_breakActive` resterait à true et l'effort serait gelé.
    _breakActive = false;
    _activeBreak = null;
    _nextBreakIndex = 0;
    // La nouvelle suite porte son propre final : son chime doit pouvoir jouer.
    _finalChimePlayed = false;
    _finaleChimeStarted = false;

    _checkSteps();
    _notify();
  }

  Future<bool> _resumeNormalSession() async {
    final upcoming = await onUseMeEnded?.call(this);
    if (upcoming == null) return false;
    _session = SessionController.buildUpgradedSession(
      previous: _session,
      upcoming: upcoming,
      start: elapsedSeconds,
    );
    _nextStepIndex = 0;
    // `_restorePreviousLoop` rejouerait sinon la dernière boucle d'escalade.
    _lastConfigStep = null;
    _breakActive = false;
    _activeBreak = null;
    _nextBreakIndex = 0;
    _finalChimePlayed = false;
    _finaleChimeStarted = false;
    return true;
  }

  /// `upcomingSession.steps[*].time` partent de 0 : la méthode les rebase.
  /// Ni `_checkSteps()` ni arrêt du TTS : le souffle post-défi est en cours.
  Future<void> requestPostChallengeRegen({
    required Session upcomingSession,
  }) async {
    if (_state != SessionState.running || _useMeActive) return;
    // Défi excisé et chrono gelé pendant le souffle : `elapsedSeconds` en est
    // déjà la fin.
    final breathEnd = elapsedSeconds;
    // Horloge gelée : `elapsedSeconds` vaut le déclencheur ou une seconde de
    // moins selon l'instant de la régénération ; `playedUntil` ne varie pas.
    final triggers = _session.challengeTriggerTimes;
    final playedUntil =
        _activeChallengeIndex >= 0 && _activeChallengeIndex < triggers.length
            ? triggers[_activeChallengeIndex]
            : null;
    _session = SessionController.buildPostChallengeRegenSession(
      previous: _session,
      upcoming: upcomingSession,
      breathEnd: breathEnd,
      playedUntil: playedUntil,
    );

    _nextStepIndex = 0;
    _lastConfigStep = null;
    _dropPendingSpeech();
    // Même clôture que `requestUpgrade` : `_breakActive` resterait coincé.
    _breakActive = false;
    _activeBreak = null;
    _nextBreakIndex = 0;
    // La nouvelle suite porte son propre final : son chime doit pouvoir jouer.
    _finalChimePlayed = false;
    _finaleChimeStarted = false;

    _notify();
  }
}
