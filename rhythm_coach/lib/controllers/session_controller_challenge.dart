part of 'session_controller.dart';

// ─── Défi intra-séance (Phase 1) ───────────────────────────────────────
//
// Machine d'états pilotée par les transitions de phase suivantes :
//   none → breath (entrée dans le step breath de countdown)
//   breath → live (entrée dans le step défi)
//   live → preExtend (à `seuil - 3 s`)
//   live | preExtend → atSeuil (au seuil cible)
//   atSeuil → openExtension (JE TIENS ENCORE)
//   atSeuil → ended (JE M'ARRÊTE ou timeout 8 s)
//   openExtension → atSeuil (prolongation expirée → re-prompt)
//   * → ended (FAIL pendant le défi, selon phase)
//
// Au passage en `ended`, `_challengeOutcome` est figé et le `_finish` de
// session applique les bumps capability/humil/obed correspondants.
//
// Les **champs** d'état du défi vivent toujours sur `SessionController`
// (les extensions Dart ne peuvent pas porter de champs d'instance). Les
// getters dérivés et toute la logique sont rassemblés ici sous forme
// d'extension `part of` — même unité de compilation, même accès aux
// membres privés, juste un meilleur regroupement physique.

/// Timeout en secondes pour le mini countdown post-seuil (`atSeuil`)
/// avant le déclenchement automatique d'un succès net (cf. spec § 4.3).
const int _challengeSeuilTimeoutSeconds = 8;

/// Durée fixe du countdown 3-2-1 en secondes. Dit en TTS immédiatement
/// après l'appui sur le bouton `GO` (plus d'auto-trigger : le défi
/// attend une action manuelle — `GO` ou `PASSE` — pendant le breath).
const int _challengeCountdownDurationSec = 3;

/// Durée du breath de récup post-défi (toutes voies). Donne au coach
/// le temps de faire son rapport et à la joueuse de souffler avant
/// que la séance ne reprenne.
const int _postChallengeBreathSeconds = 10;

/// Snapshot d'un défi complété — sert à appliquer les bumps humil/obed
/// au `_finish` quand plusieurs défis ont tourné dans la même séance
/// (Phase 19.5.b multi-défi).
class _CompletedChallengeRecord {
  final Challenge challenge;
  final ChallengeOutcome outcome;
  final int extensionsCount;

  const _CompletedChallengeRecord({
    required this.challenge,
    required this.outcome,
    required this.extensionsCount,
  });
}

extension ChallengeOrchestrator on SessionController {
  // ─── Getters de champ (lectures publiques) ──────────────────────────

  ChallengePhase get challengePhase => _challengePhase;
  int get challengeExtensionsCount => _challengeExtensionsCount;
  ChallengeOutcome? get challengeOutcome => _challengeOutcome;
  String? get challengeCurrentText => _challengeCurrentText;
  Challenge? get activeChallenge => _activeChallenge;
  int? get challengeCountdownStartedAtSec => _challengeCountdownStartedAtSec;

  // ─── Getters dérivés ────────────────────────────────────────────────

  /// Chiffre du mini countdown affiché pendant `atSeuil` (compte à
  /// rebours du timeout 8 s du stop auto). `null` hors phase atSeuil.
  /// Sert au banner UI pour matérialiser le « tu peux continuer si tu
  /// veux » en compte à rebours visible avant le stop auto.
  int? get challengeSeuilCountdownDigit {
    if (_challengePhase != ChallengePhase.atSeuil) return null;
    final start = _challengeAtSeuilStartedAtSec;
    if (start == null) return null;
    final elapsed = _realSec.toInt() - start;
    final remaining = _challengeSeuilTimeoutSeconds - elapsed;
    if (remaining < 0) return 0;
    if (remaining > _challengeSeuilTimeoutSeconds) {
      return _challengeSeuilTimeoutSeconds;
    }
    return remaining;
  }

  /// `true` quand un step défi est en cours et qu'un appui sur le bouton
  /// FAIL ne doit PAS déclencher le flow fail standard mais être routé vers
  /// la machine d'états défi (cf. spec § 4.4 — bouton FAIL repurposé).
  bool get isChallengeActive =>
      _challengePhase != ChallengePhase.none &&
      _challengePhase != ChallengePhase.ended;

  bool get _inPostChallengeBreath {
    final until = _postChallengeBreathRealEndSec;
    return until != null && _realSec.toInt() < until;
  }

  /// Instant `elapsedSeconds` auquel la séance reprend après le défi —
  /// utilisé par `requestPostChallengeRegen` pour rebaser une suite
  /// régénérée. Vu que la session a déjà été rebasée en interne par
  /// `_excisChallengeFromSession` (le défi est excisé de la timeline),
  /// c'est simplement `elapsedSeconds` (= la position où on était avant
  /// le défi). `null` hors fenêtre post-défi.
  int? get postChallengeBreathUntilSec =>
      _inPostChallengeBreath ? elapsedSeconds : null;

  /// Chiffre courant du countdown (3, 2, 1) ou `null` si on n'est pas en
  /// phase countdown. Exposé pour le banner UI qui affiche le chiffre
  /// en grand. Lit `_realSec` (wallclock brut) pour rester insensible
  /// au freeze de la timeline session.
  int? get challengeCountdownDigit {
    if (_challengePhase != ChallengePhase.countdown) return null;
    final start = _challengeCountdownStartedAtSec;
    if (start == null) return null;
    final elapsedInCountdown = _realSec.toInt() - start;
    final digit = _challengeCountdownDurationSec - elapsedInCountdown;
    if (digit < 1 || digit > _challengeCountdownDurationSec) return null;
    return digit;
  }

  // ─── Machine d'états & helpers ──────────────────────────────────────

  /// Libellé de fallback localisé pour un tier donné, quand le coach
  /// n'a pas de `challengePhrases` rédigée pour cet axe. Évite que la
  /// joueuse se retrouve sans annonce / sans feedback visuel pendant
  /// les transitions de phase défi.
  String? _fallbackChallengeText(Challenge ch, String tier) {
    final l10n = _appLocalizations;
    if (l10n == null) return null;
    switch (tier) {
      case 'attempt':
        // Tutoriel hold throat = annonce dédiée plus pédagogique.
        if (ch.isTutorial && ch.axis == CapabilityAxis.holdThroatStreak) {
          return l10n.challengeAttemptTutorialHoldThroat;
        }
        return l10n.challengeAttemptDefault;
      case 'extension':
        return l10n.challengeExtensionDefault;
      case 'success':
        return l10n.challengeSuccessDefault;
      case 'stop':
        return l10n.challengeStopDefault;
      case 'fail':
        return l10n.challengeFailDefault;
      case 'timeout':
        return l10n.challengeTimeoutDefault;
      case 'skip':
        return l10n.challengeSkipDefault;
      default:
        return null;
    }
  }

  /// Libellé d'objectif du défi (ex. « Tiens gorge 10 secondes ») —
  /// affiché en sous-titre du banner UI pendant `live`/`preExtend` pour
  /// rappeler à la joueuse ce qu'elle doit faire. Pas dit en TTS (la
  /// coach a déjà fait l'annonce pendant le breath).
  String? challengeObjectiveText() {
    final ch = _activeChallenge;
    final l10n = _appLocalizations;
    if (ch == null || l10n == null) return null;
    switch (ch.kind) {
      case ChallengeAxisKind.duration:
        if (ch.axis == CapabilityAxis.holdThroatStreak ||
            ch.axis == CapabilityAxis.gorgeApneeStreak ||
            ch.axis == CapabilityAxis.gorgeEngagementStreak) {
          return l10n.challengeBannerHoldThroat(ch.targetThreshold);
        }
        if (ch.axis == CapabilityAxis.holdFullStreak) {
          return l10n.challengeBannerHoldFull(ch.targetThreshold);
        }
        if (ch.mode == SessionMode.hold) {
          return l10n.challengeBannerHoldGeneric(ch.targetThreshold);
        }
        return l10n.challengeBannerGeneric;
      case ChallengeAxisKind.bpm:
        if (ch.mode == SessionMode.biffle) {
          return l10n.challengeBannerBiffle(ch.targetThreshold);
        }
        return l10n.challengeBannerRhythm(ch.targetThreshold);
      case ChallengeAxisKind.depthCran:
        return l10n.challengeBannerGeneric;
    }
  }

  /// Tick de mise à jour de la machine d'états défi. Drivée par
  /// `elapsedSeconds` vs `session.challengeBreathStartTime` /
  /// `challengeStepTime` : ne dépend plus de la consommation des steps
  /// (qui peut être différée par le TTS ou interrompue par un fail), ce
  /// qui rendait la transition `breath → live` peu fiable. Appelée dans
  /// `_onTick` à chaque tick (200 ms).
  void _updateChallengePhase() {
    if (_session.challenges.isEmpty) return;
    final phase = _challengePhase;
    // Phase 19.5.b — Reset post-breath du défi précédent : quand le breath
    // post-défi est fini, on rebascule en `none` pour permettre l'armement
    // du défi suivant (s'il en reste un dans `_session.challenges`).
    if (phase == ChallengePhase.ended && !_inPostChallengeBreath) {
      _activeChallenge = null;
      _activeChallengeIndex = -1;
      _challengeOutcome = null;
      _challengeExtensionsCount = 0;
      _challengeStepStartedAtSec = null;
      _challengeAtSeuilStartedAtSec = null;
      _challengeOpenExtensionDeadlineSec = null;
      _challengeCountdownStartedAtSec = null;
      _challengeCountdownLastDigitSpoken = -1;
      _challengeCurrentText = null;
      _challengeSpokenText = null;
      _challengePhase = ChallengePhase.none;
    }
    final t = elapsedSeconds;
    // Entrée en phase `breath` (annonce coach + boutons PASSE / GO visibles).
    // À partir de ce moment, la timeline est gelée par `_onTick` jusqu'à
    // l'action joueuse (GO ou PASSE) — plus d'auto-trigger countdown.
    if (_challengePhase == ChallengePhase.none) {
      // Cherche le prochain défi à armer : index `i` non encore acquitté
      // dont le breath time est atteint mais le step pas encore démarré.
      for (var i = 0; i < _session.challenges.length; i++) {
        if (_completedChallengeIndices.contains(i)) continue;
        final breathStart = _session.challengeBreathStartTimes[i];
        final stepStart = _session.challengeStepTimes[i];
        if (t < breathStart || t >= stepStart) continue;
        final ch = _session.challenges[i];
        _activeChallengeIndex = i;
        _activeChallenge = ch;
        _challengePhase = ChallengePhase.breath;
        _challengeCurrentText = _pickChallengePhrase(ch, 'attempt') ??
            _fallbackChallengeText(ch, 'attempt');
        _speakChallengePhraseIfAny();
        return;
      }
      return;
    }
    final ch = _activeChallenge;
    if (ch == null) return;
    final stepStart = _activeChallengeIndex >= 0
        ? _session.challengeStepTimes[_activeChallengeIndex]
        : null;
    if (stepStart == null) return;
    // À partir d'ici, on mesure les durées internes sur `_realSec`
    // (`_stopwatch.elapsed` brut). La timeline session est freezée pendant
    // le défi (`_onTick`) ; utiliser `elapsedSeconds` ferait stagner toutes
    // les transitions et la phase live ne basculerait jamais.
    final r = _realSec.toInt();
    // Phase `countdown` : dire 3-2-1 en TTS et passer à `live` à 3 s.
    if (_challengePhase == ChallengePhase.countdown) {
      final countdownStart = _challengeCountdownStartedAtSec;
      if (countdownStart != null) {
        final elapsedInCountdown = r - countdownStart;
        _maybeSpeakCountdownDigit(elapsedInCountdown);
        if (elapsedInCountdown >= _challengeCountdownDurationSec) {
          _challengePhase = ChallengePhase.live;
          _challengeStepStartedAtSec = r;
          _challengeCurrentText = null;
          _challengeSpokenText = null;
          _challengeCrossingsCount = 0;
          _applyChallengeStepNow(stepStart);
        }
      }
      return;
    }
    // À partir d'ici, on est forcément après le step défi (phase live,
    // preExtend, atSeuil, ou openExtension). Calcul du temps écoulé
    // dans le step défi pour piloter les transitions vers le seuil.
    if (_challengeStepStartedAtSec == null) return;
    final elapsedInStep = r - _challengeStepStartedAtSec!;
    final target = ch.targetThreshold;
    // Phase `openExtension` : la prolongation expire → re-prompt au seuil.
    if (phase == ChallengePhase.openExtension) {
      final deadline = _challengeOpenExtensionDeadlineSec;
      if (deadline != null && r >= deadline) {
        _challengePhase = ChallengePhase.atSeuil;
        _challengeAtSeuilStartedAtSec = r;
        _challengeOpenExtensionDeadlineSec = null;
      }
      return;
    }
    // Phase `atSeuil` : surveille le timeout 8 s (succès net auto).
    if (phase == ChallengePhase.atSeuil) {
      final seuilAt = _challengeAtSeuilStartedAtSec;
      if (seuilAt != null && r - seuilAt >= _challengeSeuilTimeoutSeconds) {
        _completeChallenge(ChallengeOutcome.netSuccess, byTimeout: true);
      }
      return;
    }
    // Phases `live` / `preExtend`. Pour tous les axes, on calque le seuil
    // de fin sur la durée nominale du step défi (= `targetThreshold` pour
    // les axes durée, fenêtre fixe 45 s/20 s pour BPM/profondeur).
    final stepEnd = ch.kind == ChallengeAxisKind.duration
        ? target
        : ch.nominalDurationSeconds;
    // Quand le défi pilote par franchissements (axes franchissement gorge),
    // le compteur de crossings peut court-circuiter la durée nominale.
    // L'annonce d'extension reste calée sur la durée pour les défis durée
    // / BPM standards ; sur un défi crossings, on l'annonce 2 franchissements
    // avant le seuil (équivalent dramaturgique des « 3 s avant la fin »).
    final crossingsTarget = ch.targetCrossings;
    final crossingsReached =
        crossingsTarget != null && _challengeCrossingsCount >= crossingsTarget;
    final crossingsPreExtend = crossingsTarget != null &&
        _challengeCrossingsCount >= crossingsTarget - 2 &&
        _challengeCrossingsCount < crossingsTarget;
    // Annonce coach « tu peux rester si tu veux » 3 s avant la fin
    // nominale — tous axes (BPM/profondeur inclus). L'exploratoire reste
    // exclu : il n'a pas de seuil cible, l'annonce d'extension n'a pas
    // de sens (cf. spec § 3.2).
    if (!ch.isExploratory &&
        phase == ChallengePhase.live &&
        ((crossingsTarget == null &&
                elapsedInStep >= stepEnd - 3 &&
                elapsedInStep < stepEnd) ||
            crossingsPreExtend)) {
      _challengePhase = ChallengePhase.preExtend;
      _challengeCurrentText = _pickChallengePhrase(ch, 'extension') ??
          _fallbackChallengeText(ch, 'extension');
      _speakChallengePhraseIfAny();
    }
    if (crossingsReached ||
        SessionController.shouldEnterAtSeuilPhase(
          phase: phase,
          elapsedInStep: elapsedInStep,
          stepEnd: stepEnd,
        )) {
      _challengePhase = ChallengePhase.atSeuil;
      // Wallclock (`r`) et non `t` : la timeline session est freezée pendant
      // tout le défi (cf. `_onTick` qui décrémente `_timelineOffset`), donc
      // `t` accuse l'écart accumulé depuis le breath du défi. Mesurer le
      // timeout 8 s du seuil (`r - seuilAt`) contre `t` fait déclencher le
      // timeout immédiatement à la bascule — les boutons « Je tiens » /
      // « J'arrête » apparaissent et disparaissent en un tick avant que la
      // joueuse n'ait le temps de cliquer.
      _challengeAtSeuilStartedAtSec = r;
    }

    // Retry passif de la phrase défi en attente : si la transition
    // `none → breath` (ou `live → preExtend`) a posé `_challengeCurrentText`
    // mais que le TTS était occupé (random comment, phrase scriptée d'un
    // step précédent), `_speakChallengePhraseIfAny` a skip et la phrase
    // n'est jamais prononcée. À chaque tick, si une phrase défi non-encore
    // dite est en attente et que le TTS s'est libéré, on la dit maintenant.
    if (_challengeCurrentText != null &&
        _challengeCurrentText != _challengeSpokenText) {
      _speakChallengePhraseIfAny();
    }
  }

  /// Bouton `PASSE` pendant le breath du défi — skip le défi entier.
  /// Outcome `skipped` (malus obed -3, aucun signal capability). Le skip
  /// du step défi est fait par `_completeChallenge` via
  /// `_startPostChallengeBreath` (qui appelle aussi `_skipPastChallengeStep`).
  void triggerChallengePass() {
    if (_challengePhase != ChallengePhase.breath) return;
    _completeChallenge(ChallengeOutcome.skipped);
  }

  /// Bouton `GO` pendant le breath du défi — démarre le countdown 3-2-1
  /// immédiatement. La joueuse contrôle son rythme : dès qu'elle est prête,
  /// elle tape `GO` et 3 s plus tard le step défi démarre. La timeline
  /// session est freezée pendant tout le défi : le countdown est mesuré
  /// sur `_realSec` (cf. `_updateChallengePhase`).
  void triggerChallengeGo() {
    if (_challengePhase != ChallengePhase.breath) return;
    if (_activeChallengeIndex < 0) return;
    // Le step défi est encore dans `session.steps` à
    // `time = challengeStepTimes[_activeChallengeIndex]`, mais `_checkSteps`
    // est freezé sur la timeline gelée — on l'applique donc manuellement
    // à l'entrée `live` (cf. `_updateChallengePhase`) et on avance
    // `_nextStepIndex` past lui.
    _enterChallengeCountdown();
    _notify();
  }

  /// Bascule en phase `countdown` (3-2-1 TTS + UI). Le chiffre TTS est
  /// énoncé par `_updateChallengePhase` à chaque seconde via
  /// `_maybeSpeakCountdownDigit`.
  ///
  /// Coupe le TTS en cours : si la phrase d'annonce du défi (`attempt`,
  /// posée à l'entrée en `breath`) est encore en train d'être prononcée
  /// au moment où la joueuse tape GO, le countdown skipperait les
  /// chiffres tant que `_tts.isSpeaking` (cf. `_maybeSpeakCountdownDigit`).
  /// On préfère arrêter net la phrase pour que « 3-2-1 » s'enchaîne
  /// proprement (la phrase a déjà eu sa fenêtre d'écoute pendant le breath).
  void _enterChallengeCountdown() {
    if (_challengePhase != ChallengePhase.breath) return;
    unawaited(_tts.stop());
    _challengePhase = ChallengePhase.countdown;
    _challengeCountdownStartedAtSec = _realSec.toInt();
    _challengeCountdownLastDigitSpoken = -1;
    _challengeCurrentText = null;
    _challengeSpokenText = null;
  }

  /// Énonce le chiffre courant du countdown en TTS si on ne l'a pas
  /// déjà fait pour cette seconde. Skip si le TTS est déjà occupé (le
  /// coach finit peut-être encore sa phrase d'annonce du défi).
  void _maybeSpeakCountdownDigit(int elapsedInCountdown) {
    final digit = _challengeCountdownDurationSec - elapsedInCountdown;
    if (digit < 1 || digit > _challengeCountdownDurationSec) return;
    if (_challengeCountdownLastDigitSpoken == digit) return;
    _challengeCountdownLastDigitSpoken = digit;
    if (_tts.isSpeaking) return;
    _speakScripted(digit.toString(), trackForDisplay: false);
  }

  /// Bouton `JE TIENS ENCORE` — bascule en mode ouvert, +1 humil/+1 obed
  /// par extension, deadline `max(10, comfort × 0.30)` s.
  void triggerChallengeExtend() {
    if (_challengePhase != ChallengePhase.atSeuil) return;
    final ch = _activeChallenge;
    if (ch == null) return;
    _challengeExtensionsCount++;
    _challengePhase = ChallengePhase.openExtension;
    _challengeAtSeuilStartedAtSec = null;
    _challengeOpenExtensionDeadlineSec = _realSec.toInt() + ch.extensionSeconds;
    _notify();
  }

  /// Bouton `JE M'ARRÊTE` — succès net (ou étendu si extensions > 0).
  void triggerChallengeStop() {
    if (_challengePhase != ChallengePhase.atSeuil &&
        _challengePhase != ChallengePhase.openExtension) {
      return;
    }
    final outcome = _challengeExtensionsCount > 0
        ? ChallengeOutcome.extendedSuccess
        : ChallengeOutcome.netSuccess;
    _completeChallenge(outcome);
  }

  /// Termine le défi et fige l'outcome. Les bumps capability/humil/obed
  /// sont appliqués au `_finish` de session (cf. `_applyChallengeOutcome`).
  /// Enchaîne sur un breath de récup de 10 s : le step défi est skippé
  /// dans la timeline, le BeepEngine joue un breath, le coach fait son
  /// rapport (`stop`/`fail`/`timeout`/`success`/`skip`). Pendant ce
  /// breath, `_checkSteps` ne consomme pas le step suivant — la séance
  /// "marque une pause" et la joueuse souffle.
  void _completeChallenge(ChallengeOutcome outcome, {bool byTimeout = false}) {
    if (_challengePhase == ChallengePhase.ended) return;
    _challengeOutcome = outcome;
    _challengePhase = ChallengePhase.ended;
    final ch = _activeChallenge;
    // Marque ce défi comme acquitté pour qu'il ne soit pas re-armé après
    // le reset post-breath (cf. `_updateChallengePhase`). Push aussi
    // dans l'historique pour permettre l'application des bumps multi-défi
    // au `_finish`.
    if (_activeChallengeIndex >= 0) {
      _completedChallengeIndices.add(_activeChallengeIndex);
    }
    if (ch != null) {
      _completedChallenges.add(_CompletedChallengeRecord(
        challenge: ch,
        outcome: outcome,
        extensionsCount: _challengeExtensionsCount,
      ));
    }
    if (ch != null) {
      final tier = switch (outcome) {
        ChallengeOutcome.fail => 'fail',
        ChallengeOutcome.netSuccess => byTimeout ? 'timeout' : 'stop',
        ChallengeOutcome.extendedSuccess => 'success',
        ChallengeOutcome.skipped => 'skip',
      };
      _challengeCurrentText =
          _pickChallengePhrase(ch, tier) ?? _fallbackChallengeText(ch, tier);
      _speakChallengePhraseIfAny();
      // Crédite directement le tracker capability de la valeur prouvée
      // par le défi. Indispensable parce que la timeline est freezée
      // pendant le défi (`_timelineOffset` décrémenté à chaque tick),
      // donc `_accrueHoldSecond` skipe systématiquement et le streak
      // (`_holdThroat` etc.) ne s'incrémente jamais. Sans ce crédit
      // explicite, `holdThroatStreak.best` reste null après le défi
      // tuto, `reconcileFromCapability` n'a rien à acquitter en
      // cascade et la joueuse continue de se taper des hold head en
      // session 2/3 alors qu'elle a tenu gorge.
      if (outcome == ChallengeOutcome.netSuccess ||
          outcome == ChallengeOutcome.extendedSuccess) {
        final reachedDuration = ch.targetThreshold +
            _challengeExtensionsCount * ch.extensionSeconds;
        final double reached;
        switch (ch.kind) {
          case ChallengeAxisKind.duration:
            reached = reachedDuration.toDouble();
            break;
          case ChallengeAxisKind.bpm:
            reached = (ch.bpmEnd ?? ch.bpm ?? ch.targetThreshold).toDouble();
            break;
          case ChallengeAxisKind.depthCran:
            reached = ch.targetThreshold.toDouble();
            break;
        }
        _capabilityTracker?.recordChallengeReached(ch.axis, reached);
      }
    }
    _startPostChallengeBreath();
    _notify();
    // Acquittement silencieux des milestones + consume showcase
    // **immédiatement après le défi**, pas au `_finish`. Sinon les
    // unlocks débloqués par le défi ne s'appliquent qu'à la séance
    // suivante (et la joueuse pense que son succès n'a rien changé).
    // Fire-and-forget : la persistance shared_preferences n'a pas besoin
    // de bloquer le retour de session vers la timeline.
    unawaited(_finalizeChallengeAcquittals());
    // Notifie le caller pour qu'il incrémente le compteur d'essais sur
    // l'axe (consommé par `crossingsTargetForAttempts` au défi suivant).
    if (ch != null) {
      onChallengeOutcome?.call(ch, outcome);
    }
  }

  /// Étape asynchrone post-défi : acquitte les milestones dont la capacité
  /// est satisfaite (cascade transitive — cf. spec § 5.4), consomme la
  /// tête de la file showcase si la branche du défi matche, et met à jour
  /// le set d'unlocks runtime du contrôleur pour que les filtres restants
  /// de la session (random comments, génération de punition carrière) en
  /// tiennent compte. Pas idempotente sur l'outcome bumps humil/obed —
  /// ceux-ci restent posés en fin de `_finish` via `_applyChallengeOutcome`.
  Future<void> _finalizeChallengeAcquittals() async {
    final beforeUnlocks = Set<UnlockKey>.from(_unlockedKeys);
    await _acquitMilestonesViaChallenge();
    await _consumeShowcaseIfMatched();
    final updated = milestoneService.acquiredUnlockKeys();
    final expanded = updated.length != beforeUnlocks.length ||
        !updated.containsAll(beforeUnlocks);
    if (!expanded) return;
    _unlockedKeys = Set<UnlockKey>.from(updated);
    _notify();
    // Le set d'unlocks vient de s'élargir : prévenir le caller pour qu'il
    // régénère la suite de la séance avec les nouveaux unlocks. La timeline
    // existante a été composée au start avec l'ancien set — sans regen, la
    // suite ne consomme pas la compétence fraîchement débloquée. Si le
    // caller ne câble pas le callback (sessions hors carrière, tests), on
    // se contente de la mise à jour runtime ci-dessus (filtres random
    // comments / punition carrière).
    final cb = onPostChallengeRegen;
    if (cb == null) return;
    if (_state != SessionState.running) return;
    await cb(this);
  }

  /// Lance le breath de récup : excise la fenêtre défi de la timeline
  /// session (le défi n'a jamais consommé de temps de séance), applique
  /// un step breath sur le BeepEngine, et arme la fin du breath en
  /// wallclock. La timeline reste freezée pendant tout le breath
  /// (cf. `_onTick`), donc le breath lui-même ne consomme rien non plus.
  void _startPostChallengeBreath() {
    _excisChallengeFromSession();
    _postChallengeBreathRealEndSec =
        _realSec.toInt() + _postChallengeBreathSeconds;
    // Applique le breath sur le BeepEngine — coupe le loop du défi
    // (hold/rhythm/biffle) en faveur du sample breath. Pas de
    // reconfiguration de mode "officielle" (`_lastConfigStep` reste
    // celui du step défi, restauré naturellement quand le step suivant
    // sera consommé après expiration du breath).
    if (!_released) {
      _beep.applyStep(
        const SessionStep(
          time: 0,
          mode: SessionMode.breath,
          duration: _postChallengeBreathSeconds,
        ),
        session.defaultMode,
      );
      _syncAmbienceToCurrentMode();
    }
  }

  /// Applique manuellement le step défi (à l'entrée `live`) au BeepEngine.
  /// Le step défi est dans `session.steps` à `time = challengeStepTime`,
  /// mais la timeline session est freezée pendant le défi, donc
  /// `_checkSteps` ne le consommerait jamais naturellement. On le pose
  /// nous-mêmes (BeepEngine bascule en rythme/hold/biffle) puis on
  /// avance `_nextStepIndex` past lui pour qu'à la reprise de session
  /// (post-breath fini), `_checkSteps` consomme directement le step
  /// suivant naturel — sinon le step défi se rejouerait après le breath.
  void _applyChallengeStepNow(int stepStartTime) {
    final steps = _session.steps;
    for (var i = _nextStepIndex; i < steps.length; i++) {
      final s = steps[i];
      if (s.time != stepStartTime) continue;
      if (s.isTextOnly) continue;
      _beep.applyStep(s, _session.defaultMode);
      _configApplied = true;
      _lastConfigStep = s;
      if (!_session.noStats) {
        _stats.markModeUsed(s.mode ?? _session.defaultMode);
      }
      _capabilityTracker?.onStepApplied(
        mode: s.mode ?? _session.defaultMode,
        from: s.from,
        to: s.to,
        bpm: s.bpm,
        duration: s.duration,
      );
      _armHoldVerifierIfHoldStep(s);
      _syncAmbienceToCurrentMode();
      _nextStepIndex = i + 1;
      return;
    }
  }

  /// Excise la fenêtre défi (breath d'annonce + step défi) de la timeline
  /// session, en décalant tous les steps suivants ainsi que les
  /// timestamps de fin (`durationSeconds`, `finalStepTime`,
  /// `silentFinishStartTime`, milestones) de `-shift`. À l'issue,
  /// l'`elapsedSeconds` courant (= `challengeBreathStartTime`, gelé
  /// pendant le défi) coïncide exactement avec la position du step qui
  /// suivait le défi dans l'ancienne timeline : la séance reprend
  /// **immédiatement** là où elle en était avant le défi, sans saut
  /// visible du timer.
  ///
  /// `shift = (challengeStepTime - challengeBreathStartTime) +
  /// nominalDurationSeconds` (≈ 23 s pour le tuto : 13 s de breath
  /// d'annonce + 10 s de step). Les steps qui tombaient dans la fenêtre
  /// défi sont droppés (ils ont déjà été joués manuellement : le breath
  /// par `_checkSteps` à l'entrée en phase `breath`, le step défi par
  /// `_applyChallengeStepNow` à l'entrée `live`).
  ///
  /// No-op silencieux si `challengeBreathStartTime` ou `challengeStepTime`
  /// est `null` (cas `PASSE` immédiat où le défi n'a pas été matérialisé
  /// — la fenêtre reste vide dans la timeline mais aucun temps n'a été
  /// consommé puisque le freeze s'arrête dès `phase == ended`).
  void _excisChallengeFromSession() {
    if (_activeChallengeIndex < 0) return;
    if (_activeChallengeIndex >= _session.challengeBreathStartTimes.length) {
      return;
    }
    final breathStart =
        _session.challengeBreathStartTimes[_activeChallengeIndex];
    final stepStart = _session.challengeStepTimes[_activeChallengeIndex];
    final stepDur = _activeChallenge?.nominalDurationSeconds;
    if (stepDur == null) return;
    final shift = (stepStart - breathStart) + stepDur;
    if (shift <= 0) return;
    final endOfChallenge = stepStart + stepDur;

    int? shiftLate(int? t) {
      if (t == null) return null;
      if (t < endOfChallenge) return t;
      return t - shift;
    }

    final newSteps = <SessionStep>[];
    for (final s in _session.steps) {
      if (s.time >= breathStart && s.time < endOfChallenge) {
        // Step de la fenêtre défi : déjà joué manuellement, on le drop.
        continue;
      }
      if (s.time < breathStart) {
        newSteps.add(s);
        continue;
      }
      newSteps.add(SessionStep(
        time: s.time - shift,
        text: s.text,
        mode: s.mode,
        from: s.from,
        to: s.to,
        bpm: s.bpm,
        bpmEnd: s.bpmEnd,
        duration: s.duration,
        chainAction: s.chainAction,
        swallowMode: s.swallowMode,
        background: s.background,
      ));
    }

    _session = Session(
      id: _session.id,
      name: _session.name,
      description: _session.description,
      durationSeconds: _session.durationSeconds - shift,
      defaultMode: _session.defaultMode,
      steps: newSteps,
      intro: _session.intro,
      lang: _session.lang,
      milestoneId: _session.milestoneId,
      milestoneStartTime: shiftLate(_session.milestoneStartTime),
      milestoneDurationSeconds: _session.milestoneDurationSeconds,
      secondMilestoneId: _session.secondMilestoneId,
      secondMilestoneStartTime: shiftLate(_session.secondMilestoneStartTime),
      secondMilestoneDurationSeconds: _session.secondMilestoneDurationSeconds,
      finalMilestoneId: _session.finalMilestoneId,
      finalMilestoneStartTime: shiftLate(_session.finalMilestoneStartTime),
      finalMilestoneDurationSeconds: _session.finalMilestoneDurationSeconds,
      finalCategory: _session.finalCategory,
      silentFinishStartTime: shiftLate(_session.silentFinishStartTime),
      finalStepTime: shiftLate(_session.finalStepTime),
      noStats: _session.noStats,
      // L'excise du défi en cours retire ses 2 steps (breath + défi) de
      // la timeline et shifte tout ce qui est après. On préserve la liste
      // complète des défis, mais on shifte les trigger times des défis
      // suivants (ceux après `endOfChallenge`) pour qu'ils restent
      // synchronisés avec la nouvelle timeline.
      // `_completedChallengeIndices` côté controller garantit que les
      // défis déjà acquittés (le défi excisé inclus) ne se ré-arment pas.
      challenges: _session.challenges,
      challengeBreathStartTimes: [
        for (final t in _session.challengeBreathStartTimes) shiftLate(t)!,
      ],
      challengeStepTimes: [
        for (final t in _session.challengeStepTimes) shiftLate(t)!,
      ],
    );

    // Recalcule `_nextStepIndex` : pointe vers le premier step à venir
    // (= `step.time > elapsedSeconds`). Le step défi ayant été excisé,
    // l'index original ne référence plus la bonne position.
    _nextStepIndex = 0;
    for (var i = 0; i < newSteps.length; i++) {
      if (newSteps[i].time > elapsedSeconds) break;
      _nextStepIndex = i + 1;
    }
  }

  String? _pickChallengePhrase(Challenge ch, String tier) {
    final bank = _phraseBank;
    if (bank == null) return null;
    return bank.pickChallengePhrase(ch.axisStorageKey, tier, _random);
  }

  void _speakChallengePhraseIfAny() {
    final text = _challengeCurrentText;
    if (text == null || text.isEmpty) return;
    if (text == _challengeSpokenText) return;
    if (_tts.isSpeaking) return;
    _challengeSpokenText = text;
    _speakScripted(text);
  }

  /// Applique les bumps liés à l'outcome du défi. Appelé depuis `_finish`
  /// après les bumps humil/obed standards mais avant `_capabilities.commit`.
  /// - `netSuccess` : humil/obed +2 (l'incrément capability passe par le
  ///   tracker qui voit le step défi comme un step normal).
  /// - `extendedSuccess` : netSuccess + N × (+1 humil, +1 obed).
  /// - `fail` : pas de malus humil/obed (cf. spec § 5.3). Le soft-cap
  ///   capability × 0.92 n'est pas distinct du standard pour Phase 1
  ///   (TODO : extension `CapabilityRegulator`) ; le tracker pose déjà un
  ///   ceiling via les FAILs séance, qui plafonnera l'axe naturellement.
  /// - `skipped` : malus obédiance -3, pas de signal capability.
  ///
  /// TODO Phase 1.5 : consume la tête de file showcase si la branche du
  /// défi matche (dépend de la branche `feat/specialization-showcase-queue`).
  /// Phase 3 défis — scanne le catalogue de milestones pour acquitter
  /// silencieusement celles dont `requiresCapability` matche l'axe du défi
  /// à un seuil ≤ valeur atteinte (cf. spec § 5.4).
  ///
  /// Calcul de la valeur atteinte :
  /// - axe durée : `targetThreshold + extensions × extensionSeconds` (borne
  ///   haute conservatrice — l'utilisatrice peut `JE M'ARRÊTE` avant la
  ///   fin d'une prolongation, mais on prend la valeur de référence du
  ///   défi pour rester simple).
  /// - axe BPM / profondeur : `targetThreshold` (tenu au paramètre demandé).
  ///
  /// No-op si :
  /// - outcome non succès (`fail` / `skipped` / `null`)
  /// - pas de profil de capacités (hors carrière)
  Future<void> _acquitMilestonesViaChallenge() async {
    final ch = _activeChallenge;
    final outcome = _challengeOutcome;
    if (ch == null || outcome == null) return;
    if (outcome != ChallengeOutcome.netSuccess &&
        outcome != ChallengeOutcome.extendedSuccess) {
      return;
    }
    final profile = _capabilityProfile;
    if (profile == null) return;
    final double reached;
    switch (ch.kind) {
      case ChallengeAxisKind.duration:
        reached = (ch.targetThreshold +
                _challengeExtensionsCount * ch.extensionSeconds)
            .toDouble();
        break;
      case ChallengeAxisKind.bpm:
      case ChallengeAxisKind.depthCran:
        reached = ch.targetThreshold.toDouble();
        break;
    }
    final acquittable = milestoneService.milestonesAcquittableByChallenge(
      axis: ch.axis,
      reached: reached,
      profile: profile,
      acquiredUnlocks: _unlockedKeys,
      playerLevel: _careerLevel,
    );
    for (final m in acquittable) {
      await milestoneService.markCompletedViaChallenge(m.id);
    }
  }

  /// Phase finale défis — consume la tête de la file showcase si la
  /// branche du défi de la séance matche. No-op hors carrière (pas de
  /// service) ou si le défi n'a pas tourné (`_activeChallenge == null`
  /// ou `_challengeOutcome == null`).
  Future<void> _consumeShowcaseIfMatched() async {
    final svc = _specializationService;
    if (svc == null) return;
    final ch = _activeChallenge;
    if (ch == null || _challengeOutcome == null) return;
    final branch = ch.branch;
    if (branch == null) return;
    final head = await svc.peekShowcase();
    if (head != branch) return;
    await svc.consumeShowcase(branch);
  }

  void _applyChallengeOutcome() {
    // Phase 19.5.b — itère sur tous les défis complétés cette séance pour
    // appliquer les bumps humil/obed multi-défi. Si aucun défi n'a tourné,
    // l'historique est vide → no-op. Le défi en cours non encore acquitté
    // est aussi traité (rare : la séance peut atteindre `_finish` pendant
    // qu'un défi est en `ended` mais pas encore enregistré).
    if (_challengeOutcome != null &&
        _activeChallengeIndex >= 0 &&
        !_completedChallengeIndices.contains(_activeChallengeIndex)) {
      final ch = _activeChallenge;
      if (ch != null) {
        _completedChallenges.add(_CompletedChallengeRecord(
          challenge: ch,
          outcome: _challengeOutcome!,
          extensionsCount: _challengeExtensionsCount,
        ));
        _completedChallengeIndices.add(_activeChallengeIndex);
      }
    }
    for (final record in _completedChallenges) {
      // Phase 2 défi exploratoire : pas de bump de base humil/obed +2
      // (pas de seuil cible atteint, donc pas de palier mesuré).
      // Cf. spec § 5.2 — seules les extensions comptent.
      final isExploratory = record.challenge.isExploratory;
      switch (record.outcome) {
        case ChallengeOutcome.netSuccess:
          if (!isExploratory) {
            _humiliation.onChallengeNetSuccess();
            _obedience.onChallengeNetSuccess();
            _raiseHumiliationFloorFromRecord(record);
          }
          break;
        case ChallengeOutcome.extendedSuccess:
          if (!isExploratory) {
            _humiliation.onChallengeNetSuccess();
            _obedience.onChallengeNetSuccess();
          }
          for (var i = 0; i < record.extensionsCount; i++) {
            _humiliation.onChallengeExtension();
            _obedience.onChallengeExtension();
          }
          _raiseHumiliationFloorFromRecord(record);
          break;
        case ChallengeOutcome.fail:
          // Pas de bumps humil/obed (cf. spec § 5.3).
          break;
        case ChallengeOutcome.skipped:
          _obedience.onChallengeSkip();
          break;
      }
    }
  }

  /// Élève le `careerScore` d'humiliation au plancher de l'action tenue
  /// pendant le défi (`HumiliationScale.requiredFor(...)` du step défi
  /// matérialisé). Sémantique : « tu viens de prouver que tu peux faire
  /// X — ton humiliation doit refléter le palier qu'exigeait X ». Sans
  /// ça, une joueuse qui réussit un défi hold throat 10 s peut rester
  /// sous le seuil de `intro_hold_mid` / `intro_final_hold_tip`
  /// plusieurs séances de suite, alors que la capacité a été prouvée.
  ///
  /// Pour les axes durée, on prend la durée effectivement tenue (seuil
  /// cible + N × extensionSeconds par extension acquise). Pour les axes
  /// BPM en rampe, on prend `bpmEnd` (vitesse finale atteinte). Pour les
  /// axes profondeur, c'est `ch.to` qui porte déjà l'info.
  void _raiseHumiliationFloorFromRecord(_CompletedChallengeRecord record) {
    final ch = record.challenge;
    final int durationReached;
    final int? bpmReached;
    switch (ch.kind) {
      case ChallengeAxisKind.duration:
        durationReached =
            ch.targetThreshold + record.extensionsCount * ch.extensionSeconds;
        bpmReached = ch.bpm;
        break;
      case ChallengeAxisKind.bpm:
        durationReached = ch.nominalDurationSeconds;
        bpmReached = ch.bpmEnd ?? ch.bpm;
        break;
      case ChallengeAxisKind.depthCran:
        durationReached = ch.nominalDurationSeconds;
        bpmReached = ch.bpm;
        break;
    }
    final floor = HumiliationScale.requiredFor(
      mode: ch.mode,
      from: ch.from,
      to: ch.to,
      bpm: bpmReached,
      duration: durationReached,
    );
    _humiliation.raiseCareerFloor(floor);
  }
}
