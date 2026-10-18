part of 'session_controller.dart';

// Les champs d'état du flow restent sur `SessionController` : les extensions
// Dart ne portent pas de champs d'instance.

extension FailFlowOrchestrator on SessionController {
  bool _isFailFlowAlive(int gen) => _failActive && _failGen == gen;

  Future<void> triggerFail() async {
    if (!canTriggerFail) return;

    if (_music != null) {
      await _triggerMusicalFail();
      return;
    }

    if (isChallengeActive) {
      return;
    }

    _playedAtLastFail = playedElapsed;
    final endsUseMe = _useMeActive;
    if (endsUseMe) _useMeFailEndings++;
    await _endUseMe();

    // Ce qui suit rebat la timeline sans passer par `_exitBreak`.
    _breakActive = false;
    _activeBreak = null;

    // Les plafonds de session sont figés AVANT le callback : la régénération
    // lit des `capabilitySessionCeilings` à jour (`onFail` est idempotent).
    if (_isInMilestoneWindow() && onMilestoneRetry != null) {
      _capabilityTracker?.onFail();
      final handled = await onMilestoneRetry!(this);
      if (handled) return;
    }

    if (_state == SessionState.failing && _failPhase == FailPhase.punishment) {
      _abandonPunishment();
      return;
    }

    _failActive = true;
    final myGen = ++_failGen;
    _finishMusicStarted = false;
    unawaited(_ambience.fadeOutFinishMusic(
        duration: const Duration(milliseconds: 600)));
    _hadFailThisSession = true;
    _stamina.onFail();
    _saliva.onFail();
    _capabilityTracker?.onFail();
    _swallowMode = SwallowMode.allowed;
    final lastMinuteMul = _isInLastMinute() ? 2.0 : 1.0;
    final missedMilestone = _milestoneOpportunityMissed();
    _obedience.onFail(
      multiplier: lastMinuteMul,
      milestoneOpportunityMissed: missedMilestone,
    );
    _humiliation.onFail(
      multiplier: lastMinuteMul,
      milestoneOpportunityMissed: missedMilestone,
    );
    _punishmentAbandoned = false;
    _currentHoldFullDuration = 0;
    _disarmHoldVerifier();

    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    // Borné : ticker et chronomètre sont déjà arrêtés, un canal de synthèse muet
    // figerait la séance en `running` sans recours.
    await _stopTtsBounded();
    _dropPendingSpeech();
    await _beep.pause();

    _state = SessionState.failing;

    try {
      _failPhase = FailPhase.phrase;
      // On résout immédiatement : le contenu stocké dans `_currentFailPhrase`
      // est la version affichable (sans `{name}`). Le speak qui suit est
      // alors un pass-through pour le placeholder déjà absent.
      final swallowPool = _punishmentBundle.failPhrasesSwallow;
      final usingSwallowPool =
          _swallowMode == SwallowMode.forbidden && swallowPool.isNotEmpty;
      final pool =
          usingSwallowPool ? swallowPool : _punishmentBundle.failPhrases;
      final tapoutPhrase = usingSwallowPool ? null : _tapoutPhraseOrNull();
      final raw = tapoutPhrase ?? _pickRandom(pool);
      _currentFailPhrase = raw == null ? null : _tts.resolveText(raw);
      _notify();
      if (_currentFailPhrase != null) {
        // Borné : un moteur qui ne rappelle jamais figerait la séance en `failing`.
        _lastScriptedSpeakAt = DateTime.now();
        await _speakBounded(_currentFailPhrase!);
      }
      if (!_isFailFlowAlive(myGen)) return;

      _failPhase = FailPhase.breath;
      _notify();
      final stamina = _staminaAtNow();
      final isFresh = stamina != null &&
          stamina > SessionController._breathSkipStaminaThreshold;
      final breathSeconds =
          isFresh ? (3 + _random.nextInt(3)) : (8 + _random.nextInt(8));
      await _beep.applyStep(
        SessionStep(
          time: 0,
          mode: SessionMode.breath,
          duration: breathSeconds,
        ),
        session.defaultMode,
      );
      await _syncAmbienceToCurrentMode();
      await _waitInterruptible(Duration(seconds: breathSeconds), gen: myGen);
      if (!_isFailFlowAlive(myGen)) return;

      _currentPunishment = _generateCareerPunishmentOrNull() ??
          _pickRandom(_punishmentBundle.punishments);
      _failPhase = FailPhase.punishment;
      _notify();
      if (_currentPunishment != null) {
        await _runPunishment(_currentPunishment!);
        if (_isFailFlowAlive(myGen) && !_punishmentAbandoned) {
          _humiliation.onPunishmentCompleted();
          _obedience.onPunishmentCompleted();
        }
      }
      if (!_isFailFlowAlive(myGen)) return;

      final resumed = endsUseMe && await _resumeNormalSession();
      if (!_isFailFlowAlive(myGen)) return;

      await _leaveFailFlow(mayJump: !resumed, gen: myGen);
    } finally {
      // Ne nettoie le state global que si on est toujours owner du flow —
      // sinon on écraserait celui d'un nouveau triggerFail qui aurait pris
      // la main pendant l'un de nos awaits.
      if (_failGen == myGen) {
        _failPhase = null;
        _currentFailPhrase = null;
        _currentPunishment = null;
        _failActive = false;
        _notify();
      }
    }
  }

  Future<void> _leaveFailFlow({required bool mayJump, required int gen}) async {
    if (_appInBackground) {
      _deferredFailExit =
          (replayGen) => _completeFailExit(mayJump: mayJump, gen: replayGen);
      await _pauseAfterFail();
      return;
    }
    await _completeFailExit(mayJump: mayJump, gen: gen);
  }

  /// Rejoue la sortie retenue sous la garde d'un flow de fail : jusqu'à la fin
  /// de la restauration, `pause()` et un nouveau fail sont refusés.
  Future<void> _replayDeferredFailExit(
      Future<void> Function(int gen) exit) async {
    _failActive = true;
    final myGen = ++_failGen;
    _notify();
    try {
      await exit(myGen);
    } finally {
      if (_failGen == myGen) {
        _failActive = false;
        _notify();
      }
    }
  }

  Future<void> _completeFailExit(
      {required bool mayJump, required int gen}) async {
    final jumped = mayJump && _skipToNextSection();
    if (!jumped) {
      await _restorePreviousLoop();
      if (!_isFailFlowAlive(gen)) return;
      // `pause()` ignore l'arrière-plan tant que `_failActive` est vrai.
      if (_appInBackground) {
        await _pauseAfterFail();
        return;
      }
    }

    _stopwatch.start();
    _startTicker();
    _startRandomComments();
    _state = SessionState.running;
    // Coup de pouce immédiat : si on a sauté pile sur le `time` du
    // prochain step, on le déclenche tout de suite plutôt que d'attendre
    // le prochain tick (200 ms d'écart audible sinon).
    _checkSteps();
  }

  /// Horloge, ticker et commentaires sont déjà arrêtés depuis l'entrée du flow.
  Future<void> _pauseAfterFail() async {
    await _stopTtsBounded();
    await _beep.pause();
    await _ambience.pause();
    _state = SessionState.paused;
    _notify();
  }

  Future<void> _triggerMusicalFail() async {
    final track = session.music!;
    _hadFailThisSession = true;
    _playedAtLastFail = playedElapsed;
    _stamina.onFail();
    _saliva.onFail();
    _currentHoldFullDuration = 0;
    _disarmHoldVerifier();
    final breath = track.beatPeriod * SessionController._musicBreathBeats;
    _musicBreathUntil = elapsed + breath;
    _failPhase = FailPhase.breath;
    _notify();
    await _beep.applyStep(
      SessionStep(
        time: 0,
        mode: SessionMode.breath,
        duration: (breath.inMilliseconds / 1000).ceil(),
      ),
      session.defaultMode,
    );
  }

  void _endMusicBreath(int seconds) {
    _musicBreathUntil = null;
    _failPhase = null;
    SessionStep? last;
    for (final step in session.steps) {
      if (step.time > seconds) break;
      if (!step.isTextOnly) last = step;
    }
    if (last == null) return;
    final duration = last.duration;
    _lastConfigStep = last;
    _beep.applyStep(
      SessionStep(
        time: seconds,
        from: last.from,
        to: last.to,
        bpm: last.bpm,
        bpmEnd: last.bpmEnd,
        mode: last.mode,
        duration:
            duration == null ? null : max(1, last.time + duration - seconds),
      ),
      session.defaultMode,
    );
  }

  Future<void> _releaseMusic() async {
    _musicBreathUntil = null;
    final music = _music;
    if (music == null) return;
    _failPhase = null;
    await music.stop();
    _detachMusicFromBeep();
  }

  void _detachMusicFromBeep() {
    if (!_musicAttached) return;
    _musicAttached = false;
    _beep.detachMusic();
  }

  Future<void> _runPunishment(Punishment p) async {
    final previous = _punishmentCompleter;
    if (previous != null && !previous.isCompleted) {
      if (kDebugMode) {
        debugPrint(
            '[SessionController] _runPunishment ignoré : précédent encore actif');
      }
      return;
    }
    _punishmentTicker?.cancel();
    _punishmentTicker = null;

    final completer = Completer<void>();
    _punishmentCompleter = completer;
    final stopwatch = Stopwatch()..start();
    var nextIdx = 0;

    void tick() {
      // Si on n'est plus le completer en cours (un nouveau _runPunishment
      // a démarré), on stoppe ce tick fantôme sans toucher au state global.
      if (_punishmentCompleter != completer) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (!_failActive) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final s = stopwatch.elapsed.inSeconds;
      var modeChanged = false;
      while (nextIdx < p.steps.length && p.steps[nextIdx].time <= s) {
        final step = p.steps[nextIdx];
        if (!step.isTextOnly) {
          _beep.applyStep(step, session.defaultMode);
          modeChanged = true;
        }
        if (step.text.isNotEmpty) {
          // fire-and-forget — flutter_tts file les phrases consécutives
          _speakScripted(step.text);
        }
        nextIdx++;
      }
      if (modeChanged) {
        _syncAmbienceToCurrentMode();
        // L'écran ne relit le moteur que sur notification.
        _notify();
      }

      if (s >= p.durationSeconds) {
        _punishmentTicker?.cancel();
        _punishmentTicker = null;
        stopwatch.stop();
        if (!completer.isCompleted) completer.complete();
      }
    }

    tick(); // déclenche le step à t=0 sans attendre
    _punishmentTicker =
        Timer.periodic(SessionController._tickInterval, (_) => tick());

    await completer.future;
    // Ne nille le champ que si on est toujours owner (sinon on écraserait
    // la référence d'un appelant suivant qui aurait pris la main).
    if (_punishmentCompleter == completer) {
      _punishmentCompleter = null;
    }
    await _beep.stop();
  }

  void _abandonPunishment() {
    _punishmentAbandoned = true;
    final mul = _isInLastMinute() ? 2.0 : 1.0;
    _obedience.onPunishmentAbandoned(multiplier: mul);
    _humiliation.onPunishmentAbandoned(multiplier: mul);
    _punishmentTicker?.cancel();
    _punishmentTicker = null;
    final c = _punishmentCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  void _accrueMiniPunishmentTick() {
    if (_music != null) return;
    _miniPunishmentTickAccumulator++;
    if (_miniPunishmentTickAccumulator < 60) return;
    _miniPunishmentTickAccumulator = 0;
    if (_miniPunishmentRate <= 0) return;
    if (_isInMilestoneWindow()) return;
    if (_isInLastMinute()) return;
    final shouldFire = SessionController.computeMiniPunishmentTrigger(
      rate: _miniPunishmentRate,
      rngValue: _miniPunishmentRng.nextDouble(),
    );
    if (!shouldFire) return;
    final shortPool = _punishmentBundle.punishments
        .where((p) => p.durationSeconds < 20)
        .toList();
    if (shortPool.isEmpty) return;
    final p = shortPool[_miniPunishmentRng.nextInt(shortPool.length)];
    _miniPunishmentsTriggered++;
    unawaited(_runMiniPunishmentFlow(p));
  }

  Future<void> _runMiniPunishmentFlow(Punishment p) async {
    if (_state != SessionState.running) return;

    _failActive = true;
    final myGen = ++_failGen;
    _finishMusicStarted = false;
    unawaited(_ambience.fadeOutFinishMusic(
        duration: const Duration(milliseconds: 600)));
    _disarmHoldVerifier();
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    // Borné, comme `triggerFail` : ce flow est tiré sans action de l'utilisatrice.
    await _stopTtsBounded();
    _dropPendingSpeech();
    await _beep.pause();

    _state = SessionState.failing;
    _failPhase = FailPhase.punishment;
    _currentPunishment = p;
    _notify();

    try {
      await _runPunishment(p);
      if (_isFailFlowAlive(myGen) && !_punishmentAbandoned) {
        _humiliation.onPunishmentCompleted();
        _obedience.onPunishmentCompleted();
      }
      if (!_isFailFlowAlive(myGen)) return;
      await _leaveFailFlow(mayJump: false, gen: myGen);
    } finally {
      if (_failGen == myGen) {
        _failPhase = null;
        _currentPunishment = null;
        _punishmentAbandoned = false;
        _failActive = false;
        _notify();
      }
    }
  }

  Punishment? _generateCareerPunishmentOrNull() {
    final profile = _capabilityProfile;
    final bank = _phraseBank;
    if (profile == null || bank == null) return null;
    final generator = CareerSessionGenerator();
    return generator.generatePunishment(
      level: _careerLevel,
      bank: bank,
      unlockedKeys: _unlockedKeys,
      capability: CapabilityInputs(
        profile: profile,
        sessionCeilings: _capabilityTracker?.sessionCeilings ?? const {},
        overloadAxis: _capabilityOverloadAxis,
      ),
      specialization: _specialization,
      humiliationCareer: _humiliation.careerScore,
      humiliationSession: _humiliation.sessionScore,
      obedience: _obedience.score,
      includeHand: _includeHand,
    );
  }

  Future<void> _restorePreviousLoop() async {
    final last = _lastConfigStep;
    if (last == null) return;
    final applying = _beep.applyStep(last, session.defaultMode);
    _failPhase = null;
    _currentPunishment = null;
    _state = SessionState.running;
    _notify();
    await applying;
    _capabilityTracker?.onStepApplied(
      mode: last.mode ?? session.defaultMode,
      from: last.from,
      to: last.to,
      bpm: last.bpm,
      duration: last.duration,
    );
    await _syncAmbienceToCurrentMode();
  }

  bool _skipToNextSection() {
    final currentSec = elapsedSeconds;
    // Un défi ne s'arme que si l'horloge traverse sa fenêtre d'armement sous un
    // tick : le saut est borné à l'ouverture de cette fenêtre.
    final pendingTrigger = _nextPendingChallengeTrigger(currentSec);
    for (var i = _nextStepIndex; i < session.steps.length; i++) {
      final step = session.steps[i];
      if (!step.isTextOnly && step.time > currentSec) {
        if (pendingTrigger != null && step.time > pendingTrigger) break;
        final delta = step.time - currentSec;
        _timelineOffset += Duration(seconds: delta);
        _nextStepIndex = i;
        return true;
      }
    }
    return false;
  }

  int? _nextPendingChallengeTrigger(int fromSec) {
    final armable =
        min(session.challenges.length, session.challengeTriggerTimes.length);
    int? earliest;
    for (var i = 0; i < armable; i++) {
      if (_completedChallengeIndices.contains(i)) continue;
      final trigger = session.challengeTriggerTimes[i];
      if (trigger + kChallengeBreathDurationSeconds <= fromSec) continue;
      if (earliest == null || trigger < earliest) earliest = trigger;
    }
    return earliest;
  }

  Future<void> _waitInterruptible(Duration total, {required int gen}) async {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < total) {
      if (!_isFailFlowAlive(gen)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  T? _pickRandom<T>(List<T> items) {
    if (items.isEmpty) return null;
    return items[_random.nextInt(items.length)];
  }
}
