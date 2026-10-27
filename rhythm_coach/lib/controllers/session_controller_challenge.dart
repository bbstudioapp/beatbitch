part of 'session_controller.dart';

// ─── Défi intra-séance — gameplay au tap ───────────────────────────────
//
// Machine d'états pilotée par les transitions de phase suivantes :
//   none → breath (entrée dans le step breath de countdown)
//   breath → countdown (tap DÉMARRE)
//   countdown → live (à countdown + 3 s)
//   live → ended (tap J'ABANDONNE = fail)
//   live → atSeuil (au seuil cible, durée nominale ou crossings atteints)
//   atSeuil → ended (tap JE M'ARRÊTE = netSuccess ou extendedSuccess
//                    selon le nombre d'extensions dérivées de la durée
//                    écoulée au-delà du seuil)
//   breath → ended (tap PASSE = skipped)
//
// Au passage en `ended`, `_challengeOutcome` est figé et le `_finish` de
// session applique les bumps capability/humil/obed correspondants.
//
// Les **champs** d'état du défi vivent toujours sur `SessionController`
// (les extensions Dart ne peuvent pas porter de champs d'instance). Les
// getters dérivés et toute la logique sont rassemblés ici sous forme
// d'extension `part of` — même unité de compilation, même accès aux
// membres privés, juste un meilleur regroupement physique.

/// Durée fixe du countdown 3-2-1 en secondes.
const int _challengeCountdownDurationSec = 3;

/// Durée du breath de récup post-défi (toutes voies). Donne au coach
/// le temps de faire son rapport et à la joueuse de souffler avant
/// que la séance ne reprenne.
const int _postChallengeBreathSeconds = 10;

/// Type d'événement haptique émis par le contrôleur pendant un défi.
/// Câblé côté UI à `HapticFeedback.{light,heavy}Impact()`.
enum ChallengeHapticKind {
  /// Validation positive (entrée `atSeuil`, extension franchie).
  light,

  /// Échec du défi (abandon en `live`).
  heavy,
}

// Alias privé pour conserver la cohérence interne (les helpers du
// `part of` y réfèrent sans avoir à exposer publiquement).
typedef _ChallengeHapticKind = ChallengeHapticKind;

/// Valeur créditée au profil de capacités à la clôture d'un défi réussi.
///
/// Fonction pure, extraite de `_completeChallenge` pour être testable
/// isolément — c'est ici que se joue la différence entre ce qui a été
/// **demandé** et ce qui était **produisible**.
///
/// Les axes BPM sont bornés à la plage du [BeepEngine] : la cible affichée
/// (`bpmEnd`) n'est jamais vérifiée contre ce que le moteur a joué, et la
/// créditer telle quelle referme une boucle divergente (cf.
/// `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md`).
@visibleForTesting
double challengeReachedValue(Challenge ch, {required int extensionsCount}) {
  switch (ch.kind) {
    case ChallengeAxisKind.duration:
      return (ch.targetThreshold + extensionsCount * ch.extensionSeconds)
          .toDouble();
    case ChallengeAxisKind.bpm:
      return (ch.bpmEnd ?? ch.bpm ?? ch.targetThreshold)
          .clamp(BeepEngine.kMinBpm, BeepEngine.kMaxBpm)
          .toDouble();
    case ChallengeAxisKind.depthCran:
      return ch.targetThreshold.toDouble();
  }
}

/// Plancher d'humiliation carrière posé par un défi réussi — « tu viens de
/// prouver que tu peux faire X, ton humiliation doit refléter le palier
/// qu'exigeait X ».
///
/// Fonction pure, extraite de [_raiseHumiliationFloorFromRecord] pour être
/// testable isolément. Le BPM est borné comme dans [challengeReachedValue] :
/// `HumiliationScale` est **quadratique** en BPM, une cible non bornée y
/// pose un plancher à quatre chiffres.
@visibleForTesting
double challengeHumiliationFloor(Challenge ch, {required int extensionsCount}) {
  final int durationReached;
  final int? bpmReached;
  switch (ch.kind) {
    case ChallengeAxisKind.duration:
      durationReached =
          ch.targetThreshold + extensionsCount * ch.extensionSeconds;
      bpmReached = ch.bpm;
      break;
    case ChallengeAxisKind.bpm:
      durationReached = ch.nominalDurationSeconds;
      bpmReached =
          (ch.bpmEnd ?? ch.bpm)?.clamp(BeepEngine.kMinBpm, BeepEngine.kMaxBpm);
      break;
    case ChallengeAxisKind.depthCran:
      durationReached = ch.nominalDurationSeconds;
      bpmReached = ch.bpm;
      break;
  }
  return HumiliationScale.requiredFor(
    mode: ch.mode,
    from: ch.from,
    to: ch.to,
    bpm: bpmReached,
    duration: durationReached,
  );
}

/// Snapshot d'un défi complété — sert à appliquer les bumps humil/obed
/// au `_finish` quand plusieurs défis ont tourné dans la même séance.
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

  /// `true` quand un step défi est en cours. Sert à masquer le bouton FAIL
  /// classique (la sortie défi passe par les boutons du défi).
  bool get isChallengeActive =>
      _challengePhase != ChallengePhase.none &&
      _challengePhase != ChallengePhase.ended;

  bool get _inPostChallengeBreath {
    final until = _postChallengeBreathRealEndSec;
    return until != null && _realSec.toInt() < until;
  }

  /// Instant de séance où elle reprend après le défi, `null` hors du souffle
  /// post-défi.
  int? get postChallengeBreathUntilSec => _inPostChallengeBreath
      ? (_activeChallengeTriggerSec ?? elapsedSeconds)
      : null;

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
  /// affiché en sous-titre du banner UI pendant `live` pour rappeler à la
  /// joueuse ce qu'elle doit faire. Pas dit en TTS (la coach a déjà fait
  /// l'annonce pendant le breath).
  ///
  /// Dispatch par **axe** (pas par `kind` seul) : chaque axe pilotant a
  /// son banner dédié pour décrire spécifiquement ce qu'on teste.
  String? challengeObjectiveText() {
    final ch = _activeChallenge;
    final l10n = _appLocalizations;
    if (ch == null || l10n == null) return null;
    final t = ch.targetThreshold;
    final crossings = ch.targetCrossings;
    switch (ch.axis) {
      // Tenues simples (durée).
      case CapabilityAxis.holdThroatStreak:
        return l10n.challengeBannerHoldThroat(t);
      case CapabilityAxis.holdFullStreak:
        return l10n.challengeBannerHoldFull(t);
      // Modèle gorge — apnée vs engagement (mécaniques distinctes, banners
      // distincts pour que la joueuse comprenne ce qu'on lui demande).
      case CapabilityAxis.gorgeApneeStreak:
        return l10n.challengeBannerGorgeApnee;
      case CapabilityAxis.gorgeEngagementStreak:
        return l10n.challengeBannerGorgeEngagement;
      // Franchissements gorge — compteur de passages, pas durée. Affiche
      // le nombre cible (`targetCrossings`) + BPM (`targetThreshold` =
      // BPM cible). Fallback BPM seul si crossings absent (cas exploratoire).
      case CapabilityAxis.gorgeCrossingsBpmThroat:
        return crossings != null
            ? l10n.challengeBannerGorgeCrossingsThroat(crossings, t)
            : l10n.challengeBannerRhythmThroat(t);
      case CapabilityAxis.gorgeCrossingsBpmFull:
        return crossings != null
            ? l10n.challengeBannerGorgeCrossingsFull(crossings, t)
            : l10n.challengeBannerRhythmFull(t);
      // Rythme BPM — banner par bande de profondeur (shallow/throat/full)
      // pour que la joueuse sache l'amplitude visée, pas juste le BPM.
      case CapabilityAxis.rhythmBpmCeilShallow:
        return l10n.challengeBannerRhythmShallow(t);
      case CapabilityAxis.rhythmBpmCeilThroat:
        return l10n.challengeBannerRhythmThroat(t);
      case CapabilityAxis.rhythmBpmCeilFull:
        return l10n.challengeBannerRhythmFull(t);
      // Profondeur — pousse d'un cran.
      case CapabilityAxis.rhythmDepthMax:
        return l10n.challengeBannerDepthMax;
      // Endurance — durée d'effort sans pause / sans respi / sans avaler.
      case CapabilityAxis.rhythmMotionStreak:
        return l10n.challengeBannerMotionStreak(t);
      case CapabilityAxis.effortNoBreathStreak:
        return l10n.challengeBannerNoBreathStreak(t);
      case CapabilityAxis.noswallowStreak:
        return l10n.challengeBannerNoSwallowStreak(t);
      // Biffle — durée ou BPM.
      case CapabilityAxis.biffleStreak:
        return l10n.challengeBannerBiffleStreak(t);
      case CapabilityAxis.biffleBpmMax:
        return l10n.challengeBannerBiffle(t);
      // Axes non-pilotants ou cas non-couverts (ne devrait pas arriver via
      // le flow normal, mais on garde un fallback générique).
      // ignore: no_default_cases
      default:
        if (ch.mode == SessionMode.hold) {
          return l10n.challengeBannerHoldGeneric(t);
        }
        return l10n.challengeBannerGeneric;
    }
  }

  /// Tick de mise à jour de la machine d'états défi. Drivée par
  /// `elapsedSeconds` vs `session.challengeTriggerTimes` (fenêtre du step
  /// breath de countdown) : ne dépend plus de la consommation des steps
  /// (qui peut être interrompue par un fail), ce
  /// qui rendait la transition `breath → live` peu fiable. Appelée dans
  /// `_onTick` à chaque tick (200 ms).
  ///
  /// Le step défi n'est pas posé dans la timeline : l'entrée en `live`
  /// instancie un `ChallengeSegmentBuilder`
  /// et émet ses segments en runtime (cf. `_startChallengeStreaming` +
  /// `_advanceChallengeSegment`).
  void _updateChallengePhase() {
    if (_session.challenges.isEmpty) return;
    final phase = _challengePhase;
    // Reset post-breath du défi précédent : quand le breath
    // post-défi est fini, on rebascule en `none` pour permettre l'armement
    // du défi suivant (s'il en reste un dans `_session.challenges`).
    if (phase == ChallengePhase.ended && !_inPostChallengeBreath) {
      _activeChallenge = null;
      _activeChallengeIndex = -1;
      _challengeOutcome = null;
      _challengeExtensionsCount = 0;
      _challengeStepStartedAtSec = null;
      _challengeAtSeuilStartedAtSec = null;
      _challengeCountdownStartedAtSec = null;
      _challengeCountdownLastDigitSpoken = -1;
      _challengeCurrentText = null;
      _challengeSpokenText = null;
      _segmentBuilder = null;
      _currentChallengeSegment = null;
      // Restaure le mode de déglutition pré-défi si on l'avait forcé à
      // `forbidden` pour un noswallowStreak. Pas de transition explicite
      // forbidden → allowed côté SalivaEngine ici (équivalente à un step
      // qui change le mode sans dire « avale tout »).
      if (_challengeSavedSwallowMode != null) {
        _swallowMode = _challengeSavedSwallowMode!;
        _challengeSavedSwallowMode = null;
      }
      _challengePhase = ChallengePhase.none;
    }
    final t = elapsedSeconds;
    // Entrée en phase `breath` (annonce coach + boutons PASSE / DÉMARRE
    // visibles). À partir de ce moment, la timeline est gelée par `_onTick`
    // jusqu'à l'action joueuse (DÉMARRE ou PASSE).
    if (_challengePhase == ChallengePhase.none) {
      // Cherche le prochain défi à armer : index `i` non encore acquitté
      // dont la fenêtre du step trigger (= breath de countdown 13 s) est
      // ouverte.
      //
      // Borne sur la plus courte des deux listes : un défi sans trigger time
      // n'est de toute façon pas armable, et une divergence entre elles
      // sortirait des bornes **dans le ticker**, où une exception ne
      // s'auto-annule pas (gel de séance). Le générateur ne livre que des
      // paires ; ceci est la ceinture.
      final armable = min(
          _session.challenges.length, _session.challengeTriggerTimes.length);
      if (kDebugMode &&
          !_challengeListMismatchLogged &&
          _session.challenges.length != _session.challengeTriggerTimes.length) {
        _challengeListMismatchLogged = true;
        debugPrint('[SessionController] défis désalignés : '
            '${_session.challenges.length} défis pour '
            '${_session.challengeTriggerTimes.length} trigger times — '
            'les défis au-delà du rang $armable ne seront jamais armés');
      }
      for (var i = 0; i < armable; i++) {
        if (_completedChallengeIndices.contains(i)) continue;
        final triggerStart = _session.challengeTriggerTimes[i];
        final triggerEnd = triggerStart + kChallengeBreathDurationSeconds;
        if (t < triggerStart || t >= triggerEnd) continue;
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
          _challengeCurrentText = null;
          _challengeSpokenText = null;
          _challengeCrossingsCount = 0;
          _startChallengeStreaming(ch);
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
    // Phase `atSeuil` : on attend le tap `JE M'ARRÊTE` (`onChallengeTapStop`).
    // Aucun timeout auto. À chaque tranche `extensionSeconds` franchie tant
    // que la joueuse continue, on émet un haptic léger (matérialise la
    // prolongation) et on met à jour le compteur live — `_completeChallenge`
    // lira la dernière valeur connue au tap.
    //
    // Pour les builders qui continuent d'émettre
    // des segments pendant les extensions (endurance, modèle gorge), on
    // avance aussi le segment courant ici quand sa durée est consommée.
    // Les builders monolithiques retournent null à `next()` une fois
    // leur unique segment émis → no-op (`_advanceChallengeSegment` clear
    // `_currentChallengeSegment`, plus rien à advance).
    if (phase == ChallengePhase.atSeuil) {
      final currentSegment = _currentChallengeSegment;
      if (currentSegment != null) {
        final segDur = currentSegment.duration ?? 0;
        if (segDur > 0 && elapsedInStep >= segDur) {
          _advanceChallengeSegment(r);
        }
      }
      final newExt = _deriveChallengeExtensionsCount();
      if (newExt > _challengeExtensionsCount) {
        _challengeExtensionsCount = newExt;
        _emitChallengeHaptic(_ChallengeHapticKind.light);
        _notify();
      }
      return;
    }
    // Phase `live`. Demande au builder un nouveau segment dès que la
    // durée du segment courant est consommée. Le builder décide quand le
    // seuil est atteint (`thresholdReached`) — pas le contrôleur. Le
    // court-circuit historique sur les crossings reste en place pour les
    // axes franchissement (couverts par les builders dédiés en PR-B.1.e).
    //
    // Garde explicite `phase == live` : `_challengeStepStartedAtSec` reste
    // posé pendant la fenêtre post-`ended` (10 s de breath de récup), il
    // ne faut pas continuer à demander des segments à ce moment-là.
    if (phase != ChallengePhase.live) return;
    final crossingsTarget = ch.targetCrossings;
    final crossingsReached =
        crossingsTarget != null && _challengeCrossingsCount >= crossingsTarget;
    if (crossingsReached) {
      _enterChallengeAtSeuil(ch, r);
      return;
    }
    // Builders streaming : `thresholdReached` peut basculer entre 2
    // transitions de segment (= la durée cumulée a atteint la cible
    // pendant un sous-segment). On vérifie à chaque tick, pas seulement
    // à segment-end, sinon l'entrée en atSeuil serait différée jusqu'à
    // la prochaine transition.
    if (_segmentBuilder?.thresholdReached ?? false) {
      _enterChallengeAtSeuil(ch, r);
      return;
    }
    final currentSegment = _currentChallengeSegment;
    if (currentSegment != null) {
      final segDur = currentSegment.duration ?? 0;
      if (segDur > 0 && elapsedInStep >= segDur) {
        _advanceChallengeSegment(r);
        return;
      }
    }
    // Fallback safety net : si le builder n'a plus de segment courant
    // (cas dégénéré — ne devrait pas arriver pour un builder monolithique
    // tant que le seuil n'est pas atteint), on bascule en atSeuil sur la
    // base de la durée cumulée pour les axes durée.
    if (ch.kind == ChallengeAxisKind.duration && elapsedInStep >= target) {
      _enterChallengeAtSeuil(ch, r);
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

  /// Abandon d'un défi en cours (phase `live`) : tap-out avant le seuil.
  /// Pose un FAIL capability + haptic lourd.
  void _failChallengeLive() {
    final countdownStart = _challengeCountdownStartedAtSec;
    if (_activeChallenge?.axis == CapabilityAxis.noswallowStreak &&
        countdownStart != null) {
      _capabilityTracker?.creditNoswallowSeconds(
        _realSec.toInt() - countdownStart - _challengeCountdownDurationSec,
      );
    }
    _capabilityTracker?.onFail();
    _completeChallenge(ChallengeOutcome.fail);
    _emitChallengeHaptic(_ChallengeHapticKind.heavy);
  }

  /// Validation d'un défi au seuil (phase `atSeuil`) : succès net, ou étendu
  /// selon les extensions accumulées en laissant tourner au-delà du seuil
  /// (cf. `_deriveChallengeExtensionsCount`).
  void _bankChallengeFromAtSeuil() {
    _challengeExtensionsCount = _deriveChallengeExtensionsCount();
    final outcome = _challengeExtensionsCount > 0
        ? ChallengeOutcome.extendedSuccess
        : ChallengeOutcome.netSuccess;
    _completeChallenge(outcome);
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

  /// Bouton `DÉMARRE` du breath : lance le countdown 3-2-1. No-op hors
  /// `breath`.
  void onChallengeTapGo() {
    if (_challengePhase != ChallengePhase.breath) return;
    if (_activeChallengeIndex < 0) return;
    _enterChallengeCountdown();
    _notify();
  }

  /// Bouton `J'ABANDONNE` / `JE M'ARRÊTE` pendant le défi.
  /// - `live` : abandon (tap-out avant le seuil) → fail.
  /// - `atSeuil` : validation → succès net ou étendu selon les extensions
  ///   accumulées en laissant tourner.
  /// - autres phases : no-op.
  void onChallengeTapStop() {
    final phase = _challengePhase;
    if (phase == ChallengePhase.atSeuil) {
      _bankChallengeFromAtSeuil();
      return;
    }
    if (phase == ChallengePhase.live) {
      _failChallengeLive();
      return;
    }
  }

  /// Calcule le compteur d'extensions à appliquer à la validation après seuil.
  /// = `floor((stopAtRealSec − atSeuilEnteredAtRealSec) ÷ extensionSeconds)`.
  /// Plancher 0 (validation immédiate au seuil = pas d'extension).
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
  /// au moment du tap `DÉMARRE`, le countdown skipperait les chiffres
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
        final reached = challengeReachedValue(
          ch,
          extensionsCount: _challengeExtensionsCount,
        );
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
  /// est satisfaite (cascade transitive), consomme la
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
      _pickBackground(BackgroundContext(
        mode: SessionMode.breath.name,
        coach: _coachTag,
        tier: SessionController.backgroundTierFor(elapsedSeconds, _session),
      ));
      _syncAmbienceToCurrentMode();
    }
  }

  /// Démarre le streaming de segments du défi. Appelé à l'entrée
  /// en phase `live` (= après les 3 s du countdown). Instancie le builder
  /// dédié à l'axe via `builderForAxis`, le configure avec le profil de
  /// capacités et les unlocks runtime, puis émet le premier segment via
  /// `_advanceChallengeSegment`.
  ///
  /// Cas particulier `noswallowStreak` : on force `_swallowMode = forbidden`
  /// pendant toute la durée du défi (critère intrinsèque — la salope est
  /// censée garder la salive en bouche). Le mode pré-défi est sauvegardé
  /// dans `_challengeSavedSwallowMode` et restauré au reset post-`ended`.
  void _startChallengeStreaming(Challenge challenge) {
    final builder = builderForAxis(challenge.axis)
      ..start(
        challenge: challenge,
        profile: _capabilityProfile,
        unlocks: _unlockedKeys,
        rng: _random,
      );
    _segmentBuilder = builder;
    _currentChallengeSegment = null;
    if (challenge.axis == CapabilityAxis.noswallowStreak) {
      _challengeSavedSwallowMode = _swallowMode;
      _swallowMode = SwallowMode.forbidden;
    }
    _advanceChallengeSegment(_realSec.toInt());
  }

  /// Demande au builder le prochain segment et l'applique au BeepEngine.
  /// Si le builder ne fournit plus rien et a atteint son seuil, bascule
  /// automatiquement en phase `atSeuil`. Si le builder est absent ou n'a
  /// pas atteint le seuil mais n'émet plus rien (cas dégénéré), le défi
  /// se fige sur le dernier segment — la boucle BeepEngine continue
  /// jusqu'au tap joueuse.
  void _advanceChallengeSegment(int nowRealSec) {
    final builder = _segmentBuilder;
    if (builder == null) return;
    final next = builder.next();
    if (next == null) {
      // Builder épuisé : on clear le segment courant pour que la boucle
      // tick ne retente pas un advance à chaque tour (sinon, monolithique
      // post-atSeuil = appels à next() perdus dans le vide à chaque tick).
      _currentChallengeSegment = null;
      if (builder.thresholdReached) {
        final ch = _activeChallenge;
        if (ch != null) _enterChallengeAtSeuil(ch, nowRealSec);
      }
      return;
    }
    _currentChallengeSegment = next;
    _challengeStepStartedAtSec = nowRealSec;
    if (_released) return;
    _beep.applyStep(next, _session.defaultMode);
    _pickBackground(_buildChallengeBackgroundContext(next));
    _configApplied = true;
    _lastConfigStep = next;
    if (!_session.noStats) {
      _stats.markModeUsed(next.mode ?? _session.defaultMode);
    }
    _trackConfigStep(next);
    _armHoldVerifierIfHoldStep(next);
    _syncAmbienceToCurrentMode();
  }

  /// Bascule en phase `atSeuil` + annonce coach. Extrait pour mutualiser
  /// entre la voie « builder épuisé + thresholdReached », la voie
  /// « crossings atteints » (axes franchissement) et la voie « streaming
  /// `thresholdReached` flip en plein segment » (endurance).
  ///
  /// Idempotent : re-appeler en `atSeuil` est un no-op (évite de rejouer
  /// l'annonce TTS et le haptic).
  void _enterChallengeAtSeuil(Challenge ch, int nowRealSec) {
    if (_challengePhase == ChallengePhase.atSeuil) return;
    _challengePhase = ChallengePhase.atSeuil;
    _challengeAtSeuilStartedAtSec = nowRealSec;
    if (!ch.isExploratory) {
      _challengeCurrentText = _pickChallengePhrase(ch, 'extension') ??
          _fallbackChallengeText(ch, 'extension');
      _speakChallengePhraseIfAny();
    }
    _emitChallengeHaptic(_ChallengeHapticKind.light);
  }

  /// Excise la fenêtre défi (step trigger + enveloppe estimée pour le défi)
  /// de la timeline session, en décalant tous les steps suivants ainsi que
  /// les timestamps de fin (`durationSeconds`, `finalStepTime`,
  /// `silentFinishStartTime`, milestones) de `-shift`. À l'issue, le
  /// déclencheur coïncide avec la position du step qui suivait le défi dans
  /// l'ancienne timeline : la séance reprend là où elle en était avant le
  /// défi, sans saut visible du timer.
  ///
  /// Le step défi n'est pas posé dans la timeline : le générateur ne pose que le step trigger et réserve une
  /// enveloppe `kChallengeBreathDurationSeconds + nominalDurationSeconds`
  /// pour ne pas chevaucher les blocs en aval. Le shift d'excision reprend
  /// la même formule pour rester symétrique : `breath + estimate`. Seul le
  /// step trigger lui-même tombe dans la fenêtre (la zone réservée après
  /// trigger est vide par construction côté générateur).
  ///
  /// No-op silencieux si l'index défi est hors borne (cas `PASSE` immédiat
  /// où le défi n'a pas été matérialisé) : aucune fenêtre à exciser puisque
  /// la timeline est restée à `triggerTime` pendant le `breath` puis a
  /// repris normalement à la fin du `breath` post-défi.
  void _excisChallengeFromSession() {
    if (_activeChallengeIndex < 0) return;
    if (_activeChallengeIndex >= _session.challengeTriggerTimes.length) {
      return;
    }
    final triggerStart = _session.challengeTriggerTimes[_activeChallengeIndex];
    final ch = _activeChallenge;
    if (ch == null) return;
    final reservedStepDur = ch.nominalDurationSeconds;
    final shift = kChallengeBreathDurationSeconds + reservedStepDur;
    if (shift <= 0) return;
    final breathStart = triggerStart;
    final endOfChallenge = triggerStart + shift;

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
      newSteps.add(s.rebased(s.time - shift));
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
      initialPose: _session.initialPose,
      // Sans ce report, `Session.breaks` retombe à `const []`. Longueur et
      // ordre conservés : `_nextBreakIndex` pointe dans la liste.
      breaks: [
        for (final b in _session.breaks)
          ScriptedBreak(
            time: shiftLate(b.time)!,
            durationSeconds: b.durationSeconds,
            newPose: b.newPose,
            orders: b.orders,
          ),
      ],
      postureChanges: [
        for (final c in _session.postureChanges)
          PostureChange(time: shiftLate(c.time)!, pose: c.pose),
      ],
      // On préserve la liste complète des défis, mais on shifte les trigger
      // times des défis suivants (ceux après `endOfChallenge`) pour qu'ils
      // restent synchronisés avec la nouvelle timeline — les deux listes
      // s'indexent par la même position, elles doivent rester parallèles.
      // `_completedChallengeIndices` côté controller garantit que les
      // défis déjà acquittés (le défi excisé inclus) ne se ré-arment pas.
      challenges: _session.challenges,
      challengeTriggerTimes: [
        for (final t in _session.challengeTriggerTimes) shiftLate(t)!,
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
  /// - `fail` : pas de malus humil/obed. Le soft-cap
  ///   capability × 0.92 n'est pas distinct du standard
  ///   (TODO : extension `CapabilityRegulator`) ; le tracker pose déjà un
  ///   ceiling via les FAILs séance, qui plafonnera l'axe naturellement.
  /// - `skipped` : malus obédiance -3, pas de signal capability.
  ///
  /// Scanne le catalogue de milestones pour acquitter
  /// silencieusement celles dont `requiresCapability` matche l'axe du défi
  /// à un seuil ≤ valeur atteinte.
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
    // Combine les unlocks lifetime ET les unlocks provisoires de la séance
    // courante (milestones insérées mais pas encore `markCompleted`). Sans
    // cette union, un défi tuto qui tombe au milieu de la 1ère séance ne
    // peut pas acquitter `intro_hold_throat`/`intro_hold_mid` (qui ont
    // `requires: [basics]`) parce que `intro_basics` est en cours mais pas
    // encore consolidée — la cascade post-défi ne décolle jamais.
    final acquittable = milestoneService.milestonesAcquittableByChallenge(
      axis: ch.axis,
      reached: reached,
      profile: profile,
      acquiredUnlocks: milestoneService.effectiveUnlockKeysForChallenge(),
      playerLevel: _careerLevel,
    );
    for (final m in acquittable) {
      await milestoneService.markCompletedViaChallenge(m.id);
    }
    // L'acquittement ci-dessus a pu s'appuyer sur un unlock **provisoire**
    // de la séance (cf. `effectiveUnlockKeysForChallenge`) — typiquement
    // `basics`, fourni par `intro_basics` insérée mais pas encore
    // consolidée. On consolide donc ses parents pour ne pas laisser des
    // enfants acquittés sans leur prérequis (sinon le tutoriel est
    // ré-inséré aux séances suivantes). No-op si rien à combler.
    if (acquittable.isNotEmpty) {
      await milestoneService.consolidatePrerequisites();
    }
  }

  /// Consomme la tête de la file showcase si la
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
    // Itère sur tous les défis complétés cette séance pour
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
      // Défi exploratoire : pas de bump de base humil/obed +2
      // (pas de seuil cible atteint, donc pas de palier mesuré) — seules
      // les extensions comptent.
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
          // Pas de bumps humil/obed.
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
  /// BPM en rampe, on prend `bpmEnd` **borné au jouable** (vitesse finale
  /// atteignable). Pour les axes profondeur, c'est `ch.to` qui porte déjà
  /// l'info. Le calcul vit dans [challengeHumiliationFloor].
  void _raiseHumiliationFloorFromRecord(_CompletedChallengeRecord record) {
    _humiliation.raiseCareerFloor(challengeHumiliationFloor(
      record.challenge,
      extensionsCount: record.extensionsCount,
    ));
  }
}
