import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../career/models/career_generation_inputs.dart';
import '../career/models/challenge.dart';
import '../career/models/coach_catalog.dart';
import '../career/models/level_milestone.dart';
import '../career/models/phrase_bank.dart';
import '../career/models/posture_unlock.dart';
import '../career/services/challenges/challenge_segment_builder.dart';
import '../career/services/generation/career_session_generator.dart';
import '../career/services/specialization_service.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show milestoneService;
import '../models/hold_move.dart';
import '../models/punishment.dart';
import '../models/posture.dart';
import '../models/session.dart';
import '../career/services/debug_settings_service.dart';
import '../models/session_step.dart' show BeatAnchor;
import '../services/ambience_engine.dart';
import '../services/backgrounds_service.dart';
import '../services/badge_service.dart';
import '../services/beep_engine.dart';
import '../services/capability_axis.dart';
import '../services/capability_service.dart';
import '../services/capability_tracker.dart';
import '../services/hold_verifier.dart';
import '../services/humiliation_engine.dart';
import '../services/music_engine.dart';
import '../services/obedience_engine.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/saliva_engine.dart';
import '../services/stamina_engine.dart';
import '../services/stats_service.dart';
import '../services/tts_service.dart';
import 'posture_gate.dart';

part 'session_controller_challenge.dart';
part 'session_controller_fail_flow.dart';
part 'session_controller_career_hooks.dart';
part 'session_controller_break.dart';

enum SessionState { idle, running, paused, finished, failing }

enum FailPhase { phrase, breath, punishment }

class SessionController extends ChangeNotifier {
  static const Duration _tickInterval = Duration(milliseconds: 200);

  /// Borne l'attente de la voix en cours (`_tts.isSpeaking`) : un moteur TTS
  /// qui ne signale jamais sa fin (service Android déconnecté, `onend` avalé
  /// par Safari/PWA) bloquerait toute phrase en attente et la reprise d'une
  /// pause.
  static const int _maxTtsDeferTicks = 25;

  /// Remplacée à chaud par [requestUpgrade].
  Session _session;
  final TtsService _tts;
  final BeepEngine _beep;
  final AmbienceEngine _ambience;
  final PunishmentBundle _punishmentBundle;
  final RandomCommentsBundle _randomComments;
  final StatsService _stats;
  final BadgeService _badges;

  final CapabilityService _capabilities;

  final CapabilityTracker? _capabilityTracker;

  /// Plafonds figés aux appuis FAIL de la séance ; vide hors carrière ou sans
  /// fail.
  Map<CapabilityAxis, double> get capabilitySessionCeilings =>
      _capabilityTracker?.sessionCeilings ?? const {};

  final int _careerLevel;

  /// Axe surchargé de la séance (`null` hors carrière ou profil neuf) ; sert
  /// aux phrases `record`.
  final CapabilityAxis? _capabilityOverloadAxis;

  /// Snapshot pris au début de la séance : attribue le tap-out et compare
  /// `reached` au `best` pré-séance (record). `null` hors carrière.
  final CapabilityProfile? _capabilityProfile;

  /// Mutable : un défi qui acquitte des milestones en séance l'élargit
  /// (`_finalizeChallengeAcquittals`) et les filtres runtime le voient
  /// aussitôt. La régénération des steps à venir est portée par le caller via
  /// `onPostChallengeRegen`.
  Set<UnlockKey> _unlockedKeys;

  final bool _includeHand;

  final bool _isQuickie;

  final HumiliationEngine _humiliation = HumiliationEngine();
  HumiliationEngine get humiliation => _humiliation;
  final ObedienceEngine _obedience = ObedienceEngine();
  ObedienceEngine get obedience => _obedience;
  final SalivaEngine _saliva = SalivaEngine();
  SalivaEngine get saliva => _saliva;

  /// Persiste d'un step à l'autre ; réinitialisé à [SwallowMode.allowed] au
  /// start et après un fail.
  SwallowMode _swallowMode = SwallowMode.allowed;
  SwallowMode get swallowMode => _swallowMode;

  int _salivaOverflowsThisSession = 0;
  static const int _salivaOverflowsCap = 3;

  /// Endurance live, distincte du `_staminaProfile` projeté par le générateur.
  final StaminaEngine _stamina = StaminaEngine();
  StaminaEngine get stamina => _stamina;

  /// `null` = vérification désactivée.
  final HoldVerifier? _holdVerifier;

  /// `null` pour les sessions statiques (déclenchement sans effet).
  final PhraseBank? _phraseBank;

  final Set<int> _announcedProgressMarkers = <int>{};

  static const List<int> _progressMarkers = [25, 50, 75, 90];

  /// Projection par seconde fournie par le générateur ; `null` pour les
  /// sessions statiques.
  List<double>? _staminaProfile;

  static const double _breathSkipStaminaThreshold = 60.0;

  static const int _breakOrderMinIntervalSeconds = 18;
  static const int _breakOrderMaxIntervalSeconds = 32;

  final Stopwatch _stopwatch = Stopwatch();

  /// Ajouté à `_stopwatch.elapsed` pour sauter dans la timeline : une Stopwatch
  /// ne peut pas être avancée.
  Duration _timelineOffset = Duration.zero;

  /// Ajouté à [playedElapsed], distinct de [_timelineOffset] : les sauts de
  /// timeline ne bougent pas le temps joué.
  Duration _playedOffset = Duration.zero;

  /// Seule la phrase attend la fin de la voix en cours ; la configuration du
  /// step s'applique à son heure.
  final List<SessionStep> _pendingSpeech = [];

  int _ttsDeferredTicks = 0;

  final Random _random = Random();
  Timer? _ticker;

  SessionState _state = SessionState.idle;
  int _nextStepIndex = 0;
  SessionStep? _lastSpoken;

  /// Mémorisée au speak : le resolver tire un surnom différent à chaque appel,
  /// l'affichage doit rester stable entre rebuilds.
  String? _lastSpokenResolvedText;

  SessionStep? _lastConfigStep;

  /// Non nul pour une séance à morceau : sa position de lecture est l'horloge
  /// de séance, le chronomètre ne sert plus qu'au temps joué.
  final MusicEngine? _music;
  bool _musicAttached = false;

  /// Position du morceau à laquelle le souffle d'un « JE PEUX PAS » musical
  /// prend fin. Nul hors souffle.
  Duration? _musicBreathUntil;

  /// Durée du souffle d'un « JE PEUX PAS » musical, en temps du morceau.
  static const int _musicBreathBeats = 16;

  /// Posé dès l'identification du step final (avant le speak) : `_finish` saute
  /// alors la phrase finale et le chime.
  bool _finalChimePlayed = false;

  /// Le `finale_chime` sonne réellement ; distinct de [_finalChimePlayed], posé
  /// avant le speak.
  bool _finaleChimeStarted = false;

  bool _finishMusicStarted = false;
  FinishTrack _finishTrack = AmbienceEngine.commonFinishTrack;

  // ─── État du flow fail ─────────────────────────────────────────────────

  FailPhase? _failPhase;
  String? _currentFailPhrase;
  Punishment? _currentPunishment;

  /// Mis à false par stop() pour interrompre les phases async.
  bool _failActive = false;

  /// Incrémenté à chaque entrée dans un flow fail : les awaits longs détectent
  /// ainsi qu'un `stop()` les a remplacés par un nouveau flow, là où le flag
  /// booléen seul peut être réarmé entre l'await et le check.
  int _failGen = 0;

  Timer? _punishmentTicker;

  /// Permet à `abandonPunishment()` de débloquer l'await de `_runPunishment`
  /// sans passer par `_failActive`, qui couperait tout le flow fail.
  Completer<void>? _punishmentCompleter;
  bool _punishmentAbandoned = false;

  Future<void> Function(int gen)? _deferredFailExit;

  // ─── État du défi intra-séance ────────────────────────────────────────

  ChallengePhase _challengePhase = ChallengePhase.none;
  ChallengePhase get challengePhase => _challengePhase;

  int? _challengeStepStartedAtSec;

  /// En secondes `_realSec` (wallclock).
  int? _challengeAtSeuilStartedAtSec;

  int _challengeExtensionsCount = 0;

  int _challengeCrossingsCount = 0;
  int get challengeCrossingsCount => _challengeCrossingsCount;

  ChallengeOutcome? _challengeOutcome;

  int _activeChallengeIndex = -1;

  /// Évite de ré-armer un défi traité quand la session reboucle sur le même
  /// `breathStartTime` après un rebase de timeline.
  final Set<int> _completedChallengeIndices = <int>{};

  /// La boucle d'armement tourne à chaque tick : sans ce verrou, la trace
  /// noierait le log.
  bool _challengeListMismatchLogged = false;

  final List<_CompletedChallengeRecord> _completedChallenges =
      <_CompletedChallengeRecord>[];

  /// `null` sans phrase coach pour l'axe : l'UI retombe sur les libellés
  /// localisés.
  String? _challengeCurrentText;

  /// Dernier texte réellement envoyé au TTS : permet de re-tenter au tick
  /// suivant si le TTS était occupé, sans doublon.
  String? _challengeSpokenText;

  Challenge? _activeChallenge;

  ChallengeSegmentBuilder? _segmentBuilder;

  SessionStep? _currentChallengeSegment;

  /// Mode restauré à la sortie d'un défi `noswallowStreak`, qui force
  /// `forbidden` pendant sa durée.
  SwallowMode? _challengeSavedSwallowMode;

  int? _challengeCountdownStartedAtSec;

  /// Évite de redire le chiffre à chaque tick (200 ms).
  int _challengeCountdownLastDigitSpoken = -1;

  /// Lit `_stopwatch.elapsed` sans `_timelineOffset` : ne suit pas le gel de la
  /// timeline pendant les défis.
  double get _realSec => _stopwatch.elapsedMilliseconds / 1000.0;

  // ─── État du break scénarisé ──────────────────────────────────────────

  /// Fenêtre `[break.time, break.endTime)` d'un break.
  bool _breakActive = false;
  bool get breakActive => _breakActive;

  ScriptedBreak? _activeBreak;
  ScriptedBreak? get activeBreak => _activeBreak;

  int _nextBreakIndex = 0;

  /// Phrase de reprise d'une pause tant que son `speak` n'a pas rendu la main.
  Future<void>? _resumeSpeech;

  /// Battements passés à attendre la phrase de reprise, `null` hors reprise.
  int? _resumeTicks;

  bool get _awaitingResumePhrase =>
      _resumeTicks != null &&
      _resumeTicks! < _maxTtsDeferTicks &&
      (_resumeSpeech != null || _tts.isSpeaking);

  /// Pauses et changements de position pas encore déclenchés, en temps absolu
  /// de la timeline courante : ce qu'une suite régénérée doit rejouer.
  PostureScript get unplayedPostureScript => PostureScript(
        breaks: _session.breaks.skip(_nextBreakIndex).toList(),
        changes: _session.postureChanges.skip(_nextPostureChangeIndex).toList(),
      );

  /// Secondes de pause encore à venir : celles de [unplayedPostureScript] plus
  /// le reste de la pause en cours. Hors effort, à retrancher de la durée
  /// restante pour obtenir l'effort restant.
  int get pauseSecondsAhead {
    final active = _activeBreak;
    final rest = _breakActive && active != null
        ? max(0, active.endTime - elapsedSeconds)
        : 0;
    return unplayedPostureScript.pauseSeconds + rest;
  }

  /// Effort restant de [fromSec] au début de la phase de fin, pauses à venir
  /// retranchées : une suite régénérée y ajoute sa propre phase de fin.
  int effortSecondsLeftFrom(int fromSec) =>
      (_session.silentFinishStartTime ?? _session.durationSeconds) -
      fromSec -
      pauseSecondsAhead;

  /// Pauses et changements de position restants, rebasés sur [fromSec] : ce que
  /// le générateur rejoue dans une suite régénérée à partir de cet instant.
  PostureScript postureCarryFrom(int fromSec) =>
      unplayedPostureScript.shifted(-fromSec);

  int _breakOrderLastAtSec = 0;

  int _breakOrderInterval = _breakOrderMinIntervalSeconds;

  Posture _currentPose = Posture.free;
  Posture get currentPose => _currentPose;

  int _nextPostureChangeIndex = 0;

  /// Lisible avant `start()`, qui seul initialise `_currentPose`.
  Posture get initialPose => _session.initialPose;

  /// Ce qui justifie le gel courant, `null` s'il n'y en a pas. Pas un drapeau à
  /// baisser : [awaitingPostureReady] rejoue la justification via [PostureGate]
  /// à chaque lecture, un chemin qui rebat la timeline n'a rien à lever.
  PostureGate? _postureGate;

  /// Gel ordonné par un step de posture dont la consigne attend la voix : il
  /// ne devient [_postureGate] qu'une fois la consigne dite.
  PostureGate? _postureGateUntilSaid;

  bool get awaitingPostureReady => _gateHolds(_postureGate);

  bool get _postureConsigneAwaited => _gateHolds(_postureGateUntilSaid);

  bool _gateHolds(PostureGate? gate) =>
      gate?.stillHolds(
        session: _session,
        nextStepIndex: _nextStepIndex,
        timelineOffset: _timelineOffset,
        failGeneration: _failGen,
        otherSceneActive: isChallengeActive || _inPostChallengeBreath,
      ) ??
      false;
  Timer? _readyTimeout;

  /// Garde-fou anti-soft-lock : reprise seule sans validation de la posture.
  static const Duration _readyTimeoutDuration = Duration(minutes: 2);

  // ─── Commentaires aléatoires ───────────────────────────────────────────

  Timer? _randomCommentTimer;

  /// Cooldown des commentaires aléatoires : trop près d'un speak scripté, ils
  /// sont reportés.
  DateTime _lastScriptedSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Posé par [detachAudio] et [dispose], jamais rebaissé. `dispose()` ne
  /// relance alors ni `tts.stop()` ni `beep.stop()` (ils couperaient la séance
  /// suivante) ; `start()` et `_finish()` ne repartent pas d'un contrôleur
  /// libéré.
  bool _released = false;

  AppLocalizations? _appLocalizations;
  void setAppLocalizations(AppLocalizations? l10n) {
    _appLocalizations = l10n;
  }

  /// `@protected` sur `ChangeNotifier.notifyListeners` n'autorise l'appel que
  /// depuis une sous-classe, pas depuis une extension : passe-plat pour les
  /// extensions `part of`.
  void _notify() => notifyListeners();

  /// Appelé par `triggerFail` quand un retry de milestone est disponible ;
  /// `true` si pris en charge (le flow fail standard est alors sauté).
  Future<bool> Function(SessionController controller)? onMilestoneRetry;

  Future<Session?> Function(SessionController controller)? onUseMeEnded;

  /// Appelé quand un défi élargit le set d'unlocks acquittés : le caller doit
  /// régénérer le reste de la séance puis appeler `requestPostChallengeRegen`.
  Future<void> Function(SessionController controller)? onPostChallengeRegen;

  /// Appelé à la fin de tout défi, quel que soit l'outcome.
  void Function(Challenge challenge, ChallengeOutcome outcome)?
      onChallengeOutcome;

  void Function(ChallengeHapticKind kind)? onChallengeHaptic;

  final SpecializationAllocation? _specialization;

  final SpecializationService? _specializationService;

  final double _miniPunishmentRate;

  /// `null` : séance sans coach.
  final String? _coachTag;

  int _miniPunishmentTickAccumulator = 0;

  Random _miniPunishmentRng = Random();

  int _miniPunishmentsTriggered = 0;
  @visibleForTesting
  int get miniPunishmentsTriggered => _miniPunishmentsTriggered;

  @visibleForTesting
  void debugSetMiniPunishmentRng(Random rng) {
    _miniPunishmentRng = rng;
  }

  /// Déclenche immédiatement le flow de mini-punition. Exposé parce que le
  /// tick coach ne le tire qu'après 60 s de séance réelle
  /// (`_accrueMiniPunishmentTick`), ce qui n'est pas testable autrement.
  @visibleForTesting
  Future<void> debugRunMiniPunishment(Punishment p) =>
      _runMiniPunishmentFlow(p);

  @visibleForTesting
  static bool computeMiniPunishmentTrigger({
    required double rate,
    required double rngValue,
  }) {
    if (rate <= 0) return false;
    return rngValue < rate;
  }

  SessionController({
    required Session session,
    required TtsService tts,
    required BeepEngine beep,
    required AmbienceEngine ambience,
    required PunishmentBundle punishmentBundle,
    required RandomCommentsBundle randomComments,
    StatsService? stats,
    BadgeService? badges,
    CapabilityService? capabilities,
    bool trackCapabilities = false,
    PhraseBank? phraseBank,
    List<double>? staminaProfile,
    HoldVerifier? holdVerifier,
    SpecializationAllocation? specialization,
    SpecializationService? specializationService,
    double miniPunishmentRate = 0.0,
    double seedHumiliationSession = 0.0,
    bool keepsBackgroundTier = false,
    int careerLevel = 0,
    CapabilityAxis? capabilityOverloadAxis,
    CapabilityProfile? capabilityProfile,
    Set<UnlockKey> unlockedKeys = const {},
    bool includeHand = true,
    bool isQuickie = false,
    String? coachTag,
    MusicEngine? music,
  })  : _session = session,
        _music = session.music == null ? null : (music ?? MusicEngine()),
        _tts = tts,
        _beep = beep,
        _ambience = ambience,
        _punishmentBundle = punishmentBundle,
        _randomComments = randomComments,
        _stats = stats ?? StatsService(),
        _badges = badges ?? BadgeService(),
        _capabilities = capabilities ?? CapabilityService(),
        _capabilityTracker = trackCapabilities ? CapabilityTracker() : null,
        _phraseBank = phraseBank,
        _staminaProfile = staminaProfile,
        _holdVerifier = holdVerifier,
        _specialization = specialization,
        _specializationService = specializationService,
        _miniPunishmentRate = miniPunishmentRate,
        _seedHumiliationSession = seedHumiliationSession,
        _keepsBackgroundTier = keepsBackgroundTier,
        _careerLevel = careerLevel,
        _capabilityOverloadAxis = capabilityOverloadAxis,
        _capabilityProfile = capabilityProfile,
        _unlockedKeys = Set<UnlockKey>.from(unlockedKeys),
        _includeHand = includeHand,
        _isQuickie = isQuickie,
        _coachTag = coachTag {
    _beep.onBeat = _handleBeat;
  }

  /// Valeur initiale du `sessionScore` d'humiliation ; un encore enchaîné
  /// reprend celui de la session précédente.
  final double _seedHumiliationSession;

  final bool _keepsBackgroundTier;

  /// Si la voix est occupée, l'annonce est perdue et le palier reste marqué.
  void _handleProgressMarker(int threshold) {
    final bank = _phraseBank;
    if (bank == null) return;
    final phrase = bank.pickProgress(threshold, _random);
    if (phrase == null || phrase.isEmpty) return;
    if (_tts.isSpeaking) return;
    _tts.speak(phrase);
  }

  /// Une seule phrase par tick, pour ne pas enchaîner deux annonces.
  void _checkProgressMarkers() {
    final total = session.durationSeconds;
    if (total <= 0) return;
    // Step final entamé : le chime a déjà sonné, les paliers pré-orgasme n'ont
    // plus de sens ; on les marque annoncés sans parler.
    if (_finalChimePlayed) {
      final percent = (elapsedSeconds * 100 / total).floor();
      for (final marker in _progressMarkers) {
        if (percent >= marker) _announcedProgressMarkers.add(marker);
      }
      return;
    }
    final percent = (elapsedSeconds * 100 / total).floor();
    for (final marker in _progressMarkers) {
      if (percent >= marker && !_announcedProgressMarkers.contains(marker)) {
        _announcedProgressMarkers.add(marker);
        _handleProgressMarker(marker);
        return;
      }
    }
  }

  void _maybeFireTransitionPhrase(SessionStep previous, SessionStep current) {
    final bank = _phraseBank;
    if (bank == null) return;
    final prevMode = previous.mode ?? session.defaultMode;
    final currMode = current.mode ?? session.defaultMode;
    if (prevMode != currMode) return;

    final kind = _detectTransitionKind(previous, current);
    if (kind == null) return;

    if (_tts.isSpeaking) return;
    final since = DateTime.now().difference(_lastScriptedSpeakAt).inSeconds;
    if (since < 2) return;

    final phrase = bank.pickTransition(kind, _random);
    if (phrase == null || phrase.isEmpty) return;
    _tts.speak(phrase);
  }

  TransitionKind? _detectTransitionKind(
    SessionStep previous,
    SessionStep current,
  ) {
    final prevDepth = previous.to ?? previous.from;
    final currDepth = current.to ?? current.from;
    if (prevDepth != null && currDepth != null) {
      if (currDepth.index > prevDepth.index) return TransitionKind.depthUp;
      if (currDepth.index < prevDepth.index) return TransitionKind.depthDown;
    }
    final prevBpm = previous.bpm;
    final currBpm = current.bpm;
    if (prevBpm != null && currBpm != null && prevBpm > 0) {
      final delta = (currBpm - prevBpm) / prevBpm;
      if (delta >= 0.10) return TransitionKind.speedUp;
      if (delta <= -0.10) return TransitionKind.speedDown;
    }
    return null;
  }

  void _handleBeat(BeatEvent e) {
    // Un défi surcharge volontairement : il ne compte pas dans les stats
    // lifetime.
    if (!_session.noStats && !isChallengeActive) {
      _stats.recordBeat(mode: e.mode, to: e.to);
      _stats.markModeUsed(e.mode);
    } else {
      _onChallengeBeatIfCrossingsTracked(e);
    }
    _stamina.onBeat(e);
  }

  void _onChallengeBeatIfCrossingsTracked(BeatEvent e) {
    final ch = _activeChallenge;
    if (ch == null || ch.targetCrossings == null) return;
    if (_challengePhase != ChallengePhase.live) {
      return;
    }
    final target = ch.to;
    if (target == null) return;
    if (e.to == target) _challengeCrossingsCount++;
  }

  bool _hadFailThisSession = false;

  bool get hadFailThisSession => _hadFailThisSession;

  static const Duration useMeUnlockAfter = Duration(minutes: 2);
  static const Duration useMeUnlockStep = Duration(minutes: 1);

  Duration _playedAtLastFail = Duration.zero;
  bool _useMeActive = false;
  Duration _useMeStartedPlayed = Duration.zero;
  int _useMeFailEndings = 0;

  bool get useMeActive => _useMeActive;

  Duration get useMeUnlockDelay =>
      useMeUnlockAfter + useMeUnlockStep * _useMeFailEndings;

  bool get useMeUnlocked =>
      playedElapsed - _playedAtLastFail >= useMeUnlockDelay;

  Future<void> _endUseMe() async {
    if (!_useMeActive) return;
    _useMeActive = false;
    final held = playedElapsed - _useMeStartedPlayed;
    _capabilityTracker?.recordUseMeHeld(held.inSeconds);
    await _stats.recordUseMeHeld(held.inSeconds);
  }

  void _trackConfigStep(SessionStep step) {
    _capabilityTracker?.onStepApplied(
      mode: step.mode ?? session.defaultMode,
      from: step.from,
      to: step.to,
      bpm: step.bpm,
      duration: step.duration,
      useMe: step.useMe,
    );
  }

  @visibleForTesting
  void debugAddPlayed(Duration d) => _playedOffset += d;

  List<BadgeUnlock> _sessionBadgeUnlocks = const [];
  List<BadgeUnlock> get sessionBadgeUnlocks => _sessionBadgeUnlocks;

  List<BadgeUnlock> _pendingBadgeUnlocks = const [];

  List<LevelMilestone> _sessionMilestoneUnlocks = const [];
  List<LevelMilestone> get sessionMilestoneUnlocks => _sessionMilestoneUnlocks;

  bool get milestoneAcquittedThisSession => _sessionMilestoneUnlocks.isNotEmpty;

  bool _milestoneOpportunityMissed() {
    final ids = <String?>[
      _session.milestoneId,
      _session.secondMilestoneId,
      _session.finalMilestoneId,
    ];
    for (final id in ids) {
      if (id == null) continue;
      if (!milestoneService.isCompleted(id)) return true;
    }
    return false;
  }

  /// Secondes passées dans la position courante en hold throat/full.
  int _currentHoldFullDuration = 0;

  int _lastHoldTickAtSecond = -1;

  void updateStaminaProfile(List<double>? profile) {
    _staminaProfile = profile;
  }

  bool _isInLastMinute() {
    return remaining.inSeconds <= 60 && remaining.inSeconds >= 0;
  }

  bool _isInMilestoneWindow() => currentMilestoneIdInWindow != null;

  /// Id de la milestone dont la fenêtre contient `elapsedSeconds`, ou `null`.
  String? get currentMilestoneIdInWindow {
    final t = elapsedSeconds;
    bool within(int? start, int? dur) {
      if (start == null || dur == null) return false;
      return t >= start && t < start + dur;
    }

    if (within(
        _session.milestoneStartTime, _session.milestoneDurationSeconds)) {
      return _session.milestoneId;
    }
    if (within(_session.secondMilestoneStartTime,
        _session.secondMilestoneDurationSeconds)) {
      return _session.secondMilestoneId;
    }
    if (within(_session.finalMilestoneStartTime,
        _session.finalMilestoneDurationSeconds)) {
      return _session.finalMilestoneId;
    }
    return null;
  }

  double? _staminaAtNow() {
    final profile = _staminaProfile;
    if (profile == null || profile.isEmpty) return null;
    final idx = elapsedSeconds.clamp(0, profile.length - 1);
    return profile[idx];
  }

  // ─── Getters d'état ────────────────────────────────────────────────────

  Session get session => _session;
  SessionState get state => _state;
  Duration get elapsed {
    final music = _music;
    if (music != null && _state != SessionState.idle) {
      return music.position + Duration(milliseconds: _musicBeepAdvanceMs);
    }
    return _stopwatch.elapsed + _timelineOffset;
  }

  bool get isMusical => _music != null;

  static const int musicBeepAdvanceMaxMs = 400;
  static const int musicBeepAdvanceStepMs = 10;
  int _musicBeepAdvanceMs = DebugSettingsService.defaultMusicBeepAdvanceMs;

  int get musicBeepAdvanceMs => _music == null ? 0 : _musicBeepAdvanceMs;

  Future<void> setMusicBeepAdvanceMs(int ms) async {
    if (_music == null) return;
    _musicBeepAdvanceMs = ms.clamp(0, musicBeepAdvanceMaxMs);
    _beep.musicBeepAdvance = Duration(milliseconds: _musicBeepAdvanceMs);
    notifyListeners();
    await DebugSettingsService().setMusicBeepAdvanceMs(_musicBeepAdvanceMs);
  }

  /// Vrai pendant le souffle d'un « JE PEUX PAS » sur une séance à morceau :
  /// la séance reste `running`, la musique continue.
  bool get isMusicBreathing => _musicBreathUntil != null;

  /// Vrai tant que `_onTick` gèle l'horloge de séance (défi, respiration de
  /// récupération, posture et sa consigne, phrase de reprise d'une pause) : les
  /// instants des steps à venir ne situent alors plus rien. `_onTick` passe par ce getter pour ne pas
  /// diverger.
  bool get isTimelineFrozen =>
      isChallengeActive ||
      _inPostChallengeBreath ||
      awaitingPostureReady ||
      _postureConsigneAwaited ||
      _awaitingResumePhrase;
  int get elapsedSeconds => elapsed.inSeconds;

  /// Temps réellement joué, pauses exclues, défis compris. Contrairement à
  /// [elapsed] (horloge de **timeline**, gelée pendant les défis et sautée
  /// après un fail), c'est lui que l'écran de fin affiche et que `_finish`
  /// crédite au temps de jeu cumulé.
  Duration get playedElapsed => _stopwatch.elapsed + _playedOffset;
  int get playedSeconds => playedElapsed.inSeconds;
  Duration get remaining {
    final r = session.duration - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  SessionStep? get lastSpoken => _lastSpoken;

  /// Version résolue (`{name}` substitué) de la dernière phrase parlée, ou de
  /// la phrase de fail en cours.
  String? get currentDisplayText {
    if (_state == SessionState.failing && _currentFailPhrase != null) {
      return _currentFailPhrase;
    }
    return _lastSpokenResolvedText;
  }

  bool _configApplied = false;
  bool get hasConfig => _configApplied;

  SessionMode get currentMode => _beep.currentMode;
  Position get currentFrom => _beep.currentFrom;
  Position? get currentTo => _beep.currentTo;
  int get currentBpm => _beep.currentBpm;
  List<HoldMove> get currentMoves => _beep.currentMoves;

  double get progress {
    if (session.durationSeconds == 0) return 0;
    final p = elapsed.inMilliseconds / (session.durationSeconds * 1000);
    return p.clamp(0.0, 1.0);
  }

  bool get isRunning => _state == SessionState.running;
  bool get isPaused => _state == SessionState.paused;
  bool get isFinished => _state == SessionState.finished;
  bool get isIdle => _state == SessionState.idle;
  bool get isFailing => _state == SessionState.failing;

  /// Vrai de l'arrêt de l'horloge à son redémarrage, délai de reprise du moteur
  /// compris : [isRunning] l'est déjà alors que l'horloge est encore gelée.
  bool get isFailFlowActive => _failActive;

  bool get finaleChimeStarted => _finaleChimeStarted;

  FailPhase? get failPhase => _failPhase;
  String? get currentFailPhrase => _currentFailPhrase;
  Punishment? get currentPunishment => _currentPunishment;

  /// Actif aussi pendant la phase punishment, pour abandonner la punition.
  bool get canTriggerFail {
    if (_music != null) {
      return _state == SessionState.running && _musicBreathUntil == null;
    }
    return (_state == SessionState.running &&
            !_failActive &&
            _punishmentBundle.isEmpty == false) ||
        (_state == SessionState.failing && _failPhase == FailPhase.punishment);
  }

  // ─── Ambiance ──────────────────────────────────────────────────────────

  double get ambienceVolume => _ambience.volume;

  Future<void> setAmbienceVolume(double v) async {
    await _ambience.setVolume(v);
    notifyListeners();
  }

  Future<void> _syncAmbienceToCurrentMode() async {
    if (_music != null) return;
    final from = _beep.currentFrom;
    final to = _beep.currentTo;
    await _ambience.playForMode(
      _beep.currentMode,
      depth: to != null && to.index > from.index ? to : from,
    );
  }

  // ─── Cycle principal ───────────────────────────────────────────────────

  bool _starting = false;
  bool _appInBackground = false;
  bool _backgroundedDuringStart = false;

  bool get appInBackground => _appInBackground;

  void onAppBackgrounded() {
    _appInBackground = true;
    if (_starting) _backgroundedDuringStart = true;
    notifyListeners();
    unawaited(pause());
  }

  void onAppForegrounded() {
    _appInBackground = false;
    notifyListeners();
  }

  Future<void> start() async {
    // Synchrone : un double-clic entre deux fois avant que `_state` ne bascule.
    if (_starting) return;
    if (_state == SessionState.running) return;
    _starting = true;
    _backgroundedDuringStart = _appInBackground;
    try {
      if (_state == SessionState.idle || _state == SessionState.finished) {
        _stopwatch.reset();
        _timelineOffset = Duration.zero;
        _playedOffset = Duration.zero;
        _playedAtLastFail = Duration.zero;
        _useMeActive = false;
        _useMeFailEndings = 0;
        _dropPendingSpeech();
        _nextStepIndex = 0;
        _lastSpoken = null;
        _lastSpokenResolvedText = null;
        _lastConfigStep = null;
        _configApplied = false;
        _deferredFailExit = null;
        _hadFailThisSession = false;
        _finalChimePlayed = _music != null;
        _musicBreathUntil = null;
        _finaleChimeStarted = false;
        _finishMusicStarted = false;
        _sessionBadgeUnlocks = const [];
        _sessionMilestoneUnlocks = const [];
        _currentHoldFullDuration = 0;
        _lastHoldTickAtSecond = -1;
        _miniPunishmentTickAccumulator = 0;
        _miniPunishmentsTriggered = 0;
        _announcedProgressMarkers.clear();
        _breakActive = false;
        _activeBreak = null;
        _nextBreakIndex = 0;
        _nextPostureChangeIndex = 0;
        _breakOrderLastAtSec = 0;
        _currentPose = _session.initialPose;
        _postureGate = null;
        _readyTimeout?.cancel();
        _readyTimeout = null;
        _capabilityTracker?.onSessionStart();
        _humiliation.seed(career: 0, session: _seedHumiliationSession);
        _obedience.seed(0);
        _saliva.reset();
        _swallowMode = SwallowMode.allowed;
        _salivaOverflowsThisSession = 0;
        if (milestoneService.hasUnlock(UnlockKey.sloppyDroolBasic)) {
          _saliva.setLickProductionMultiplier(1.5);
          _saliva.setMax(SalivaEngine.sloppyBaseMax);
        } else {
          _saliva.setMax(SalivaEngine.defaultMax);
        }
        if (milestoneService.hasUnlock(UnlockKey.sloppyBiffleSlow)) {
          _saliva.setBiffleProductionMultiplier(3.0);
        }
        _stamina.reset();
        // Lectures async : valeurs neutres tant qu'elles n'ont pas répondu.
        _stats.getHumiliationLevel().then(
              (h) => _humiliation.seed(
                career: h,
                session: _seedHumiliationSession,
              ),
            );
        _stats.getObedienceLevel().then(_obedience.seed);
      }

      // Inits best-effort : un échec ne doit jamais avorter `start()` (iOS
      // Safari/PWA : `_state` resterait `idle`, sans bouton play en prod).
      try {
        // Le `try/catch` n'attrape que les exceptions : un canal muet rend un
        // Future qui ne se complète jamais, d'où la borne.
        await _tts.init().timeout(const Duration(seconds: 2), onTimeout: () {});
      } catch (e) {
        debugPrint('start(): _tts.init() a échoué (non bloquant) : $e');
      }
      if (_released) return;
      try {
        await _beep.init();
      } catch (e) {
        debugPrint('start(): _beep.init() a échoué (non bloquant) : $e');
      }
      if (_released) return;
      _finishTrack = await _ambience.finishTrackFor(_coachTag).timeout(
          const Duration(seconds: 2),
          onTimeout: () => AmbienceEngine.commonFinishTrack);
      if (_released) return;
      final music = _music;
      final track = _session.music;
      if (music != null && track != null) {
        try {
          _musicBeepAdvanceMs =
              (await DebugSettingsService().getMusicBeepAdvanceMs())
                  .clamp(0, musicBeepAdvanceMaxMs);
        } catch (_) {}
        if (_released) return;
        await music.start(track);
        if (_released) return;
        _beep.attachMusic(track, () => music.position);
        _beep.musicBeepAdvance = Duration(milliseconds: _musicBeepAdvanceMs);
        _musicAttached = true;
      } else {
        _beep.detachMusic();
      }
      try {
        // Sur iOS Safari/PWA la Wake Lock API exige un geste utilisateur et
        // peut lever `NotAllowedError`. Borné comme `_tts.init()` : un canal
        // muet laisserait `_starting` collé à `true`.
        await WakelockPlus.enable().timeout(_wakelockTimeout);
      } catch (e) {
        debugPrint(
            'start(): WakelockPlus.enable() a échoué (non bloquant) : $e');
      }
      if (_released) {
        await WakelockPlus.disable()
            .timeout(_wakelockTimeout, onTimeout: () {});
        return;
      }

      BackgroundsService.instance.clear(keepTier: _keepsBackgroundTier);
      _lastBackgroundContext = null;
      _failMoment = null;
      _failBackgroundShown = false;

      if (_backgroundedDuringStart) {
        await _music?.pause();
        _state = SessionState.paused;
        notifyListeners();
        return;
      }

      _stopwatch.start();
      _state = SessionState.running;
      _startTicker();
      _startRandomComments();
      notifyListeners();
      _checkSteps();
    } finally {
      _starting = false;
    }
  }

  /// Borne de tous les appels de coupure du canal de synthèse : il reste
  /// best-effort et ne doit jamais retarder une bascule d'état.
  static const Duration _ttsStopTimeout = Duration(milliseconds: 300);

  /// Borne des appels à `wakelock_plus` : un simple toggle natif répond
  /// immédiatement, et le wakelock ne doit jamais retarder le passage en
  /// `running`, `idle` ou `finished`.
  static const Duration _wakelockTimeout = Duration(milliseconds: 300);

  /// Borne des deux `speak` attendus avant une bascule d'état (phrase de fail,
  /// phrase finale) : calibrée sur la durée d'énoncé du contenu, surveillée par
  /// `session_freeze_tts_speaking_test.dart`. Délibérément non alignée sur le
  /// watchdog de 60 s de `TtsService` : `timeout` libère l'appelant sans couper
  /// la synthèse.
  @visibleForTesting
  static const Duration ttsSpeakTimeout = Duration(seconds: 20);

  /// Coupe le canal de synthèse sans jamais bloquer l'appelant.
  ///
  /// Tout chemin qui arrête la séance coupe d'abord le TTS, puis bascule son
  /// état. Quand le plugin met ses appels en file (perte de connexion au
  /// service TTS Android), ce Future ne se complète jamais : sans borne, ticker
  /// et chronomètre sont arrêtés mais `_state` ne change plus.
  Future<void> _stopTtsBounded() =>
      _tts.stop().timeout(_ttsStopTimeout, onTimeout: () {});

  /// Prononce [text] sans jamais bloquer l'appelant au-delà de
  /// [ttsSpeakTimeout]. Réservé aux deux `speak` qui précèdent une bascule
  /// d'état : les autres sont soit fire-and-forget, soit post-bascule, et un
  /// moteur muet n'y coûte qu'une phrase silencieuse.
  Future<void> _speakBounded(String text) =>
      _tts.speak(text).timeout(ttsSpeakTimeout, onTimeout: () {});

  Future<void> pause() async {
    if (_state != SessionState.running || _failActive) return;
    final musicPaused = _music?.pause();
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    _disarmHoldVerifier();
    // Borné : sinon `_state` resterait `running` avec ticker et chronomètre
    // déjà arrêtés (`resume()` sortirait immédiatement).
    await _stopTtsBounded();
    await _beep.pause();
    await musicPaused;
    await _ambience.pause();
    _state = SessionState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_state != SessionState.paused) return;
    final failExit = _deferredFailExit;
    if (failExit != null) {
      _deferredFailExit = null;
      await _replayDeferredFailExit(failExit);
      notifyListeners();
      return;
    }
    final musicResumed = _music?.resume();
    _stopwatch.start();
    _state = SessionState.running;
    _startTicker();
    _startRandomComments();
    // Pendant une pause scénarisée ou l'attente de mise en place, le loop
    // d'effort est coupé et le step posé après le trou le reconfigure : le
    // reprendre ici ferait repartir l'effort en pleine pause. Même paire de
    // gardes que le gel d'accrual dans `_onTick`. L'ambiance n'est pas coupée
    // par le break : elle reprend inconditionnellement. Avant le premier step de
    // config, la config par défaut du moteur ferait battre un rythme fantôme.
    if (_configApplied && !_breakActive && !awaitingPostureReady) {
      await _beep.resume();
    }
    await musicResumed;
    if (_music == null) await _ambience.resume();
    notifyListeners();
  }

  Future<void> stop() async {
    _failActive = false;
    _punishmentTicker?.cancel();
    _punishmentTicker = null;
    _stopRandomComments();
    _disarmHoldVerifier();

    _stopwatch.stop();
    _stopwatch.reset();
    _timelineOffset = Duration.zero;
    _playedOffset = Duration.zero;
    _playedAtLastFail = Duration.zero;
    _useMeActive = false;
    _useMeFailEndings = 0;
    _ticker?.cancel();
    _ticker = null;
    // Borné, comme dans `pause()` : un canal de synthèse muet ne doit pas
    // empêcher le retour à `idle`.
    await _stopTtsBounded();
    await _beep.stop();
    await _releaseMusic();
    await _ambience.stop();
    await _ambience.stopFinishMusic();
    // Borné comme le canal de synthèse : `_state` ne bascule qu'après, ticker
    // déjà annulé.
    await WakelockPlus.disable().timeout(_wakelockTimeout, onTimeout: () {});

    _state = SessionState.idle;
    _dropPendingSpeech();
    _nextStepIndex = 0;
    _lastSpoken = null;
    _lastSpokenResolvedText = null;
    _lastConfigStep = null;
    _configApplied = false;
    _failPhase = null;
    _currentFailPhrase = null;
    _currentPunishment = null;
    _hadFailThisSession = false;
    _currentHoldFullDuration = 0;
    _lastHoldTickAtSecond = -1;
    // Le `Timer` de sécurité du gel survivrait à l'arrêt et réveillerait plus
    // tard un contrôleur inactif.
    _postureGate = null;
    _readyTimeout?.cancel();
    _readyTimeout = null;
    _challengePhase = ChallengePhase.none;
    _challengeStepStartedAtSec = null;
    _challengeAtSeuilStartedAtSec = null;
    _challengeExtensionsCount = 0;
    _challengeOutcome = null;
    _challengeCurrentText = null;
    _challengeSpokenText = null;
    _activeChallenge = null;
    _challengeCountdownStartedAtSec = null;
    _challengeCountdownLastDigitSpoken = -1;
    _postChallengeBreathRealEndSec = null;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
  }

  Future<void> debugFinishSuccess() async {
    if (_state != SessionState.running && _state != SessionState.paused) {
      return;
    }
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    _stopRandomComments();
    await _tts.stop();
    await _beep.stop();
    // Cale les deux horloges sur la durée totale : la logique pour que les
    // steps de fin soient considérés joués, celle du temps joué pour que les
    // compteurs cumulés (badges, points de spé) créditent la session entière.
    final missing = Duration(seconds: session.durationSeconds) - elapsed;
    if (missing > Duration.zero) _timelineOffset += missing;
    final missingPlayed =
        Duration(seconds: session.durationSeconds) - playedElapsed;
    if (missingPlayed > Duration.zero) _playedOffset += missingPlayed;
    _hadFailThisSession = false;
    await _finish();
  }

  @visibleForTesting
  void debugTick() => _onTick();

  void _onTick() {
    _burySpentPostureGate();
    // `_updateChallengePhase` AVANT `_checkSteps` : si la fin nominale du step
    // défi est franchie à ce tick, la phase doit basculer en `atSeuil` avant
    // que `_checkSteps` ne consomme le step suivant.
    _updateChallengePhase();
    // Avant `_checkSteps` : à la sortie d'un break, `_breakActive` doit être
    // relâché pour que `_checkSteps` applique le step d'effort qui suit le
    // trou.
    _updateBreakPhase();
    // Après `_updateBreakPhase` : fenêtres disjointes.
    _updateMilestonePose();
    _updatePostureChange();
    _checkSteps();
    _refreshBackgroundTier();
    _speakPendingWhenFree();
    // Gel de l'effort pendant un break : pas de crédit hold/saliva/stamina/
    // mini-punition ni de marqueurs de progression.
    if (!_breakActive && !awaitingPostureReady) {
      _accrueHoldSecond();
      _checkProgressMarkers();
    }
    // Les transitions internes du défi sont mesurées sur `_realSec`, jamais
    // gelé : sinon `_inPostChallengeBreath` ne se terminerait jamais, son seuil
    // n'étant jamais franchi par un `elapsedSeconds` gelé.
    if (isTimelineFrozen) {
      _timelineOffset -= _tickInterval;
    }
    if (elapsedSeconds >= session.durationSeconds) {
      _finish();
      return;
    }
    notifyListeners();
  }

  /// Une seule fois par `elapsedSeconds` (le ticker tourne à 200 ms).
  void _accrueHoldSecond() {
    final now = elapsedSeconds;
    if (now == _lastHoldTickAtSecond) return;
    _lastHoldTickAtSecond = now;
    _capabilityTracker?.onTickSecond(
      swallowMode: _swallowMode,
      useMeActive: _useMeActive,
    );
    _obedience.onTickSecond();
    _humiliation.onTickSecond(obedienceLevel: _obedience.score);
    _stamina.setCurrentMode(
      _beep.currentMode,
      from: _beep.currentFrom,
      bpm: _beep.currentBpm,
    );
    _stamina.onTickSecond();
    _saliva.onTickSecond(
      mode: _beep.currentMode,
      from: _beep.currentFrom,
      to: _beep.currentTo,
      swallowMode: _swallowMode,
      elapsedSecond: now,
    );
    final overflows = _saliva.popOverflowEvents();
    if (overflows > 0) {
      final remaining = _salivaOverflowsCap - _salivaOverflowsThisSession;
      final apply = overflows > remaining ? remaining : overflows;
      for (var i = 0; i < apply; i++) {
        _humiliation.onSalivaOverflow();
      }
      _salivaOverflowsThisSession += apply;
    }
    _accrueMiniPunishmentTick();
    if (_beep.currentMode != SessionMode.hold) return;
    final pos = _beep.currentFrom;
    if (pos == Position.throat || pos == Position.full) {
      if (!_session.noStats) {
        _stats.recordHoldSecond(pos);
      }
      if (pos == Position.full) {
        _currentHoldFullDuration++;
      }
    }
  }

  void _flushHoldFull() {
    if (_currentHoldFullDuration > 0) {
      if (!_session.noStats) {
        _stats.recordHoldFullCompleted(_currentHoldFullDuration);
      }
      _currentHoldFullDuration = 0;
    }
  }

  void _armHoldVerifierIfHoldStep(SessionStep step) {
    final verifier = _holdVerifier;
    if (verifier == null) return;
    if (!shouldArmHoldVerifier(step, session.defaultMode)) return;
    // La cible d'un hold est `step.to` ; `applyStep`, déjà appelé, l'a reflété
    // dans `currentFrom`, sur lequel on se rabat sans override.
    final expected = step.to ?? _beep.currentFrom;
    verifier.arm(expected);
  }

  @visibleForTesting
  static bool shouldArmHoldVerifier(SessionStep step, SessionMode defaultMode) {
    final mode = step.mode ?? defaultMode;
    return mode == SessionMode.hold && step.anchor != BeatAnchor.to;
  }

  @visibleForTesting
  static String? backgroundTierFor(int seconds, Session session) {
    final finish = session.silentFinishStartTime ?? session.finalStepTime;
    final total = session.durationSeconds;
    if ((finish != null && seconds >= finish) || seconds * 3 >= total * 2) {
      return 'nu2';
    }
    return seconds * 3 >= total ? 'nu1' : null;
  }

  BackgroundContext? _lastBackgroundContext;
  String? _failMoment;
  bool _failBackgroundShown = false;

  void _pickBackground(BackgroundContext ctx, {bool playerScene = false}) {
    _lastBackgroundContext = ctx;
    BackgroundsService.instance.pickForContext(ctx, playerScene: playerScene);
  }

  void _refreshBackgroundTier() {
    final last = _lastBackgroundContext;
    if (last == null) return;
    final tier = backgroundTierFor(elapsedSeconds, _session);
    if (tier == null ||
        (last.tier != null && tier.compareTo(last.tier!) <= 0)) {
      return;
    }
    _pickBackground(BackgroundContext(
      mode: last.mode,
      position: last.position,
      coach: last.coach,
      phase: last.phase,
      tier: tier,
    ));
  }

  // Dérivé de l'état : tous les chemins d'échec (JE PEUX PAS, mini-punition,
  // séance musicale) passent par `failing`.
  @override
  void notifyListeners() {
    final moment = _state != SessionState.failing
        ? null
        : (_failPhase == FailPhase.punishment ? 'punish' : 'fail');
    if (moment != _failMoment) {
      _failMoment = moment;
      final backgrounds = BackgroundsService.instance;
      if (moment == 'punish') {
        _failBackgroundShown =
            backgrounds.pickPunish(_coachTag) || _failBackgroundShown;
      } else if (moment == 'fail') {
        _failBackgroundShown =
            backgrounds.pickFail(_coachTag) || _failBackgroundShown;
      } else if (_failBackgroundShown) {
        _failBackgroundShown = false;
        final last = _lastBackgroundContext;
        if (last != null) backgrounds.pickForContext(last);
      }
    }
    super.notifyListeners();
  }

  BackgroundContext _buildBackgroundContext(
    SessionStep step,
    SessionMode resolvedMode,
  ) {
    final pos = step.to ?? step.from;
    String? phase;
    final finalT = _session.finalStepTime;
    if (finalT != null) {
      if (step.time == finalT) {
        phase = 'final';
      } else if (step.time > finalT) {
        phase = 'post-final';
      }
    }
    return BackgroundContext(
      mode: resolvedMode.name,
      position: pos?.name,
      coach: _coachTag,
      phase: phase,
      tier: backgroundTierFor(elapsedSeconds, _session),
    );
  }

  void pickIntroBackground() {
    BackgroundsService.instance
        .pickIntro(_coachTag, tier: backgroundTierFor(0, _session));
  }

  BackgroundContext _buildChallengeBackgroundContext(SessionStep segment) {
    final pos = segment.to ?? segment.from;
    return BackgroundContext(
      mode: (segment.mode ?? _session.defaultMode).name,
      position: pos?.name,
      coach: _coachTag,
      phase: 'challenge',
      tier: backgroundTierFor(elapsedSeconds, _session),
    );
  }

  void _disarmHoldVerifier() {
    final verifier = _holdVerifier;
    if (verifier == null || !verifier.isArmed) return;
    final report = verifier.disarm();
    if (kDebugMode && report.armedWithDetection) {
      debugPrint(
        '[HoldVerifier] accuracy=${(report.accuracy * 100).toStringAsFixed(0)}%'
        ' total=${report.total.inMilliseconds}ms'
        ' maxDrift=${report.maxDrift.inMilliseconds}ms'
        ' nudges=${report.nudges}',
      );
    }
  }

  void _checkSteps() {
    // `atSeuil` : le step défi continue de jouer son loop, les suivants
    // attendent.
    if (_challengePhase == ChallengePhase.atSeuil) {
      return;
    }
    // Pareil pendant le breath de récup post-défi.
    if (_inPostChallengeBreath) return;
    // Gate posture : le step d'effort suivant attend la confirmation.
    if (awaitingPostureReady || _postureConsigneAwaited) return;
    if (_awaitingResumePhrase) return;
    final s = elapsedSeconds;
    var modeChanged = false;
    final breathUntil = _musicBreathUntil;
    if (breathUntil != null) {
      while (_nextStepIndex < session.steps.length &&
          session.steps[_nextStepIndex].time <= s) {
        _nextStepIndex++;
      }
      if (elapsed < breathUntil) return;
      _endMusicBreath(s);
    }
    while (_nextStepIndex < session.steps.length &&
        session.steps[_nextStepIndex].time <= s) {
      final step = session.steps[_nextStepIndex];

      // Toggle déglutition (sticky), AVANT l'éventuelle config de bip. Le
      // retour à `allowed` est toujours permis, le forçage à `forbidden` exige
      // l'unlock.
      final stepSwallow = step.swallowMode;
      if (stepSwallow != null) {
        final previous = _swallowMode;
        if (stepSwallow == SwallowMode.allowed ||
            milestoneService.hasUnlock(UnlockKey.sloppySwallowControl)) {
          _swallowMode = stepSwallow;
          if (previous == SwallowMode.forbidden &&
              stepSwallow == SwallowMode.allowed) {
            _saliva.forceSwallow();
            _obedience.onPunishmentCompleted();
          }
        }
      }

      if (!step.isTextOnly) {
        // Un fail interrompt avant ce flush : seul un hold full mené à terme
        // est crédité.
        _flushHoldFull();
        _disarmHoldVerifier();
        final previousConfig = _lastConfigStep;
        _beep.applyStep(step, session.defaultMode);
        final resolvedMode = step.mode ?? session.defaultMode;
        if (!_session.noStats) {
          _stats.markModeUsed(resolvedMode);
        }
        _configApplied = true;
        _lastConfigStep = step;
        modeChanged = true;
        _trackConfigStep(step);
        _armHoldVerifierIfHoldStep(step);
        _pickBackground(
          _buildBackgroundContext(step, resolvedMode),
          playerScene:
              resolvedMode != SessionMode.beg && !_isInMilestoneWindow(),
        );
        if (_music == null && step.text.isEmpty && previousConfig != null) {
          _maybeFireTransitionPhrase(previousConfig, step);
        }
      }

      // Posé après `pickForContext` pour gagner si les deux s'appliquent au
      // même tick.
      if (step.background != null) {
        BackgroundsService.instance.setById(step.background!);
      }

      final finalT = session.finalStepTime;
      final isFinal = finalT != null && step.time == finalT;
      if (isFinal) _dropPendingSpeech();
      final speechWaits = step.text.isNotEmpty &&
          _music == null &&
          !isFinal &&
          (_tts.isSpeaking || _pendingSpeech.isNotEmpty);
      if (speechWaits) {
        _pendingSpeech.add(step);
      } else if (step.text.isNotEmpty) {
        _lastSpoken = step;
        _speakScripted(step.text);
      }

      // Le `finale_chime` part PENDANT le step final, une fois sa phrase
      // d'action terminée. Fire-and-forget pour ne pas bloquer le tick.
      if (isFinal && !_finalChimePlayed) {
        _finalChimePlayed = true;
        unawaited(_playFinalChimeAfterAction(step.text));
      }
      _updateFinishMusic(step);

      _nextStepIndex++;

      if (step.awaitReady) {
        if (speechWaits) {
          _postureGateUntilSaid = _newPostureGate();
        } else {
          _enterAwaitReady();
        }
        break;
      }
    }
    _fadeFinishMusicAtFinalEnd(s);
    if (modeChanged) {
      _syncAmbienceToCurrentMode();
    }
  }

  void _updateFinishMusic(SessionStep step) {
    final finalT = session.finalStepTime;
    final finishStart = session.silentFinishStartTime;
    if (_music != null || finalT == null || finishStart == null) return;
    if (step.time > finalT) {
      if (!step.isTextOnly) {
        unawaited(_ambience.fadeOutFinishMusic());
      }
      return;
    }
    final peak = _finishTrack.peak.inSeconds;
    if (_finishMusicStarted || step.time < max(finishStart, finalT - peak)) {
      return;
    }
    _finishMusicStarted = true;
    unawaited(_ambience.startFinishMusic(
        Duration(seconds: finalT - step.time), _finishTrack));
  }

  void _fadeFinishMusicAtFinalEnd(int elapsedSeconds) {
    final step = _lastConfigStep;
    final duration = step?.duration;
    if (!_finishMusicStarted ||
        step == null ||
        duration == null ||
        step.time != session.finalStepTime ||
        elapsedSeconds < step.time + duration) {
      return;
    }
    _finishMusicStarted = false;
    unawaited(_ambience.fadeOutFinishMusic());
  }

  /// Prononce la plus ancienne phrase en attente dès que la voix se libère.
  /// Passé [_maxTtsDeferTicks], elle part quand même (au pire une phrase est
  /// coupée).
  void _speakPendingWhenFree() {
    if (_pendingSpeech.isEmpty) return;
    if (_tts.isSpeaking && _ttsDeferredTicks < _maxTtsDeferTicks) {
      _ttsDeferredTicks++;
      return;
    }
    _ttsDeferredTicks = 0;
    final step = _pendingSpeech.removeAt(0);
    _lastSpoken = step;
    _speakScripted(step.text);
    if (step.awaitReady) {
      final stillOrdered = _postureConsigneAwaited;
      _postureGateUntilSaid = null;
      if (stillOrdered) _enterAwaitReady();
    }
  }

  void _dropPendingSpeech() {
    _pendingSpeech.clear();
    _ttsDeferredTicks = 0;
    _postureGateUntilSaid = null;
    _resumeSpeech = null;
    _resumeTicks = null;
  }

  /// Arme le timeout de sécurité ; l'annonce de la posture a déjà été prononcée
  /// par le step qui déclenche la gate.
  void _enterAwaitReady() {
    if (awaitingPostureReady) return;
    // Fixe `_currentPose` AVANT de notifier, sinon l'indicateur affiche
    // l'ancienne pose : `_onTick` l'a déjà fait, mais pas quand le gate s'arme
    // depuis `start()`.
    _updateMilestonePose();
    _postureGate = _newPostureGate();
    _readyTimeout?.cancel();
    _readyTimeout = Timer(_readyTimeoutDuration, confirmPostureReady);
    notifyListeners();
  }

  PostureGate _newPostureGate() => PostureGate(
        session: _session,
        nextStepIndex: _nextStepIndex,
        timelineOffset: _timelineOffset,
        failGeneration: _failGen,
      );

  /// Lève la gate (aussi appelée par le timeout de sécurité). Sans effet hors
  /// gate.
  void confirmPostureReady() {
    if (_postureGate == null) return;
    _postureGate = null;
    _readyTimeout?.cancel();
    _readyTimeout = null;
    notifyListeners();
  }

  /// Jouée à chaque battement : [awaitingPostureReady] vaut déjà `false`, la
  /// purge évite qu'un gel enterré **ressuscite** si sa justification
  /// redevenait vraie (une scène concurrente qui se termine), et qu'un `Timer`
  /// courre derrière une séance qui a repris.
  void _burySpentPostureGate() {
    if (_postureGate == null || awaitingPostureReady) return;
    if (kDebugMode) {
      debugPrint('[SessionController] gel de posture levé : la scène qui '
          "l'a ordonné n'est plus la scène courante");
    }
    _postureGate = null;
    _readyTimeout?.cancel();
    _readyTimeout = null;
  }

  /// Marque le dernier instant scripté (cooldown des commentaires aléatoires).
  /// Coupe un éventuel random en cours avant de parler, sinon `flutter_tts`
  /// peut conserver l'audio précédent et le scripted n'est jamais entendu (race
  /// observée sur Android).
  ///
  /// `{name}` est résolu AVANT le speak et stocké dans
  /// [_lastSpokenResolvedText] : le resolver re-tirerait un surnom différent
  /// depuis le widget.
  ///
  /// [trackForDisplay] : `false` pour les énoncés courts (chiffres du countdown
  /// défi) qui ne doivent pas rester affichés dans le panneau d'instruction.
  Future<void> _speakScripted(String text, {bool trackForDisplay = true}) {
    _lastScriptedSpeakAt = DateTime.now();
    final resolved = _tts.resolveText(text);
    if (trackForDisplay) {
      _lastSpokenResolvedText = resolved;
    }
    if (_tts.isSpeaking) {
      return _tts.stop().then((_) => _tts.speak(resolved));
    }
    return _tts.speak(resolved);
  }

  /// Attend la fin du speak de la phrase d'action du step final puis joue le
  /// `finale_chime`.
  ///
  /// Le polling sur `_tts.isSpeaking` est nécessaire car `_speakScripted` est
  /// non-await. Warmup de 80 ms avant le poll pour laisser le start handler
  /// mettre `_speaking` à `true`, deadline de 8 s pour ne jamais bloquer si le
  /// TTS échoue.
  Future<void> _playFinalChimeAfterAction(String text) async {
    if (text.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 80));
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (
          _tts.isSpeaking && DateTime.now().isBefore(deadline) && !_released) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    if (_released) return;
    _finaleChimeStarted = true;
    notifyListeners();
    unawaited(_ambience.playClimax());
    await _beep.playFinaleChime(category: session.finalCategory);
  }

  /// Instant **wallclock** d'expiration du breath de récup post-défi (`null` =
  /// pas de breath). Doit être wallclock : la timeline est gelée pendant le
  /// défi, `elapsedSeconds` ne franchirait jamais le seuil.
  int? _postChallengeBreathRealEndSec;

  Future<void> _finish() async {
    if (_released) return;
    _stopwatch.stop();
    _ticker?.cancel();
    _ticker = null;
    // Le `Timer` de sécurité du gel de posture est libéré aux trois bornes de
    // vie d'une séance (`start`, `stop`, ici) : la garde du battement ne tourne
    // plus sans ticker, et il réveillerait l'écran de fin.
    _postureGate = null;
    _readyTimeout?.cancel();
    _readyTimeout = null;
    // Borné : sur un backend audio engorgé (seek/stop qui ne rendent plus la
    // main), `_beep.stop()` bloquerait ici et la session ne passerait jamais en
    // `finished`.
    await _beep.stop().timeout(const Duration(seconds: 2), onTimeout: () {});
    await _releaseMusic();
    // Même garde-fou : toute la clôture de séance (stats, badges, apothéose,
    // `_state = finished`) est en aval de cet appel. Un wakelock muet
    // laisserait la séance sans écran de fin, ticker déjà arrêté.
    await WakelockPlus.disable().timeout(_wakelockTimeout, onTimeout: () {});
    _flushHoldFull();
    _disarmHoldVerifier();
    // La tenue « Utilise-moi » entre dans le rapport : `_endUseMe` passe avant
    // `finalizeReport`.
    await _endUseMe();
    // Les streaks sont clos dès maintenant ; le rapport sert au commit plus bas
    // et à détecter un record battu sur l'axe poussé. `_capabilityTracker` est
    // null hors carrière. `finalizeReport` est idempotent.
    final capTracker = _capabilityTracker;
    final SessionCapabilityReport? capReport =
        (capTracker != null && !_released) ? capTracker.finalizeReport() : null;
    final CapabilityAxis? recordAxis = _detectCapabilityRecord(capReport);
    if (!_session.noStats) {
      await _stats.addElapsedSeconds(playedSeconds);
      await _stats.recordSessionCompleted(hadFail: _hadFailThisSession);
      if (_coachTag == CoachCatalog.lilith.slug) {
        await _stats.recordSabbatSession();
      }
      // `encoresAsked` = 0 : l'encore est déclenché depuis l'écran finished
      // APRÈS ce `_finish`.
      _humiliation.applyEndOfSessionDelta(
        clean: !_hadFailThisSession,
        encoresAsked: 0,
        failsCount: _hadFailThisSession && _music == null ? 1 : 0,
      );
      if (!_hadFailThisSession) {
        _obedience.onSessionCleanFinish();
        // AVANT les persistances `setObedienceLevel` / `setHumiliationLevel`.
        if (recordAxis != null) {
          _humiliation.bumpCareer(HumiliationEngine.bumpProgressRecord);
          _obedience.onCapabilityRecord();
        }
        final finalStep = _findFinalStep();
        final finalMode = finalStep?.mode;
        if (finalMode != null) {
          await _stats.recordFinalMode(finalMode);
        }
        final postFinalStep = _findPostFinalStep();
        final postFinalMode = postFinalStep?.mode;
        if (postFinalMode != null) {
          await _stats.recordPostFinalMode(postFinalMode);
        }
      }
      // L'humiliation career est persistée plus bas, après les bonus milestone.
      await _stats.setObedienceLevel(_obedience.score);
    }

    // Acquittement AVANT le basculement en `finished`, pour alimenter les
    // unlocks avant que `_FinishedPanel` ne capture son état initial. L'annonce
    // TTS est déplacée APRÈS le basculement : sinon `notifyListeners` attend sa
    // fin.
    String? milestoneAnnouncement;
    // Une seule annonce TTS (priorité à celle de la final) pour ne pas tasser
    // deux phrases d'unlock.
    final newlyUnlocked = <LevelMilestone>[];
    Future<void> markIfPresent(String? id, {required bool isFinal}) async {
      if (id == null) return;
      final wasAlreadyCompleted = milestoneService.isCompleted(id);
      await milestoneService.markCompleted(id, hadFail: _hadFailThisSession);
      if (!_hadFailThisSession && !wasAlreadyCompleted && !_released) {
        final m = milestoneService.findById(id);
        if (m != null) newlyUnlocked.add(m);
        final announce = milestoneService.getUnlockAnnouncement(
          id,
          l10n: _appLocalizations,
        );
        if (announce != null && (isFinal || milestoneAnnouncement == null)) {
          milestoneAnnouncement = announce;
        }
        _humiliation.bumpCareer(HumiliationEngine.bumpMilestoneAcquired);
      }
    }

    await markIfPresent(session.milestoneId, isFinal: false);
    await markIfPresent(session.secondMilestoneId, isFinal: false);
    await markIfPresent(session.finalMilestoneId, isFinal: true);
    _sessionMilestoneUnlocks = List<LevelMilestone>.unmodifiable(newlyUnlocked);

    // Après les bonus milestone, avant la persistance ci-dessous.
    _applyChallengeOutcome();

    // Rattrapage idempotent : la séance peut se terminer avant que le défi ne
    // s'achève, auquel cas `_finalizeChallengeAcquittals` n'a pas eu lieu.
    if (_challengePhase != ChallengePhase.ended && _challengeOutcome != null) {
      await _acquitMilestonesViaChallenge();
      await _consumeShowcaseIfMatched();
    }
    if (!_session.noStats) {
      // Repersiste l'obédiance si elle a bougé via l'outcome défi
      // (le `setObedienceLevel` ci-dessus a été appelé AVANT
      // `_applyChallengeOutcome`).
      if (_challengeOutcome != null) {
        await _stats.setObedienceLevel(_obedience.score);
      }
      await _stats.setHumiliationLevel(_humiliation.careerScore);

      // Avant le basculement en `finished` : `_FinishedPanel` initialise
      // `_badgesHidden` d'après `hasPendingBadges` au premier rendu ; vide, il
      // skippe l'étape MERCI et les badges ne sont jamais révélés.
      final snap = await _stats.snapshot();
      final unlocks = await _badges.reconcileAndDetectUnlocks(snap);
      _pendingBadgeUnlocks = unlocks;

      // `sessionIndex` (sessions complétées, déjà incrémenté par
      // `recordSessionCompleted`) est l'horloge de decay du
      // `CapabilityRegulator`. L'axe imputé au tap-out renvoyé est ignoré :
      // déjà attribué live.
      if (capReport != null && !capReport.isEmpty) {
        await _capabilities.commit(capReport,
            sessionIndex: snap.sessionsCompleted, quickie: _isQuickie);
      }
    }

    // Apothéose AVANT le basculement en `finished`. Avec un step final dédié,
    // `_finalChimePlayed` est déjà `true` (chime joué PENDANT le step final) :
    // on skippe. Sinon (hors carrière, ou sans `finalStepTime`), phrase
    // `finale` et chime sont joués ici, ce qui bloque le rendu du panel le
    // temps de l'apothéose.
    if (!_hadFailThisSession && !_released && !_finalChimePlayed) {
      final finalStep = _findFinalStep();
      final mode = finalStep?.mode;
      final bank = _phraseBank;
      if (mode != null && bank != null) {
        final phrase = bank.pickFor(mode, 'finale', _random);
        if (phrase.isNotEmpty) {
          // Borné : tout le reste de la clôture (chime, panel de fin) est en
          // aval de cet `await`.
          await _speakBounded(phrase);
        }
      }
      if (!_released) {
        unawaited(_ambience.playClimax());
        await _beep.playFinaleChime(category: session.finalCategory);
        _finalChimePlayed = true;
      }
    }

    _state = SessionState.finished;
    if (_sessionMilestoneUnlocks.isNotEmpty) {
      BackgroundsService.instance.pickMilestone(_coachTag);
    }
    notifyListeners();

    // Post-basculement pour ne pas bloquer le rendu du panel de fin sur
    // l'await.
    final announce = milestoneAnnouncement;
    if (announce != null && announce.isNotEmpty) {
      await _tts.speak(announce);
    } else if (recordAxis != null &&
        _phraseBank != null &&
        !_released &&
        _random.nextDouble() <
            CapabilityRegulator.progressPhraseChanceForLevel(_careerLevel)) {
      final phrase = _phraseBank.pickProgressPhrase(
          recordAxis.storageKey, 'record', _random);
      if (phrase != null && phrase.isNotEmpty) {
        await _tts.speak(phrase);
      }
    }
  }

  SessionStep? _findFinalStep() {
    final finalT = session.finalStepTime;
    if (finalT != null) {
      for (final s in session.steps) {
        if (!s.isTextOnly && s.time == finalT) return s;
      }
    }
    for (var i = session.steps.length - 1; i >= 0; i--) {
      final s = session.steps[i];
      if (!s.isTextOnly) return s;
    }
    return null;
  }

  SessionStep? _findPostFinalStep() {
    final finalT = session.finalStepTime;
    if (finalT == null) return null;
    for (final s in session.steps) {
      if (s.isTextOnly) continue;
      if (s.time > finalT) return s;
    }
    return null;
  }

  /// Helper pur : assemble la [Session] qui remplace la suite après un Supplier
  /// ou un retry milestone. Préfixe un beg insistant à [start], rebase les
  /// steps de [upcoming] sur `start + insistentBeg.duration` (`start` sans beg) et fusionne les
  /// milestones :
  ///
  /// - **Body milestones de [previous]** : conservées uniquement si leur
  ///   fenêtre se termine avant [start] ; sinon abandonnées, `_finish`
  ///   acquitterait une milestone non jouée.
  /// - **Body milestones de [upcoming]** : ajoutées avec décalage `offset`.
  /// - **Final milestone** : prise de [upcoming] uniquement.
  ///
  /// Au-delà de 2 body milestones, on conserve les 2 premières
  /// chronologiquement.
  @visibleForTesting
  static Session buildUpgradedSession({
    required Session previous,
    required Session upcoming,
    SessionStep? insistentBeg,
    required int start,
    bool useMe = false,
  }) {
    final begDuration =
        insistentBeg == null ? 0 : (insistentBeg.duration ?? 12);
    final offset = start + begDuration;

    final newSteps = <SessionStep>[
      if (insistentBeg != null)
        SessionStep(
          time: start,
          text: insistentBeg.text,
          mode: insistentBeg.mode,
          from: insistentBeg.from,
          to: insistentBeg.to,
          bpm: insistentBeg.bpm,
          duration: begDuration,
          useMe: useMe,
        ),
      for (final s in upcoming.steps)
        s.rebased(s.time + offset, useMe: s.useMe || useMe),
    ];

    final bodies = <({String id, int start, int? duration})>[];
    void addPrevIfWindowEnded(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null || mDur == null) return;
      if ((mStart + mDur) <= start) {
        bodies.add((id: id, start: mStart, duration: mDur));
      }
    }

    addPrevIfWindowEnded(previous.milestoneStartTime,
        previous.milestoneDurationSeconds, previous.milestoneId);
    addPrevIfWindowEnded(previous.secondMilestoneStartTime,
        previous.secondMilestoneDurationSeconds, previous.secondMilestoneId);

    void addUpcoming(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null) return;
      bodies.add((id: id, start: mStart + offset, duration: mDur));
    }

    addUpcoming(upcoming.milestoneStartTime, upcoming.milestoneDurationSeconds,
        upcoming.milestoneId);
    addUpcoming(upcoming.secondMilestoneStartTime,
        upcoming.secondMilestoneDurationSeconds, upcoming.secondMilestoneId);

    bodies.sort((a, b) => a.start.compareTo(b.start));
    final mid1 = bodies.isNotEmpty ? bodies[0] : null;
    final mid2 = bodies.length >= 2 ? bodies[1] : null;

    final upFinalStepTime = upcoming.finalStepTime;
    final upSilentFinish = upcoming.silentFinishStartTime;
    final upFinalMsStart = upcoming.finalMilestoneStartTime;
    final script = PostureScript(
      breaks: upcoming.breaks,
      changes: upcoming.postureChanges,
    ).shifted(offset);

    return Session(
      id: '${previous.id}:upgraded',
      name: previous.name,
      description: previous.description,
      durationSeconds: offset + upcoming.durationSeconds,
      defaultMode: previous.defaultMode,
      steps: newSteps,
      milestoneId: mid1?.id,
      milestoneStartTime: mid1?.start,
      milestoneDurationSeconds: mid1?.duration,
      secondMilestoneId: mid2?.id,
      secondMilestoneStartTime: mid2?.start,
      secondMilestoneDurationSeconds: mid2?.duration,
      finalMilestoneId: upcoming.finalMilestoneId,
      finalMilestoneStartTime:
          upFinalMsStart != null ? upFinalMsStart + offset : null,
      finalMilestoneDurationSeconds: upcoming.finalMilestoneDurationSeconds,
      finalStepTime: upFinalStepTime != null ? upFinalStepTime + offset : null,
      silentFinishStartTime:
          upSilentFinish != null ? upSilentFinish + offset : null,
      finalCategory: upcoming.finalCategory,
      noStats: previous.noStats,
      breaks: script.breaks,
      postureChanges: script.changes,
    );
  }

  /// Conserve [previous.challenges] (et leurs timestamps) :
  /// `_updateChallengePhase` est en `phase == ended` à ce stade, le défi ne
  /// sera pas re-déclenché.
  @visibleForTesting
  static Session buildPostChallengeRegenSession({
    required Session previous,
    required Session upcoming,
    required int breathEnd,
    int? playedUntil,
  }) {
    final newSteps = <SessionStep>[
      for (final s in upcoming.steps) s.rebased(s.time + breathEnd),
    ];

    final windowLimit = playedUntil ?? breathEnd;
    final bodies = <({String id, int start, int? duration})>[];
    void addPrevIfWindowEnded(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null || mDur == null) return;
      if ((mStart + mDur) <= windowLimit) {
        bodies.add((id: id, start: mStart, duration: mDur));
      }
    }

    addPrevIfWindowEnded(previous.milestoneStartTime,
        previous.milestoneDurationSeconds, previous.milestoneId);
    addPrevIfWindowEnded(previous.secondMilestoneStartTime,
        previous.secondMilestoneDurationSeconds, previous.secondMilestoneId);

    void addUpcoming(int? mStart, int? mDur, String? id) {
      if (id == null || mStart == null) return;
      bodies.add((id: id, start: mStart + breathEnd, duration: mDur));
    }

    addUpcoming(upcoming.milestoneStartTime, upcoming.milestoneDurationSeconds,
        upcoming.milestoneId);
    addUpcoming(upcoming.secondMilestoneStartTime,
        upcoming.secondMilestoneDurationSeconds, upcoming.secondMilestoneId);
    bodies.sort((a, b) => a.start.compareTo(b.start));
    final mid1 = bodies.isNotEmpty ? bodies[0] : null;
    final mid2 = bodies.length >= 2 ? bodies[1] : null;

    final upFinalStepTime = upcoming.finalStepTime;
    final upSilentFinish = upcoming.silentFinishStartTime;
    final upFinalMsStart = upcoming.finalMilestoneStartTime;
    final script = PostureScript(
      breaks: upcoming.breaks,
      changes: upcoming.postureChanges,
    ).shifted(breathEnd);
    return Session(
      id: '${previous.id}:postchallenge',
      name: previous.name,
      description: previous.description,
      durationSeconds: breathEnd + upcoming.durationSeconds,
      defaultMode: previous.defaultMode,
      steps: newSteps,
      milestoneId: mid1?.id,
      milestoneStartTime: mid1?.start,
      milestoneDurationSeconds: mid1?.duration,
      secondMilestoneId: mid2?.id,
      secondMilestoneStartTime: mid2?.start,
      secondMilestoneDurationSeconds: mid2?.duration,
      finalMilestoneId: upcoming.finalMilestoneId,
      finalMilestoneStartTime:
          upFinalMsStart != null ? upFinalMsStart + breathEnd : null,
      finalMilestoneDurationSeconds: upcoming.finalMilestoneDurationSeconds,
      finalStepTime:
          upFinalStepTime != null ? upFinalStepTime + breathEnd : null,
      silentFinishStartTime:
          upSilentFinish != null ? upSilentFinish + breathEnd : null,
      finalCategory: upcoming.finalCategory,
      noStats: previous.noStats,
      breaks: script.breaks,
      postureChanges: script.changes,
      challenges: previous.challenges,
      challengeTriggerTimes: previous.challengeTriggerTimes,
    );
  }

  /// Garde indispensable : après `_completeChallenge`, `phase` passe à `ended`
  /// mais `_challengeStepStartedAtSec` reste posé jusqu'à l'expiration du
  /// breath post-défi ; sans elle, `elapsedInStep` dépasse `stepEnd` et la
  /// transition vers `atSeuil` écrase `phase=ended`.
  @visibleForTesting
  static bool shouldEnterAtSeuilPhase({
    required ChallengePhase phase,
    required int elapsedInStep,
    required int stepEnd,
  }) {
    if (phase != ChallengePhase.live) {
      return false;
    }
    return elapsedInStep >= stepEnd;
  }

  // ─── Scheduler des commentaires aléatoires ─────────────────────────────

  void _startRandomComments() {
    _randomCommentTimer?.cancel();
    if (_music != null || _randomComments.isEmpty) return;
    _randomCommentTimer = Timer(_nextRandomDelay(), _fireRandomComment);
  }

  void _stopRandomComments() {
    _randomCommentTimer?.cancel();
    _randomCommentTimer = null;
  }

  Duration _nextRandomDelay() {
    final min = _randomComments.minIntervalSeconds;
    final max = _randomComments.maxIntervalSeconds;
    final spread = (max - min).clamp(0, 3600);
    final seconds = min + (spread > 0 ? _random.nextInt(spread + 1) : 0);
    return Duration(seconds: seconds);
  }

  /// Reporté si le TTS parle (le nouveau `speak()` interromprait la phrase en
  /// cours via QUEUE_FLUSH) ou si une phrase scriptée vient d'être dite.
  void _fireRandomComment() {
    if (_state != SessionState.running) return;
    if (_randomComments.isEmpty) return;

    // Fenêtre finish : les phrases scriptées ne doivent pas être chevauchées.
    // On stoppe le scheduler au lieu de re-Timer : plus rien ne joue jusqu'au
    // `_finish`.
    final silentStart = session.silentFinishStartTime;
    if (silentStart != null && elapsedSeconds >= silentStart) {
      _stopRandomComments();
      return;
    }

    // Fenêtre milestone : report de 3 s plutôt qu'arrêt, le scheduler reprend à
    // la fermeture de la fenêtre.
    if (_isInMilestoneWindow()) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    // Break scénarisé : le séquenceur du break pilote la voix ; report de 3 s.
    if (_breakActive) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    // Défi : un random écraserait l'annonce d'explication (QUEUE_FLUSH du TTS).
    // Le filtre `mode == breath` plus bas ne suffit pas : entre la transition
    // de phase défi et l'application du step breath, le mode courant peut
    // encore être le mode précédent.
    if (isChallengeActive || _inPostChallengeBreath) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    final mode = _beep.currentMode;
    if (mode == SessionMode.beg || mode == SessionMode.breath) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 3), _fireRandomComment);
      return;
    }

    if (_tts.isSpeaking) {
      _randomCommentTimer =
          Timer(const Duration(seconds: 2), _fireRandomComment);
      return;
    }

    final since = DateTime.now().difference(_lastScriptedSpeakAt).inSeconds;
    final cooldown = _randomComments.scriptedCooldownSeconds;
    if (since < cooldown) {
      _randomCommentTimer = Timer(
        Duration(seconds: cooldown - since + 1),
        _fireRandomComment,
      );
      return;
    }

    final unlockedKeys =
        milestoneService.acquiredUnlockKeys().map((k) => k.serialized).toSet();
    final phrase = _randomComments.pickFor(
      mode: _beep.currentMode,
      bpm: _beep.currentBpm,
      depth: _beep.currentTo ?? _beep.currentFrom,
      saliva: _saliva.ratio,
      rng: _random,
      unlockedKeys: unlockedKeys,
    );
    if (phrase != null) _tts.speak(phrase);

    _randomCommentTimer = Timer(_nextRandomDelay(), _fireRandomComment);
  }

  // ─── Disposal ──────────────────────────────────────────────────────────

  /// Détache le controller des services audio partagés. À appeler avant qu'une
  /// *autre* SessionScreen prenne la main.
  ///
  /// Sans ça, le `dispose()` de l'ancien controller (déclenché par le
  /// `pushReplacement`) fait un `_tts.stop()` / `_beep.stop()` en
  /// fire-and-forget qui résout APRÈS le `start()` du nouveau controller et
  /// coupe sa première phrase TTS et son loop de bips (race condition).
  ///
  /// Awaite le `_tts.stop()` AVANT que le nouveau controller parle, et marque
  /// le controller « released » pour que `dispose()` ne re-stoppe pas les
  /// services partagés.
  Future<void> detachAudio() async {
    _released = true;
    _failActive = false;
    _punishmentTicker?.cancel();
    _randomCommentTimer?.cancel();
    _readyTimeout?.cancel();
    _ticker?.cancel();
    _stopwatch.stop();
    await _tts.stop();
    await _releaseMusic();
  }

  @override
  void dispose() {
    // Released avant tout : les awaits encore en vol testent ce flag avant de
    // relancer un speak/beep.
    final wasAlreadyReleased = _released;
    _released = true;
    _failActive = false;
    _punishmentTicker?.cancel();
    _randomCommentTimer?.cancel();
    _readyTimeout?.cancel();
    _ticker?.cancel();
    _stopwatch.stop();
    _detachMusicFromBeep();
    unawaited(_music?.dispose());
    if (!wasAlreadyReleased) {
      // Séquentiel : une rafale de stops parallèles, dont l'ordre résolu peut
      // couper le speak/beep d'un nouveau controller (cas `pushReplacement` non
      // capturé par `detachAudio`).
      unawaited(() async {
        try {
          await _tts.stop();
          await _beep.stop();
          await _ambience.stop();
          await _ambience.stopFinishMusic();
        } catch (_) {}
      }());
      WakelockPlus.disable();
    }
    super.dispose();
  }
}
