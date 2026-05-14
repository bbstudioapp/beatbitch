// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'BeatBitch';

  @override
  String get modeSelectionAppBarTitle => 'BEATBITCH';

  @override
  String get modeSelectionProfileTooltip => 'Profil & Abzeichen';

  @override
  String get modeSelectionSoundsTooltip => 'Die Sounds lernen';

  @override
  String get modeSelectionHeaderTitle => 'Wähl deinen Modus';

  @override
  String get modeSelectionHeaderSubtitle =>
      'Leg dein Handy weg, hör zu, gehorch.';

  @override
  String get modeSelectionScenarioTitle => 'SZENARIO';

  @override
  String get modeSelectionScenarioSubtitle => 'Vorgeschriebene Sessions.';

  @override
  String get modeSelectionCareerTitle => 'KARRIERE';

  @override
  String get modeSelectionCareerSubtitle =>
      'Generierte Sessions. Beende sie, um die nächste Stufe freizuschalten.';

  @override
  String get homeAppBarTitle => 'SZENARIO';

  @override
  String get homeCameraTestTooltip => 'Kamera-Test (Holds)';

  @override
  String get homeDeleteSessionTitle => 'Diese Session löschen?';

  @override
  String homeDeleteSessionContent(String sessionName) {
    return '„$sessionName“ wird aus deinen Szenarien entfernt.';
  }

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonContinue => 'Weiter';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String homeLoadError(String error) {
    return 'Fehler beim Laden der Sessions:\n$error';
  }

  @override
  String get homeEmpty => 'Keine Session verfügbar.';

  @override
  String get homeMySessions => 'Meine Sessions';

  @override
  String get homeBuiltinSessions => 'Integrierte Sessions';

  @override
  String get homeHeaderTitle => 'Wähl deine Session';

  @override
  String get homeHeaderSubtitle => 'Leg dein Handy weg, hör zu, gehorch.';

  @override
  String get sessionStopTitle => 'Session beenden?';

  @override
  String get sessionStopContent => 'Der Fortschritt geht verloren.';

  @override
  String get sessionStopConfirm => 'Beenden';

  @override
  String get sessionVoiceLabel => 'Stimme';

  @override
  String get sessionAmbienceLabel => 'Ambiente';

  @override
  String get sessionBegRequestLabel => 'GEFORDERT';

  @override
  String get sessionBegSupplicateLabel => 'BETTLE';

  @override
  String get sessionStateIdle => 'BEREIT';

  @override
  String get sessionStateRunning => 'LÄUFT';

  @override
  String get sessionStatePaused => 'PAUSE';

  @override
  String get sessionStateFinished => 'FERTIG';

  @override
  String get sessionStateFailing => 'FAIL';

  @override
  String get sessionFailPhasePhrase => 'Fail-Satz';

  @override
  String get sessionFailPhaseBreath => 'Atmen';

  @override
  String get sessionFailPhasePunishment => 'Strafe';

  @override
  String get sessionStartPrompt =>
      'Starte die Session, um die Anweisungen zu hören.';

  @override
  String get sessionFailButton => 'ICH KANN NICHT';

  @override
  String get sessionIntroBriefing => 'BRIEFING';

  @override
  String get sessionIntroReplay => 'Nochmal hören';

  @override
  String get sessionIntroReady => 'ICH BIN BEREIT';

  @override
  String get sessionPausedIndicator => 'PAUSIERT';

  @override
  String get sessionPrepInPlace => 'IN POSITION';

  @override
  String get sessionPrepInstruction => 'Leg dein Handy weg, geh in Position.';

  @override
  String get sessionFinishedTitle => 'SESSION ABGESCHLOSSEN';

  @override
  String sessionFinishedDuration(String duration) {
    return 'Dauer: $duration';
  }

  @override
  String get sessionFinishedDefaultEnd => 'Danke!';

  @override
  String get sessionFinishedBadgesTitle => 'Neue Abzeichen-Stufen';

  @override
  String get sessionFinishedNoNewBadges =>
      'Diesmal keine neue Stufe — die nächste wird\'s.';

  @override
  String get sessionFinishedMilestonesTitle => 'Gelerntes';

  @override
  String get sessionFinishedEncore => 'ICH WILL MEHR…';

  @override
  String get sessionFinishedSaved => 'GESPEICHERT';

  @override
  String get sessionFinishedSaving => 'SPEICHERN…';

  @override
  String get sessionFinishedSaveButton => 'DIESE SESSION SPEICHERN';

  @override
  String sessionFinishedSavedSnack(String name) {
    return '„$name“ in deinen Szenarien gespeichert.';
  }

  @override
  String sessionSaveDefaultName(int day, int month) {
    return 'Meine Session $day.$month';
  }

  @override
  String get sessionSaveDialogTitle => 'Session speichern';

  @override
  String get sessionSaveDialogContent =>
      'Gib ihr einen Namen — sie erscheint in der SZENARIO-Liste.';

  @override
  String get sessionSaveDialogHint => 'Name der Session';

  @override
  String get sessionSaveDialogConfirm => 'Speichern';

  @override
  String get cameraTestEndButton => 'Zurück';

  @override
  String get profileAppBarTitle => 'PROFIL';

  @override
  String profileLoadError(String error) {
    return 'Fehler:\n$error';
  }

  @override
  String get profileStatsSection => 'STATISTIKEN';

  @override
  String get profileStatsEmpty =>
      'Noch keine Statistiken. Beende ein paar Sessions, um deine Zähler zu enthüllen.';

  @override
  String get profileBadgesSection => 'ABZEICHEN';

  @override
  String get profileBadgesEmpty => 'Noch kein Abzeichen freigeschaltet.';

  @override
  String profileLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String get profileReputationUnit => 'Reputationspunkte';

  @override
  String get profileStatSessionsCompleted => 'Abgeschlossene Sessions';

  @override
  String get profileStatNoFailStreak => 'Serie ohne Fail';

  @override
  String get profileStatDailyStreak => 'Tägliche Serie';

  @override
  String get profileStatTotalTime => 'Gesamtzeit';

  @override
  String get profileStatThroatfucks => 'Throatfucks';

  @override
  String get profileStatBiffles => 'Schwanzschläge';

  @override
  String get profileStatHoldFullMax => 'Längster Tief-Hold';

  @override
  String get profileStatHoldThroatTotal => 'Kehlen-Hold (gesamt)';

  @override
  String get profileStatHoldFullTotal => 'Tief-Hold (gesamt)';

  @override
  String get profileStatEncores => 'Geforderte Zugaben';

  @override
  String get profileStatQuickies => 'Abgeschlossene Quickies';

  @override
  String get profileStatModesUsed => 'Benutzte Modi';

  @override
  String get profileCapabilitiesSection => 'FÄHIGKEITEN';

  @override
  String get profileCapabilitiesEmpty =>
      'Noch nichts zu zeigen — deine Fähigkeiten zeigen sich beim Spielen.';

  @override
  String profileCapBpm(int n) {
    return '$n BPM';
  }

  @override
  String get profileCapApnea => 'Atemstillstand';

  @override
  String get profileCapEngagement => 'Kehle geöffnet';

  @override
  String get profileCapCrossingsThroat => 'Kehlenbarriere';

  @override
  String get profileCapCrossingsFull => 'Kehlenbarriere (tief)';

  @override
  String get profileCapCrossingsLifetime => 'Durchstöße (gesamt)';

  @override
  String get profileCapRhythmFastShallow => 'Mund-Rhythmus — schnell';

  @override
  String get profileCapRhythmFastThroat => 'Kehlen-Rhythmus — schnell';

  @override
  String get profileCapRhythmFastFull => 'Tiefer Rhythmus — schnell';

  @override
  String get profileCapRhythmSlowShallow => 'Mund-Rhythmus — langsam';

  @override
  String get profileCapRhythmSlowThroat => 'Kehlen-Rhythmus — langsam';

  @override
  String get profileCapRhythmSlowFull => 'Tiefer Rhythmus — langsam';

  @override
  String get profileCapRhythmDepth => 'Rhythmus-Tiefe';

  @override
  String get profileCapRhythmMotion => 'Ununterbrochene Bewegung';

  @override
  String get profileCapHoldThroat => 'Kehlen-Hold';

  @override
  String get profileCapHoldFull => 'Tief-Hold';

  @override
  String get profileCapNoSwallow => 'Ohne Schlucken';

  @override
  String get profileCapBiffle => 'Klatschen';

  @override
  String get profileCapBiffleFast => 'Klatschen — schnell';

  @override
  String get profileCapEffortNoBreath => 'Anstrengung ohne Pause';

  @override
  String get profileCapBreathMinDose => 'Kürzeste Verschnaufpause';

  @override
  String get profileCapLickDepth => 'Zungentiefe';

  @override
  String get profileCapLickStreak => 'Ununterbrochene Zunge';

  @override
  String get profileCapHandStreak => 'Ununterbrochene Hand';

  @override
  String get profileResetSection => 'GEFAHRENZONE';

  @override
  String get profileResetButton => 'Alles zurücksetzen';

  @override
  String get profileResetDialogTitle => 'Alles zurücksetzen?';

  @override
  String get profileResetDialogMessage =>
      'Das löscht alle deine Statistiken, Fähigkeiten, Abzeichen, den Karrierefortschritt und die Spezialisierungspunkte. Unwiderruflich.';

  @override
  String get profileResetCancel => 'Abbrechen';

  @override
  String get profileResetConfirm => 'Alles löschen';

  @override
  String get profileResetDoneSnackbar => 'Profil zurückgesetzt.';

  @override
  String get careerAppBarTitle => 'KARRIERE';

  @override
  String get careerSpecializationTooltip => 'Spezialisierung';

  @override
  String careerLoadError(String error) {
    return 'Fehler beim Laden:\n$error';
  }

  @override
  String get careerLevelSection => 'Stufe';

  @override
  String careerMaxLevel(int level) {
    return 'max. $level';
  }

  @override
  String get careerQuickieToggle => 'Quickie';

  @override
  String get careerQuickieSubtitle => '6 Min. — intensiv';

  @override
  String get careerQuickieDescription =>
      '6 Min., durchgehend intensiv. Für wenn du keine Zeit hast.';

  @override
  String get careerIncludeHandToggle => 'Handstimulation einbeziehen';

  @override
  String get careerIncludeHandSubtitle =>
      'Deaktiviert auch die Schwanzschläge (Biffle) — beide brauchen die Hand.';

  @override
  String get careerIncludeHandMilestoneLocked =>
      'Für diese Session gesperrt — der Lern-Meilenstein nutzt die Hand.';

  @override
  String specPointsBannerTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count freie Punkte',
      one: '1 freier Punkt',
    );
    return '$_temp0';
  }

  @override
  String get specPointsBannerSubtitle =>
      'Du hast Spezialisierungspunkte verdient. Vergib sie, bevor du startest.';

  @override
  String get specPointsBannerCta => 'ZUWEISEN';

  @override
  String get careerStartButton => 'STARTEN';

  @override
  String careerCompletedSessions(int count) {
    return 'Abgeschlossene Sessions: $count';
  }

  @override
  String get careerLevelLockedHint =>
      'Stufe 1 (beende eine Session, um die nächste freizuschalten)';

  @override
  String careerSessionName(int level) {
    return 'Karriere Stufe $level';
  }

  @override
  String careerSessionNameQuickie(int level) {
    return 'Karriere Stufe $level — Quickie';
  }

  @override
  String get careerMilestonesBranchesPrefix => 'Zweig: ';

  @override
  String get careerMilestonesBranchesPrefixPlural => 'Zweige: ';

  @override
  String get cameraTestAppBarTitle => 'KAMERA-TEST';

  @override
  String get cameraPreviewUnavailable => 'Vorschau nicht verfügbar';

  @override
  String get cameraStartSession => 'Session starten';

  @override
  String get cameraPermissionDenied =>
      'Kamera-Berechtigung verweigert oder Init fehlgeschlagen. Aktiviere die Kamera in den Android-Einstellungen.';

  @override
  String get cameraUnknownError => 'Unbekannter Fehler.';

  @override
  String get cameraInitializing => 'Kamera wird initialisiert…';

  @override
  String get cameraRecalibrate => 'Neu kalibrieren';

  @override
  String get cameraCalibrate => 'Kalibrieren (10 s)';

  @override
  String cameraAxisLabel(String axis) {
    return 'Achse: $axis';
  }

  @override
  String get cameraAxisHorizontal => 'horizontal';

  @override
  String get cameraAxisVertical => 'vertikal';

  @override
  String cameraLivePositionLabel(String position) {
    return 'Live-Position: $position';
  }

  @override
  String get cameraCalibrationTitle => 'Kalibrierung';

  @override
  String get cameraCalibrationInstructions =>
      'Mach 10 Sekunden lang 3 oder 4 langsame, weite Bewegungen — von der höchsten Position (Spitze) bis zur tiefsten (ganz). Die App leitet daraus die Achse und die Grenzen der 5 Stufen ab.';

  @override
  String get cameraCalibratingMessage =>
      'Kalibrierung läuft… mach langsame, tiefe Bewegungen.';

  @override
  String get cameraCalibratedTitle => 'Kalibrierung OK';

  @override
  String cameraCalibrationSummary(String axis, String range, int samples) {
    return 'Achse: $axis — Bereich $range ($samples Messwerte)';
  }

  @override
  String get cameraCalibratedHint =>
      'Du kannst die Session starten. Wenn die Polarität vertauscht ist (Spitze ↔ ganz), kalibriere in der richtigen Richtung neu.';

  @override
  String cameraCalibrationFailedRange(String range) {
    return 'Bereich zu klein ($range). Mach weitere Bewegungen.';
  }

  @override
  String cameraCalibrationFailed(String error) {
    return 'Kalibrierung fehlgeschlagen: $error';
  }

  @override
  String get cameraReturnButton => 'Zurück';

  @override
  String get specAppBarTitle => 'SPEZIALISIERUNG';

  @override
  String specLoadError(String error) {
    return 'Fehler:\n$error';
  }

  @override
  String get specNotEnoughPoints => 'Nicht genug Punkte verfügbar.';

  @override
  String get specRespecConfirmTitle => 'Spezialisierung neu vergeben?';

  @override
  String get specRespecConfirmContent =>
      'Alle deine Spezialisierungspunkte werden zurückgesetzt, du verlierst 1 globale Stufe und du kannst 3 Tage lang keinen Respec mehr machen.';

  @override
  String get specRespecConfirmAction => 'Respec';

  @override
  String get specIntro =>
      'Vergib deine Punkte, um der Engine zu sagen, was du magst. Je mehr du in einen Zweig investierst, desto stärker geht der Generator in diesen Stil — ohne deine Stats aus dem Gleichgewicht zu bringen.';

  @override
  String get specPointsAvailableLabel => 'verfügbare Punkte';

  @override
  String specLevelLabel(int level) {
    return 'Stufe $level';
  }

  @override
  String specSpentLabel(int spent, int cap) {
    return '$spent / $cap vergeben';
  }

  @override
  String get specPointsUnit => 'Pkt.';

  @override
  String get specRespecActiveLabel => 'Spezialisierung zurücksetzen (-1 Stufe)';

  @override
  String specRespecCooldownLabel(int hours) {
    return 'Respec in $hours Std.';
  }

  @override
  String formatDurationSeconds(int s) {
    return '$s s';
  }

  @override
  String formatDurationMinutes(int m) {
    return '$m Min.';
  }

  @override
  String formatDurationMinutesSeconds(int m, int s) {
    return '$m Min. $s s';
  }

  @override
  String formatDurationHours(int h) {
    return '$h Std.';
  }

  @override
  String formatDurationHoursMinutes(int h, String mm) {
    return '$h Std. $mm';
  }

  @override
  String formatDaysShort(int d) {
    return '$d T';
  }

  @override
  String get settingsAppBarTitle => 'EINSTELLUNGEN';

  @override
  String get settingsLanguageSection => 'Sprache';

  @override
  String get settingsLanguageSubtitle =>
      'Sprache der Oberfläche, der Coach-Sätze und der redaktionellen Inhalte.';

  @override
  String get settingsLanguageSystem => 'System folgen';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get languagePickerTitle => 'Wähl deine Sprache';

  @override
  String get languagePickerBody =>
      'Die Sprache deines Handys ist (noch) nicht in BeatBitch verfügbar. Wähl die, die du nutzen willst — du kannst sie später in den Einstellungen (Equalizer-Symbol) ändern.';

  @override
  String languageNewlyAvailableTitle(String language) {
    return 'Verfügbar auf $language';
  }

  @override
  String languageNewlyAvailableBody(String language) {
    return 'BeatBitch ist jetzt auf $language übersetzt, der Sprache deines Handys. Du kannst umschalten oder die aktuelle Sprache behalten (jederzeit in den Einstellungen änderbar).';
  }

  @override
  String languageNewlyAvailableSwitch(String language) {
    return 'Auf $language umschalten';
  }

  @override
  String get languageNewlyAvailableKeep => 'Aktuelle Sprache behalten';

  @override
  String get soundsAppBarTitle => 'SOUNDS';

  @override
  String get soundsStopLoopTooltip => 'Loop stoppen';

  @override
  String get soundsIdentitySection => 'Identität';

  @override
  String soundsIdentitySubtitle(String token) {
    return 'Der Platzhalter „$token“ in den Sätzen wird durch eine Zufallsauswahl zwischen deinem Vornamen (falls eingegeben) und der Spitznamenliste unten ersetzt.';
  }

  @override
  String get soundsFirstNameLabel => 'Vorname (optional)';

  @override
  String get soundsFirstNameHelper =>
      'Leer = kein Vorname im Pool. Netzwerkstimmen sprechen Vornamen ungleichmäßig aus.';

  @override
  String get soundsTestSubstitution => 'Ersetzung testen';

  @override
  String get soundsDefaultNicknames => 'Standard-Spitznamen';

  @override
  String get soundsCustomNicknames => 'Eigene Spitznamen';

  @override
  String get soundsNoCustomNicknames => 'Noch kein eigener Spitzname.';

  @override
  String get soundsAddNicknameLabel => 'Spitznamen hinzufügen';

  @override
  String get soundsRemoveNicknameTooltip => 'Entfernen';

  @override
  String get soundsVoiceSection => 'Stimme';

  @override
  String get soundsVoiceSubtitle =>
      'Wähl die Stimme und die Geschwindigkeit. Der Knopf „Testen“ spricht einen Beispielsatz.';

  @override
  String get soundsRateLabel => 'Geschwindigkeit';

  @override
  String get soundsPitchLabel => 'Tonhöhe';

  @override
  String get soundsTestVoice => 'Stimme testen';

  @override
  String get soundsNoVoiceDetected =>
      'Keine passende Stimme auf diesem Gerät gefunden.';

  @override
  String get soundsAmbienceSection => 'Ambiente';

  @override
  String get soundsAmbienceSubtitle =>
      'Hintergrund-Pack, das während der Sessions läuft. Auswahl wird mit dem Spielbildschirm geteilt. Tippe einen Modus an, um ihn anzuhören.';

  @override
  String get soundsPackLabel => 'Pack';

  @override
  String get soundsPackNoneLabel => 'Keins';

  @override
  String soundsModeLabel(String name) {
    return 'Modus $name';
  }

  @override
  String get soundsNoTrack => 'kein Track für diesen Modus';

  @override
  String get soundsRhythmPositionsSection => 'Positionen (Rhythmus)';

  @override
  String get soundsRhythmPositionsSubtitle =>
      'Beep-Ton je nach Tiefe. Vom höchsten zum tiefsten Ton.';

  @override
  String get soundsLickPositionsSection => 'Positionen (Lecken)';

  @override
  String get soundsLickPositionsSubtitle =>
      'Gleiche Positionen, geringere Lautstärke für das „leichtere“ Gefühl.';

  @override
  String soundsLickPositionLabel(String name) {
    return '$name · Lecken';
  }

  @override
  String soundsLickPositionSubtitle(String name) {
    return 'Position $name im Leck-Modus';
  }

  @override
  String get soundsHoldSection => 'Hold (Position + Overlay-Schicht)';

  @override
  String get soundsHoldSubtitle =>
      'Positions-Beep, der gleichzeitig mit der Hold-Schicht (dicker) gespielt wird.';

  @override
  String soundsHoldButton(String position) {
    return 'Hold $position';
  }

  @override
  String soundsHoldPositionSubtitle(String name) {
    return '$name + Hold-Schicht';
  }

  @override
  String get soundsSpecificSounds => 'Spezifische Sounds';

  @override
  String get soundsBiffleOneShot => 'Schwanzschlag (One-Shot)';

  @override
  String get soundsBiffleOneShotSubtitle =>
      'Kurzer, perkussiver Sound. Im Loop folgt er den BPM.';

  @override
  String get soundsBreath => 'Breath';

  @override
  String get soundsBreathSubtitle => 'Langer, tiefer Ton, „Erlösungs“-Effekt.';

  @override
  String get soundsLoopsDemoSection => 'Loop-Demos';

  @override
  String get soundsLoopsDemoSubtitle =>
      'BPM einstellen, Loop starten, anhören, stoppen.';

  @override
  String get soundsBpmLabel => 'BPM';

  @override
  String get soundsLoopActive => 'LÄUFT';

  @override
  String get soundsLoopRhythmHeadMid => 'Rhythmus Eichel→Mitte';

  @override
  String get soundsLoopRhythmThroatFull => 'Rhythmus Kehle→ganz';

  @override
  String get soundsLoopLickTipHead => 'Lecken Spitze→Eichel';

  @override
  String get soundsLoopBiffle => 'Schwanzschlag';

  @override
  String get soundsPosDescTip => 'Sehr hoch, leicht';

  @override
  String get soundsPosDescHead => 'Hoch';

  @override
  String get soundsPosDescMid => 'Mittel';

  @override
  String get soundsPosDescThroat => 'Tief';

  @override
  String get soundsPosDescFull => 'Sehr tief, schwer';

  @override
  String get soundsDebugSection => 'Debug';

  @override
  String get soundsDebugSubtitle => 'Technische Optionen für die Entwicklung.';

  @override
  String get soundsDebugShowTimer => 'Timer anzeigen';

  @override
  String get soundsDebugShowTimerSubtitle =>
      'Ersetzt die Bewegungsanimation während der Session durch den mm:ss-Zähler.';

  @override
  String get soundsDebugShowStaminaBar => 'Ausdauerleiste anzeigen';

  @override
  String get soundsDebugShowStaminaBarSubtitle =>
      'Zeigt das projizierte Ausdauerprofil während einer Karriere-Session.';

  @override
  String get soundsDebugShowHumiliationBar =>
      'Erniedrigungs-Anzeige einblenden';

  @override
  String get soundsDebugShowHumiliationBarSubtitle =>
      'Zeigt den kumulierten Erniedrigungswert während der Session.';

  @override
  String get soundsDebugShowObedienceBar => 'Gehorsamswert anzeigen';

  @override
  String get soundsDebugShowObedienceBarSubtitle =>
      'Zeigt den Gehorsamswert von 0–100 (sinkt bei jedem Fail, steigt mit Strafen).';

  @override
  String get soundsDebugShowSalivaBar => 'Speichel-Anzeige einblenden';

  @override
  String get soundsDebugShowSalivaBarSubtitle =>
      'Zeigt die Speichelanzeige von 0–max., die sich während der Session ansammelt. Steigt mit tiefem Lecken/Rhythmus/Hold, sinkt mit Breath/Hand. Auto-Schlucken bei 75, wenn Schlucken erlaubt ist.';

  @override
  String get soundsDebugShowSessionControls => 'Pause / Stop anzeigen';

  @override
  String get soundsDebugShowSessionControlsSubtitle =>
      'Nur Debug: im Produktivbetrieb läuft die Session ohne Interaktion (Handy weggelegt), nur der FAIL-Knopf bleibt nützlich.';

  @override
  String get soundsDebugShowModeBadge => 'Modus / BPM / Position anzeigen';

  @override
  String get soundsDebugShowModeBadgeSubtitle =>
      'Nur Debug: im Produktivbetrieb reicht die Animation, um anzuzeigen, was passiert.';

  @override
  String get debugBarLabelHumiliation => 'ERNIEDR.';

  @override
  String get debugBarLabelObedience => 'GEHORS.';

  @override
  String get debugBarLabelSaliva => 'SPEICHEL';

  @override
  String get soundsDebugCameraHoldCheck => 'Kamera-Hold-Prüfung';

  @override
  String get soundsDebugCameraHoldCheckSubtitle =>
      'Während der Holds prüft die Frontkamera, ob die Position gehalten wird. Der Coach gibt einen kurzen Hinweis, wenn du abdriftest. Erfordert eine kalibrierte Kamera (Kamera-Symbol im SZENARIO-Bildschirm).';

  @override
  String get soundsDebugSkipSession => 'Knopf „als Erfolg beenden“';

  @override
  String get soundsDebugSkipSessionSubtitle =>
      'Zeigt einen Knopf in der Session, der sie sofort als vollen Erfolg beendet (Abzeichen, Meilensteine, Stufe). Praktisch, um an Inhalten zu feilen, ohne alles durchzuspielen.';

  @override
  String get soundsShowBackgroundMedia => 'Hintergrundmedien in der Session';

  @override
  String get soundsShowBackgroundMediaSubtitle =>
      'Zeigt die Bilder/GIFs aus assets/backgrounds/ im Hintergrund, mit Wechsel bei jedem Step. Deaktivieren, um nur den Ambiente-Verlauf zu sehen.';

  @override
  String get sessionDebugFinishButton => 'DEBUG: als Erfolg beenden';

  @override
  String get soundsDebugScenarioButton => 'Debug — Karriere-Szenario';

  @override
  String get soundsDebugScenarioSubtitle =>
      'Visualisiere eine generierte Session, ohne sie zu spielen: Stufe, Erniedr., Gehors., Meilensteine, Unlocks und Bettel-/Fail-Simulation.';

  @override
  String get careerDebugTitle => 'Debug — Karriere-Szenario';

  @override
  String get careerDebugSectionParams => 'Parameter';

  @override
  String get careerDebugSectionScenario => 'Szenario';

  @override
  String get careerDebugLevel => 'Stufe';

  @override
  String get careerDebugHumiliation => 'Erniedrigung';

  @override
  String get careerDebugObedience => 'Gehorsam';

  @override
  String get careerDebugIncludeHand => 'Handstimulation einbeziehen';

  @override
  String get careerDebugQuickie => 'Quickie-Modus';

  @override
  String get careerDebugIntense => 'Intensiv-Modus (nach dem Betteln)';

  @override
  String get careerDebugDurationOverride => 'Dauer-Override';

  @override
  String get careerDebugMilestoneBody => 'Meilenstein-Körper';

  @override
  String get careerDebugMilestoneFinal => 'Meilenstein-Finale';

  @override
  String get careerDebugUnlocks => 'Unlocks';

  @override
  String get careerDebugUnlocksLoadCurrent => 'Erworben';

  @override
  String get careerDebugUnlocksClear => 'Keine';

  @override
  String get careerDebugUnlocksAll => 'Alle';

  @override
  String get careerDebugAuto => 'Auto';

  @override
  String get careerDebugNone => 'Keine';

  @override
  String get careerDebugRegenerate => 'Neu generieren';

  @override
  String get careerDebugShowTtsTexts => 'TTS-Texte anzeigen';

  @override
  String get careerDebugStatStamina => 'Ausdauer am Ende';

  @override
  String get careerDebugStatHumilCap => 'Erniedr.-Cap am Ende';

  @override
  String get careerDebugTagMilestoneBody => 'MEILENSTEIN';

  @override
  String get careerDebugTagMilestoneFinal => 'MEILENSTEIN-FINALE';

  @override
  String get careerDebugTagBoost => 'BOOST';

  @override
  String get careerDebugTagFinal => 'FINALE';

  @override
  String get careerDebugTagPostFinal => 'NACH-FINALE';

  @override
  String get careerDebugTextOnly => 'NUR-TEXT';

  @override
  String get careerDebugHumilReq => 'Anf.';

  @override
  String get careerDebugStepActionsTitle => 'Step';

  @override
  String get careerDebugSimulateFail => 'Hier einen Fail simulieren';

  @override
  String get careerDebugSimulateSupplier => 'Hier ein Betteln simulieren';

  @override
  String get careerDebugClearFork => 'Zweig löschen';

  @override
  String get careerDebugClearAnnotation => 'Anmerkung löschen';

  @override
  String get careerDebugForkBanner => 'BETTEL-ZWEIG';

  @override
  String get careerDebugForkFrom => 'Ab';

  @override
  String get careerDebugForkSteps => 'Steps';

  @override
  String get careerDebugFailSnapshotTitle => 'Simulierter FAIL';

  @override
  String get careerDebugFailSnapshotNext => 'Setzt fort bei Step';

  @override
  String get careerDebugFailSnapshotNoNext =>
      'Kein spielbarer Step nach diesem Fail (Session-Ende).';

  @override
  String get positionTip => 'Spitze';

  @override
  String get positionHead => 'Eichel';

  @override
  String get positionMid => 'Mitte';

  @override
  String get positionThroat => 'Kehle';

  @override
  String get positionFull => 'Ganz';

  @override
  String get modeShortRhythm => 'LUTSCH';

  @override
  String get modeShortHold => 'TIEF';

  @override
  String get modeShortLick => 'LECK';

  @override
  String get modeShortBiffle => 'KLATSCH';

  @override
  String get modeShortBreath => 'ATME';

  @override
  String get modeShortBeg => 'BETTLE';

  @override
  String get modeShortFreestyle => 'FREI';

  @override
  String get modeShortHand => 'WICHS';

  @override
  String get badgeTierBronze => 'Bronze';

  @override
  String get badgeTierSilver => 'Silber';

  @override
  String get badgeTierGold => 'Gold';

  @override
  String get badgeTierPlatinium => 'Platin';

  @override
  String badgeUnlockAnnouncement(String name, String tier) {
    return 'Abzeichen freigeschaltet: $name, Stufe $tier.';
  }

  @override
  String get badgeNameMarathonien => 'Marathonläuferin';

  @override
  String get badgeNameThroatQueen => 'Throat Queen';

  @override
  String get badgeNameIronLungs => 'Stahllunge';

  @override
  String get badgeNameToutTerrain => 'Allrounderin';

  @override
  String get badgeNameSansBroncher => 'Unerschütterlich';

  @override
  String get badgeNameReguliere => 'Regelmäßig';

  @override
  String get badgeNameJamaisRassasiee => 'Nie genug';

  @override
  String get badgeNameVideCouilles => 'Eierleererin';

  @override
  String get badgeNameBouchePleine => 'Mundvoll';

  @override
  String get badgeNameRepeinte => 'Glasiert';

  @override
  String get badgeNameGobeuse => 'Schluckerin';

  @override
  String get badgeNameNettoyeuse => 'Saubermacherin';

  @override
  String get badgeNameSuppliante => 'Bettlerin';

  @override
  String get badgeUnitMarathonien => 'Minuten gesamt';

  @override
  String get badgeUnitThroatQueen => 'Throatfucks gesamt';

  @override
  String get badgeUnitIronLungs => 'Sekunden des längsten Tief-Holds';

  @override
  String get badgeUnitToutTerrain => 'verschiedene benutzte Modi';

  @override
  String get badgeUnitSansBroncher =>
      'komplette Sessions hintereinander ohne Fail';

  @override
  String get badgeUnitReguliere => 'aufeinanderfolgende Tage mit Session';

  @override
  String get badgeUnitJamaisRassasiee =>
      'Male, in denen du um „mehr“ gebettelt hast';

  @override
  String get badgeUnitVideCouilles => 'abgeschlossene Quickies';

  @override
  String get badgeUnitBouchePleine => 'Abspritzer in den Mund';

  @override
  String get badgeUnitRepeinte => 'Abspritzer ins Gesicht';

  @override
  String get badgeUnitGobeuse => 'Abspritzer auf die Zunge';

  @override
  String get badgeUnitNettoyeuse => 'sauber geleckte Reste danach';

  @override
  String get badgeUnitSuppliante => 'Betteleien nach dem Orgasmus';

  @override
  String get careerLevelTitleDebutante => 'Anfängerin';

  @override
  String get careerLevelTitleApprentieSuceuse => 'Lutsch-Lehrling';

  @override
  String get careerLevelTitlePetiteSalopeConfirmee =>
      'Bestätigte kleine Schlampe';

  @override
  String get careerLevelTitleBoucheAPipe => 'Blasmaul';

  @override
  String get careerLevelTitleAvaleuse => 'Schluckerin';

  @override
  String get careerLevelTitleThroatQueen => 'Throat Queen';

  @override
  String get careerLevelTitleReineDuSloppy => 'Sloppy-Queen';

  @override
  String get careerLevelTitleTrouABiteOfficiel => 'Offizielles Schwanzloch';

  @override
  String get careerLevelTitleVideCouillesPro => 'Profi-Eierleererin';

  @override
  String get careerLevelTitleReineDesPutes => 'Königin der Huren';

  @override
  String get specBranchEnduranceLabel => 'Ausdauer';

  @override
  String get specBranchEnduranceDesc =>
      'Lange durchhalten. Mehr Holds, längere Dauern.';

  @override
  String get specBranchProfondeurLabel => 'Tiefe';

  @override
  String get specBranchProfondeurDesc =>
      'Tief runtergehen. Tendenz zu Kehle / ganz.';

  @override
  String get specBranchRythmeBiffleLabel => 'Rhythmus & Klatschen';

  @override
  String get specBranchRythmeBiffleDesc =>
      'Höhere BPM, häufigere Schwanzschläge.';

  @override
  String get specBranchObeissanceLabel => 'Gehorsam';

  @override
  String get specBranchObeissanceDesc =>
      'Eindringliches Betteln, anhaltendes Flehen.';

  @override
  String get specBranchSloppyLabel => 'Sloppy';

  @override
  String get specBranchSloppyDesc =>
      'Feuchtes Lecken, tiefe Schläge, mehr Sabber.';

  @override
  String get specBranchResilienceLabel => 'Resilienz';

  @override
  String get specBranchResilienceDesc => 'Fails einstecken. Härtere Strafen.';

  @override
  String get coachPickerTitle => 'Coach wählen';

  @override
  String get coachPickerSection => 'COACH';

  @override
  String coachPickerTierLabel(int tier) {
    return 'STUFE $tier';
  }

  @override
  String get coachBadgePrincipal => 'HAUPT';

  @override
  String get coachBadgePalierAcquis => 'STUFE FREIGESCHALTET';

  @override
  String get coachBadgeFreeTraining => 'FREIES TRAINING';

  @override
  String get coachBadgeLocked => 'GESPERRT';

  @override
  String get coachRequiresHands => 'Hände erforderlich';

  @override
  String coachSummaryPrincipal(String title, int tier) {
    return '$title · Haupt-Stufe $tier';
  }

  @override
  String coachSummaryFree(String title) {
    return '$title · freies Training';
  }

  @override
  String get coachFreeTrainingDialogTitle => 'Freies Training';

  @override
  String coachFreeTrainingDialogBody(String coachName) {
    return 'Du trainierst mit $coachName. Du machst Fortschritte bei deinen Fähigkeiten, aber deine Stufenanzeige bewegt sich nicht.';
  }

  @override
  String coachFreeTrainingDialogHint(String principalName) {
    return 'Um in deiner Stufe voranzukommen, wähl $principalName.';
  }

  @override
  String coachFreeTrainingDialogChoosePrincipal(String principalName) {
    return '$principalName wählen';
  }

  @override
  String get coachFreeTrainingDialogContinueAnyway => 'Trotzdem fortfahren';

  @override
  String coachPrenomGateTitle(String coachName) {
    return '$coachName will dich kennenlernen';
  }

  @override
  String coachPrenomGateBody(String coachName) {
    return 'Bevor du die Session mit $coachName startest, gib mir deinen Vornamen — sie spricht dich nicht mehr anonym an.';
  }

  @override
  String get coachPrenomGateField => 'Dein Vorname';

  @override
  String get coachPrenomGateConfirm => 'Weiter';

  @override
  String coachFreeTrainingBannerTitle(String coachName) {
    return 'Freie Session mit $coachName';
  }

  @override
  String coachFreeTrainingBannerBodyWithPrincipal(String principalName) {
    return 'Du machst Fortschritte bei deinen Fähigkeiten. Deine Stufe bewegt sich nicht — dafür wähl $principalName.';
  }

  @override
  String get coachFreeTrainingBannerBodyNoPrincipal =>
      'Du machst Fortschritte bei deinen Fähigkeiten. Deine Stufe bewegt sich nicht.';

  @override
  String get coachFreeTrainingBannerSwitchAction => 'WECHSELN';

  @override
  String coachErrorLockedTier(int tier) {
    return 'Dieser Coach ist noch gesperrt — erreiche Stufe $tier, um ihn freizuschalten.';
  }

  @override
  String coachErrorRequiresHands(String coachName) {
    return '$coachName braucht, dass du die Hand in den Optionen aktivierst.';
  }

  @override
  String coachErrorMinLevel(String coachName, int minLevel) {
    return '$coachName erfordert mindestens Stufe $minLevel.';
  }

  @override
  String get coachErrorMissingSpecialization =>
      'Dieser Coach erfordert mindestens 1 Punkt in einer Spezialisierung, in die du nicht investiert hast.';

  @override
  String coachErrorInsufficientBranchPoints(
      String coachName, String requirements) {
    return '$coachName erfordert: $requirements. Vergib deine Spezialisierungspunkte.';
  }

  @override
  String get unlockAnnouncementSloppyDroolBasic =>
      'Ab jetzt hält dein Mund mehr Spucke, und dein Lecken erzeugt mehr davon. Sabber auf mich, sei dreckig.';

  @override
  String get unlockAnnouncementSloppyBiffleSlow =>
      'Die Schwanzschläge bringen dich jetzt zum Sabbern. Nimm sie mit weit offenem Mund entgegen.';

  @override
  String get unlockAnnouncementSloppySwallowControl =>
      'Du kannst deine Spucke jetzt auf Befehl zurückhalten. Wenn ich es dir sage, schluckst du nicht.';

  @override
  String get unlockAnnouncementSloppySpit =>
      'Du weißt jetzt, wie du für mich spuckst. Wenn ich darum bitte, lässt du alles raus.';

  @override
  String get unlockAnnouncementSloppyDroolDeep =>
      'Wenn du tief gehst, läuft dein Mund noch mehr über. Genieß es.';

  @override
  String get unlockAnnouncementRhythmHeadMidSustained =>
      'Du kannst das Tempo jetzt länger als eine Minute halten, ohne Pause. Ich werde danach verlangen.';

  @override
  String get modeSelectionSurpriseTooltip => 'Überraschungs-Erinnerungen';

  @override
  String get surpriseNotifTitle => 'Es ist Zeit';

  @override
  String get surpriseNotifBody1 => 'Lutsch mich, sofort';

  @override
  String get surpriseNotifBody2 => 'Ich will dir den Mund vollmachen, JETZT';

  @override
  String get surpriseNotifBody3 => 'Auf die Knie, es ist Zeit!';

  @override
  String get surpriseSettingsAppBarTitle => 'Überraschungs-Erinnerung';

  @override
  String get surpriseSettingsHeaderSubtitle =>
      'Während des Zeitfensters kann die App zu zufälligen Zeitpunkten Benachrichtigungen senden. Beim Antippen öffnet sie eine kurze Session.';

  @override
  String get surpriseSettingsEnableLabel => 'Erinnerungen aktivieren';

  @override
  String get surpriseSettingsEnableSubtitle =>
      'Zufällige Benachrichtigungen während des Zeitfensters.';

  @override
  String get surpriseSettingsWindowLabel => 'Zeitfenster';

  @override
  String surpriseSettingsWindowValue(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get surpriseSettingsAlertCountLabel => 'Anzahl der Erinnerungen';

  @override
  String surpriseSettingsAlertCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Erinnerungen',
      one: '1 Erinnerung',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsDurationLabel => 'Dauer der Sessions';

  @override
  String surpriseSettingsDurationValue(int minSec, int maxSec) {
    return '$minSec s – $maxSec s';
  }

  @override
  String surpriseSettingsActiveStatus(String endTime) {
    return 'Aktiv bis $endTime';
  }

  @override
  String surpriseSettingsActiveAlertsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Alarme übrig',
      one: '1 Alarm übrig',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsInactiveStatus => 'Keine Erinnerung geplant';

  @override
  String get surpriseSettingsPermissionMissing =>
      'Erlaube Benachrichtigungen in den Systemeinstellungen.';

  @override
  String get surpriseSettingsExactAlarmMissing =>
      'Exakte Alarme werden vom System verweigert.';

  @override
  String get surpriseSettingsBatteryHintTitle => 'Akku-Optimierung';

  @override
  String get surpriseSettingsBatteryHintBody =>
      'Auf manchen Handys (Xiaomi, Huawei, Samsung) solltest du die Akku-Optimierung für BeatBitch deaktivieren, um die Erinnerungen zu garantieren.';

  @override
  String get surpriseSettingsOpenBatterySettings => 'Einstellungen öffnen';

  @override
  String get adultGateTitle => 'Nur für Erwachsene';

  @override
  String get adultGateBody =>
      'BeatBitch enthält explizite sexuelle Inhalte: eine ordinäre, dominante Coach-Stimme, explizite Texte und Hintergrund-GIFs. Indem du fortfährst, bestätigst du:\n\n• dass du mindestens 18 bist (oder das Volljährigkeitsalter in deinem Land);\n• dass du die App im privaten Rahmen nutzt — Audio und Bild eignen sich nicht für den Gebrauch in der Öffentlichkeit;\n• dass dir bewusst ist, dass die Sätze ordinär und dominant sein können.';

  @override
  String get adultGateAccept => 'Ich bin 18+, ich stimme zu';

  @override
  String get adultGateLeave => 'Verlassen';

  @override
  String get onboardingStep1Title => 'Behalte den Bildschirm anfangs im Auge';

  @override
  String get onboardingStep1Body =>
      'Behalte das Handy bei deinen ersten Sessions im Blick: die Animation und die Balken helfen dir, Positionen und Rhythmus zu treffen. Wenn du dich sicher fühlst, kannst du es seitlich ablegen und blind spielen, geführt von Stimme und Beeps.';

  @override
  String get onboardingStep2Title => 'Dreh die Lautstärke auf';

  @override
  String get onboardingStep2Body =>
      'Der Coach spricht leise und die Beeps sind dezent. Dreh die Medienlautstärke hoch oder nutze Kopfhörer/einen Lautsprecher. Die App schickt nichts ins Internet.';

  @override
  String get onboardingStep3Title =>
      'Stell die Stimme ein, gib deinen Vornamen ein';

  @override
  String get onboardingStep3Body =>
      'Im Profil-Bildschirm (Silhouette-Symbol): gib deinen Vornamen ein, wähl deine Spitznamen, deine Oberflächensprache und stell die Standardstimme ein (Geschwindigkeit, Klangfarbe) — hör dir ein Beispiel an. Die Karriere-Coaches haben ihre eigene feste Stimme; nur die Standardstimme, die außerhalb der Karriere genutzt wird, ist einstellbar. Der Coach kann dich dann beim Namen nennen.';

  @override
  String get onboardingNext => 'Weiter';

  @override
  String get onboardingPrevious => 'Zurück';

  @override
  String get onboardingTestVoice => 'Meine Stimme testen';

  @override
  String get onboardingSkip => 'Später';

  @override
  String get profileAboutSection => 'ÜBER';

  @override
  String profileAboutVersion(String appName, String version, String build) {
    return '$appName v$version (Build $build)';
  }

  @override
  String get profileAboutOffline =>
      '100 % offline — keine Telemetrie, nichts wird über das Netzwerk gesendet.';

  @override
  String get profileUpdatesSection => 'UPDATES';

  @override
  String get profileUpdatesBody =>
      'BeatBitch ist 100 % offline und sucht niemals von selbst nach Updates. Um benachrichtigt zu werden, sobald eine neue Version erscheint, installiere Obtainium — einen quelloffenen Android-Store, der GitHub-Releases-Seiten überwacht:\n\n• Obtainium: github.com/ImranR98/Obtainium\n• In Obtainium → „Add App“ einfügen: github.com/bbstudioapp/beatbitch\n\nVon BeatBitch geht kein Netzwerkverkehr aus: Obtainium fragt GitHub selbst ab, unabhängig von der App.';

  @override
  String get profileDisclaimerSection => 'HAFTUNGSAUSSCHLUSS';

  @override
  String get profileDisclaimerBody =>
      'BeatBitch ist ein Spiel für einwilligende Erwachsene, gedacht für den streng privaten Rahmen. Es sicher zu nutzen liegt bei dir, und nur bei dir: hör auf deinen Körper, halte niemals eine Position oder eine Dauer, die wehtut, und behalte jederzeit die Möglichkeit, sofort aufzuhören (der „Ich kann nicht“-Knopf oder einfach die App schließen). Nutze die App nicht unter dem Einfluss von etwas, das dein Urteilsvermögen beeinträchtigt.\n\nDie Stimmen, Texte und Szenarien sind spielerische Dominanzfiktion: kein Satz ist ein echter Befehl, und nichts, was der Coach sagt, sollte jemals an einer anderen Person getan werden ohne deren ausdrückliche, informierte Einwilligung.\n\nDer Herausgeber kann für keine Verletzung und keinen Schaden — körperlich oder psychisch — haftbar gemacht werden, der aus der Nutzung oder dem Missbrauch der App resultiert. Wenn du Zweifel an deiner Gesundheit hast, sprich mit einer Fachperson.';

  @override
  String get sessionCameraInactiveWarning =>
      'Kamera-Prüfung inaktiv — neu kalibrieren';

  @override
  String get sessionCameraInactiveAction => 'Kalibrieren';

  @override
  String get modeSelectionCustomTitle => 'CUSTOM';

  @override
  String get modeSelectionCustomSubtitle =>
      'Maßgeschneiderte Sessions: Dauer, Modus-Mix, Schwierigkeit, Non-Stop.';

  @override
  String get customAppBarTitle => 'Custom-Sessions';

  @override
  String get customListEmptyTitle => 'Noch keine gespeicherte Konfiguration';

  @override
  String get customListEmptyBody =>
      'Erstelle deine erste Konfiguration, um maßgeschneiderte Sessions zu generieren.';

  @override
  String get customNewConfig => 'Neue Konfiguration';

  @override
  String get customLaunchLastTitle => 'Letzte Konfiguration erneut starten';

  @override
  String get customUnnamed => 'Unbenannt';

  @override
  String get customNonStopBadge => 'Non-Stop';

  @override
  String get customDeleteConfirmTitle => 'Diese Konfiguration löschen?';

  @override
  String customDeleteConfirmBody(String name) {
    return '„$name“ wird endgültig gelöscht.';
  }

  @override
  String get customDuplicateSuffix => ' (Kopie)';

  @override
  String get customActionEdit => 'Bearbeiten';

  @override
  String get customActionDuplicate => 'Duplizieren';

  @override
  String get customActionDelete => 'Löschen';

  @override
  String get customActionLaunch => 'Starten';

  @override
  String get customConfigSavedSnack => 'Konfiguration gespeichert.';

  @override
  String customSessionName(String name) {
    return 'Custom — $name';
  }

  @override
  String get customEditorTitleNew => 'Neue Custom-Konfiguration';

  @override
  String get customEditorTitleEdit => 'Konfiguration bearbeiten';

  @override
  String get customFieldNameLabel => 'Name der Konfiguration';

  @override
  String get customFieldNameHint => 'z. B. Tiefer Marathon';

  @override
  String get customSectionCoach => 'Coach';

  @override
  String get customCoachDefaultVoice => 'Standardstimme (ohne Coach)';

  @override
  String get customCoachPickerTitle => 'Coach wählen';

  @override
  String get customCoachPickerDefaultSubtitle =>
      'Generische Satzbank, System-TTS-Stimme';

  @override
  String get customSectionDuration => 'Dauer';

  @override
  String get customNonStopToggle => 'Non-Stop-Modus';

  @override
  String get customNonStopDescription =>
      'Verkettet endlos ganze Zyklen (Boosts + Finale). Der Knopf „Bring mich zum Ende“ löst einen letzten Boost aus und beendet dann wirklich.';

  @override
  String get customCycleDurationLabel => 'Dauer eines Zyklus';

  @override
  String get customProgressiveDifficultyToggle => 'Progressive Schwierigkeit';

  @override
  String get customProgressiveDifficultyDescription =>
      'Jeder Zyklus ist ein bisschen härter und länger als der vorherige.';

  @override
  String customDurationMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get customSectionDifficulty => 'Globale Schwierigkeit';

  @override
  String get customSectionDoses => 'Modus-Mix';

  @override
  String get customDosesHint =>
      '„Keine“ schließt den Modus aus. „Häufig“ bevorzugt ihn.';

  @override
  String get customDangerNoMouthMode =>
      'Lass mindestens einen Mund-Modus aktiv (Rhythmus, Lecken oder Hold).';

  @override
  String get customSectionAxes => 'Orientierungsachsen';

  @override
  String get customAxesHint =>
      'Vergib Punkte, um den Generator zu lenken. Beeinflusst nicht deine Karriere-Spezialisierung.';

  @override
  String customAxesSpent(int spent) {
    return '$spent Pkt. vergeben';
  }

  @override
  String get customSectionAdvanced => 'Erweitert';

  @override
  String get customIncludeHandToggle => 'Handstimulation einbeziehen';

  @override
  String get customIncludeHandDescription =>
      'Aktiviert die Modi Hand und Biffle in der Generierung.';

  @override
  String get customMaxDepthLabel => 'Maximale Tiefe';

  @override
  String get customSaveAndLaunch => 'Speichern und starten';

  @override
  String get customSaveOnly => 'Speichern';

  @override
  String customHostLoadError(String error) {
    return 'Die Custom-Session konnte nicht geladen werden: $error';
  }

  @override
  String get customFinishNowButton => 'Bring mich zum Ende';

  @override
  String get customFinishNowSubtitle => 'letzter Boost, dann Schluss';

  @override
  String get customDifficultyFacile => 'Leicht';

  @override
  String get customDifficultyNormal => 'Normal';

  @override
  String get customDifficultyDifficile => 'Schwer';

  @override
  String get customDifficultyExtreme => 'Extrem';

  @override
  String get customDoseNone => 'Keine';

  @override
  String get customDoseRare => 'Selten';

  @override
  String get customDoseNormal => 'Normal';

  @override
  String get customDoseFrequent => 'Häufig';

  @override
  String get profileSessionDisplaySection => 'Sitzungsanzeige';

  @override
  String get profileShowRemainingTime => 'Restzeit anzeigen';

  @override
  String get profileShowRemainingTimeSubtitle =>
      'Kleine mm:ss-Uhr oben auf dem Bildschirm während der Sitzung.';

  @override
  String sessionRemainingTimeLabel(String time) {
    return 'Rest: $time';
  }
}
