part of 'session_controller.dart';

// ─── Flow fail / punition ─────────────────────────────────────────────
//
// Tout ce qui se passe entre l'appui sur le bouton FAIL (ou un tick
// mini-punition coach) et la reprise de la timeline principale. Vit ici
// pour la cohésion physique :
//
//   triggerFail
//     ├─ phrase de fail (tier `tapout` si la limite est attribuée à
//     │  un axe poussé, sinon pool standard / pool swallow)
//     ├─ respiration (durée modulée par la stamina projetée)
//     ├─ punition (carrière contextuelle si profil dispo, sinon
//     │  tirage statique dans `punishments.json`)
//     └─ saut de section / restauration du loop précédent
//
//   _runMiniPunishmentFlow (déclenché par `_accrueMiniPunishmentTick`,
//   1× par minute, gaté par `Coach.miniPunishmentRate`) — variante
//   allégée : pas de phrase fail, pas de breath de récup, pas de saut
//   de section.
//
// Les champs d'état (`_failActive`, `_failGen`, `_failPhase`,
// `_currentFailPhrase`, `_currentPunishment`, `_punishmentCompleter`,
// `_punishmentTicker`, `_punishmentAbandoned`, compteurs mini-punition)
// restent sur `SessionController` (les extensions Dart ne portent pas de
// champs d'instance) ; les méthodes async qui les manipulent sont
// rassemblées ici sous forme d'extension `part of`.

extension FailFlowOrchestrator on SessionController {
  /// Prédicat « le flow fail courant est toujours le mien » : combine le
  /// flag `_failActive` (annulé par `stop()` global) et la génération
  /// (`_failGen`) pour qu'un await long ne reprenne pas la main si un
  /// nouveau `triggerFail` a démarré entre-temps.
  bool _isFailFlowAlive(int gen) => _failActive && _failGen == gen;

  /// Déclenche la séquence : pause → phrase fail → respiration → punition →
  /// reprise du loop session là où il était.
  ///
  /// Le bouton appelant doit vérifier [canTriggerFail] pour ne pas appeler
  /// cette méthode hors d'un état running.
  Future<void> triggerFail() async {
    if (!canTriggerFail) return;

    // Phase 1 défis — pendant un défi, le bouton FAIL classique est masqué
    // côté UI (cf. _ChallengeButtons remplace _FailButton). La sortie est
    // pilotée par le release du doigt : tolérance épuisée pendant
    // `countdown`/`live` = fail, release pendant `atSeuil` = succès, release
    // pendant `countdown` = retour breath / skipped (selon compteur). Si on
    // arrive ici malgré tout (debug, test, harness), on no-op : la machine
    // d'états défi a déjà son moteur dans `_updateChallengePhase`.
    if (isChallengeActive) {
      return;
    }

    // Retry milestone : si on rate dans la fenêtre pédagogique, on tente
    // d'abord de proposer une nouvelle tentative via le callback (qui
    // regénère + appelle requestUpgrade). Si le callback prend la main,
    // on saute entièrement le flow fail standard — pas de pénalités, pas
    // de phrase fail, pas de punition. La milestone est juste rejouée.
    //
    // Le profil de capacités, lui, voit ce fail : on fige les plafonds de
    // session AVANT le callback pour que la régénération du retry lise des
    // `capabilitySessionCeilings` à jour. `onFail` est idempotent (streaks
    // remis à 0), donc le ré-appel du flow standard plus bas (cas retry non
    // pris en charge) est sans effet.
    if (_isInMilestoneWindow() && onMilestoneRetry != null) {
      _capabilityTracker?.onFail();
      final handled = await onMilestoneRetry!(this);
      if (handled) return;
    }

    // Cas particulier : on est déjà dans le flow fail, en pleine punition
    // → on abandonne la punition (malus obéissance, pas de re-punition).
    if (_state == SessionState.failing && _failPhase == FailPhase.punishment) {
      _abandonPunishment();
      return;
    }

    _failActive = true;
    final myGen = ++_failGen;
    _hadFailThisSession = true;
    _stamina.onFail();
    _saliva.onFail();
    // Capacités : fige les plafonds de session sur la valeur live des
    // streaks, puis les vide — un streak interrompu par un fail ne devient
    // jamais un record propre (cf. §3/§6 de la spec).
    _capabilityTracker?.onFail();
    // Le mode forbidden est levé par le fail : la salope a craqué, on
    // repart sur des bases neutres. Si la session veut re-imposer le
    // forbidden après reprise, c'est au scénario de poser un step le
    // demandant explicitement.
    _swallowMode = SwallowMode.allowed;
    // Pénalités amplifiées si on craque dans la dernière minute (la
    // session est presque terminée — c'est ruiné). Cumulable avec ×2 si
    // une milestone candidate au niveau courant était présente et n'a pas
    // été acquittée : « tu pouvais avancer, tu as raté ». Au pire ×4.
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
    // Le hold full en cours est interrompu : pas de crédit Iron Lungs.
    _currentHoldFullDuration = 0;
    // Le hold éventuellement en cours est interrompu — disarm la caméra
    // pour ne pas spammer de rappels pendant la phrase de fail / breath.
    _disarmHoldVerifier();

    // 1) Mise en pause du timing principal et du loop courant.
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    // Borné : le ticker et le chronomètre sont déjà arrêtés, et `_state` ne
    // bascule qu'après. Sur un canal de synthèse muet, la séance resterait
    // `running` sans horloge ni ticker — un gel sans recours, sur le seul
    // contrôle de séance visible en production (play/pause/stop sont derrière
    // le toggle debug `showSessionControls`, off par défaut).
    await _stopTtsBounded();
    await _beep.pause();

    _state = SessionState.failing;

    try {
      // 2) Phrase de fail.
      _failPhase = FailPhase.phrase;
      // On résout immédiatement : le contenu stocké dans `_currentFailPhrase`
      // est la version affichable (sans `{name}`). Le speak qui suit est
      // alors un pass-through pour le placeholder déjà absent.
      // Si la salope a avalé alors que c'était interdit, on tire dans le
      // pool dédié `failPhrasesSwallow` (transgression de consigne) plutôt
      // que dans le pool générique. Fallback transparent au pool standard
      // si le pool dédié est vide (sécurité contre un JSON incomplet).
      final swallowPool = _punishmentBundle.failPhrasesSwallow;
      final usingSwallowPool =
          _swallowMode == SwallowMode.forbidden && swallowPool.isNotEmpty;
      final pool =
          usingSwallowPool ? swallowPool : _punishmentBundle.failPhrases;
      // Phase 4 — coach audible : si le « je peux pas » est imputable à un axe
      // poussé au-delà de sa zone de confort (§6, attribution non ambiguë grâce
      // à la surcharge isolée) et que le dé ∝ niveau tombe juste, on remplace la
      // phrase de fail standard par une variante DOUCE « limite reconnue » (tier
      // `tapout`). Jamais sur le pool « avalement interdit transgressé »
      // (indiscipline ≠ limite légitime).
      final tapoutPhrase = usingSwallowPool ? null : _tapoutPhraseOrNull();
      final raw = tapoutPhrase ?? _pickRandom(pool);
      _currentFailPhrase = raw == null ? null : _tts.resolveText(raw);
      _notify();
      if (_currentFailPhrase != null) {
        // awaitSpeakCompletion(true) → ce await retourne quand la phrase
        // est entièrement prononcée.
        _lastScriptedSpeakAt = DateTime.now();
        await _tts.speak(_currentFailPhrase!);
      }
      if (!_isFailFlowAlive(myGen)) return;

      // 3) Respiration : toujours présente comme phase de transition,
      //    mais raccourcie quand l'endurance projetée à l'instant t est
      //    confortable (pas besoin d'imposer une longue récup à
      //    quelqu'une qui n'en a pas besoin).
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

      // 4) Punition. En carrière, on génère une composition contextuelle
      //    bornée par le profil de capacités (§7 — Phase 5). Hors carrière
      //    (Custom, scénarios JSON), on retombe sur le tirage statique dans
      //    `punishments.json` — comportement historique.
      _currentPunishment = _generateCareerPunishmentOrNull() ??
          _pickRandom(_punishmentBundle.punishments);
      _failPhase = FailPhase.punishment;
      _notify();
      if (_currentPunishment != null) {
        await _runPunishment(_currentPunishment!);
        // Bonus seulement si la punition a été menée à terme (ni stop()
        // global, ni abandon volontaire via le bouton FAIL).
        if (_isFailFlowAlive(myGen) && !_punishmentAbandoned) {
          _humiliation.onPunishmentCompleted();
          _obedience.onPunishmentCompleted();
        }
      }
      if (!_isFailFlowAlive(myGen)) return;

      // 5) Saut à la section suivante : on cherche le prochain step de
      //    config et on avance la timeline jusqu'à son `time`. Tous les
      //    steps text-only intermédiaires sont consommés silencieusement.
      //    Si aucune section suivante n'existe, on restaure le loop d'avant
      //    le fail pour ne pas laisser la séance sans audio.
      final jumped = _skipToNextSection();
      if (!jumped) {
        await _restorePreviousLoop();
      }

      _stopwatch.start();
      _startTicker();
      _startRandomComments();
      _state = SessionState.running;
      // Coup de pouce immédiat : si on a sauté pile sur le `time` du
      // prochain step, on le déclenche tout de suite plutôt que d'attendre
      // le prochain tick (200 ms d'écart audible sinon).
      _checkSteps();
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

  /// Joue toutes les étapes d'une punition selon leur `time` relatif,
  /// jusqu'à atteindre [Punishment.durationSeconds]. Interruptible via
  /// `_abandonPunishment()` (qui complète `_punishmentCompleter`).
  Future<void> _runPunishment(Punishment p) async {
    // Refuse les appels concurrents : si un précédent est encore actif,
    // c'est un état incohérent (les flows fail/mini-punition s'attendent
    // tous via await). On ne ré-entre pas ; le caller verra un retour
    // immédiat et la séquence en cours continuera son cycle.
    final previous = _punishmentCompleter;
    if (previous != null && !previous.isCompleted) {
      if (kDebugMode) {
        debugPrint(
            '[SessionController] _runPunishment ignoré : précédent encore actif');
      }
      return;
    }
    // Annule un ticker éventuellement orphelin pour ne pas le superposer.
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
    await _beep.stop(); // coupe les bips de la punition avant de continuer
  }

  /// Interrompt la punition en cours (déclenché par un appui sur FAIL
  /// pendant la phase punishment). Pénalité d'obéissance, pas de
  /// re-punition pour éviter la spirale.
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

  /// Tick mini-punition : 1 tirage par minute. Si le coach a un
  /// `miniPunishmentRate` > 0 et que l'état autorise une mini-punition (pas
  /// en milestone, pas dernière minute, pas en finish), tente de déclencher
  /// `_runMiniPunishmentFlow`. Pas de garde sur `_state == running` ici
  /// — `_accrueHoldSecond` ne s'appelle que sous le ticker, qui ne tourne
  /// que pendant `running`.
  void _accrueMiniPunishmentTick() {
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
    // Fire-and-forget : on ne bloque pas le ticker.
    unawaited(_runMiniPunishmentFlow(p));
  }

  /// Joue une mini-punition inopinée déclenchée par le tick coach.
  /// Variante allégée du flow fail : pas de phrase fail, pas de breath de
  /// récup, pas de saut de section. On enchaîne directement la punition
  /// puis on restaure le loop précédent.
  Future<void> _runMiniPunishmentFlow(Punishment p) async {
    if (_state != SessionState.running) return;

    _failActive = true;
    final myGen = ++_failGen;
    _disarmHoldVerifier();
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    // Borné, même schéma que `triggerFail` — et plus insidieux ici : ce flow
    // est tiré automatiquement (~1 fois par minute en carrière selon
    // `Coach.miniPunishmentRate`), donc la séance pourrait progresser
    // normalement puis se figer sans aucune action de l'utilisatrice.
    await _stopTtsBounded();
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
      await _restorePreviousLoop();
      _stopwatch.start();
      _startTicker();
      _startRandomComments();
      _state = SessionState.running;
      _checkSteps();
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

  /// Génère une punition carrière contextuelle (Phase 5, §7) via
  /// `CareerSessionGenerator.generatePunishment`. Renvoie `null` hors
  /// carrière (pas de profil de capacités ou pas de banque coach) — le
  /// caller retombe alors sur le tirage statique dans `punishments.json`.
  ///
  /// On reconstruit un générateur à la volée (pas d'état conservé entre
  /// fails) : la classe est suffisamment légère, le `Random()` interne
  /// suffit pour la variation et on évite de propager une référence partagée
  /// avec la chaîne de génération de session principale.
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

  /// Restaure le loop de bips qui tournait avant le fail (ou no-op
  /// si aucune étape de config n'avait encore été appliquée).
  Future<void> _restorePreviousLoop() async {
    final last = _lastConfigStep;
    if (last == null) return;
    await _beep.applyStep(last, session.defaultMode);
    _capabilityTracker?.onStepApplied(
      mode: last.mode ?? session.defaultMode,
      from: last.from,
      to: last.to,
      bpm: last.bpm,
      duration: last.duration,
    );
    await _syncAmbienceToCurrentMode();
  }

  /// Cherche la prochaine étape avec configuration de bip (i.e. le début
  /// d'une nouvelle « section ») strictement après [elapsedSeconds]. Si
  /// trouvée, avance [_timelineOffset] pour faire correspondre l'horloge
  /// effective à son `time`, et place [_nextStepIndex] dessus. Les éventuels
  /// steps text-only entre la position courante et la nouvelle section
  /// sont sautés silencieusement.
  ///
  /// Retourne true si un saut a eu lieu, false si on est déjà dans la
  /// dernière section (pas de saut effectué).
  bool _skipToNextSection() {
    final currentSec = elapsedSeconds;
    for (var i = _nextStepIndex; i < session.steps.length; i++) {
      final step = session.steps[i];
      if (!step.isTextOnly && step.time > currentSec) {
        final delta = step.time - currentSec;
        _timelineOffset += Duration(seconds: delta);
        _nextStepIndex = i;
        return true;
      }
    }
    return false;
  }

  /// Délai annulable : si [_failActive] passe à false pendant l'attente
  /// — ou si la génération a changé (un nouveau flow fail nous a remplacés)
  /// — on retourne immédiatement.
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
