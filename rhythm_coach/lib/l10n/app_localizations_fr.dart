// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'BeatBitch';

  @override
  String get modeSelectionAppBarTitle => 'BEATBITCH';

  @override
  String get modeSelectionProfileTooltip => 'Profil & badges';

  @override
  String get modeSelectionSoundsTooltip => 'Apprendre les sons';

  @override
  String get modeSelectionHeaderTitle => 'Choisis ton mode';

  @override
  String get modeSelectionHeaderSubtitle =>
      'Pose ton téléphone, écoute, exécute.';

  @override
  String get modeSelectionScenarioTitle => 'SCÉNARIO';

  @override
  String get modeSelectionScenarioSubtitle => 'Sessions écrites à l\'avance.';

  @override
  String get modeSelectionCareerTitle => 'CARRIÈRE';

  @override
  String get modeSelectionCareerSubtitle =>
      'Sessions générées. Termine pour débloquer le niveau suivant.';

  @override
  String get homeAppBarTitle => 'SCÉNARIO';

  @override
  String get homeCameraTestTooltip => 'Test caméra (holds)';

  @override
  String get homeDeleteSessionTitle => 'Supprimer cette séance ?';

  @override
  String homeDeleteSessionContent(String sessionName) {
    return '« $sessionName » sera retirée de tes scénarios.';
  }

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String homeLoadError(String error) {
    return 'Erreur de chargement des sessions :\n$error';
  }

  @override
  String get homeEmpty => 'Aucune session disponible.';

  @override
  String get homeMySessions => 'Mes séances';

  @override
  String get homeBuiltinSessions => 'Séances intégrées';

  @override
  String get homeHeaderTitle => 'Choisis ta séance';

  @override
  String get homeHeaderSubtitle => 'Pose ton téléphone, écoute, exécute.';

  @override
  String get sessionStopTitle => 'Arrêter la séance ?';

  @override
  String get sessionStopContent => 'La progression sera perdue.';

  @override
  String get sessionStopConfirm => 'Arrêter';

  @override
  String get sessionVoiceLabel => 'Voix';

  @override
  String get sessionAmbienceLabel => 'Ambiance';

  @override
  String get sessionBegRequestLabel => 'DEMANDÉ';

  @override
  String get sessionBegSupplicateLabel => 'SUPPLIER';

  @override
  String get sessionStateIdle => 'PRÊT';

  @override
  String get sessionStateRunning => 'EN COURS';

  @override
  String get sessionStatePaused => 'PAUSE';

  @override
  String get sessionStateFinished => 'TERMINÉ';

  @override
  String get sessionStateFailing => 'FAIL';

  @override
  String get sessionFailPhasePhrase => 'Phrase de fail';

  @override
  String get sessionFailPhaseBreath => 'Respiration';

  @override
  String get sessionFailPhasePunishment => 'Punition';

  @override
  String get sessionStartPrompt =>
      'Démarre la séance pour entendre les instructions.';

  @override
  String get sessionFailButton => 'JE PEUX PAS';

  @override
  String get sessionIntroBriefing => 'BRIEFING';

  @override
  String get sessionIntroReplay => 'Réécouter';

  @override
  String get sessionIntroReady => 'JE SUIS PRÊTE';

  @override
  String get sessionPausedIndicator => 'EN PAUSE';

  @override
  String get sessionPrepInPlace => 'EN PLACE';

  @override
  String get sessionPrepInstruction =>
      'Pose ton téléphone, mets-toi en position.';

  @override
  String get sessionFinishedTitle => 'SÉANCE TERMINÉE';

  @override
  String sessionFinishedDuration(String duration) {
    return 'Durée : $duration';
  }

  @override
  String get sessionFinishedDefaultEnd => 'Merci !';

  @override
  String get sessionFinishedBadgesTitle => 'Nouveaux paliers de badges';

  @override
  String get sessionFinishedNoNewBadges =>
      'Pas de nouveau palier cette fois — la prochaine sera la bonne.';

  @override
  String get sessionFinishedMilestonesTitle => 'Apprentissages validés';

  @override
  String get sessionFinishedEncore => 'J\'EN VEUX ENCORE…';

  @override
  String get sessionFinishedSaved => 'ENREGISTRÉE';

  @override
  String get sessionFinishedSaving => 'ENREGISTREMENT…';

  @override
  String get sessionFinishedSaveButton => 'ENREGISTRER CETTE SÉANCE';

  @override
  String sessionFinishedSavedSnack(String name) {
    return '« $name » enregistrée dans tes scénarios.';
  }

  @override
  String sessionSaveDefaultName(int day, int month) {
    return 'Ma séance $day/$month';
  }

  @override
  String get sessionSaveDialogTitle => 'Enregistrer la séance';

  @override
  String get sessionSaveDialogContent =>
      'Donne-lui un nom — elle apparaîtra dans la liste SCÉNARIO.';

  @override
  String get sessionSaveDialogHint => 'Nom de la séance';

  @override
  String get sessionSaveDialogConfirm => 'Enregistrer';

  @override
  String get cameraTestEndButton => 'Retour';

  @override
  String get profileAppBarTitle => 'PROFIL';

  @override
  String profileLoadError(String error) {
    return 'Erreur :\n$error';
  }

  @override
  String get profileStatsSection => 'STATISTIQUES';

  @override
  String get profileStatsEmpty =>
      'Aucune statistique pour l\'instant. Termine quelques séances pour révéler tes compteurs.';

  @override
  String get profileBadgesSection => 'BADGES';

  @override
  String get profileBadgesEmpty => 'Aucun badge décroché pour l\'instant.';

  @override
  String profileLevel(int level) {
    return 'Niveau $level';
  }

  @override
  String get profileReputationUnit => 'pts de réputation';

  @override
  String get profileStatSessionsCompleted => 'Sessions terminées';

  @override
  String get profileStatNoFailStreak => 'Streak sans fail';

  @override
  String get profileStatDailyStreak => 'Streak quotidien';

  @override
  String get profileStatTotalTime => 'Temps cumulé';

  @override
  String get profileStatThroatfucks => 'Throatfucks';

  @override
  String get profileStatBiffles => 'Biffles';

  @override
  String get profileStatHoldFullMax => 'Hold full max';

  @override
  String get profileStatHoldThroatTotal => 'Hold throat (cumul)';

  @override
  String get profileStatHoldFullTotal => 'Hold full (cumul)';

  @override
  String get profileStatEncores => 'Encores demandés';

  @override
  String get profileStatQuickies => 'Sessions bâclées';

  @override
  String get profileStatModesUsed => 'Modes utilisés';

  @override
  String get profileCapabilitiesSection => 'CAPACITÉS';

  @override
  String get profileCapabilitiesEmpty =>
      'Rien à montrer pour l\'instant — tes capacités se découvrent en jouant.';

  @override
  String profileCapBpm(int n) {
    return '$n BPM';
  }

  @override
  String get profileCapApnea => 'Apnée';

  @override
  String get profileCapEngagement => 'Gorge engagée';

  @override
  String get profileCapCrossingsThroat => 'Barrière de gorge';

  @override
  String get profileCapCrossingsFull => 'Barrière de gorge (au fond)';

  @override
  String get profileCapCrossingsLifetime => 'Franchissements (cumul)';

  @override
  String get profileCapRhythmFastShallow => 'Rythme bouche — rapide';

  @override
  String get profileCapRhythmFastThroat => 'Rythme gorge — rapide';

  @override
  String get profileCapRhythmFastFull => 'Rythme au fond — rapide';

  @override
  String get profileCapRhythmSlowShallow => 'Rythme bouche — lent';

  @override
  String get profileCapRhythmSlowThroat => 'Rythme gorge — lent';

  @override
  String get profileCapRhythmSlowFull => 'Rythme au fond — lent';

  @override
  String get profileCapRhythmDepth => 'Profondeur rythme';

  @override
  String get profileCapRhythmMotion => 'Mouvement continu';

  @override
  String get profileCapHoldThroat => 'Gorge tenue';

  @override
  String get profileCapHoldFull => 'Au fond tenu';

  @override
  String get profileCapNoSwallow => 'Sans avaler';

  @override
  String get profileCapBiffle => 'Biffle';

  @override
  String get profileCapBiffleFast => 'Biffle — rapide';

  @override
  String get profileCapEffortNoBreath => 'Effort sans pause';

  @override
  String get profileCapBreathMinDose => 'Sas de souffle mini';

  @override
  String get profileCapLickDepth => 'Profondeur langue';

  @override
  String get profileCapLickStreak => 'Langue continue';

  @override
  String get profileCapHandStreak => 'Main continue';

  @override
  String get profileResetSection => 'ZONE DANGER';

  @override
  String get profileResetButton => 'Tout remettre à zéro';

  @override
  String get profileResetDialogTitle => 'Tout remettre à zéro ?';

  @override
  String get profileResetDialogMessage =>
      'Cette action efface toutes tes statistiques, capacités, badges, progression carrière et points de spécialisation. Irréversible.';

  @override
  String get profileResetCancel => 'Annuler';

  @override
  String get profileResetConfirm => 'Tout effacer';

  @override
  String get profileResetDoneSnackbar => 'Profil remis à zéro.';

  @override
  String get careerAppBarTitle => 'CARRIÈRE';

  @override
  String get careerSpecializationTooltip => 'Spécialisation';

  @override
  String careerLoadError(String error) {
    return 'Erreur de chargement :\n$error';
  }

  @override
  String get careerLevelSection => 'Niveau';

  @override
  String careerMaxLevel(int level) {
    return 'max $level';
  }

  @override
  String get careerQuickieToggle => 'Session bâclée';

  @override
  String get careerQuickieSubtitle => '6 min — intense';

  @override
  String get careerQuickieDescription =>
      '6 min, intense tout du long. Pour quand t\'as pas le temps.';

  @override
  String get careerIncludeHandToggle => 'Inclure la stimulation à la main';

  @override
  String get careerIncludeHandSubtitle =>
      'Désactive aussi les coups de queue (biffle) — les deux nécessitent la main.';

  @override
  String get careerIncludeHandMilestoneLocked =>
      'Verrouillé pour cette séance — le milestone d\'apprentissage utilise la main.';

  @override
  String specPointsBannerTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points libres',
      one: '1 point libre',
    );
    return '$_temp0';
  }

  @override
  String get specPointsBannerSubtitle =>
      'Tu as gagné des points de spécialisation. Investis-les avant de démarrer.';

  @override
  String get specPointsBannerCta => 'ALLOUER';

  @override
  String get careerStartButton => 'DÉMARRER';

  @override
  String careerCompletedSessions(int count) {
    return 'Sessions complétées : $count';
  }

  @override
  String get careerLevelLockedHint =>
      'Niveau 1 (termine une séance pour débloquer le suivant)';

  @override
  String careerSessionName(int level) {
    return 'Carrière niveau $level';
  }

  @override
  String careerSessionNameQuickie(int level) {
    return 'Carrière niveau $level — bâclée';
  }

  @override
  String get careerMilestonesBranchesPrefix => 'Branche : ';

  @override
  String get careerMilestonesBranchesPrefixPlural => 'Branches : ';

  @override
  String get cameraTestAppBarTitle => 'TEST CAMÉRA';

  @override
  String get cameraPreviewUnavailable => 'Aperçu indisponible';

  @override
  String get cameraStartSession => 'Lancer la session';

  @override
  String get cameraPermissionDenied =>
      'Permission caméra refusée ou init impossible. Active la caméra dans les réglages Android.';

  @override
  String get cameraUnknownError => 'Erreur inconnue.';

  @override
  String get cameraInitializing => 'Initialisation caméra…';

  @override
  String get cameraRecalibrate => 'Recalibrer';

  @override
  String get cameraCalibrate => 'Calibrer (10 s)';

  @override
  String cameraAxisLabel(String axis) {
    return 'Axe : $axis';
  }

  @override
  String get cameraAxisHorizontal => 'horizontal';

  @override
  String get cameraAxisVertical => 'vertical';

  @override
  String cameraLivePositionLabel(String position) {
    return 'Position live : $position';
  }

  @override
  String get cameraCalibrationTitle => 'Calibration';

  @override
  String get cameraCalibrationInstructions =>
      'Pendant 10 secondes, fais 3 ou 4 mouvements lents et amples — de la position la plus haute (tip) à la plus basse (full). L\'app en déduira l\'axe et les bornes des 5 niveaux.';

  @override
  String get cameraCalibratingMessage =>
      'Calibration en cours… fais des mouvements lents et profonds.';

  @override
  String get cameraCalibratedTitle => 'Calibration OK';

  @override
  String cameraCalibrationSummary(String axis, String range, int samples) {
    return 'Axe : $axis — range $range ($samples échantillons)';
  }

  @override
  String get cameraCalibratedHint =>
      'Tu peux lancer la session. Si la polarité est inversée (tip ↔ full), recalibre dans le bon sens.';

  @override
  String cameraCalibrationFailedRange(String range) {
    return 'Range trop faible ($range). Refais des mouvements plus amples.';
  }

  @override
  String cameraCalibrationFailed(String error) {
    return 'Calibration échouée : $error';
  }

  @override
  String get cameraReturnButton => 'Retour';

  @override
  String get specAppBarTitle => 'SPÉCIALISATION';

  @override
  String specLoadError(String error) {
    return 'Erreur :\n$error';
  }

  @override
  String get specNotEnoughPoints => 'Pas assez de points disponibles.';

  @override
  String get specRespecConfirmTitle => 'Recommencer la spé ?';

  @override
  String get specRespecConfirmContent =>
      'Tous les points de spécialisation seront remis à zéro, tu perdras 1 niveau global et tu ne pourras pas respec à nouveau pendant 3 jours.';

  @override
  String get specRespecConfirmAction => 'Respec';

  @override
  String get specIntro =>
      'Investis tes points pour signaler au moteur ce que tu aimes. Plus tu investis dans une branche, plus le générateur te proposera ce style — sans déséquilibrer tes stats.';

  @override
  String get specPointsAvailableLabel => 'points disponibles';

  @override
  String specLevelLabel(int level) {
    return 'Niveau $level';
  }

  @override
  String specSpentLabel(int spent, int cap) {
    return '$spent / $cap dépensés';
  }

  @override
  String get specPointsUnit => 'pts';

  @override
  String get specRespecActiveLabel =>
      'Recommencer la spécialisation (-1 niveau)';

  @override
  String specRespecCooldownLabel(int hours) {
    return 'Respec dans ${hours}h';
  }

  @override
  String formatDurationSeconds(int s) {
    return '$s s';
  }

  @override
  String formatDurationMinutes(int m) {
    return '$m min';
  }

  @override
  String formatDurationMinutesSeconds(int m, int s) {
    return '$m min $s s';
  }

  @override
  String formatDurationHours(int h) {
    return '$h h';
  }

  @override
  String formatDurationHoursMinutes(int h, String mm) {
    return '$h h $mm';
  }

  @override
  String formatDaysShort(int d) {
    return '$d j';
  }

  @override
  String get settingsAppBarTitle => 'RÉGLAGES';

  @override
  String get settingsLanguageSection => 'Langue';

  @override
  String get settingsLanguageSubtitle =>
      'Langue de l\'interface, des phrases coach et du contenu éditorial.';

  @override
  String get settingsLanguageSystem => 'Suivre le système';

  @override
  String get settingsLanguageFrench => 'Français';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageGerman => 'Deutsch';

  @override
  String get languagePickerTitle => 'Choisis ta langue';

  @override
  String get languagePickerBody =>
      'La langue de ton téléphone n\'est pas (encore) disponible dans BeatBitch. Choisis celle que tu veux utiliser — tu pourras en changer plus tard dans les réglages (icône équaliseur).';

  @override
  String languageNewlyAvailableTitle(String language) {
    return 'Disponible en $language';
  }

  @override
  String languageNewlyAvailableBody(String language) {
    return 'BeatBitch est maintenant traduite en $language, la langue de ton téléphone. Tu peux basculer dessus, ou garder la langue actuelle (modifiable à tout moment dans les réglages).';
  }

  @override
  String languageNewlyAvailableSwitch(String language) {
    return 'Passer en $language';
  }

  @override
  String get languageNewlyAvailableKeep => 'Garder la langue actuelle';

  @override
  String get soundsAppBarTitle => 'SONS';

  @override
  String get soundsStopLoopTooltip => 'Stop loop';

  @override
  String get soundsIdentitySection => 'Identité';

  @override
  String soundsIdentitySubtitle(String token) {
    return 'Le placeholder « $token » dans les phrases est remplacé par un tirage aléatoire entre ton prénom (si saisi) et la liste de surnoms ci-dessous.';
  }

  @override
  String get soundsFirstNameLabel => 'Prénom (optionnel)';

  @override
  String get soundsFirstNameHelper =>
      'Vide = pas de prénom dans le pool. Les voix réseau prononcent inégalement les prénoms.';

  @override
  String get soundsTestSubstitution => 'Tester la substitution';

  @override
  String get soundsDefaultNicknames => 'Surnoms par défaut';

  @override
  String get soundsCustomNicknames => 'Surnoms personnalisés';

  @override
  String get soundsNoCustomNicknames =>
      'Aucun surnom personnalisé pour l\'instant.';

  @override
  String get soundsAddNicknameLabel => 'Ajouter un surnom';

  @override
  String get soundsRemoveNicknameTooltip => 'Supprimer';

  @override
  String get soundsVoiceSection => 'Voix';

  @override
  String get soundsVoiceSubtitle =>
      'Choisis la voix française et la vitesse. Le bouton « Tester » prononce une phrase d\'exemple.';

  @override
  String get soundsRateLabel => 'Vitesse';

  @override
  String get soundsPitchLabel => 'Hauteur';

  @override
  String get soundsTestVoice => 'Tester la voix';

  @override
  String get soundsNoVoiceDetected =>
      'Aucune voix française détectée sur cet appareil.';

  @override
  String get soundsAmbienceSection => 'Ambiance';

  @override
  String get soundsAmbienceSubtitle =>
      'Pack d\'arrière-plan appliqué pendant les séances. Sélection partagée avec l\'écran de jeu. Touche un mode pour écouter.';

  @override
  String get soundsPackLabel => 'Pack';

  @override
  String get soundsPackNoneLabel => 'Aucune';

  @override
  String soundsModeLabel(String name) {
    return 'Mode $name';
  }

  @override
  String get soundsNoTrack => 'pas de track pour ce mode';

  @override
  String get soundsRhythmPositionsSection => 'Positions (rhythm)';

  @override
  String get soundsRhythmPositionsSubtitle =>
      'Tonalité du bip selon la profondeur. Du plus aigu au plus grave.';

  @override
  String get soundsLickPositionsSection => 'Positions (lick)';

  @override
  String get soundsLickPositionsSubtitle =>
      'Mêmes positions, volume réduit pour le ressenti « plus léger ».';

  @override
  String soundsLickPositionLabel(String name) {
    return '$name · lick';
  }

  @override
  String soundsLickPositionSubtitle(String name) {
    return 'Position $name en mode lick';
  }

  @override
  String get soundsHoldSection => 'Hold (position + couche overlay)';

  @override
  String get soundsHoldSubtitle =>
      'Bip de la position joué simultanément avec la couche hold (plus épaisse).';

  @override
  String soundsHoldButton(String position) {
    return 'Hold $position';
  }

  @override
  String soundsHoldPositionSubtitle(String name) {
    return '$name + hold layer';
  }

  @override
  String get soundsSpecificSounds => 'Sons spécifiques';

  @override
  String get soundsBiffleOneShot => 'Biffle (one-shot)';

  @override
  String get soundsBiffleOneShotSubtitle =>
      'Son court et percutant. Au loop, suit le BPM.';

  @override
  String get soundsBreath => 'Breath';

  @override
  String get soundsBreathSubtitle =>
      'Tonalité grave et longue, effet « libérateur ».';

  @override
  String get soundsLoopsDemoSection => 'Loops démos';

  @override
  String get soundsLoopsDemoSubtitle =>
      'Ajuste le BPM, lance le loop, écoute, stoppe.';

  @override
  String get soundsBpmLabel => 'BPM';

  @override
  String get soundsLoopActive => 'EN COURS';

  @override
  String get soundsLoopRhythmHeadMid => 'Rhythm head→mid';

  @override
  String get soundsLoopRhythmThroatFull => 'Rhythm throat→full';

  @override
  String get soundsLoopLickTipHead => 'Lick tip→head';

  @override
  String get soundsLoopBiffle => 'Biffle';

  @override
  String get soundsPosDescTip => 'Très aigu, léger';

  @override
  String get soundsPosDescHead => 'Aigu';

  @override
  String get soundsPosDescMid => 'Médium';

  @override
  String get soundsPosDescThroat => 'Grave';

  @override
  String get soundsPosDescFull => 'Très grave, lourd';

  @override
  String get soundsDebugSection => 'Debug';

  @override
  String get soundsDebugSubtitle => 'Options techniques pour le développement.';

  @override
  String get soundsDebugShowTimer => 'Afficher le timer';

  @override
  String get soundsDebugShowTimerSubtitle =>
      'Remplace l\'animation des mouvements par le compteur mm:ss pendant la séance.';

  @override
  String get soundsDebugShowStaminaBar => 'Afficher la barre d\'endurance';

  @override
  String get soundsDebugShowStaminaBarSubtitle =>
      'Affiche le profil d\'endurance projeté pendant une séance Carrière.';

  @override
  String get soundsDebugShowHumiliationBar =>
      'Afficher la jauge d\'humiliation';

  @override
  String get soundsDebugShowHumiliationBarSubtitle =>
      'Affiche le score d\'humiliation cumulé pendant la séance.';

  @override
  String get soundsDebugShowObedienceBar => 'Afficher le score d\'obéissance';

  @override
  String get soundsDebugShowObedienceBarSubtitle =>
      'Affiche le score 0–100 d\'obéissance (baisse à chaque fail, remonte avec les punitions).';

  @override
  String get soundsDebugShowSalivaBar => 'Afficher la jauge de salive';

  @override
  String get soundsDebugShowSalivaBarSubtitle =>
      'Affiche la jauge 0–max de salive accumulée pendant la séance. Monte avec lick/rhythm/hold profond, descend avec breath/hand. Auto-déglutition à 75 quand la déglutition est autorisée.';

  @override
  String get soundsDebugShowSessionControls => 'Afficher pause / stop';

  @override
  String get soundsDebugShowSessionControlsSubtitle =>
      'Réservé au debug : en prod la séance se déroule sans interaction (téléphone posé), seul le bouton FAIL reste utile.';

  @override
  String get soundsDebugShowModeBadge => 'Afficher mode / BPM / position';

  @override
  String get soundsDebugShowModeBadgeSubtitle =>
      'Réservé au debug : en prod l\'animation suffit à indiquer ce qui se passe.';

  @override
  String get debugBarLabelHumiliation => 'HUMIL.';

  @override
  String get debugBarLabelObedience => 'OBÉI.';

  @override
  String get debugBarLabelSaliva => 'SALIVE';

  @override
  String get soundsDebugCameraHoldCheck => 'Vérif caméra des holds';

  @override
  String get soundsDebugCameraHoldCheckSubtitle =>
      'Pendant les holds, la caméra avant vérifie que la position est tenue. Le coach lance un rappel court si tu dérives. Nécessite d\'avoir calibré la caméra (icône caméra de l\'écran SCÉNARIO).';

  @override
  String get soundsDebugSkipSession => 'Bouton « terminer en succès »';

  @override
  String get soundsDebugSkipSessionSubtitle =>
      'Affiche un bouton dans la séance qui termine immédiatement comme un succès complet (badges, milestones, niveau). Pratique pour itérer sur le contenu sans tout jouer.';

  @override
  String get soundsShowBackgroundMedia => 'Fonds média en séance';

  @override
  String get soundsShowBackgroundMediaSubtitle =>
      'Affiche les images/GIF présents dans assets/backgrounds/ en arrière-plan, avec rotation à chaque step. Désactive pour ne voir que le dégradé d\'ambiance.';

  @override
  String get sessionDebugFinishButton => 'DEBUG : terminer en succès';

  @override
  String get soundsDebugScenarioButton => 'Debug — scénario carrière';

  @override
  String get soundsDebugScenarioSubtitle =>
      'Visualise une session générée sans la jouer : niveau, humil, obéi, milestones, unlocks, et simulation Supplier / fail.';

  @override
  String get careerDebugTitle => 'Debug — Scénario carrière';

  @override
  String get careerDebugSectionParams => 'Paramètres';

  @override
  String get careerDebugSectionScenario => 'Scénario';

  @override
  String get careerDebugLevel => 'Niveau';

  @override
  String get careerDebugHumiliation => 'Humiliation';

  @override
  String get careerDebugObedience => 'Obéissance';

  @override
  String get careerDebugIncludeHand => 'Inclure la stimulation à la main';

  @override
  String get careerDebugQuickie => 'Mode bâclée';

  @override
  String get careerDebugIntense => 'Mode intense (post-Supplier)';

  @override
  String get careerDebugDurationOverride => 'Durée override';

  @override
  String get careerDebugMilestoneBody => 'Milestone body';

  @override
  String get careerDebugMilestoneFinal => 'Milestone final';

  @override
  String get careerDebugUnlocks => 'Unlocks';

  @override
  String get careerDebugUnlocksLoadCurrent => 'Acquis';

  @override
  String get careerDebugUnlocksClear => 'Aucun';

  @override
  String get careerDebugUnlocksAll => 'Tous';

  @override
  String get careerDebugAuto => 'Auto';

  @override
  String get careerDebugNone => 'Aucune';

  @override
  String get careerDebugRegenerate => 'Régénérer';

  @override
  String get careerDebugShowTtsTexts => 'Afficher les textes TTS';

  @override
  String get careerDebugStatStamina => 'Stamina fin';

  @override
  String get careerDebugStatHumilCap => 'Humil cap fin';

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
  String get careerDebugSimulateFail => 'Simuler un fail ici';

  @override
  String get careerDebugSimulateSupplier => 'Simuler un Supplier ici';

  @override
  String get careerDebugClearFork => 'Effacer la branche';

  @override
  String get careerDebugClearAnnotation => 'Effacer l\'annotation';

  @override
  String get careerDebugForkBanner => 'BRANCHE SUPPLIER';

  @override
  String get careerDebugForkFrom => 'Depuis';

  @override
  String get careerDebugForkSteps => 'steps';

  @override
  String get careerDebugFailSnapshotTitle => 'FAIL simulé';

  @override
  String get careerDebugFailSnapshotNext => 'Reprend au step';

  @override
  String get careerDebugFailSnapshotNoNext =>
      'Plus de step jouable après ce fail (fin de séance).';

  @override
  String get positionTip => 'Bout';

  @override
  String get positionHead => 'Gland';

  @override
  String get positionMid => 'Milieu';

  @override
  String get positionThroat => 'Gorge';

  @override
  String get positionFull => 'Tout';

  @override
  String get modeShortRhythm => 'SUCE';

  @override
  String get modeShortHold => 'AU FOND';

  @override
  String get modeShortLick => 'LÈCHE';

  @override
  String get modeShortBiffle => 'BIFFLE';

  @override
  String get modeShortBreath => 'RESPIRE';

  @override
  String get modeShortBeg => 'SUPPLIE';

  @override
  String get modeShortFreestyle => 'LIBRE';

  @override
  String get modeShortHand => 'BRANLE';

  @override
  String get badgeTierBronze => 'Bronze';

  @override
  String get badgeTierSilver => 'Argent';

  @override
  String get badgeTierGold => 'Or';

  @override
  String get badgeTierPlatinium => 'Platine';

  @override
  String badgeUnlockAnnouncement(String name, String tier) {
    return 'Badge débloqué : $name, palier $tier.';
  }

  @override
  String get badgeNameMarathonien => 'Marathonienne';

  @override
  String get badgeNameThroatQueen => 'Throat Queen';

  @override
  String get badgeNameIronLungs => 'Iron Lungs';

  @override
  String get badgeNameToutTerrain => 'Tout-terrain';

  @override
  String get badgeNameSansBroncher => 'Sans broncher';

  @override
  String get badgeNameReguliere => 'Régulière';

  @override
  String get badgeNameJamaisRassasiee => 'Jamais rassasiée';

  @override
  String get badgeNameVideCouilles => 'Vide-Couilles';

  @override
  String get badgeNameBouchePleine => 'Bouche pleine';

  @override
  String get badgeNameRepeinte => 'Repeinte';

  @override
  String get badgeNameGobeuse => 'Gobeuse';

  @override
  String get badgeNameNettoyeuse => 'Nettoyeuse';

  @override
  String get badgeNameSuppliante => 'Suppliante';

  @override
  String get badgeUnitMarathonien => 'minutes cumulées';

  @override
  String get badgeUnitThroatQueen => 'throatfucks cumulés';

  @override
  String get badgeUnitIronLungs => 'secondes du plus long hold full';

  @override
  String get badgeUnitToutTerrain => 'modes différents utilisés';

  @override
  String get badgeUnitSansBroncher =>
      'séances complètes consécutives sans fail';

  @override
  String get badgeUnitReguliere => 'jours consécutifs avec séance';

  @override
  String get badgeUnitJamaisRassasiee => 'fois où tu as redemandé \"encore\"';

  @override
  String get badgeUnitVideCouilles => 'sessions bâclées terminées';

  @override
  String get badgeUnitBouchePleine => 'finals dans la bouche';

  @override
  String get badgeUnitRepeinte => 'finals sur le visage';

  @override
  String get badgeUnitGobeuse => 'finals sur la langue';

  @override
  String get badgeUnitNettoyeuse => 'post-finals à lécher';

  @override
  String get badgeUnitSuppliante => 'suppliques post-orgasme';

  @override
  String get careerLevelTitleDebutante => 'Débutante';

  @override
  String get careerLevelTitleApprentieSuceuse => 'Apprentie Suceuse';

  @override
  String get careerLevelTitlePetiteSalopeConfirmee => 'Petite Salope Confirmée';

  @override
  String get careerLevelTitleBoucheAPipe => 'Bouche à Pipe';

  @override
  String get careerLevelTitleAvaleuse => 'Avaleuse';

  @override
  String get careerLevelTitleThroatQueen => 'Throat Queen';

  @override
  String get careerLevelTitleReineDuSloppy => 'Reine du Sloppy';

  @override
  String get careerLevelTitleTrouABiteOfficiel => 'Trou à Bite Officiel';

  @override
  String get careerLevelTitleVideCouillesPro => 'Vide-Couilles Pro';

  @override
  String get careerLevelTitleReineDesPutes => 'Reine des Putes';

  @override
  String get specBranchEnduranceLabel => 'Endurance';

  @override
  String get specBranchEnduranceDesc =>
      'Tenir longtemps. Plus de holds, durées rallongées.';

  @override
  String get specBranchProfondeurLabel => 'Profondeur';

  @override
  String get specBranchProfondeurDesc =>
      'Aller chercher loin. Biais throat / full.';

  @override
  String get specBranchRythmeBiffleLabel => 'Rythme & Biffle';

  @override
  String get specBranchRythmeBiffleDesc =>
      'BPM élevés, coups de queue plus fréquents.';

  @override
  String get specBranchObeissanceLabel => 'Obéissance';

  @override
  String get specBranchObeissanceDesc => 'Beg insistants, supplique soutenue.';

  @override
  String get specBranchSloppyLabel => 'Sloppy';

  @override
  String get specBranchSloppyDesc => 'Lick humide, biffle bas, plus de bave.';

  @override
  String get specBranchResilienceLabel => 'Résilience';

  @override
  String get specBranchResilienceDesc =>
      'Encaisser les fails. Punitions plus dures.';

  @override
  String get coachPickerTitle => 'Choisir un coach';

  @override
  String get coachPickerSection => 'COACH';

  @override
  String coachPickerTierLabel(int tier) {
    return 'PALIER $tier';
  }

  @override
  String get coachBadgePrincipal => 'PRINCIPAL';

  @override
  String get coachBadgePalierAcquis => 'PALIER ACQUIS';

  @override
  String get coachBadgeFreeTraining => 'ENTRAÎNEMENT LIBRE';

  @override
  String get coachBadgeLocked => 'VERROUILLÉ';

  @override
  String get coachRequiresHands => 'Mains obligatoires';

  @override
  String coachSummaryPrincipal(String title, int tier) {
    return '$title · Principal palier $tier';
  }

  @override
  String coachSummaryFree(String title) {
    return '$title · entraînement libre';
  }

  @override
  String get coachFreeTrainingDialogTitle => 'Entraînement libre';

  @override
  String coachFreeTrainingDialogBody(String coachName) {
    return 'Tu vas t\'entraîner avec $coachName. Tu progresseras sur tes compétences, mais ta jauge de palier n\'avancera pas.';
  }

  @override
  String coachFreeTrainingDialogHint(String principalName) {
    return 'Pour avancer dans ton palier, choisis $principalName.';
  }

  @override
  String coachFreeTrainingDialogChoosePrincipal(String principalName) {
    return 'Choisir $principalName';
  }

  @override
  String get coachFreeTrainingDialogContinueAnyway => 'Continuer quand même';

  @override
  String coachPrenomGateTitle(String coachName) {
    return '$coachName demande à te connaître';
  }

  @override
  String coachPrenomGateBody(String coachName) {
    return 'Avant de démarrer la séance avec $coachName, donne-moi ton prénom — elle ne s\'adressera plus à toi anonymement.';
  }

  @override
  String get coachPrenomGateField => 'Ton prénom';

  @override
  String get coachPrenomGateConfirm => 'Continuer';

  @override
  String coachFreeTrainingBannerTitle(String coachName) {
    return 'Session libre avec $coachName';
  }

  @override
  String coachFreeTrainingBannerBodyWithPrincipal(String principalName) {
    return 'Tu progresses sur tes compétences. Ton palier n\'avance pas — pour ça, choisis $principalName.';
  }

  @override
  String get coachFreeTrainingBannerBodyNoPrincipal =>
      'Tu progresses sur tes compétences. Ton palier n\'avance pas.';

  @override
  String get coachFreeTrainingBannerSwitchAction => 'CHANGER';

  @override
  String coachErrorLockedTier(int tier) {
    return 'Ce coach est encore verrouillé — atteins le palier $tier pour le débloquer.';
  }

  @override
  String coachErrorRequiresHands(String coachName) {
    return '$coachName a besoin que tu actives la main dans les options.';
  }

  @override
  String coachErrorMinLevel(String coachName, int minLevel) {
    return '$coachName demande le niveau $minLevel minimum.';
  }

  @override
  String get coachErrorMissingSpecialization =>
      'Ce coach demande au moins 1 point dans une spécialisation que tu n\'as pas investie.';

  @override
  String coachErrorInsufficientBranchPoints(
      String coachName, String requirements) {
    return '$coachName demande : $requirements. Investis tes points de spécialisation.';
  }

  @override
  String get unlockAnnouncementSloppyDroolBasic =>
      'Désormais ta bouche garde plus de salive, et ton lèche en produit plus. Bave-moi dessus, sois sale.';

  @override
  String get unlockAnnouncementSloppyBiffleSlow =>
      'Les biffles te font baver maintenant. Reçois-les bouche grande ouverte.';

  @override
  String get unlockAnnouncementSloppySwallowControl =>
      'Tu peux désormais retenir ta salive sur ordre. Quand je te le dis, tu n\'avales plus.';

  @override
  String get unlockAnnouncementSloppySpit =>
      'Tu sais cracher pour moi maintenant. Quand je te le demande, tu craches tout.';

  @override
  String get unlockAnnouncementSloppyDroolDeep =>
      'Quand tu vas profond, ta bouche déborde encore plus. Profite.';

  @override
  String get unlockAnnouncementRhythmHeadMidSustained =>
      'Tu peux tenir la cadence plus d\'une minute maintenant, sans pause. Je te le demanderai.';

  @override
  String get modeSelectionSurpriseTooltip => 'Rappels surprise';

  @override
  String get surpriseNotifTitle => 'C\'est l\'heure';

  @override
  String get surpriseNotifBody1 => 'Suce-moi tout de suite';

  @override
  String get surpriseNotifBody2 =>
      'Je veux t\'en mettre plein la bouche MAINTENANT';

  @override
  String get surpriseNotifBody3 => 'Mets-toi à genoux, c\'est l\'heure !';

  @override
  String get surpriseSettingsAppBarTitle => 'Rappel surprise';

  @override
  String get surpriseSettingsHeaderSubtitle =>
      'Pendant la fenêtre, l\'app peut envoyer des notifications à des moments aléatoires. Au tap, elle ouvre une session courte.';

  @override
  String get surpriseSettingsEnableLabel => 'Activer les rappels';

  @override
  String get surpriseSettingsEnableSubtitle =>
      'Notifications aléatoires pendant la fenêtre.';

  @override
  String get surpriseSettingsWindowLabel => 'Fenêtre temporelle';

  @override
  String surpriseSettingsWindowValue(int minutes) {
    return '$minutes min';
  }

  @override
  String get surpriseSettingsAlertCountLabel => 'Nombre de rappels';

  @override
  String surpriseSettingsAlertCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rappels',
      one: '1 rappel',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsDurationLabel => 'Durée des sessions';

  @override
  String surpriseSettingsDurationValue(int minSec, int maxSec) {
    return '$minSec s – $maxSec s';
  }

  @override
  String surpriseSettingsActiveStatus(String endTime) {
    return 'Actif jusqu\'à $endTime';
  }

  @override
  String surpriseSettingsActiveAlertsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alertes restantes',
      one: '1 alerte restante',
    );
    return '$_temp0';
  }

  @override
  String get surpriseSettingsInactiveStatus => 'Aucun rappel programmé';

  @override
  String get surpriseSettingsPermissionMissing =>
      'Autorise les notifications dans les paramètres système.';

  @override
  String get surpriseSettingsExactAlarmMissing =>
      'Les alarmes exactes sont refusées par le système.';

  @override
  String get surpriseSettingsBatteryHintTitle => 'Optimisation batterie';

  @override
  String get surpriseSettingsBatteryHintBody =>
      'Sur certains téléphones (Xiaomi, Huawei, Samsung), désactive l\'optimisation batterie pour BeatBitch pour garantir les rappels.';

  @override
  String get surpriseSettingsOpenBatterySettings => 'Ouvrir les paramètres';

  @override
  String get adultGateTitle => 'Accès réservé aux adultes';

  @override
  String get adultGateBody =>
      'BeatBitch contient du contenu sexuel explicite : voix de coach crue et dominante, textes explicites, GIFs en arrière-plan. En continuant, tu confirmes :\n\n• avoir au moins 18 ans (ou l\'âge légal de majorité dans ton pays) ;\n• utiliser l\'app dans un cadre privé — l\'audio et le visuel ne se prêtent pas à un usage en lieu public ;\n• comprendre que les phrases peuvent être crues et dominantes.';

  @override
  String get adultGateAccept => 'J\'ai 18 ans, j\'accepte';

  @override
  String get adultGateLeave => 'Quitter';

  @override
  String get onboardingStep1Title => 'Garde un œil sur l\'écran au début';

  @override
  String get onboardingStep1Body =>
      'Pour tes premières séances, garde le téléphone sous les yeux : l\'animation et les barres t\'aident à caler les positions et le rythme. Quand tu seras à l\'aise, tu pourras le poser sur le côté et jouer à l\'aveugle, guidée par la voix et les bips.';

  @override
  String get onboardingStep2Title => 'Monte le volume';

  @override
  String get onboardingStep2Body =>
      'La coach parle bas et les bips sont fins. Mets le média à fond ou utilise un casque/enceinte. L\'app n\'envoie rien sur Internet.';

  @override
  String get onboardingStep3Title => 'Règle la voix, mets ton prénom';

  @override
  String get onboardingStep3Body =>
      'Sur l\'écran Profil (icône silhouette) : indique ton prénom, choisis tes surnoms, ta langue d\'interface et règle la voix par défaut (vitesse, timbre) — écoute un exemple. Les coachs de carrière ont leur propre voix figée ; seule la voix par défaut, utilisée hors-carrière, est paramétrable. La coach pourra t\'appeler par ton nom.';

  @override
  String get onboardingNext => 'Suivant';

  @override
  String get onboardingPrevious => 'Précédent';

  @override
  String get onboardingTestVoice => 'Tester ma voix';

  @override
  String get onboardingSkip => 'Plus tard';

  @override
  String get profileAboutSection => 'À PROPOS';

  @override
  String profileAboutVersion(String appName, String version, String build) {
    return '$appName v$version (build $build)';
  }

  @override
  String get profileAboutOffline =>
      '100 % hors ligne — aucune télémétrie, aucun envoi réseau.';

  @override
  String get profileUpdatesSection => 'MISES À JOUR';

  @override
  String get profileUpdatesBody =>
      'BeatBitch est 100 % hors ligne et ne va jamais chercher de mise à jour toute seule. Pour être prévenue dès qu\'une nouvelle version sort, installe Obtainium — un store Android open-source qui surveille les pages GitHub Releases :\n\n• Obtainium : github.com/ImranR98/Obtainium\n• Dans Obtainium → « Add App », colle : github.com/bbstudioapp/beatbitch\n\nAucun trafic réseau ne vient de BeatBitch : c\'est Obtainium qui interroge GitHub, indépendamment de l\'app.';

  @override
  String get profileDisclaimerSection => 'AVERTISSEMENT';

  @override
  String get profileDisclaimerBody =>
      'BeatBitch est un jeu pour adultes consentants, à utiliser dans un cadre strictement privé. C\'est à toi, et à toi seule, qu\'il revient de l\'utiliser de façon sûre : écoute ton corps, ne tiens jamais une position ou une durée qui te fait mal, et garde à tout moment la possibilité de t\'arrêter (bouton « Je peux pas », ou simplement fermer l\'app). N\'utilise pas l\'app sous l\'effet de substances qui altèrent ton jugement.\n\nLes voix, textes et scénarios relèvent de la fiction de domination ludique : aucune phrase n\'est un ordre réel, et rien de ce que dit la coach ne doit être reproduit sur une autre personne sans son consentement explicite et éclairé.\n\nL\'éditeur ne pourra être tenu responsable d\'aucune blessure ni d\'aucun dommage — physique ou psychologique — résultant de l\'usage ou du mésusage de l\'application. En cas de doute sur ta santé, parles-en à un professionnel.';

  @override
  String get sessionCameraInactiveWarning =>
      'Vérif caméra inactive — relancer la calibration';

  @override
  String get sessionCameraInactiveAction => 'Calibrer';

  @override
  String get modeSelectionCustomTitle => 'CUSTOM';

  @override
  String get modeSelectionCustomSubtitle =>
      'Sessions sur mesure : durée, dosage des modes, difficulté, non-stop.';

  @override
  String get customAppBarTitle => 'Sessions custom';

  @override
  String get customListEmptyTitle => 'Aucune config enregistrée';

  @override
  String get customListEmptyBody =>
      'Crée ta première config pour générer des séances sur mesure.';

  @override
  String get customNewConfig => 'Nouvelle config';

  @override
  String get customLaunchLastTitle => 'Relancer la dernière config';

  @override
  String get customUnnamed => 'Sans nom';

  @override
  String get customNonStopBadge => 'Non-stop';

  @override
  String get customDeleteConfirmTitle => 'Supprimer cette config ?';

  @override
  String customDeleteConfirmBody(String name) {
    return '« $name » sera définitivement supprimée.';
  }

  @override
  String get customDuplicateSuffix => ' (copie)';

  @override
  String get customActionEdit => 'Modifier';

  @override
  String get customActionDuplicate => 'Dupliquer';

  @override
  String get customActionDelete => 'Supprimer';

  @override
  String get customActionLaunch => 'Lancer';

  @override
  String get customConfigSavedSnack => 'Config enregistrée.';

  @override
  String customSessionName(String name) {
    return 'Custom — $name';
  }

  @override
  String get customEditorTitleNew => 'Nouvelle config custom';

  @override
  String get customEditorTitleEdit => 'Modifier la config';

  @override
  String get customFieldNameLabel => 'Nom de la config';

  @override
  String get customFieldNameHint => 'ex. Marathon profond';

  @override
  String get customSectionCoach => 'Coach';

  @override
  String get customCoachDefaultVoice => 'Voix par défaut (sans coach)';

  @override
  String get customCoachPickerTitle => 'Choisir un coach';

  @override
  String get customCoachPickerDefaultSubtitle =>
      'PhraseBank générique, voix TTS système';

  @override
  String get customSectionDuration => 'Durée';

  @override
  String get customNonStopToggle => 'Mode non-stop';

  @override
  String get customNonStopDescription =>
      'Enchaîne des cycles complets (boosts + final) sans fin. Le bouton « Termine-moi » sort un boost final puis termine vraiment.';

  @override
  String get customCycleDurationLabel => 'Durée d\'un cycle';

  @override
  String get customProgressiveDifficultyToggle => 'Difficulté progressive';

  @override
  String get customProgressiveDifficultyDescription =>
      'Chaque cycle est un peu plus dur et plus long que le précédent.';

  @override
  String customDurationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get customSectionDifficulty => 'Difficulté globale';

  @override
  String get customSectionDoses => 'Dosage des modes';

  @override
  String get customDosesHint =>
      '« Aucun » exclut le mode. « Fréquent » le favorise.';

  @override
  String get customDangerNoMouthMode =>
      'Garde au moins un mode bouche actif (rythme, lick ou hold).';

  @override
  String get customSectionAxes => 'Axes d\'orientation';

  @override
  String get customAxesHint =>
      'Répartis des points pour orienter le générateur. N\'affecte pas ta spécialisation de carrière.';

  @override
  String customAxesSpent(int spent) {
    return '$spent pts répartis';
  }

  @override
  String get customSectionAdvanced => 'Avancé';

  @override
  String get customIncludeHandToggle => 'Inclure la stimulation à la main';

  @override
  String get customIncludeHandDescription =>
      'Active les modes main et biffle dans la génération.';

  @override
  String get customMaxDepthLabel => 'Profondeur maximale';

  @override
  String get customSaveAndLaunch => 'Enregistrer et lancer';

  @override
  String get customSaveOnly => 'Enregistrer';

  @override
  String customHostLoadError(String error) {
    return 'Impossible de charger la session custom : $error';
  }

  @override
  String get customFinishNowButton => 'Termine-moi';

  @override
  String get customFinishNowSubtitle => 'boost final puis fin';

  @override
  String get customDifficultyFacile => 'Facile';

  @override
  String get customDifficultyNormal => 'Normal';

  @override
  String get customDifficultyDifficile => 'Difficile';

  @override
  String get customDifficultyExtreme => 'Extrême';

  @override
  String get customDoseNone => 'Aucun';

  @override
  String get customDoseRare => 'Rare';

  @override
  String get customDoseNormal => 'Normal';

  @override
  String get customDoseFrequent => 'Fréquent';

  @override
  String get profileSessionDisplaySection => 'Affichage de session';

  @override
  String get profileShowRemainingTime => 'Afficher le temps restant';

  @override
  String get profileShowRemainingTimeSubtitle =>
      'Petite horloge mm:ss en haut de l\'écran pendant la séance.';

  @override
  String sessionRemainingTimeLabel(String time) {
    return 'Restant : $time';
  }
}
