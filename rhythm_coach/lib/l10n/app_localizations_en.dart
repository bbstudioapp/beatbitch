// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BeatBitch';

  @override
  String get modeSelectionAppBarTitle => 'BEATBITCH';

  @override
  String get modeSelectionProfileTooltip => 'Profile & badges';

  @override
  String get modeSelectionSoundsTooltip => 'Learn the sounds';

  @override
  String get modeSelectionHeaderTitle => 'Pick your mode';

  @override
  String get modeSelectionHeaderSubtitle =>
      'Put your phone down, listen, perform.';

  @override
  String get modeSelectionScenarioTitle => 'SCENARIO';

  @override
  String get modeSelectionScenarioSubtitle => 'Pre-written sessions.';

  @override
  String get modeSelectionCareerTitle => 'CAREER';

  @override
  String get modeSelectionCareerSubtitle =>
      'Generated sessions. Finish to unlock the next level.';

  @override
  String get homeAppBarTitle => 'SCENARIO';

  @override
  String get homeCameraTestTooltip => 'Camera test (holds)';

  @override
  String get homeDeleteSessionTitle => 'Delete this session?';

  @override
  String homeDeleteSessionContent(String sessionName) {
    return '“$sessionName” will be removed from your scenarios.';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonAdd => 'Add';

  @override
  String homeLoadError(String error) {
    return 'Failed to load sessions:\n$error';
  }

  @override
  String get homeEmpty => 'No session available.';

  @override
  String get homeMySessions => 'My sessions';

  @override
  String get homeBuiltinSessions => 'Built-in sessions';

  @override
  String get homeHeaderTitle => 'Pick your session';

  @override
  String get homeHeaderSubtitle => 'Put your phone down, listen, perform.';

  @override
  String get sessionStopTitle => 'Stop the session?';

  @override
  String get sessionStopContent => 'Your progress will be lost.';

  @override
  String get sessionStopConfirm => 'Stop';

  @override
  String get sessionVoiceLabel => 'Voice';

  @override
  String get sessionAmbienceLabel => 'Ambience';

  @override
  String get sessionBegRequestLabel => 'REQUESTED';

  @override
  String get sessionBegSupplicateLabel => 'BEG';

  @override
  String get sessionStateIdle => 'READY';

  @override
  String get sessionStateRunning => 'RUNNING';

  @override
  String get sessionStatePaused => 'PAUSED';

  @override
  String get sessionStateFinished => 'DONE';

  @override
  String get sessionStateFailing => 'FAIL';

  @override
  String get sessionFailPhasePhrase => 'Fail phrase';

  @override
  String get sessionFailPhaseBreath => 'Breath';

  @override
  String get sessionFailPhasePunishment => 'Punishment';

  @override
  String get sessionStartPrompt =>
      'Start the session to hear the instructions.';

  @override
  String get sessionFailButton => 'I CAN\'T';

  @override
  String get sessionIntroBriefing => 'BRIEFING';

  @override
  String get sessionIntroReplay => 'Replay';

  @override
  String get sessionIntroReady => 'I\'M READY';

  @override
  String get sessionPausedIndicator => 'PAUSED';

  @override
  String get sessionPrepInPlace => 'IN POSITION';

  @override
  String get sessionPrepInstruction =>
      'Put your phone down, get into position.';

  @override
  String get sessionFinishedTitle => 'SESSION COMPLETE';

  @override
  String sessionFinishedDuration(String duration) {
    return 'Duration: $duration';
  }

  @override
  String get sessionFinishedDefaultEnd => 'Thank you!';

  @override
  String get sessionFinishedBadgesTitle => 'New badge tiers';

  @override
  String get sessionFinishedNoNewBadges =>
      'No new tier this time — next one will be it.';

  @override
  String get sessionFinishedMilestonesTitle => 'Lessons learned';

  @override
  String get sessionFinishedEncore => 'I WANT MORE…';

  @override
  String get sessionFinishedSaved => 'SAVED';

  @override
  String get sessionFinishedSaving => 'SAVING…';

  @override
  String get sessionFinishedSaveButton => 'SAVE THIS SESSION';

  @override
  String sessionFinishedSavedSnack(String name) {
    return '“$name” saved to your scenarios.';
  }

  @override
  String sessionSaveDefaultName(int day, int month) {
    return 'My session $month/$day';
  }

  @override
  String get sessionSaveDialogTitle => 'Save the session';

  @override
  String get sessionSaveDialogContent =>
      'Give it a name — it will show up in the SCENARIO list.';

  @override
  String get sessionSaveDialogHint => 'Session name';

  @override
  String get sessionSaveDialogConfirm => 'Save';

  @override
  String get cameraTestEndButton => 'Back';

  @override
  String get profileAppBarTitle => 'PROFILE';

  @override
  String profileLoadError(String error) {
    return 'Error:\n$error';
  }

  @override
  String get profileAnatomySection => 'ANATOMY';

  @override
  String get profileAnatomyHasBalls => 'Include testicles';

  @override
  String get profileAnatomyHasBallsSubtitle =>
      'Disable if your setup doesn\'t have them (toy without testicles, other). The coach won\'t direct actions to that area anymore.';

  @override
  String get profileStatsSection => 'STATISTICS';

  @override
  String get profileStatsEmpty =>
      'No stats yet. Finish a few sessions to reveal your counters.';

  @override
  String get profileBadgesSection => 'BADGES';

  @override
  String get profileBadgesEmpty => 'No badge unlocked yet.';

  @override
  String profileLevel(int level) {
    return 'Level $level';
  }

  @override
  String get profileReputationUnit => 'reputation pts';

  @override
  String get profileStatSessionsCompleted => 'Sessions completed';

  @override
  String get profileStatNoFailStreak => 'No-fail streak';

  @override
  String get profileStatDailyStreak => 'Daily streak';

  @override
  String get profileStatTotalTime => 'Total time';

  @override
  String get profileStatThroatfucks => 'Throatfucks';

  @override
  String get profileStatBiffles => 'Cock slaps';

  @override
  String get profileStatHoldFullMax => 'Longest deep hold';

  @override
  String get profileStatHoldThroatTotal => 'Throat hold (total)';

  @override
  String get profileStatHoldFullTotal => 'Full hold (total)';

  @override
  String get profileStatEncores => 'Encores requested';

  @override
  String get profileStatQuickies => 'Quickies completed';

  @override
  String get profileStatModesUsed => 'Modes used';

  @override
  String get profileCapabilitiesSection => 'CAPABILITIES';

  @override
  String get profileCapabilitiesEmpty =>
      'Nothing to show yet — your capabilities reveal themselves as you play.';

  @override
  String profileCapBpm(int n) {
    return '$n BPM';
  }

  @override
  String get profileCapApnea => 'Apnea';

  @override
  String get profileCapEngagement => 'Throat engaged';

  @override
  String get profileCapCrossingsThroat => 'Throat barrier';

  @override
  String get profileCapCrossingsFull => 'Throat barrier (deep)';

  @override
  String get profileCapCrossingsLifetime => 'Crossings (total)';

  @override
  String get profileCapRhythmFastShallow => 'Mouth rhythm — fast';

  @override
  String get profileCapRhythmFastThroat => 'Throat rhythm — fast';

  @override
  String get profileCapRhythmFastFull => 'Deep rhythm — fast';

  @override
  String get profileCapRhythmSlowShallow => 'Mouth rhythm — slow';

  @override
  String get profileCapRhythmSlowThroat => 'Throat rhythm — slow';

  @override
  String get profileCapRhythmSlowFull => 'Deep rhythm — slow';

  @override
  String get profileCapRhythmDepth => 'Rhythm depth';

  @override
  String get profileCapRhythmMotion => 'Unbroken motion';

  @override
  String get profileCapHoldThroat => 'Throat hold';

  @override
  String get profileCapHoldFull => 'Deep hold';

  @override
  String get profileCapNoSwallow => 'No swallowing';

  @override
  String get profileCapBiffle => 'Biffle';

  @override
  String get profileCapBiffleFast => 'Biffle — fast';

  @override
  String get profileCapEffortNoBreath => 'Effort without a break';

  @override
  String get profileCapBreathMinDose => 'Shortest breather';

  @override
  String get profileCapLickDepth => 'Tongue depth';

  @override
  String get profileCapLickStreak => 'Unbroken tongue';

  @override
  String get profileCapHandStreak => 'Unbroken hand';

  @override
  String get profileDiagnosticSection => 'DIAGNOSTIC';

  @override
  String get profileDiagnosticDescription =>
      'Export a JSON file with your progress data — useful when reporting a bug. Nothing is sent automatically, you choose what to do with it.';

  @override
  String get profileDiagnosticExportButton => 'Export my data';

  @override
  String get profileDiagnosticSheetTitle => 'Export my data';

  @override
  String get profileDiagnosticSheetIntro => 'The file contains:';

  @override
  String get profileDiagnosticItemCareer =>
      'Career: your max level, completed sessions, milestones earned.';

  @override
  String get profileDiagnosticItemStats =>
      'Stats: session counters (total time, throatfucks, holds, streaks…).';

  @override
  String get profileDiagnosticItemCapabilities =>
      'Capabilities: your records and comfort zones per axis.';

  @override
  String get profileDiagnosticItemAnatomy =>
      'Anatomy: your profile toggles (whether you have balls).';

  @override
  String get profileDiagnosticItemPreferences =>
      'Preferences: language, voice, display, surprises, debug.';

  @override
  String get profileDiagnosticItemBadges =>
      'Badges: the tiers you\'ve unlocked.';

  @override
  String get profileDiagnosticIncludeNicknames => 'Include my custom nicknames';

  @override
  String get profileDiagnosticIncludeNicknamesSubtitle =>
      'Off by default — they may contain a real first name.';

  @override
  String get profileDiagnosticShareButton => 'Share';

  @override
  String get profileDiagnosticSaveButton => 'Save';

  @override
  String get profileDiagnosticDownloadButton => 'Download';

  @override
  String get profileDiagnosticCancel => 'Cancel';

  @override
  String get profileDiagnosticShareSubject => 'BeatBitch export';

  @override
  String get profileDiagnosticShareSnackbar => 'Export ready to share.';

  @override
  String get profileDiagnosticSavedSnackbar => 'File saved.';

  @override
  String profileDiagnosticErrorSnackbar(String error) {
    return 'Export failed: $error';
  }

  @override
  String get profileResetSection => 'DANGER ZONE';

  @override
  String get profileResetButton => 'Reset everything';

  @override
  String get profileResetDialogTitle => 'Reset everything?';

  @override
  String get profileResetDialogMessage =>
      'This wipes all your stats, capabilities, badges, career progression and specialization points. Irreversible.';

  @override
  String get profileResetCancel => 'Cancel';

  @override
  String get profileResetConfirm => 'Wipe everything';

  @override
  String get profileResetDoneSnackbar => 'Profile reset.';

  @override
  String get careerAppBarTitle => 'CAREER';

  @override
  String get careerSpecializationTooltip => 'Specialization';

  @override
  String careerLoadError(String error) {
    return 'Failed to load:\n$error';
  }

  @override
  String get careerLevelSection => 'Level';

  @override
  String careerMaxLevel(int level) {
    return 'max $level';
  }

  @override
  String get careerQuickieToggle => 'Quickie';

  @override
  String get careerQuickieSubtitle => '6 min — intense';

  @override
  String get careerQuickieDescription =>
      '6 min, intense the whole way through. For when you don\'t have time.';

  @override
  String get careerChallengesToggle => 'In-session challenges';

  @override
  String get careerChallengesDescription =>
      'An opt-in challenge around 60% of the session. Calibrates fast, can speed up your level progression.';

  @override
  String get challengePassButton => 'SKIP';

  @override
  String get challengeGoButton => 'GO';

  @override
  String get challengeExtendButton => 'I HOLD';

  @override
  String get challengeStopButton => 'I STOP';

  @override
  String get challengeTutorialBanner =>
      'First challenge: you\'ll hold a position for the requested time. Tap GO when ready, or SKIP to skip it.';

  @override
  String challengeBannerCountdown(int digit) {
    return '$digit';
  }

  @override
  String get challengeAttemptDefault =>
      'Challenge: we\'re pushing your limit. Tap GO when ready, I\'ll count three two one before we start.';

  @override
  String get challengeAttemptTutorialHoldThroat =>
      'First challenge: you\'ll hold deep for ten seconds. Tap GO when ready, I\'ll count three two one before we start. At the threshold, two buttons will appear to hold longer or stop.';

  @override
  String get challengeExtensionDefault =>
      'You can stay longer if you want. Buttons will appear.';

  @override
  String get challengeSuccessDefault => 'You held it all the way. Good girl.';

  @override
  String get challengeStopDefault => 'You chose to stop. Good.';

  @override
  String get challengeFailDefault =>
      'You broke before the threshold. No worries, you\'ll get it next time.';

  @override
  String get challengeTimeoutDefault => 'Time\'s up — you held it. Good.';

  @override
  String get challengeSkipDefault =>
      'As you wish, we\'ll keep it for next time.';

  @override
  String challengeBannerHoldThroat(int seconds) {
    return 'Hold deep $seconds seconds';
  }

  @override
  String challengeBannerHoldFull(int seconds) {
    return 'Hold all the way $seconds seconds';
  }

  @override
  String challengeBannerHoldGeneric(int seconds) {
    return 'Hold the position $seconds seconds';
  }

  @override
  String challengeBannerRhythm(int bpm) {
    return 'Keep up the rhythm at $bpm BPM';
  }

  @override
  String challengeBannerBiffle(int bpm) {
    return 'Take the slaps at $bpm BPM';
  }

  @override
  String get challengeBannerGeneric => 'Push your limit';

  @override
  String get challengeBannerThresholdReached =>
      'Threshold reached — keep going or stop';

  @override
  String get careerIncludeHandToggle => 'Include hand stimulation';

  @override
  String get careerIncludeHandSubtitle =>
      'Also disables cock slaps (biffle) — both need the hand.';

  @override
  String get careerIncludeHandMilestoneLocked =>
      'Locked for this session — the learning milestone uses the hand.';

  @override
  String specPointsBannerTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unspent points',
      one: '1 unspent point',
    );
    return '$_temp0';
  }

  @override
  String get specPointsBannerSubtitle =>
      'You\'ve earned specialization points. Spend them before you start.';

  @override
  String get specPointsBannerCta => 'ALLOCATE';

  @override
  String get careerStartButton => 'START';

  @override
  String careerCompletedSessions(int count) {
    return 'Sessions completed: $count';
  }

  @override
  String get careerLevelLockedHint =>
      'Level 1 (finish a session to unlock the next one)';

  @override
  String careerSessionName(int level) {
    return 'Career level $level';
  }

  @override
  String careerSessionNameQuickie(int level) {
    return 'Career level $level — quickie';
  }

  @override
  String get careerMilestonesBranchesPrefix => 'Branch: ';

  @override
  String get careerMilestonesBranchesPrefixPlural => 'Branches: ';

  @override
  String get cameraTestAppBarTitle => 'CAMERA TEST';

  @override
  String get cameraPreviewUnavailable => 'Preview unavailable';

  @override
  String get cameraStartSession => 'Start the session';

  @override
  String get cameraPermissionDenied =>
      'Camera permission denied or init failed. Enable the camera in Android settings.';

  @override
  String get cameraUnknownError => 'Unknown error.';

  @override
  String get cameraInitializing => 'Initializing camera…';

  @override
  String get cameraRecalibrate => 'Recalibrate';

  @override
  String get cameraCalibrate => 'Calibrate (10s)';

  @override
  String cameraAxisLabel(String axis) {
    return 'Axis: $axis';
  }

  @override
  String get cameraAxisHorizontal => 'horizontal';

  @override
  String get cameraAxisVertical => 'vertical';

  @override
  String cameraLivePositionLabel(String position) {
    return 'Live position: $position';
  }

  @override
  String get cameraCalibrationTitle => 'Calibration';

  @override
  String get cameraCalibrationInstructions =>
      'For 10 seconds, do 3 or 4 slow, wide movements — from the highest point (tip) to the lowest (full). The app will infer the axis and the bounds of the 5 levels.';

  @override
  String get cameraCalibratingMessage =>
      'Calibrating… make slow, deep movements.';

  @override
  String get cameraCalibratedTitle => 'Calibration OK';

  @override
  String cameraCalibrationSummary(String axis, String range, int samples) {
    return 'Axis: $axis — range $range ($samples samples)';
  }

  @override
  String get cameraCalibratedHint =>
      'You can start the session. If polarity is reversed (tip ↔ full), recalibrate the right way.';

  @override
  String cameraCalibrationFailedRange(String range) {
    return 'Range too small ($range). Try wider movements.';
  }

  @override
  String cameraCalibrationFailed(String error) {
    return 'Calibration failed: $error';
  }

  @override
  String get cameraReturnButton => 'Back';

  @override
  String get specAppBarTitle => 'SPECIALIZATION';

  @override
  String specLoadError(String error) {
    return 'Error:\n$error';
  }

  @override
  String get specNotEnoughPoints => 'Not enough points available.';

  @override
  String get specRespecConfirmTitle => 'Reset your spec?';

  @override
  String get specRespecConfirmContent =>
      'All your specialization points will reset, you\'ll lose 1 global level and you won\'t be able to respec again for 3 days.';

  @override
  String get specRespecConfirmAction => 'Respec';

  @override
  String get specIntro =>
      'Spend your points to tell the engine what you like. The more you invest in a branch, the more the generator leans into that style — without unbalancing your stats.';

  @override
  String get specPointsAvailableLabel => 'available points';

  @override
  String specLevelLabel(int level) {
    return 'Level $level';
  }

  @override
  String specSpentLabel(int spent, int cap) {
    return '$spent / $cap spent';
  }

  @override
  String get specPointsUnit => 'pts';

  @override
  String get specRespecActiveLabel => 'Reset specialization (-1 level)';

  @override
  String specRespecCooldownLabel(int hours) {
    return 'Respec in ${hours}h';
  }

  @override
  String formatDurationSeconds(int s) {
    return '${s}s';
  }

  @override
  String formatDurationMinutes(int m) {
    return '${m}m';
  }

  @override
  String formatDurationMinutesSeconds(int m, int s) {
    return '${m}m ${s}s';
  }

  @override
  String formatDurationHours(int h) {
    return '${h}h';
  }

  @override
  String formatDurationHoursMinutes(int h, String mm) {
    return '${h}h $mm';
  }

  @override
  String formatDaysShort(int d) {
    return '${d}d';
  }

  @override
  String get settingsAppBarTitle => 'SETTINGS';

  @override
  String get settingsLanguageSection => 'Language';

  @override
  String get settingsLanguageSubtitle =>
      'Interface language, coach lines and editorial content.';

  @override
  String get settingsLanguageSystem => 'Follow system';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get languagePickerTitle => 'Choose your language';

  @override
  String get languagePickerBody =>
      'Your phone\'s language isn\'t available in BeatBitch (yet). Pick the one you\'d like to use — you can change it later in the settings (equalizer icon).';

  @override
  String languageNewlyAvailableTitle(String language) {
    return 'Available in $language';
  }

  @override
  String languageNewlyAvailableBody(String language) {
    return 'BeatBitch is now translated into $language, your phone\'s language. You can switch to it, or keep your current language (changeable any time in the settings).';
  }

  @override
  String languageNewlyAvailableSwitch(String language) {
    return 'Switch to $language';
  }

  @override
  String get languageNewlyAvailableKeep => 'Keep current language';

  @override
  String get soundsAppBarTitle => 'SOUNDS';

  @override
  String get soundsStopLoopTooltip => 'Stop loop';

  @override
  String get soundsIdentitySection => 'Identity';

  @override
  String soundsIdentitySubtitle(String token) {
    return 'The “$token” placeholder in the lines is replaced by a random pick between your first name (if entered) and the nickname list below.';
  }

  @override
  String get soundsFirstNameLabel => 'First name (optional)';

  @override
  String get soundsFirstNameHelper =>
      'Empty = no first name in the pool. Network voices pronounce names unevenly.';

  @override
  String get soundsTestSubstitution => 'Test substitution';

  @override
  String get soundsDefaultNicknames => 'Default nicknames';

  @override
  String get soundsCustomNicknames => 'Custom nicknames';

  @override
  String get soundsNoCustomNicknames => 'No custom nickname yet.';

  @override
  String get soundsAddNicknameLabel => 'Add a nickname';

  @override
  String get soundsRemoveNicknameTooltip => 'Remove';

  @override
  String get soundsVoiceSection => 'Voice';

  @override
  String get soundsVoiceSubtitle =>
      'Pick the voice and the speed. The “Test” button speaks a sample line.';

  @override
  String get soundsRateLabel => 'Speed';

  @override
  String get soundsPitchLabel => 'Pitch';

  @override
  String get soundsTestVoice => 'Test the voice';

  @override
  String get soundsNoVoiceDetected =>
      'No matching voice detected on this device.';

  @override
  String get soundsAmbienceSection => 'Ambience';

  @override
  String get soundsAmbienceSubtitle =>
      'Background pack played during sessions. Selection shared with the play screen. Tap a mode to listen.';

  @override
  String get soundsPackLabel => 'Pack';

  @override
  String get soundsPackNoneLabel => 'None';

  @override
  String soundsModeLabel(String name) {
    return 'Mode $name';
  }

  @override
  String get soundsNoTrack => 'no track for this mode';

  @override
  String get soundsRhythmPositionsSection => 'Positions (rhythm)';

  @override
  String get soundsRhythmPositionsSubtitle =>
      'Beep tone by depth. Highest to lowest pitch.';

  @override
  String get soundsLickPositionsSection => 'Positions (lick)';

  @override
  String get soundsLickPositionsSubtitle =>
      'Same positions, lower volume for the “lighter” feel.';

  @override
  String soundsLickPositionLabel(String name) {
    return '$name · lick';
  }

  @override
  String soundsLickPositionSubtitle(String name) {
    return 'Position $name in lick mode';
  }

  @override
  String get soundsHoldSection => 'Hold (position + overlay layer)';

  @override
  String get soundsHoldSubtitle =>
      'Position beep played simultaneously with the hold layer (thicker).';

  @override
  String soundsHoldButton(String position) {
    return 'Hold $position';
  }

  @override
  String soundsHoldPositionSubtitle(String name) {
    return '$name + hold layer';
  }

  @override
  String get soundsSuckleSection => 'Suckle (suction)';

  @override
  String get soundsSuckleSubtitle =>
      'Pulsed wet slurp. One tap plays a single hit; in session it repeats every ~1.2 s for the step duration.';

  @override
  String soundsSuckleButton(String position) {
    return 'Suckle $position';
  }

  @override
  String soundsSucklePositionSubtitle(String name) {
    return 'Suckle on $name';
  }

  @override
  String get soundsSpecificSounds => 'Specific sounds';

  @override
  String get soundsBiffleOneShot => 'Cock slap (one-shot)';

  @override
  String get soundsBiffleOneShotSubtitle =>
      'Short, percussive sound. On loop, follows the BPM.';

  @override
  String get soundsBreath => 'Breath';

  @override
  String get soundsBreathSubtitle => 'Long, low tone, “release” effect.';

  @override
  String get soundsLoopsDemoSection => 'Loop demos';

  @override
  String get soundsLoopsDemoSubtitle =>
      'Adjust BPM, start the loop, listen, stop.';

  @override
  String get soundsBpmLabel => 'BPM';

  @override
  String get soundsLoopActive => 'RUNNING';

  @override
  String get soundsLoopRhythmHeadMid => 'Rhythm head→mid';

  @override
  String get soundsLoopRhythmThroatFull => 'Rhythm throat→full';

  @override
  String get soundsLoopLickTipHead => 'Lick tip→head';

  @override
  String get soundsLoopBiffle => 'Cock slap';

  @override
  String get soundsPosDescTip => 'Very high, light';

  @override
  String get soundsPosDescHead => 'High';

  @override
  String get soundsPosDescMid => 'Mid';

  @override
  String get soundsPosDescThroat => 'Low';

  @override
  String get soundsPosDescFull => 'Very low, heavy';

  @override
  String get soundsPosDescBalls => 'Very low and muffled, side area';

  @override
  String get soundsPosDescSuckle => 'Mid wet tone, steady suction pulse';

  @override
  String get soundsDebugSection => 'Debug';

  @override
  String get soundsDebugSubtitle => 'Technical options for development.';

  @override
  String get soundsDebugShowTimer => 'Show timer';

  @override
  String get soundsDebugShowTimerSubtitle =>
      'Replaces the movement animation with the mm:ss counter during the session.';

  @override
  String get soundsDebugShowStaminaBar => 'Show stamina bar';

  @override
  String get soundsDebugShowStaminaBarSubtitle =>
      'Shows the projected stamina profile during a Career session.';

  @override
  String get soundsDebugShowHumiliationBar => 'Show humiliation gauge';

  @override
  String get soundsDebugShowHumiliationBarSubtitle =>
      'Shows the cumulated humiliation score during the session.';

  @override
  String get soundsDebugShowObedienceBar => 'Show obedience score';

  @override
  String get soundsDebugShowObedienceBarSubtitle =>
      'Shows the 0–100 obedience score (drops on each fail, rises with punishments).';

  @override
  String get soundsDebugShowSalivaBar => 'Show saliva gauge';

  @override
  String get soundsDebugShowSalivaBarSubtitle =>
      'Shows the 0–max saliva gauge accumulated during the session. Rises with deep lick/rhythm/hold, drops with breath/hand. Auto-swallow at 75 when swallowing is allowed.';

  @override
  String get soundsDebugShowSessionControls => 'Show pause / stop';

  @override
  String get soundsDebugShowSessionControlsSubtitle =>
      'Debug only: in prod the session runs without interaction (phone down), only the FAIL button stays useful.';

  @override
  String get soundsDebugShowModeBadge => 'Show mode / BPM / position';

  @override
  String get soundsDebugShowModeBadgeSubtitle =>
      'Debug only: in prod the animation is enough to indicate what\'s happening.';

  @override
  String get debugBarLabelHumiliation => 'HUMIL.';

  @override
  String get debugBarLabelObedience => 'OBED.';

  @override
  String get debugBarLabelSaliva => 'SALIVA';

  @override
  String get soundsDebugCameraHoldCheck => 'Camera hold check';

  @override
  String get soundsDebugCameraHoldCheckSubtitle =>
      'During holds, the front camera checks that the position is being held. The coach gives a short cue if you drift. Requires the camera to be calibrated (camera icon in the SCENARIO screen).';

  @override
  String get soundsDebugSkipSession => '“Finish as success” button';

  @override
  String get soundsDebugSkipSessionSubtitle =>
      'Shows a button in the session that ends it immediately as a full success (badges, milestones, level). Useful to iterate on content without playing through.';

  @override
  String get soundsShowBackgroundMedia => 'Background media in session';

  @override
  String get soundsShowBackgroundMediaSubtitle =>
      'Shows images/GIFs from assets/backgrounds/ in the background, rotating each step. Disable to see only the ambience gradient.';

  @override
  String get sessionDebugFinishButton => 'DEBUG: finish as success';

  @override
  String get soundsDebugScenarioButton => 'Debug — career scenario';

  @override
  String get soundsDebugScenarioSubtitle =>
      'Visualize a generated session without playing it: level, humil, obed, milestones, unlocks, and Beg / fail simulation.';

  @override
  String get careerDebugTitle => 'Debug — Career scenario';

  @override
  String get careerDebugSectionParams => 'Parameters';

  @override
  String get careerDebugSectionScenario => 'Scenario';

  @override
  String get careerDebugLevel => 'Level';

  @override
  String get careerDebugHumiliation => 'Humiliation';

  @override
  String get careerDebugObedience => 'Obedience';

  @override
  String get careerDebugIncludeHand => 'Include hand stimulation';

  @override
  String get careerDebugQuickie => 'Quickie mode';

  @override
  String get careerDebugIntense => 'Intense mode (post-Beg)';

  @override
  String get careerDebugDurationOverride => 'Duration override';

  @override
  String get careerDebugMilestoneBody => 'Milestone body';

  @override
  String get careerDebugMilestoneFinal => 'Milestone final';

  @override
  String get careerDebugUnlocks => 'Unlocks';

  @override
  String get careerDebugUnlocksLoadCurrent => 'Earned';

  @override
  String get careerDebugUnlocksClear => 'None';

  @override
  String get careerDebugUnlocksAll => 'All';

  @override
  String get careerDebugAuto => 'Auto';

  @override
  String get careerDebugNone => 'None';

  @override
  String get careerDebugRegenerate => 'Regenerate';

  @override
  String get careerDebugShowTtsTexts => 'Show TTS texts';

  @override
  String get careerDebugStatStamina => 'End stamina';

  @override
  String get careerDebugStatHumilCap => 'End humil cap';

  @override
  String get careerDebugTagMilestoneBody => 'MILESTONE';

  @override
  String get careerDebugTagMilestoneFinal => 'MILESTONE FINAL';

  @override
  String get careerDebugTagBoost => 'BOOST';

  @override
  String get careerDebugTagFinal => 'FINAL';

  @override
  String get careerDebugTagPostFinal => 'POST-FINAL';

  @override
  String get careerDebugTextOnly => 'TEXT-ONLY';

  @override
  String get careerDebugHumilReq => 'req';

  @override
  String get careerDebugStepActionsTitle => 'Step';

  @override
  String get careerDebugSimulateFail => 'Simulate a fail here';

  @override
  String get careerDebugSimulateSupplier => 'Simulate a Beg here';

  @override
  String get careerDebugClearFork => 'Clear the branch';

  @override
  String get careerDebugClearAnnotation => 'Clear the annotation';

  @override
  String get careerDebugForkBanner => 'BEG BRANCH';

  @override
  String get careerDebugForkFrom => 'From';

  @override
  String get careerDebugForkSteps => 'steps';

  @override
  String get careerDebugFailSnapshotTitle => 'Simulated FAIL';

  @override
  String get careerDebugFailSnapshotNext => 'Resumes at step';

  @override
  String get careerDebugFailSnapshotNoNext =>
      'No playable step after this fail (end of session).';

  @override
  String get positionTip => 'Tip';

  @override
  String get positionHead => 'Head';

  @override
  String get positionMid => 'Mid';

  @override
  String get positionThroat => 'Throat';

  @override
  String get positionFull => 'Full';

  @override
  String get positionBalls => 'Balls';

  @override
  String get modeShortRhythm => 'SUCK';

  @override
  String get modeShortHold => 'DEEP';

  @override
  String get modeShortLick => 'LICK';

  @override
  String get modeShortBiffle => 'SLAP';

  @override
  String get modeShortBreath => 'BREATHE';

  @override
  String get modeShortBeg => 'BEG';

  @override
  String get modeShortFreestyle => 'FREE';

  @override
  String get modeShortHand => 'STROKE';

  @override
  String get modeShortSuckle => 'SUCKLE';

  @override
  String get badgeTierBronze => 'Bronze';

  @override
  String get badgeTierSilver => 'Silver';

  @override
  String get badgeTierGold => 'Gold';

  @override
  String get badgeTierPlatinium => 'Platinum';

  @override
  String badgeUnlockAnnouncement(String name, String tier) {
    return 'Badge unlocked: $name, $tier tier.';
  }

  @override
  String get badgeNameMarathonien => 'Marathoner';

  @override
  String get badgeNameThroatQueen => 'Throat Queen';

  @override
  String get badgeNameIronLungs => 'Iron Lungs';

  @override
  String get badgeNameToutTerrain => 'All-Terrain';

  @override
  String get badgeNameSansBroncher => 'Unflinching';

  @override
  String get badgeNameReguliere => 'Regular';

  @override
  String get badgeNameJamaisRassasiee => 'Never Satisfied';

  @override
  String get badgeNameVideCouilles => 'Ball-Drainer';

  @override
  String get badgeNameBouchePleine => 'Mouthful';

  @override
  String get badgeNameRepeinte => 'Glazed';

  @override
  String get badgeNameGobeuse => 'Swallower';

  @override
  String get badgeNameNettoyeuse => 'Cleaner';

  @override
  String get badgeNameSuppliante => 'Beggar';

  @override
  String get badgeUnitMarathonien => 'minutes total';

  @override
  String get badgeUnitThroatQueen => 'throatfucks total';

  @override
  String get badgeUnitIronLungs => 'seconds of the longest full hold';

  @override
  String get badgeUnitToutTerrain => 'different modes used';

  @override
  String get badgeUnitSansBroncher =>
      'complete sessions in a row without a fail';

  @override
  String get badgeUnitReguliere => 'consecutive days with a session';

  @override
  String get badgeUnitJamaisRassasiee => 'times you asked for “more”';

  @override
  String get badgeUnitVideCouilles => 'quickies completed';

  @override
  String get badgeUnitBouchePleine => 'finishes in the mouth';

  @override
  String get badgeUnitRepeinte => 'finishes on the face';

  @override
  String get badgeUnitGobeuse => 'finishes on the tongue';

  @override
  String get badgeUnitNettoyeuse => 'post-finishes licked clean';

  @override
  String get badgeUnitSuppliante => 'post-orgasm begs';

  @override
  String get careerLevelTitleDebutante => 'Beginner';

  @override
  String get careerLevelTitleApprentieSuceuse => 'Apprentice Cocksucker';

  @override
  String get careerLevelTitlePetiteSalopeConfirmee => 'Confirmed Little Slut';

  @override
  String get careerLevelTitleBoucheAPipe => 'Cocksucking Mouth';

  @override
  String get careerLevelTitleAvaleuse => 'Swallower';

  @override
  String get careerLevelTitleThroatQueen => 'Throat Queen';

  @override
  String get careerLevelTitleReineDuSloppy => 'Sloppy Queen';

  @override
  String get careerLevelTitleTrouABiteOfficiel => 'Official Cock Hole';

  @override
  String get careerLevelTitleVideCouillesPro => 'Pro Ball-Drainer';

  @override
  String get careerLevelTitleReineDesPutes => 'Queen of Whores';

  @override
  String get specBranchEnduranceLabel => 'Endurance';

  @override
  String get specBranchEnduranceDesc =>
      'Last long. More holds, longer durations.';

  @override
  String get specBranchProfondeurLabel => 'Depth';

  @override
  String get specBranchProfondeurDesc => 'Reach far down. Throat / full bias.';

  @override
  String get specBranchRythmeBiffleLabel => 'Rhythm & Slap';

  @override
  String get specBranchRythmeBiffleDesc =>
      'Higher BPM, more frequent cock slaps.';

  @override
  String get specBranchObeissanceLabel => 'Obedience';

  @override
  String get specBranchObeissanceDesc =>
      'Insistent begging, sustained pleading.';

  @override
  String get specBranchSloppyLabel => 'Sloppy';

  @override
  String get specBranchSloppyDesc => 'Wet lick, low slap, more drool.';

  @override
  String get specBranchResilienceLabel => 'Resilience';

  @override
  String get specBranchResilienceDesc => 'Take the fails. Harsher punishments.';

  @override
  String get coachPickerTitle => 'Pick a coach';

  @override
  String get coachPickerSection => 'COACH';

  @override
  String coachPickerTierLabel(int tier) {
    return 'TIER $tier';
  }

  @override
  String get coachBadgePrincipal => 'PRIMARY';

  @override
  String get coachBadgePalierAcquis => 'TIER UNLOCKED';

  @override
  String get coachBadgeFreeTraining => 'FREE TRAINING';

  @override
  String get coachBadgeLocked => 'LOCKED';

  @override
  String get coachRequiresHands => 'Hands required';

  @override
  String coachSummaryPrincipal(String title, int tier) {
    return '$title · Primary tier $tier';
  }

  @override
  String coachSummaryFree(String title) {
    return '$title · free training';
  }

  @override
  String get coachFreeTrainingDialogTitle => 'Free training';

  @override
  String coachFreeTrainingDialogBody(String coachName) {
    return 'You\'ll be training with $coachName. You\'ll progress on your skills, but your tier gauge won\'t move.';
  }

  @override
  String coachFreeTrainingDialogHint(String principalName) {
    return 'To advance in your tier, pick $principalName.';
  }

  @override
  String coachFreeTrainingDialogChoosePrincipal(String principalName) {
    return 'Pick $principalName';
  }

  @override
  String get coachFreeTrainingDialogContinueAnyway => 'Continue anyway';

  @override
  String coachPrenomGateTitle(String coachName) {
    return '$coachName wants to know you';
  }

  @override
  String coachPrenomGateBody(String coachName) {
    return 'Before starting the session with $coachName, give me your first name — she won\'t speak to you anonymously anymore.';
  }

  @override
  String get coachPrenomGateField => 'Your first name';

  @override
  String get coachPrenomGateConfirm => 'Continue';

  @override
  String coachFreeTrainingBannerTitle(String coachName) {
    return 'Free session with $coachName';
  }

  @override
  String coachFreeTrainingBannerBodyWithPrincipal(String principalName) {
    return 'You\'re progressing on your skills. Your tier doesn\'t move — for that, pick $principalName.';
  }

  @override
  String get coachFreeTrainingBannerBodyNoPrincipal =>
      'You\'re progressing on your skills. Your tier doesn\'t move.';

  @override
  String get coachFreeTrainingBannerSwitchAction => 'SWITCH';

  @override
  String coachErrorLockedTier(int tier) {
    return 'This coach is still locked — reach tier $tier to unlock her.';
  }

  @override
  String coachErrorRequiresHands(String coachName) {
    return '$coachName needs you to enable the hand in the options.';
  }

  @override
  String coachErrorMinLevel(String coachName, int minLevel) {
    return '$coachName requires level $minLevel minimum.';
  }

  @override
  String get unlockAnnouncementSloppyDroolBasic =>
      'From now on your mouth holds more spit, and your licking makes more. Drool on me, be filthy.';

  @override
  String get unlockAnnouncementSloppyBiffleSlow =>
      'Cock slaps make you drool now. Take them with your mouth wide open.';

  @override
  String get unlockAnnouncementSloppySwallowControl =>
      'You can hold your spit on command now. When I tell you, you don\'t swallow.';

  @override
  String get unlockAnnouncementSloppySpit =>
      'You know how to spit for me now. When I ask, you let it all out.';

  @override
  String get unlockAnnouncementSloppyDroolDeep =>
      'When you go deep, your mouth overflows even more. Enjoy it.';

  @override
  String get unlockAnnouncementRhythmHeadMidSustained =>
      'You can hold the pace longer than a minute now, no break. I\'ll be asking for it.';

  @override
  String get modeSelectionSurpriseTooltip => 'Surprise reminders';

  @override
  String get surpriseNotifTitle => 'It\'s time';

  @override
  String get surpriseNotifBody1 => 'Suck me right now';

  @override
  String get surpriseNotifBody2 => 'I want to fill your mouth NOW';

  @override
  String get surpriseNotifBody3 => 'On your knees, it\'s time!';

  @override
  String get surpriseSettingsAppBarTitle => 'Surprise reminder';

  @override
  String get surpriseSettingsHeaderSubtitle =>
      'During the window, the app can send notifications at random times. On tap, it opens a short session.';

  @override
  String get surpriseSettingsEnableLabel => 'Enable reminders';

  @override
  String get surpriseSettingsEnableSubtitle =>
      'Random notifications during the window.';

  @override
  String get surpriseSettingsWindowLabel => 'Time window';

  @override
  String surpriseSettingsWindowValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get surpriseSettingsAlertCountLabel => 'Number of reminders';

  @override
  String surpriseSettingsAlertCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reminders',
      one: '1 reminder',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsDurationLabel => 'Session duration';

  @override
  String surpriseSettingsDurationValue(int minSec, int maxSec) {
    return '${minSec}s – ${maxSec}s';
  }

  @override
  String surpriseSettingsActiveStatus(String endTime) {
    return 'Active until $endTime';
  }

  @override
  String surpriseSettingsActiveAlertsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alerts left',
      one: '1 alert left',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsInactiveStatus => 'No reminder scheduled';

  @override
  String get surpriseSettingsPermissionMissing =>
      'Allow notifications in the system settings.';

  @override
  String get surpriseSettingsExactAlarmMissing =>
      'Exact alarms are denied by the system.';

  @override
  String get surpriseSettingsBatteryHintTitle => 'Battery optimization';

  @override
  String get surpriseSettingsBatteryHintBody =>
      'On some phones (Xiaomi, Huawei, Samsung), disable battery optimization for BeatBitch to guarantee reminders.';

  @override
  String get surpriseSettingsOpenBatterySettings => 'Open the settings';

  @override
  String get adultGateTitle => 'Adults only';

  @override
  String get adultGateBody =>
      'BeatBitch contains explicit sexual content: crude, dominant coach voice, explicit text, and background GIFs. By continuing, you confirm that:\n\n• you are at least 18 (or the age of majority where you live);\n• you will use the app in private — audio and visuals are not suited to public use;\n• you understand the phrases can be crude and dominant.';

  @override
  String get adultGateAccept => 'I\'m 18+, I accept';

  @override
  String get adultGateLeave => 'Leave';

  @override
  String get onboardingStep1Title => 'Keep an eye on the screen at first';

  @override
  String get onboardingStep1Body =>
      'For your first sessions, keep the phone in view: the animation and bars help you nail positions and rhythm. Once you\'re comfortable, you can lay it on its side and play hands-free, guided by voice and beeps.';

  @override
  String get onboardingStep2Title => 'Crank the volume';

  @override
  String get onboardingStep2Body =>
      'The coach speaks low and the beeps are subtle. Push media volume up or use headphones/a speaker. The app sends nothing to the Internet.';

  @override
  String get onboardingStep3Title => 'Set up voice and name';

  @override
  String get onboardingStep3Body =>
      'On the Profile screen (silhouette icon): enter your first name, pick your nicknames, choose your interface language and tune the default voice (speed, timbre) — play a sample. Career coaches use their own fixed voices; only the default (non-career) voice is adjustable. The coach can then call you by name.';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingPrevious => 'Back';

  @override
  String get onboardingTestVoice => 'Test my voice';

  @override
  String get onboardingSkip => 'Later';

  @override
  String get profileAboutSection => 'ABOUT';

  @override
  String profileAboutVersion(String appName, String version, String build) {
    return '$appName v$version (build $build)';
  }

  @override
  String get profileAboutOffline =>
      '100% offline — no telemetry, nothing sent over the network.';

  @override
  String get profileUpdatesSection => 'UPDATES';

  @override
  String get profileUpdatesBody =>
      'BeatBitch is 100% offline and never checks for updates on its own. To get notified when a new version ships, install Obtainium — an open-source Android store that watches GitHub Releases pages:\n\n• Obtainium: github.com/ImranR98/Obtainium\n• In Obtainium → \"Add App\", paste: github.com/bbstudioapp/beatbitch\n\nNo network traffic comes from BeatBitch: Obtainium queries GitHub on its own, independently of the app.';

  @override
  String get profileDisclaimerSection => 'DISCLAIMER';

  @override
  String get profileDisclaimerBody =>
      'BeatBitch is a game for consenting adults, meant to be used in a strictly private setting. Using it safely is on you, and you alone: listen to your body, never hold a position or a duration that hurts, and always keep the ability to stop right away (the \"I can\'t\" button, or simply closing the app). Don\'t use the app under the influence of anything that impairs your judgement.\n\nThe voices, texts and scenarios are playful domination fiction: no line is a real order, and nothing the coach says should ever be done to another person without their explicit, informed consent.\n\nThe publisher cannot be held liable for any injury or harm — physical or psychological — resulting from the use, or misuse, of the app. If you have any doubt about your health, talk to a professional.';

  @override
  String get sessionCameraInactiveWarning =>
      'Camera check inactive — recalibrate';

  @override
  String get sessionCameraInactiveAction => 'Calibrate';

  @override
  String get modeSelectionCustomTitle => 'CUSTOM';

  @override
  String get modeSelectionCustomSubtitle =>
      'Tailor-made sessions: duration, mode mix, difficulty, non-stop.';

  @override
  String get customAppBarTitle => 'Custom sessions';

  @override
  String get customListEmptyTitle => 'No saved config yet';

  @override
  String get customListEmptyBody =>
      'Create your first config to generate tailor-made sessions.';

  @override
  String get customNewConfig => 'New config';

  @override
  String get customLaunchLastTitle => 'Relaunch last config';

  @override
  String get customUnnamed => 'Untitled';

  @override
  String get customNonStopBadge => 'Non-stop';

  @override
  String get customDeleteConfirmTitle => 'Delete this config?';

  @override
  String customDeleteConfirmBody(String name) {
    return '\"$name\" will be permanently deleted.';
  }

  @override
  String get customDuplicateSuffix => ' (copy)';

  @override
  String get customActionEdit => 'Edit';

  @override
  String get customActionDuplicate => 'Duplicate';

  @override
  String get customActionDelete => 'Delete';

  @override
  String get customActionLaunch => 'Launch';

  @override
  String get customConfigSavedSnack => 'Config saved.';

  @override
  String customSessionName(String name) {
    return 'Custom — $name';
  }

  @override
  String get customEditorTitleNew => 'New custom config';

  @override
  String get customEditorTitleEdit => 'Edit config';

  @override
  String get customFieldNameLabel => 'Config name';

  @override
  String get customFieldNameHint => 'e.g. Deep marathon';

  @override
  String get customSectionCoach => 'Coach';

  @override
  String get customCoachDefaultVoice => 'Default voice (no coach)';

  @override
  String get customCoachPickerTitle => 'Pick a coach';

  @override
  String get customCoachPickerDefaultSubtitle =>
      'Generic phrase bank, system TTS voice';

  @override
  String get customSectionDuration => 'Duration';

  @override
  String get customNonStopToggle => 'Non-stop mode';

  @override
  String get customNonStopDescription =>
      'Chains full cycles (boosts + finale) endlessly. The \"Finish me\" button triggers a final boost then really ends.';

  @override
  String get customCycleDurationLabel => 'Cycle duration';

  @override
  String get customProgressiveDifficultyToggle => 'Progressive difficulty';

  @override
  String get customProgressiveDifficultyDescription =>
      'Each cycle is a bit harder and longer than the previous one.';

  @override
  String customDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get customSectionDifficulty => 'Global difficulty';

  @override
  String get customSectionDoses => 'Mode mix';

  @override
  String get customDosesHint =>
      '\"None\" excludes the mode. \"Frequent\" favours it.';

  @override
  String get customDangerNoMouthMode =>
      'Keep at least one mouth mode active (rhythm, lick or hold).';

  @override
  String get customSectionAxes => 'Focus axes';

  @override
  String get customAxesHint =>
      'Spend points to bias the generator. Does not affect your career specialization.';

  @override
  String customAxesSpent(int spent) {
    return '$spent pts spent';
  }

  @override
  String get customSectionAdvanced => 'Advanced';

  @override
  String get customIncludeHandToggle => 'Include hand stimulation';

  @override
  String get customIncludeHandDescription =>
      'Enables the hand and biffle modes in the generation.';

  @override
  String get customMaxDepthLabel => 'Maximum depth';

  @override
  String get customBpmRangeLabel => 'BPM range';

  @override
  String customBpmRangeValue(int min, int max) {
    return '$min–$max BPM';
  }

  @override
  String get customBpmRangeHint =>
      'Applies to rhythmic modes (rhythm, lick, biffle, hand).';

  @override
  String get customHoldDurationRangeLabel => 'Hold duration';

  @override
  String customHoldDurationRangeValue(int min, int max) {
    return '$min–$max s';
  }

  @override
  String get customHoldDurationRangeHint =>
      'Bounds the duration of holds and held begs.';

  @override
  String get customSaveAndLaunch => 'Save and launch';

  @override
  String get customSaveOnly => 'Save';

  @override
  String customHostLoadError(String error) {
    return 'Could not load the custom session: $error';
  }

  @override
  String customSaveError(String error) {
    return 'Could not save the configuration: $error';
  }

  @override
  String customLaunchError(String error) {
    return 'Could not launch the session: $error';
  }

  @override
  String get customFinishNowButton => 'Finish me';

  @override
  String get customFinishNowSubtitle => 'final boost then end';

  @override
  String get customDifficultyFacile => 'Easy';

  @override
  String get customDifficultyNormal => 'Normal';

  @override
  String get customDifficultyDifficile => 'Hard';

  @override
  String get customDifficultyExtreme => 'Extreme';

  @override
  String get customDoseNone => 'None';

  @override
  String get customDoseRare => 'Rare';

  @override
  String get customDoseNormal => 'Normal';

  @override
  String get customDoseFrequent => 'Frequent';

  @override
  String get profileSessionDisplaySection => 'Session display';

  @override
  String get profileShowRemainingTime => 'Show remaining time';

  @override
  String get profileShowRemainingTimeSubtitle =>
      'Small mm:ss clock at the top of the screen during the session.';

  @override
  String sessionRemainingTimeLabel(String time) {
    return 'Left: $time';
  }
}
