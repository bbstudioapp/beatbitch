part of 'session_controller.dart';

// ─── Défi intra-séance (Phase 1) — gameplay hold-to-keep ───────────────
//
// Machine d'états pilotée par les transitions de phase suivantes :
//   none → breath (entrée dans le step breath de countdown)
//   breath → countdown (1ʳᵉ pression sur GO — début du hold)
//   countdown → live (à countdown + 3 s)
//   countdown → breath (release pendant le countdown — 1ère fois)
//   countdown → ended (release pendant le countdown — 2ème fois = skipped)
//   countdown | live → ended (release prolongé > tolérance = fail)
//   live → atSeuil (au seuil cible, durée nominale ou crossings atteints)
//   atSeuil → ended (release du doigt = netSuccess ou extendedSuccess
//                    selon le nombre d'extensions dérivées de la durée
//                    tenue au-delà du seuil)
//   breath → ended (tap PASSE = skipped)
//
// Au passage en `ended`, `_challengeOutcome` est figé et le `_finish` de
// session applique les bumps capability/humil/obed correspondants.
//
// La présence du doigt (touch) ou de la touche espace (desktop) est
// signalée par `onChallengeHoldStart`/`onChallengeHoldEnd`. La perte du
// doigt en `live`/`countdown` arme une tolérance de
// `_challengeReleaseToleranceSec` s (le temps que le doigt « se repose »
// par maladresse) avant fail.
//
// Les **champs** d'état du défi vivent toujours sur `SessionController`
// (les extensions Dart ne peuvent pas porter de champs d'instance). Les
// getters dérivés et toute la logique sont rassemblés ici sous forme
// d'extension `part of` — même unité de compilation, même accès aux
// membres privés, juste un meilleur regroupement physique.

/// Durée fixe du countdown 3-2-1 en secondes. Dit en TTS immédiatement
/// après le début du hold sur `GO` (le doigt doit rester sur l'écran
/// pendant ces 3 s, sinon retour `breath` ou skip selon le compteur de
/// releases — cf. `onChallengeHoldEnd`).
const int _challengeCountdownDurationSec = 3;

/// Tolérance, en secondes, accordée à la joueuse quand son doigt
/// décroche pendant `countdown` ou `live`. Sous cette fenêtre, replacer
/// le doigt remet le défi en marche transparent. Au-delà, le défi est
/// fail.
const int _challengeReleaseToleranceSec = 1;

/// Durée du breath de récup post-défi (toutes voies). Donne au coach
/// le temps de faire son rapport et à la joueuse de souffler avant
/// que la séance ne reprenne.
const int _postChallengeBreathSeconds = 10;

/// Type d'événement haptique émis par le contrôleur pendant un défi.
/// Câblé côté UI à `HapticFeedback.{light,heavy}Impact()`.
enum ChallengeHapticKind {
  /// Validation positive (entrée `atSeuil`, extension franchie).
  light,

  /// Échec du défi (tolérance de release expirée).
  heavy,
}

// Alias privé pour conserver la cohérence interne (les helpers du
// `part of` y réfèrent sans avoir à exposer publiquement).
typedef _ChallengeHapticKind = ChallengeHapticKind;

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

  /// Progression de la tolérance de release [0..1] pour pulse UI.
  /// 0 = doigt présent (pas de tolérance en cours).
  /// 1 = sur le point d'expirer (fail imminent).
  /// Hors `countdown`/`live` ou doigt présent → 0.
  double get challengeReleaseToleranceProgress {
    final releaseAt = _challengeReleaseAtRealSec;
    if (releaseAt == null) return 0;
    if (_challengePhase != ChallengePhase.countdown &&
        _challengePhase != ChallengePhase.live) {
      return 0;
    }
    final elapsedMs = (_realSec * 1000).toInt() - releaseAt * 1000;
    final progress = elapsedMs / (_challengeReleaseToleranceSec * 1000);
    if (progress < 0) return 0;
    if (progress > 1) return 1;
    return progress;
  }

  /// `true` quand un step défi est en cours. Sert à masquer le bouton FAIL
  /// classique (la sortie défi est pilotée par le release du doigt) et à
  /// activer la capture globale du touch côté UI.
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
      case 'skip':
        return l10n.challengeSkipDefault;
      default:
        return null;
    }
  }

  /// Libellé d'objectif du défi (ex. « Tiens gorge 10 secondes ») —
  /// affiché en sous-titre du banner UI pendant `live` pour
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
      _challengeHoldActive = false;
      _challengeReleaseAtRealSec = null;
      _challengeCountdownReleaseCount = 0;
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
        _challengeCountdownReleaseCount = 0;
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
      // Tolérance release pendant le countdown : si le doigt décroche et
      // ne revient pas dans la fenêtre, retour `breath` au 1er release,
      // skip au 2e. Voir `onChallengeHoldEnd`.
      if (_checkChallengeReleaseTolerance(r)) return;
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
    // À partir d'ici, on est forcément après le step défi (phase live ou
    // atSeuil). Calcul du temps écoulé dans le step défi pour piloter
    // les transitions.
    if (_challengeStepStartedAtSec == null) return;
    final elapsedInStep = r - _challengeStepStartedAtSec!;
    final target = ch.targetThreshold;
    // Phase `live` ou `atSeuil` : tolérance de release (perte du doigt).
    if (phase == ChallengePhase.live || phase == ChallengePhase.atSeuil) {
      if (_checkChallengeReleaseTolerance(r)) return;
    }
    // Phase `atSeuil` : on attend le release du doigt (handled dans
    // `onChallengeHoldEnd`). Aucun timeout auto. À chaque tranche
    // `extensionSeconds` franchie tant que la joueuse tient encore, on
    // émet un haptic léger (matérialise la prolongation) et on met à
    // jour le compteur live — `_completeChallenge` lira la dernière
    // valeur connue au release.
    if (phase == ChallengePhase.atSeuil) {
      final newExt = _deriveChallengeExtensionsCount();
      if (newExt > _challengeExtensionsCount) {
        _challengeExtensionsCount = newExt;
        _emitChallengeHaptic(_ChallengeHapticKind.light);
        _notify();
      }
      return;
    }
    // Phase `live`. Pour tous les axes, on calque le seuil de fin sur la
    // durée nominale du step défi (= `targetThreshold` pour les axes
    // durée, fenêtre fixe 45 s/20 s pour BPM/profondeur).
    final stepEnd = ch.kind == ChallengeAxisKind.duration
        ? target
        : ch.nominalDurationSeconds;
    // Quand le défi pilote par franchissements (axes franchissement gorge),
    // le compteur de crossings peut court-circuiter la durée nominale.
    final crossingsTarget = ch.targetCrossings;
    final crossingsReached =
        crossingsTarget != null && _challengeCrossingsCount >= crossingsTarget;
    if (crossingsReached ||
        SessionController.shouldEnterAtSeuilPhase(
          phase: phase,
          elapsedInStep: elapsedInStep,
          stepEnd: stepEnd,
        )) {
      _challengePhase = ChallengePhase.atSeuil;
      _challengeAtSeuilStartedAtSec = r;
      // Annonce coach « tu peux relâcher quand tu veux, ou continuer » à
      // l'entrée seuil — remplace l'annonce historique `extension` qui
      // tombait 3 s avant la fin nominale. L'exploratoire reste exclu :
      // il n'a pas de seuil cible.
      if (!ch.isExploratory) {
        _challengeCurrentText = _pickChallengePhrase(ch, 'extension') ??
            _fallbackChallengeText(ch, 'extension');
        _speakChallengePhraseIfAny();
      }
      _emitChallengeHaptic(_ChallengeHapticKind.light);
    }

    // Retry passif de la phrase défi en attente : si la transition
    // `none → breath` (ou `live → atSeuil`) a posé `_challengeCurrentText`
    // mais que le TTS était occupé (random comment, phrase scriptée d'un
    // step précédent), `_speakChallengePhraseIfAny` a skip et la phrase
    // n'est jamais prononcée. À chaque tick, si une phrase défi non-encore
    // dite est en attente et que le TTS s'est libéré, on la dit maintenant.
    if (_challengeCurrentText != null &&
        _challengeCurrentText != _challengeSpokenText) {
      _speakChallengePhraseIfAny();
    }
  }

  /// Si le doigt a décroché depuis assez longtemps (> tolérance), bascule
  /// la machine d'états selon la phase courante : retour `breath` ou skip
  /// pendant `countdown`, fail pendant `live`. Pendant `atSeuil`, le
  /// release est traité immédiatement dans `onChallengeHoldEnd`, mais on
  /// laisse aussi la tolérance s'exprimer si jamais l'ordre des events
  /// l'amène jusqu'ici (cas dégénéré). Retourne `true` si une transition
  /// a été appliquée (early-return côté caller).
  bool _checkChallengeReleaseTolerance(int r) {
    final releaseAt = _challengeReleaseAtRealSec;
    if (releaseAt == null) return false;
    if (r - releaseAt < _challengeReleaseToleranceSec) return false;
    _challengeReleaseAtRealSec = null;
    final phase = _challengePhase;
    if (phase == ChallengePhase.countdown) {
      // 1er release → retour `breath` avec rappel pédagogique ; 2e release
      // au même défi → outcome `skipped`.
      _challengeCountdownReleaseCount++;
      if (_challengeCountdownReleaseCount >= 2) {
        _completeChallenge(ChallengeOutcome.skipped);
        return true;
      }
      _challengePhase = ChallengePhase.breath;
      _challengeCountdownStartedAtSec = null;
      _challengeCountdownLastDigitSpoken = -1;
      _challengeCurrentText = _appLocalizations?.challengeCountdownReleaseRetry;
      _challengeSpokenText = null;
      _speakChallengePhraseIfAny();
      _notify();
      return true;
    }
    if (phase == ChallengePhase.live) {
      _capabilityTracker?.onFail();
      _completeChallenge(ChallengeOutcome.fail);
      _emitChallengeHaptic(_ChallengeHapticKind.heavy);
      return true;
    }
    return false;
  }

  void _emitChallengeHaptic(_ChallengeHapticKind kind) {
    final cb = onChallengeHaptic;
    if (cb == null) return;
    cb(kind);
  }

  /// Bouton `PASSE` pendant le breath du défi — skip le défi entier.
  /// Outcome `skipped` (malus obed -3, aucun signal capability). Le skip
  /// du step défi est fait par `_completeChallenge` via
  /// `_startPostChallengeBreath` (qui appelle aussi `_skipPastChallengeStep`).
  void triggerChallengePass() {
    if (_challengePhase != ChallengePhase.breath) return;
    _completeChallenge(ChallengeOutcome.skipped);
  }

  /// Signal d'entrée du doigt (touch) ou de la touche espace (desktop)
  /// pendant un défi. Idempotent : un appel répété tant que le hold est
  /// déjà actif est un no-op (utile pour combiner touch + clavier sans
  /// state synchronisé côté UI).
  ///
  /// Comportement par phase :
  /// - `breath` : démarre le countdown 3-2-1 (équivalent ex-bouton GO).
  /// - `countdown`/`live`/`atSeuil` : annule une éventuelle tolérance de
  ///   release en cours (le doigt revient à temps).
  /// - `none`/`ended` : no-op.
  void onChallengeHoldStart() {
    if (_challengePhase == ChallengePhase.none ||
        _challengePhase == ChallengePhase.ended) {
      return;
    }
    if (_challengeHoldActive) return;
    _challengeHoldActive = true;
    _challengeReleaseAtRealSec = null;
    if (_challengePhase == ChallengePhase.breath) {
      if (_activeChallengeIndex < 0) return;
      _enterChallengeCountdown();
    }
    _notify();
  }

  /// Signal de sortie du doigt / touche. Idempotent.
  ///
  /// Comportement par phase :
  /// - `countdown`/`live` : arme la tolérance de release (`_realSec` figé).
  ///   La transition effective (retour breath / skip / fail) est faite par
  ///   `_checkChallengeReleaseTolerance` au prochain tick si le doigt ne
  ///   revient pas dans la fenêtre.
  /// - `atSeuil` : termine immédiatement le défi — netSuccess ou
  ///   extendedSuccess selon le nombre d'extensions dérivées de la durée
  ///   tenue au-delà du seuil.
  /// - `breath`/`none`/`ended` : no-op (le hold n'a pas commencé / est
  ///   déjà clos).
  void onChallengeHoldEnd() {
    if (!_challengeHoldActive) return;
    _challengeHoldActive = false;
    final phase = _challengePhase;
    if (phase == ChallengePhase.atSeuil) {
      _challengeReleaseAtRealSec = null;
      _challengeExtensionsCount = _deriveChallengeExtensionsCount();
      final outcome = _challengeExtensionsCount > 0
          ? ChallengeOutcome.extendedSuccess
          : ChallengeOutcome.netSuccess;
      _completeChallenge(outcome);
      return;
    }
    if (phase == ChallengePhase.countdown || phase == ChallengePhase.live) {
      _challengeReleaseAtRealSec = _realSec.toInt();
      _notify();
      return;
    }
  }

  /// Calcule le compteur d'extensions à appliquer au release après seuil.
  /// = `floor((releaseAtRealSec − atSeuilEnteredAtRealSec) ÷ extensionSeconds)`.
  /// Plancher 0 (release immédiate au seuil = pas d'extension).
  int _deriveChallengeExtensionsCount() {
    final ch = _activeChallenge;
    if (ch == null) return 0;
    final at = _challengeAtSeuilStartedAtSec;
    if (at == null) return 0;
    final tenu = _realSec.toInt() - at;
    if (tenu <= 0) return 0;
    final step = ch.extensionSeconds;
    if (step <= 0) return 0;
    return tenu ~/ step;
  }

  /// Bascule en phase `countdown` (3-2-1 TTS + UI). Le chiffre TTS est
  /// énoncé par `_updateChallengePhase` à chaque seconde via
  /// `_maybeSpeakCountdownDigit`.
  ///
  /// Coupe le TTS en cours : si la phrase d'annonce du défi (`attempt`,
  /// posée à l'entrée en `breath`) est encore en train d'être prononcée
  /// au moment du début du hold, le countdown skipperait les chiffres
  /// tant que `_tts.isSpeaking`. On préfère arrêter net la phrase pour
  /// que « 3-2-1 » s'enchaîne proprement.
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

  /// Termine le défi et fige l'outcome. Les bumps capability/humil/obed
  /// sont appliqués au `_finish` de session (cf. `_applyChallengeOutcome`).
  /// Enchaîne sur un breath de récup de 10 s : le step défi est skippé
  /// dans la timeline, le BeepEngine joue un breath, le coach fait son
  /// rapport (`stop`/`fail`/`success`/`skip`). Pendant ce breath,
  /// `_checkSteps` ne consomme pas le step suivant — la séance "marque
  /// une pause" et la joueuse souffle.
  void _completeChallenge(ChallengeOutcome outcome) {
    if (_challengePhase == ChallengePhase.ended) return;
    _challengeOutcome = outcome;
    _challengePhase = ChallengePhase.ended;
    _challengeHoldActive = false;
    _challengeReleaseAtRealSec = null;
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
        ChallengeOutcome.netSuccess => 'stop',
        ChallengeOutcome.extendedSuccess => 'success',
        ChallengeOutcome.skipped => 'skip',
      };
      final closingText =
          _pickChallengePhrase(ch, tier) ?? _fallbackChallengeText(ch, tier);
      _challengeCurrentText = closingText;
      // Pose aussi le texte résolu sur `_lastSpokenResolvedText` :
      // - `_speakChallengePhraseIfAny` bail si TTS speaking → sans cela
      //   l'affichage retombe sur la phrase du step pré-défi pendant
      //   tout le breath post-défi.
      // - Le widget consulte `challengeCurrentText` pendant la phase
      //   live, mais après `phase == ended` il retombe sur
      //   `currentDisplayText` → ce dernier doit refléter la phrase
      //   de clôture du défi, pas l'historique pré-défi.
      if (closingText != null && closingText.isNotEmpty) {
        _lastSpokenResolvedText = _tts.resolveText(closingText);
      }
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
