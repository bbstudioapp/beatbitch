import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../career/models/challenge.dart';
import '../career/models/level_milestone.dart';
import '../career/models/phrase_bank.dart';
import '../career/models/specialization.dart';
import '../career/models/unlock_key.dart';
import '../career/screens/specialization_screen.dart';
import '../career/services/career_progress_service.dart';
import '../career/services/specialization_service.dart';
import '../career/widgets/free_spec_points_banner.dart';
import '../main.dart' show milestoneService;
import '../l10n/app_localizations.dart';
import '../l10n/enum_labels.dart';
import '../l10n/format_helpers.dart';
import '../models/anatomy_profile.dart';
import '../models/badge.dart';
import '../career/services/debug_settings_service.dart';
import '../career/widgets/stamina_bar.dart';
import '../widgets/debug_score_bar.dart';
import '../controllers/session_controller.dart';
import '../models/session.dart';
import '../services/ambience_engine.dart';
import '../services/badge_service.dart';
import '../services/beep_engine.dart';
import '../services/capability_axis.dart';
import '../services/capability_service.dart';
import '../services/coach_phrases_loader.dart';
import '../services/hold_verifier.dart';
import '../services/platform_capabilities.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/saved_sessions_repository.dart';
import '../services/stats_service.dart';
import '../services/tts_service.dart';
import 'camera_test_screen.dart';
import '../theme/app_theme.dart';
import '../models/posture.dart';
import '../widgets/mode_badge_row.dart';
import '../widgets/movement_animation.dart';
import '../widgets/movement_trajectory_forecast.dart';
import '../widgets/posture_indicator.dart';
import '../widgets/session_background.dart';
import '../widgets/session_finale_overlay.dart';
import '../widgets/timer_display.dart';

class SessionScreen extends StatefulWidget {
  final Session session;
  final TtsService tts;
  final BeepEngine beep;
  final AmbienceEngine ambience;
  final PunishmentBundle punishmentBundle;
  final RandomCommentsBundle randomComments;

  final bool isCareer;

  final bool isQuickie;

  final List<double>? staminaProfile;

  final Future<void> Function(SessionController controller)? onRequestUpgrade;

  final Future<void> Function(SessionController controller)? onRequestFinishNow;

  final bool autoContinueOnFinish;

  final String? introText;

  final PhraseBank? phraseBank;

  final String? endButtonLabel;

  final Future<void> Function(SessionController controller)? onRequestEncore;

  /// Doit rendre `true` quand le retry est géré : le flow fail standard est
  /// alors sauté.
  final Future<bool> Function(SessionController controller)? onMilestoneRetry;

  final Future<void> Function(SessionController controller)?
      onPostChallengeRegen;

  final void Function(Challenge challenge, ChallengeOutcome outcome)?
      onChallengeOutcome;

  final bool autoStart;

  final HoldVerifier? holdVerifier;

  final bool canSave;

  final int? careerLevel;

  final CapabilityAxis? capabilityOverloadAxis;

  final CapabilityProfile? capabilityProfile;

  final Set<UnlockKey>? unlockedKeys;

  final bool includeHand;

  final bool coachAdvancesTier;

  final SpecializationAllocation? specialization;

  final SpecializationService? specializationService;

  /// Probabilité par minute.
  final double miniPunishmentRate;

  final String? coachTag;

  final double seedHumiliationSession;

  final bool closeAppOnEnd;

  final AnatomyProfile? anatomy;

  /// Prime sur le réglage debug.
  final bool hideTimerOverride;

  const SessionScreen({
    super.key,
    required this.session,
    required this.tts,
    required this.beep,
    required this.ambience,
    required this.punishmentBundle,
    required this.randomComments,
    this.isCareer = false,
    this.isQuickie = false,
    this.staminaProfile,
    this.onRequestUpgrade,
    this.onRequestFinishNow,
    this.autoContinueOnFinish = false,
    this.introText,
    this.phraseBank,
    this.endButtonLabel,
    this.onRequestEncore,
    this.onMilestoneRetry,
    this.onPostChallengeRegen,
    this.onChallengeOutcome,
    this.autoStart = false,
    this.holdVerifier,
    this.canSave = false,
    this.careerLevel,
    this.capabilityOverloadAxis,
    this.capabilityProfile,
    this.unlockedKeys,
    this.includeHand = true,
    this.coachAdvancesTier = true,
    this.specialization,
    this.specializationService,
    this.miniPunishmentRate = 0.0,
    this.coachTag,
    this.seedHumiliationSession = 0.0,
    this.closeAppOnEnd = false,
    this.anatomy,
    this.hideTimerOverride = false,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  late final SessionController _controller;
  bool _careerRecorded = false;

  /// Figé au démarrage : un déblocage acquis en cours de séance vaut pour la
  /// suivante.
  late final int _positionRowCount;

  // Enchaînement : le `dispose` de l'ancien écran suit l'`initState` du nouveau.
  static _SessionScreenState? _immersiveOwner;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(
      session: widget.session,
      tts: widget.tts,
      beep: widget.beep,
      ambience: widget.ambience,
      punishmentBundle: widget.punishmentBundle,
      randomComments: widget.randomComments,
      staminaProfile: widget.staminaProfile,
      phraseBank: widget.phraseBank,
      holdVerifier: widget.holdVerifier,
      specialization: widget.specialization,
      specializationService: widget.specializationService,
      miniPunishmentRate: widget.miniPunishmentRate,
      coachTag: widget.coachTag,
      seedHumiliationSession: widget.seedHumiliationSession,
      trackCapabilities: widget.isCareer,
      careerLevel: widget.careerLevel ?? 0,
      capabilityOverloadAxis: widget.capabilityOverloadAxis,
      capabilityProfile: widget.capabilityProfile,
      unlockedKeys: widget.unlockedKeys ?? const {},
      includeHand: widget.includeHand,
      isQuickie: widget.isQuickie,
    );
    _controller.onMilestoneRetry = widget.onMilestoneRetry;
    _controller.onPostChallengeRegen = widget.onPostChallengeRegen;
    _controller.onChallengeOutcome = widget.onChallengeOutcome;
    _controller.onChallengeHaptic = _handleChallengeHaptic;
    final anatomy = widget.anatomy ?? AnatomyProfile.defaults;
    final ballsRevealed = anatomy.hasBalls &&
        (!widget.isCareer ||
            milestoneService
                .acquiredUnlockKeys()
                .contains(UnlockKey.lickBalls));
    _positionRowCount = ballsRevealed ? 6 : 5;
    if (widget.isCareer) {
      _controller.addListener(_onCareerStateChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    _immersiveOwner = this;
    _enterImmersive();
    _relayLifecycle(WidgetsBinding.instance.lifecycleState);
    // `buildVerifierIfEnabled` rend null en silence (permission refusée,
    // calibration absente).
    if (widget.holdVerifier == null) {
      _maybeShowCameraInactiveSnackbar();
    }
  }

  Future<void> _maybeShowCameraInactiveSnackbar() async {
    if (!PlatformCapabilities.supportsCameraHoldCheck) return;
    final enabled = await DebugSettingsService().getCameraHoldCheck();
    if (!enabled || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final t = AppLocalizations.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.sessionCameraInactiveWarning),
        action: SnackBarAction(
          label: t.sessionCameraInactiveAction,
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CameraTestScreen(
                  tts: widget.tts,
                  beep: widget.beep,
                  ambience: widget.ambience,
                ),
              ),
            );
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pas en initState : `Localizations` n'y est pas encore lisible. Rejoué à
    // chaque changement de locale.
    _controller.setAppLocalizations(AppLocalizations.of(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.isCareer) {
      _controller.removeListener(_onCareerStateChanged);
    }
    _controller.dispose();
    if (identical(_immersiveOwner, this)) {
      _immersiveOwner = null;
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  void _enterImmersive() => unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

  void _handleChallengeHaptic(ChallengeHapticKind kind) {
    switch (kind) {
      case ChallengeHapticKind.light:
        HapticFeedback.lightImpact();
        break;
      case ChallengeHapticKind.heavy:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _relayLifecycle(state);

  void _relayLifecycle(AppLifecycleState? state) {
    // Reprise manuelle : le son ne repart jamais seul au retour dans l'app.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _controller.onAppBackgrounded();
      case AppLifecycleState.resumed:
        _enterImmersive();
        _controller.onAppForegrounded();
      case AppLifecycleState.detached:
      case null:
        break;
    }
  }

  void _onCareerStateChanged() {
    if (_controller.isFinished && !_careerRecorded) {
      _careerRecorded = true;
      _recordCareerCompletion();
      if (widget.isQuickie) {
        StatsService().recordQuickieCompleted();
      }
    }
  }

  Future<void> _recordCareerCompletion() async {
    await CareerProgressService().recordSessionCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SessionController>.value(
      value: _controller,
      child: _SessionScreenContent(
        tts: widget.tts,
        beep: widget.beep,
        isCareer: widget.isCareer,
        staminaProfile: widget.staminaProfile,
        onRequestUpgrade: widget.onRequestUpgrade,
        onRequestFinishNow: widget.onRequestFinishNow,
        autoContinueOnFinish: widget.autoContinueOnFinish,
        introText: widget.introText,
        endButtonLabel: widget.endButtonLabel,
        onRequestEncore: widget.onRequestEncore,
        autoStart: widget.autoStart,
        canSave: widget.canSave,
        closeAppOnEnd: widget.closeAppOnEnd,
        positionRowCount: _positionRowCount,
        hideTimerOverride: widget.hideTimerOverride,
      ),
    );
  }
}

class _SessionScreenContent extends StatefulWidget {
  final TtsService tts;
  final bool isCareer;
  final List<double>? staminaProfile;
  final Future<void> Function(SessionController controller)? onRequestUpgrade;
  final Future<void> Function(SessionController controller)? onRequestFinishNow;
  final bool autoContinueOnFinish;
  final String? introText;
  final String? endButtonLabel;
  final Future<void> Function(SessionController controller)? onRequestEncore;
  final bool autoStart;
  final bool canSave;
  final bool closeAppOnEnd;
  final int positionRowCount;
  final bool hideTimerOverride;

  final BeepEngine beep;

  const _SessionScreenContent({
    required this.tts,
    required this.beep,
    required this.isCareer,
    required this.staminaProfile,
    required this.onRequestUpgrade,
    required this.onRequestFinishNow,
    required this.autoContinueOnFinish,
    required this.introText,
    required this.endButtonLabel,
    required this.onRequestEncore,
    required this.autoStart,
    required this.canSave,
    required this.closeAppOnEnd,
    required this.positionRowCount,
    required this.hideTimerOverride,
  });

  @override
  State<_SessionScreenContent> createState() => _SessionScreenContentState();
}

class _SessionScreenContentState extends State<_SessionScreenContent> {
  late double _volume = widget.tts.volume;
  bool _showStaminaBar = false;
  bool _showTimer = false;
  bool _showHumiliationBar = false;
  bool _showObedienceBar = false;
  bool _showSalivaBar = false;
  bool _showSessionControls = false;
  bool _settingsOpen = false;
  bool _showModeBadge = false;
  bool _showTrajectoryDots = false;
  bool _showSkipSessionButton = false;
  bool _showBackgroundMedia = true;
  bool _showRemainingTime = false;
  bool _upgradeRequested = false;
  bool _upgradeInFlight = false;
  bool _finishNowInFlight = false;
  bool _finishNowDone = false;

  static const int _finishNowMinRemainingSeconds = 75;

  final Set<int> _challengeActivePointers = <int>{};
  static const int _challengeKeyboardPointerId = -1;
  late final FocusNode _challengeFocus =
      FocusNode(debugLabel: 'challenge-hold');

  bool _introPending = false;

  /// Résolu une seule fois : le resolver retire un surnom à chaque appel,
  /// l'écrit et le TTS divergeraient.
  String? _resolvedIntroText;

  int? _prepCountdown;
  Timer? _prepTimer;

  static const int _prepDurationSeconds = 7;

  static const Duration _autoContinueDelay = Duration(seconds: 4);

  SessionController? _autoChainCtrl;

  bool _autoChainScheduled = false;

  late final SessionController _lifecycleCtrl;
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    _lifecycleCtrl = context.read<SessionController>()
      ..addListener(_onAppLifecycleChanged);
    if (widget.autoContinueOnFinish) {
      _autoChainCtrl = context.read<SessionController>();
      _autoChainCtrl!.addListener(_maybeAutoChain);
    }
    final debug = DebugSettingsService();
    if (widget.isCareer && widget.staminaProfile != null) {
      debug.getShowStaminaBar().then((value) {
        if (!mounted) return;
        setState(() => _showStaminaBar = value);
      });
    }
    debug.getShowTimer().then((value) {
      if (!mounted) return;
      setState(() => _showTimer = value && !widget.hideTimerOverride);
    });
    debug.getShowHumiliationBar().then((value) {
      if (!mounted) return;
      setState(() => _showHumiliationBar = value);
    });
    debug.getShowObedienceBar().then((value) {
      if (!mounted) return;
      setState(() => _showObedienceBar = value);
    });
    debug.getShowSalivaBar().then((value) {
      if (!mounted) return;
      setState(() => _showSalivaBar = value);
    });
    debug.getShowSessionControls().then((value) {
      if (!mounted) return;
      setState(() => _showSessionControls = value);
    });
    debug.getSkipSessionButton().then((value) {
      if (!mounted) return;
      setState(() => _showSkipSessionButton = value);
    });
    debug.getShowModeBadge().then((value) {
      if (!mounted) return;
      setState(() => _showModeBadge = value);
    });
    debug.getShowTrajectoryDots().then((value) {
      if (!mounted) return;
      setState(() => _showTrajectoryDots = value);
    });
    debug.getShowBackgroundMedia().then((value) {
      if (!mounted) return;
      setState(() => _showBackgroundMedia = value);
    });
    debug.getShowSessionRemainingTime().then((value) {
      if (!mounted) return;
      setState(() => _showRemainingTime = value && !widget.hideTimerOverride);
    });
    if (widget.introText != null && widget.introText!.trim().isNotEmpty) {
      _introPending = true;
      _resolvedIntroText = widget.tts.resolveText(widget.introText!);
      WidgetsBinding.instance.addPostFrameCallback((_) => _speakIntro());
    } else if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SessionController>().start();
      });
    }
  }

  @override
  void dispose() {
    _prepTimer?.cancel();
    _lifecycleCtrl.removeListener(_onAppLifecycleChanged);
    _autoChainCtrl?.removeListener(_maybeAutoChain);
    _challengeFocus.dispose();
    super.dispose();
  }

  void _handleChallengePointerDown(PointerDownEvent e) {
    final ctrl = context.read<SessionController>();
    if (!ctrl.isChallengeActive) return;
    if (!ctrl.challengeUsesHoldInput) return;
    _challengeActivePointers.add(e.pointer);
    if (ctrl.challengePhase != ChallengePhase.breath) {
      ctrl.onChallengeHoldStart();
    }
  }

  void _handleChallengePointerUp(PointerEvent e) {
    if (!_challengeActivePointers.remove(e.pointer)) return;
    if (_challengeActivePointers.isEmpty) {
      context.read<SessionController>().onChallengeHoldEnd();
    }
  }

  KeyEventResult _handleChallengeKeyEvent(FocusNode node, KeyEvent e) {
    if (e.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    final ctrl = context.read<SessionController>();
    if (!ctrl.isChallengeActive) return KeyEventResult.ignored;
    if (!ctrl.challengeUsesHoldInput) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      if (_challengeActivePointers.add(_challengeKeyboardPointerId)) {
        // Au clavier, espace arme aussi en `breath`.
        ctrl.onChallengeHoldStart();
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) {
      if (_challengeActivePointers.remove(_challengeKeyboardPointerId) &&
          _challengeActivePointers.isEmpty) {
        ctrl.onChallengeHoldEnd();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _maybeAutoChain() {
    final ctrl = _autoChainCtrl;
    if (ctrl == null || !ctrl.isFinished) return;
    if (_autoChainScheduled || _finishNowDone) return;
    _autoChainScheduled = true;
    Future.delayed(_autoContinueDelay, () async {
      if (!mounted || _finishNowDone) return;
      final cb = widget.onRequestEncore;
      if (cb != null && ctrl.isFinished) await cb(ctrl);
    });
  }

  Future<void> _speakIntro() async {
    final text = _resolvedIntroText;
    if (text == null || text.trim().isEmpty) return;
    await widget.tts.init();
    await widget.tts.speak(text);
  }

  void _onAppLifecycleChanged() {
    final inBackground = _lifecycleCtrl.appInBackground;
    if (inBackground == _wasInBackground) return;
    _wasInBackground = inBackground;
    if (_prepCountdown == null) return;
    if (inBackground) {
      _prepTimer?.cancel();
      unawaited(widget.tts.stop());
    } else {
      _startPrepCountdown();
    }
  }

  Future<void> _onIntroReady() async {
    if (!_introPending) return;
    _startPrepCountdown();
  }

  void _startPrepCountdown() {
    // L'UI bascule avant `stop()` : sur Linux, arrêter le TTS prend plusieurs
    // centaines de ms.
    setState(() {
      _introPending = false;
      _prepCountdown = _prepDurationSeconds;
    });
    unawaited(widget.tts.stop());
    widget.tts.speak(
      CoachPhrasesService.instance.current.prepCountdown(_prepDurationSeconds),
    );

    _prepTimer?.cancel();
    _prepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final next = (_prepCountdown ?? 0) - 1;
      if (next <= 0) {
        t.cancel();
        _startSessionAfterPrep();
      } else {
        setState(() => _prepCountdown = next);
      }
    });
  }

  Future<void> _startSessionAfterPrep() async {
    if (!mounted) return;
    setState(() => _prepCountdown = null);
    // Pas de `tts.stop()` : sur Android, un stop juste avant le speak du step 0
    // le fait perdre ; QUEUE_FLUSH suffit.
    await context.read<SessionController>().start();
  }

  Future<void> _onUpgrade() async {
    final callback = widget.onRequestUpgrade;
    if (callback == null || _upgradeRequested || _upgradeInFlight) return;
    final ctrl = context.read<SessionController>();
    if (!ctrl.isRunning) return;
    setState(() => _upgradeInFlight = true);
    try {
      await callback(ctrl);
      if (!mounted) return;
      setState(() {
        _upgradeRequested = true;
        _upgradeInFlight = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _upgradeInFlight = false);
    }
  }

  Future<void> _onFinishNow() async {
    final callback = widget.onRequestFinishNow;
    if (callback == null || _finishNowInFlight || _finishNowDone) return;
    final ctrl = context.read<SessionController>();
    if (!ctrl.isRunning) return;
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    if (remaining < _finishNowMinRemainingSeconds) return;
    setState(() => _finishNowInFlight = true);
    try {
      await callback(ctrl);
      if (mounted) setState(() => _finishNowDone = true);
    } finally {
      if (mounted) setState(() => _finishNowInFlight = false);
    }
  }

  Future<String?> _handleSave(SessionController ctrl) async {
    final t = AppLocalizations.of(context);
    final now = DateTime.now();
    final defaultName = t.sessionSaveDefaultName(now.day, now.month);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SaveSessionDialog(initialName: defaultName),
    );
    if (name == null || name.trim().isEmpty) return null;
    final repo = SavedSessionsRepository();
    await repo.save(
      source: ctrl.session,
      id: repo.newId(),
      name: name.trim(),
    );
    return name.trim();
  }

  void _toggleSettings() => setState(() => _settingsOpen = !_settingsOpen);

  Future<bool> _confirmExit(BuildContext context) async {
    final ctrl = context.read<SessionController>();
    if (ctrl.isIdle || ctrl.isFinished) return true;

    final t = AppLocalizations.of(context);
    final shouldLeave = await showDialog<bool>(
      context: context,
      // Un clic sur la barrière rendrait null : la séance reprendrait sans
      // arrêt.
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t.sessionStopTitle),
        content: Text(t.sessionStopContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(t.commonContinue),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(t.sessionStopConfirm),
          ),
        ],
      ),
    );
    if (shouldLeave == true) {
      await ctrl.stop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SessionController>();
    final t = AppLocalizations.of(context);

    final inPrep = _prepCountdown != null;
    final showRunning = !_introPending && !inPrep && !ctrl.isFinished;
    return PopScope(
      canPop: ctrl.isIdle || ctrl.isFinished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: showRunning || inPrep
            ? null
            : AppBar(title: Text(ctrl.session.name)),
        body: Focus(
          focusNode: _challengeFocus,
          autofocus: true,
          onKeyEvent: _handleChallengeKeyEvent,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleChallengePointerDown,
            onPointerUp: _handleChallengePointerUp,
            onPointerCancel: _handleChallengePointerUp,
            child: Stack(
              children: [
                Positioned.fill(
                    child: SessionBackground(
                  mediaEnabled: _showBackgroundMedia,
                  bottomVeilOnly: showRunning,
                )),
                SafeArea(
                  child: _introPending
                      ? _IntroPanel(
                          text: _resolvedIntroText!,
                          pose: ctrl.initialPose,
                          onReady: _onIntroReady,
                          onReplay: _speakIntro,
                        )
                      : (inPrep
                          ? _PrepCountdownPanel(seconds: _prepCountdown!)
                          : (ctrl.isFinished
                              ? (ctrl.hasPendingBadges
                                  ? Stack(
                                      children: [
                                        Positioned.fill(
                                          child: _buildRunningView(ctrl),
                                        ),
                                        Positioned.fill(
                                          child: _FinishedOverlay(
                                            endButtonLabel:
                                                widget.endButtonLabel ??
                                                    t.sessionFinishedDefaultEnd,
                                            onThanks: ctrl.revealBadgeUnlocks,
                                            onEncore: (widget.onRequestEncore ==
                                                        null ||
                                                    _finishNowDone)
                                                ? null
                                                : () => widget
                                                    .onRequestEncore!(ctrl),
                                            onSave: widget.canSave
                                                ? () => _handleSave(ctrl)
                                                : null,
                                          ),
                                        ),
                                      ],
                                    )
                                  : _FinishedPanel(
                                      badgeUnlocks: ctrl.sessionBadgeUnlocks,
                                      milestoneUnlocks:
                                          ctrl.sessionMilestoneUnlocks,
                                      hasPendingBadges: false,
                                      onRevealBadges: ctrl.revealBadgeUnlocks,
                                      endButtonLabel: widget.endButtonLabel ??
                                          t.sessionFinishedDefaultEnd,
                                      onEnd: widget.closeAppOnEnd
                                          ? SystemNavigator.pop
                                          : () => Navigator.of(context).pop(),
                                      onEncore: (widget.onRequestEncore ==
                                                  null ||
                                              _finishNowDone)
                                          ? null
                                          : () => widget.onRequestEncore!(ctrl),
                                      onSave: widget.canSave
                                          ? () => _handleSave(ctrl)
                                          : null,
                                      elapsedSeconds: ctrl.playedSeconds,
                                    ))
                              : Stack(
                                  children: [
                                    Positioned.fill(
                                        child: _buildRunningView(ctrl)),
                                    if (ctrl.isPaused)
                                      Positioned.fill(
                                        child: _PausedOverlay(
                                          onResume: ctrl.resume,
                                        ),
                                      ),
                                  ],
                                ))),
                ),
                // Ses résidus blancs masqueraient le texte blanc de
                // `_FinishedPanel`.
                if (!ctrl.isFinished || ctrl.hasPendingBadges)
                  Positioned.fill(
                    child: SessionFinaleOverlay(
                      active: ctrl.isRunning && ctrl.finaleChimeStarted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRunningView(SessionController ctrl) {
    final t = AppLocalizations.of(context);
    final showBar = _showStaminaBar && widget.staminaProfile != null;
    // Sous la barre de stamina, on compresse : overflow sur petit écran.
    final animHeight = showBar ? 130.0 : 160.0;
    // `IntrinsicHeight` garde les Spacer tout en permettant le scroll quand
    // toutes les barres debug sont affichées.
    return Stack(
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: showBar ? 6 : 16,
                  ),
                  child: Column(
                    children: [
                      if (ctrl.state != SessionState.running) ...[
                        _StateBadge(state: ctrl.state),
                        SizedBox(height: showBar ? 6 : 12),
                      ],
                      if (ctrl.isFailing || ctrl.isMusicBreathing)
                        _FailPhaseIndicator(controller: ctrl)
                      else if (ctrl.hasConfig)
                        ModeBadgeRow(
                          mode: ctrl.currentMode,
                          from: ctrl.currentFrom,
                          to: ctrl.currentTo,
                          bpm: ctrl.currentBpm,
                          showDetails: _showModeBadge,
                        )
                      else
                        const SizedBox(height: 30),
                      if (ctrl.currentPose != Posture.free) ...[
                        SizedBox(height: showBar ? 4 : 8),
                        PostureIndicator(pose: ctrl.currentPose),
                      ],
                      if (showBar) ...[
                        const SizedBox(height: 4),
                        StaminaBar(
                          profile: widget.staminaProfile!,
                          currentSecond: ctrl.elapsedSeconds,
                          liveValue: ctrl.stamina.value,
                        ),
                      ],
                      if (_showHumiliationBar) ...[
                        const SizedBox(height: 4),
                        HumiliationBar(
                          careerScore: ctrl.humiliation.careerScore,
                          sessionScore: ctrl.humiliation.sessionScore,
                        ),
                      ],
                      if (_showObedienceBar) ...[
                        const SizedBox(height: 4),
                        ObedienceBar(value: ctrl.obedience.score),
                      ],
                      if (_showSalivaBar) ...[
                        const SizedBox(height: 4),
                        SalivaBar(
                          value: ctrl.saliva.value,
                          max: ctrl.saliva.maxValue,
                        ),
                      ],
                      const Spacer(flex: 5),
                      if (_showTimer)
                        TimerDisplay(
                            elapsed: ctrl.elapsed, total: ctrl.session.duration)
                      else if (ctrl.hasConfig && !ctrl.breakActive)
                        MovementAnimation(
                          mode: ctrl.currentMode,
                          from: ctrl.currentFrom,
                          to: ctrl.currentTo,
                          bpm: ctrl.currentBpm,
                          height: animHeight,
                          beepEngine: widget.beep,
                          positionRowCount: widget.positionRowCount,
                          stepSerial: widget.beep.stepSerial,
                          elapsed: ctrl.elapsed,
                          paused: ctrl.isPaused,
                          showTrajectoryDots: _showTrajectoryDots,
                          moves: ctrl.currentMoves,
                          // Un défi ou un flow fail joue des segments absents de
                          // `session.steps` sur une horloge de séance figée : rien
                          // à annoncer tant qu'elle l'est.
                          upcomingSteps:
                              ctrl.isTimelineFrozen || ctrl.isFailFlowActive
                                  ? const []
                                  : resolveUpcomingMovementSteps(
                                      steps: ctrl.session.steps,
                                      defaultMode: ctrl.session.defaultMode,
                                      afterSecond: ctrl.elapsedSeconds,
                                      currentMode: ctrl.currentMode,
                                      currentFrom: ctrl.currentFrom,
                                      currentBpm: ctrl.currentBpm,
                                    ),
                        )
                      else
                        SizedBox(height: animHeight),
                      const Spacer(flex: 9),
                      // Réserve fixe : la courbe ne bouge pas avec la hauteur
                      // du texte de consigne.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: constraints.maxHeight * 0.30),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!ctrl.isChallengeActive)
                                _CurrentInstruction(
                                  text: ctrl.currentDisplayText,
                                ),
                              SizedBox(height: showBar ? 8 : 12),
                              if (_showSessionControls) ...[
                                _ControlsRow(controller: ctrl),
                                SizedBox(height: showBar ? 10 : 16),
                              ],
                              if (widget.onRequestFinishNow != null &&
                                  !_finishNowDone) ...[
                                _FinishNowButton(
                                  enabled: ctrl.isRunning &&
                                      !ctrl.isFailFlowActive &&
                                      !_finishNowInFlight &&
                                      (ctrl.session.durationSeconds -
                                              ctrl.elapsedSeconds) >=
                                          _finishNowMinRemainingSeconds,
                                  onPressed: _onFinishNow,
                                ),
                                SizedBox(height: showBar ? 8 : 12),
                              ],
                              if (ctrl.breakActive) ...[
                                _BreakBanner(controller: ctrl),
                                SizedBox(height: showBar ? 8 : 12),
                              ],
                              if (ctrl.awaitingPostureReady) ...[
                                _PostureReadyButton(controller: ctrl),
                                SizedBox(height: showBar ? 8 : 12),
                              ],
                              if (ctrl.isChallengeActive) ...[
                                _ChallengeBanner(controller: ctrl),
                                SizedBox(height: showBar ? 6 : 10),
                                _ChallengeButtons(controller: ctrl),
                              ] else
                                _buildActionRow(ctrl),
                              if (_showSkipSessionButton &&
                                  (ctrl.isRunning || ctrl.isPaused)) ...[
                                SizedBox(height: showBar ? 8 : 12),
                                Builder(
                                  builder: (ctx) => OutlinedButton.icon(
                                    onPressed: () => ctrl.debugFinishSuccess(),
                                    icon: const Icon(Icons.fast_forward,
                                        size: 18),
                                    label: Text(AppLocalizations.of(ctx)
                                        .sessionDebugFinishButton),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.greenAccent,
                                      side: const BorderSide(
                                          color: Colors.greenAccent),
                                      minimumSize: const Size.fromHeight(36),
                                    ),
                                  ),
                                ),
                              ],
                              if (kDebugMode && ctrl.isMusical)
                                _MusicBeepAdvanceRow(controller: ctrl),
                              SizedBox(height: showBar ? 10 : 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!ctrl.isFinished) ...[
          Positioned(
            top: 6,
            left: 8,
            child: _OverlayIconButton(
              key: const Key('session-back-button'),
              icon: Icons.arrow_back,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            top: 6,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showRemainingTime &&
                    (ctrl.isRunning || ctrl.isPaused || ctrl.isFailing) &&
                    ctrl.session.durationSeconds > 0)
                  _RemainingTimeChip(
                    remainingSeconds:
                        (ctrl.session.durationSeconds - ctrl.elapsedSeconds)
                            .clamp(0, ctrl.session.durationSeconds),
                  ),
                _OverlayIconButton(
                  key: const Key('session-settings-button'),
                  icon: Icons.tune,
                  tooltip: t.sessionSettingsTooltip,
                  onPressed: _toggleSettings,
                ),
              ],
            ),
          ),
          if (_settingsOpen)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Material(
                key: const Key('session-settings-panel'),
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: _VolumesBlock(
                    ttsVolume: _volume,
                    ambienceVolume: ctrl.ambienceVolume,
                    onTtsVolume: (v) {
                      setState(() => _volume = v);
                      widget.tts.setVolume(v);
                    },
                    onAmbienceVolume: ctrl.setAmbienceVolume,
                    showAmbience: !ctrl.isMusical,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// « JE PEUX PAS » reste en pleine opacité et plus large que « UTILISE-MOI »,
  /// qui n'apparaît qu'une fois débloqué.
  Widget _buildActionRow(SessionController ctrl) {
    return ListenableBuilder(
      listenable: milestoneService,
      builder: (context, _) {
        final showUseMe = widget.isCareer &&
            widget.onRequestUpgrade != null &&
            milestoneService.hasUnlock(UnlockKey.begLibre) &&
            ctrl.useMeUnlocked;
        return Row(
          children: [
            if (showUseMe) ...[
              Flexible(
                flex: 2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 0.6),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  builder: (_, v, child) => Opacity(opacity: v, child: child),
                  child: _UseMeButton(
                    key: const Key('session-useme-button'),
                    enabled: ctrl.isRunning &&
                        !ctrl.isFailFlowActive &&
                        !_upgradeRequested &&
                        !_upgradeInFlight,
                    used: _upgradeRequested,
                    onPressed: _onUpgrade,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 3,
              child: _FailButton(
                key: const Key('session-fail-button'),
                controller: ctrl,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StateBadge extends StatelessWidget {
  final SessionState state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final (label, color) = switch (state) {
      SessionState.idle => (t.sessionStateIdle, AppTheme.textMuted),
      SessionState.running => (t.sessionStateRunning, AppTheme.accent),
      SessionState.paused => (t.sessionStatePaused, Colors.amber),
      SessionState.finished => (t.sessionStateFinished, Colors.greenAccent),
      SessionState.failing => (t.sessionStateFailing, const Color(0xFFEF5350)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: color,
        ),
      ),
    );
  }
}

class _FailPhaseIndicator extends StatelessWidget {
  final SessionController controller;
  const _FailPhaseIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phase = controller.failPhase;
    final (label, sub) = switch (phase) {
      FailPhase.phrase => (t.sessionFailPhasePhrase, null),
      FailPhase.breath => (t.sessionFailPhaseBreath, null),
      FailPhase.punishment => (
          t.sessionFailPhasePunishment,
          controller.currentPunishment?.name,
        ),
      null => ('—', null),
    };
    const color = Color(0xFFEF5350);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _CurrentInstruction extends StatelessWidget {
  static const List<Shadow> _shadows = [
    Shadow(blurRadius: 4, color: Color(0xDD000000), offset: Offset(0, 1)),
    Shadow(blurRadius: 14, color: Color(0x99000000)),
  ];

  final String? text;
  const _CurrentInstruction({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text(
            AppLocalizations.of(context).sessionStartPrompt,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, shadows: _shadows),
          ),
        ),
      );
    }
    return Text(
      text!,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 17,
        color: Colors.white,
        height: 1.4,
        shadows: _shadows,
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final SessionController controller;
  const _ControlsRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isRunning = controller.isRunning;
    final disabledByFail = controller.isFailFlowActive;
    final mainIcon = isRunning ? Icons.pause : Icons.play_arrow;
    final mainAction = disabledByFail
        ? null
        : switch (controller.state) {
            SessionState.idle => controller.start,
            SessionState.running => controller.pause,
            SessionState.paused => controller.resume,
            SessionState.finished => controller.start,
            SessionState.failing => null,
          };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          icon: Icons.stop,
          size: 64,
          onPressed: controller.isIdle ? null : controller.stop,
        ),
        const SizedBox(width: 32),
        _CircleButton(
          icon: mainIcon,
          size: 88,
          primary: true,
          onPressed: mainAction,
        ),
        const SizedBox(width: 32),
        const SizedBox(width: 64),
      ],
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  final VoidCallback onResume;
  const _PausedOverlay({required this.onResume});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onResume,
        splashColor: AppTheme.accent.withValues(alpha: 0.15),
        highlightColor: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.black.withValues(alpha: 0.55),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.45),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 72,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    t.sessionPausedIndicator,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailButton extends StatelessWidget {
  static const Color _failColor = Color(0xFFEF5350);
  static const Color _failColorDark = Color(0xFF8A1A1A);

  final SessionController controller;
  const _FailButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canTriggerFail;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? _failColor : _failColorDark.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? controller.triggerFail : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.flag,
                    color: enabled ? Colors.white : Colors.white38,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context).sessionFailButton,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: enabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostureReadyButton extends StatelessWidget {
  final SessionController controller;
  const _PostureReadyButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: controller.confirmPostureReady,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.black, size: 22),
                const SizedBox(width: 12),
                Text(
                  AppLocalizations.of(context).sessionPostureReadyButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChallengeButtons extends StatelessWidget {
  static const Color _passColor = Color(0xFF757575);
  static const Color _goColor = Color(0xFFFFB300);
  static const Color _atSeuilColor = Color(0xFF4CAF50);
  static const Color _toleranceColor = Color(0xFFEF5350);

  final SessionController controller;
  const _ChallengeButtons({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phase = controller.challengePhase;
    final isTap =
        controller.activeChallenge?.inputMode == ChallengeInputMode.tapToggle;
    if (phase == ChallengePhase.breath) {
      // En mode tap, `onChallengeHoldEnd` n'est jamais recâblé derrière.
      return Row(
        children: [
          Expanded(
            child: _tapButton(
              color: _passColor,
              label: t.challengePassButton,
              onTap: controller.triggerChallengePass,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: isTap
                ? _tapButton(
                    color: _goColor,
                    label: t.challengeTapGoButton,
                    onTap: controller.onChallengeHoldStart,
                  )
                : _holdButton(
                    color: _goColor,
                    label: t.challengeGoButton,
                    onHoldStart: controller.onChallengeHoldStart,
                    onHoldEnd: controller.onChallengeHoldEnd,
                  ),
          ),
        ],
      );
    }
    // Ne pas taper = continuer : les extensions s'accumulent comme en tenant.
    if (isTap) {
      if (phase == ChallengePhase.countdown) {
        return _tapButton(
          color: _passColor,
          label: t.challengeTapCountdownHint,
          onTap: null,
        );
      }
      if (phase == ChallengePhase.live) {
        return _tapButton(
          color: _toleranceColor,
          label: t.challengeTapStopLive,
          onTap: controller.onChallengeTapStop,
        );
      }
      if (phase == ChallengePhase.atSeuil) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _tapButton(
            color: _atSeuilColor,
            label: t.challengeTapStopAtSeuil,
            onTap: controller.onChallengeTapStop,
          ),
        );
      }
      return const SizedBox.shrink();
    }
    if (phase == ChallengePhase.countdown || phase == ChallengePhase.live) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final progress = controller.challengeReleaseToleranceProgress;
          final color = progress <= 0
              ? _goColor
              : Color.lerp(_goColor, _toleranceColor, progress) ?? _goColor;
          final label = progress <= 0
              ? t.challengeHoldHintLive
              : t.challengeHoldHintTolerance;
          return _tapButton(color: color, label: label, onTap: null);
        },
      );
    }
    if (phase == ChallengePhase.atSeuil) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return _tapButton(
            color: _atSeuilColor,
            label: t.challengeHoldHintAtSeuil,
            onTap: null,
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _tapButton({
    required Color color,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: _buttonContent(label),
        ),
      ),
    );
  }

  /// `Listener` plutôt que `GestureDetector` : aucun délai de reconnaissance.
  Widget _holdButton({
    required Color color,
    required String label,
    required VoidCallback onHoldStart,
    required VoidCallback onHoldEnd,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onHoldStart(),
        onPointerUp: (_) => onHoldEnd(),
        onPointerCancel: (_) => onHoldEnd(),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          child: _buttonContent(label),
        ),
      ),
    );
  }

  Widget _buttonContent(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ChallengeBanner extends StatelessWidget {
  static const Color _bg = Color(0xFF1F1F26);
  static const Color _border = Color(0xFFFFB300);

  final SessionController controller;
  const _ChallengeBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phase = controller.challengePhase;
    final ch = controller.activeChallenge;
    final text = controller.challengeCurrentText;
    if (phase == ChallengePhase.countdown) {
      final digit = controller.challengeCountdownDigit;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border, width: 2),
        ),
        child: Center(
          child: Text(
            digit?.toString() ?? '',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFFB300),
              height: 1.0,
            ),
          ),
        ),
      );
    }
    final objective = phase == ChallengePhase.atSeuil
        ? t.challengeBannerThresholdReached
        : controller.challengeObjectiveText();
    final isTutorial = ch?.isTutorial ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (objective != null && objective.isNotEmpty)
            Text(
              objective,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          if (!isTutorial && text != null && text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BreakBanner extends StatelessWidget {
  static const Color _bg = Color(0xFF14201A);
  static const Color _border = Color(0xFF66BB6A);

  final SessionController controller;
  const _BreakBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final b = controller.activeBreak;
    final remaining = b == null
        ? 0
        : (b.endTime - controller.elapsedSeconds).clamp(0, b.durationSeconds);
    final mm = (remaining ~/ 60).toString();
    final ss = (remaining % 60).toString().padLeft(2, '0');
    final newPose = b?.newPose;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.sessionBreakBanner,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: _border,
                ),
              ),
              Text(
                '$mm:$ss',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (newPose != null && newPose != Posture.free) ...[
            const SizedBox(height: 10),
            PostureIndicator(pose: newPose),
          ],
        ],
      ),
    );
  }
}

class _UseMeButton extends StatelessWidget {
  static const Color _color = Color(0xFFCE93D8);
  static const Color _colorMuted = Color(0xFF4A2C5C);

  final bool enabled;
  final bool used;
  final VoidCallback onPressed;

  const _UseMeButton({
    super.key,
    required this.enabled,
    required this.used,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = used ? t.sessionUseMeUsedLabel : t.sessionUseMeLabel;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? _color : _colorMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.front_hand,
                    color: enabled ? Colors.black : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: enabled ? Colors.black : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinishNowButton extends StatelessWidget {
  static const Color _color = Color(0xFFE8B33A);
  static const Color _colorMuted = Color(0xFF5A4715);

  final bool enabled;
  final VoidCallback onPressed;

  const _FinishNowButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? _color : _colorMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bolt,
                  color: enabled ? Colors.black : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.customFinishNowButton,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: enabled ? Colors.black : Colors.white38,
                        ),
                      ),
                      Text(
                        t.customFinishNowSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          color: enabled
                              ? Colors.black.withValues(alpha: 0.65)
                              : Colors.white30,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 22,
        color: Colors.white.withValues(alpha: 0.75),
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool primary;
  final VoidCallback? onPressed;

  const _CircleButton({
    required this.icon,
    required this.size,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final bg = primary
        ? AppTheme.accent
        : (disabled ? const Color(0xFF1F1F1F) : AppTheme.surface);
    final fg = primary ? Colors.black : AppTheme.textPrimary;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Icon(
            icon,
            color: disabled ? AppTheme.textMuted : fg,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}

class _MusicBeepAdvanceRow extends StatelessWidget {
  final SessionController controller;

  const _MusicBeepAdvanceRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final ms = controller.musicBeepAdvanceMs;
    const step = SessionController.musicBeepAdvanceStepMs;
    return Row(
      children: [
        Expanded(
          child: Text(t.sessionDebugMusicBeepAdvanceLabel,
              style: const TextStyle(fontSize: 12)),
        ),
        IconButton(
          tooltip: t.sessionDebugMusicBeepAdvanceDecrease,
          icon: const Icon(Icons.remove),
          onPressed: () => controller.setMusicBeepAdvanceMs(ms - step),
        ),
        Text('$ms ms', key: const Key('musicBeepAdvanceValue')),
        IconButton(
          tooltip: t.sessionDebugMusicBeepAdvanceIncrease,
          icon: const Icon(Icons.add),
          onPressed: () => controller.setMusicBeepAdvanceMs(ms + step),
        ),
      ],
    );
  }
}

class _VolumesBlock extends StatelessWidget {
  final double ttsVolume;
  final double ambienceVolume;
  final ValueChanged<double> onTtsVolume;
  final ValueChanged<double> onAmbienceVolume;
  final bool showAmbience;

  const _VolumesBlock({
    required this.ttsVolume,
    required this.ambienceVolume,
    required this.onTtsVolume,
    required this.onAmbienceVolume,
    required this.showAmbience,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        _LabeledSlider(
          label: t.sessionVoiceLabel,
          value: ttsVolume,
          min: 0.0,
          max: 1.0,
          onChanged: onTtsVolume,
        ),
        if (showAmbience) ...[
          const SizedBox(height: 4),
          _LabeledSlider(
            label: t.sessionAmbienceLabel,
            value: ambienceVolume,
            min: 0.0,
            max: AmbienceEngine.maxVolume,
            onChanged: onAmbienceVolume,
          ),
        ],
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _IntroPanel extends StatelessWidget {
  final String text;

  final Posture pose;
  final VoidCallback onReady;
  final Future<void> Function() onReplay;

  const _IntroPanel({
    required this.text,
    required this.pose,
    required this.onReady,
    required this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _IntroHeader(),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          if (pose != Posture.free) ...[
            const SizedBox(height: 16),
            Center(child: PostureIndicator(pose: pose)),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReplay,
              icon: const Icon(Icons.replay, size: 18),
              label: Text(t.sessionIntroReplay),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onReady,
              child: Text(
                t.sessionIntroReady,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroHeader extends StatelessWidget {
  const _IntroHeader();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.accent.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.record_voice_over,
                  size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                t.sessionIntroBriefing,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrepCountdownPanel extends StatelessWidget {
  final int seconds;
  const _PrepCountdownPanel({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              t.sessionPrepInPlace,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              seconds.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
                height: 1,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              t.sessionPrepInstruction,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedOverlay extends StatefulWidget {
  final String endButtonLabel;
  final Future<void> Function() onThanks;
  final Future<void> Function()? onEncore;
  final Future<String?> Function()? onSave;

  const _FinishedOverlay({
    required this.endButtonLabel,
    required this.onThanks,
    required this.onEncore,
    required this.onSave,
  });

  @override
  State<_FinishedOverlay> createState() => _FinishedOverlayState();
}

class _FinishedOverlayState extends State<_FinishedOverlay> {
  bool _encoreInFlight = false;
  bool _saveInFlight = false;
  bool _saved = false;

  Future<void> _handleEncore() async {
    final cb = widget.onEncore;
    if (cb == null || _encoreInFlight) return;
    setState(() => _encoreInFlight = true);
    try {
      await cb();
    } finally {
      if (mounted) setState(() => _encoreInFlight = false);
    }
  }

  Future<void> _handleSave() async {
    final cb = widget.onSave;
    if (cb == null || _saveInFlight || _saved) return;
    setState(() => _saveInFlight = true);
    try {
      final name = await cb();
      if (!mounted) return;
      if (name != null) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).sessionFinishedSavedSnack(name),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saveInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.sessionFinishedTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed:
                          _encoreInFlight ? null : () => widget.onThanks(),
                      child: Text(
                        widget.endButtonLabel.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onEncore != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _encoreInFlight ? null : _handleEncore,
                        child: _encoreInFlight
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Text(
                                t.sessionFinishedEncore,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                ),
                              ),
                      ),
                    ),
                  ],
                  if (widget.onSave != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                      ),
                      onPressed: (_saveInFlight || _saved) ? null : _handleSave,
                      icon: Icon(
                        _saved ? Icons.check : Icons.bookmark_add_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _saved
                            ? t.sessionFinishedSaved
                            : (_saveInFlight
                                ? t.sessionFinishedSaving
                                : t.sessionFinishedSaveButton),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedPanel extends StatefulWidget {
  final List<BadgeUnlock> badgeUnlocks;
  final List<LevelMilestone> milestoneUnlocks;
  final bool hasPendingBadges;
  final Future<void> Function() onRevealBadges;
  final String endButtonLabel;
  final VoidCallback onEnd;
  final Future<void> Function()? onEncore;

  final Future<String?> Function()? onSave;

  final int elapsedSeconds;

  const _FinishedPanel({
    required this.badgeUnlocks,
    required this.milestoneUnlocks,
    required this.hasPendingBadges,
    required this.onRevealBadges,
    required this.endButtonLabel,
    required this.onEnd,
    required this.onEncore,
    required this.onSave,
    required this.elapsedSeconds,
  });

  @override
  State<_FinishedPanel> createState() => _FinishedPanelState();
}

class _FinishedPanelState extends State<_FinishedPanel> {
  bool _encoreInFlight = false;
  bool _saveInFlight = false;
  bool _saved = false;
  int _availableSpecPoints = 0;

  late bool _badgesHidden = widget.hasPendingBadges;

  @override
  void initState() {
    super.initState();
    _refreshSpecPoints();
  }

  Future<void> _refreshSpecPoints() async {
    // `availablePoints` attend des secondes cumulées, pas un nombre de séances.
    final totalSeconds = await StatsService().getTotalSeconds();
    final available =
        await SpecializationService().availablePoints(totalSeconds);
    if (!mounted) return;
    setState(() => _availableSpecPoints = available);
  }

  Future<void> _handleThanks() async {
    if (_badgesHidden) {
      setState(() => _badgesHidden = false);
      await widget.onRevealBadges();
      return;
    }
    if (_availableSpecPoints > 0) {
      await _openSpecializationScreen();
      return;
    }
    widget.onEnd();
  }

  Future<void> _openSpecializationScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SpecializationScreen()),
    );
    await _refreshSpecPoints();
  }

  Future<void> _handleEncore() async {
    final cb = widget.onEncore;
    if (cb == null || _encoreInFlight) return;
    setState(() => _encoreInFlight = true);
    try {
      await cb();
    } finally {
      if (mounted) setState(() => _encoreInFlight = false);
    }
  }

  Future<void> _handleSave() async {
    final cb = widget.onSave;
    if (cb == null || _saveInFlight || _saved) return;
    setState(() => _saveInFlight = true);
    try {
      final name = await cb();
      if (!mounted) return;
      if (name != null) {
        setState(() => _saved = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).sessionFinishedSavedSnack(name),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saveInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final unlocks = widget.badgeUnlocks;
    final milestoneUnlocks = widget.milestoneUnlocks;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            t.sessionFinishedTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.sessionFinishedDuration(
              formatDurationDetailed(context, widget.elapsedSeconds),
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: _badgesHidden
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_availableSpecPoints > 0) ...[
                          FreeSpecPointsBanner(
                            count: _availableSpecPoints,
                            onAllocate: _openSpecializationScreen,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (milestoneUnlocks.isNotEmpty) ...[
                          _MilestoneUnlocksBlock(unlocks: milestoneUnlocks),
                          const SizedBox(height: 16),
                        ],
                        _BadgeUnlocksBlock(unlocks: unlocks),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          () {
            final pendingAllocation =
                !_badgesHidden && _availableSpecPoints > 0;
            if (pendingAllocation) {
              return SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _handleThanks,
                  child: Text(
                    t.specPointsBannerCta,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              );
            }
            return SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _encoreInFlight ? null : _handleThanks,
                child: Text(
                  widget.endButtonLabel.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            );
          }(),
          if (widget.onEncore != null && _availableSpecPoints == 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _encoreInFlight ? null : _handleEncore,
                child: _encoreInFlight
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(
                        t.sessionFinishedEncore,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ),
          ],
          if (widget.onSave != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: (_saveInFlight || _saved) ? null : _handleSave,
                icon: Icon(
                  _saved ? Icons.check : Icons.bookmark_add_outlined,
                  size: 18,
                ),
                label: Text(
                  _saved
                      ? t.sessionFinishedSaved
                      : (_saveInFlight
                          ? t.sessionFinishedSaving
                          : t.sessionFinishedSaveButton),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BadgeUnlocksBlock extends StatelessWidget {
  final List<BadgeUnlock> unlocks;
  const _BadgeUnlocksBlock({required this.unlocks});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (unlocks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          t.sessionFinishedNoNewBadges,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.sessionFinishedBadgesTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        for (final u in unlocks) ...[
          _BadgeUnlockTile(unlock: u),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _BadgeUnlockTile extends StatelessWidget {
  final BadgeUnlock unlock;
  const _BadgeUnlockTile({required this.unlock});

  Color _tierColor() {
    return switch (unlock.tier) {
      BadgeTier.bronze => const Color(0xFFCD7F32),
      BadgeTier.silver => const Color(0xFFC0C0C0),
      BadgeTier.gold => const Color(0xFFFFD54F),
      BadgeTier.platinium => const Color(0xFFE0F7FA),
      BadgeTier.none => AppTheme.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _tierColor();
    final familyName = unlock.definition.family.localizedDisplayName(context);
    final tierLabel = unlock.tier.localizedLabel(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  familyName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tierLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneUnlocksBlock extends StatelessWidget {
  final List<LevelMilestone> unlocks;
  const _MilestoneUnlocksBlock({required this.unlocks});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.sessionFinishedMilestonesTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textMuted,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        for (final m in unlocks) ...[
          _MilestoneUnlockTile(milestone: m),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MilestoneUnlockTile extends StatelessWidget {
  final LevelMilestone milestone;
  const _MilestoneUnlockTile({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final branches = milestone.branches;
    final branchPrefix = branches.length > 1
        ? t.careerMilestonesBranchesPrefixPlural
        : t.careerMilestonesBranchesPrefix;
    final branchLabels =
        branches.map((b) => b.localizedLabel(context)).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.school, color: AppTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestoneService.getDisplayLabel(milestone.id),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (branches.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$branchPrefix$branchLabels',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveSessionDialog extends StatefulWidget {
  final String initialName;
  const _SaveSessionDialog({required this.initialName});

  @override
  State<_SaveSessionDialog> createState() => _SaveSessionDialogState();
}

class _SaveSessionDialogState extends State<_SaveSessionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.sessionSaveDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.sessionSaveDialogContent,
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: t.sessionSaveDialogHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(t.sessionSaveDialogConfirm),
        ),
      ],
    );
  }
}

class _RemainingTimeChip extends StatelessWidget {
  final int remainingSeconds;

  const _RemainingTimeChip({required this.remainingSeconds});

  String _format(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: Text(
          t.sessionRemainingTimeLabel(_format(remainingSeconds)),
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
