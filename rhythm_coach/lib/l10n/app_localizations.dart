import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('fr')];

  /// Nom de l'application affiché par le système Android.
  ///
  /// In fr, this message translates to:
  /// **'Rhythm Coach'**
  String get appTitle;

  /// No description provided for @modeSelectionAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'RHYTHM COACH'**
  String get modeSelectionAppBarTitle;

  /// No description provided for @modeSelectionProfileTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Profil & badges'**
  String get modeSelectionProfileTooltip;

  /// No description provided for @modeSelectionSoundsTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Apprendre les sons'**
  String get modeSelectionSoundsTooltip;

  /// No description provided for @modeSelectionHeaderTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisis ton mode'**
  String get modeSelectionHeaderTitle;

  /// No description provided for @modeSelectionHeaderSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pose ton téléphone, écoute, exécute.'**
  String get modeSelectionHeaderSubtitle;

  /// No description provided for @modeSelectionScenarioTitle.
  ///
  /// In fr, this message translates to:
  /// **'SCÉNARIO'**
  String get modeSelectionScenarioTitle;

  /// No description provided for @modeSelectionScenarioSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Sessions écrites à l\'avance.'**
  String get modeSelectionScenarioSubtitle;

  /// No description provided for @modeSelectionCareerTitle.
  ///
  /// In fr, this message translates to:
  /// **'CARRIÈRE'**
  String get modeSelectionCareerTitle;

  /// No description provided for @modeSelectionCareerSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Sessions générées. Termine pour débloquer le niveau suivant.'**
  String get modeSelectionCareerSubtitle;

  /// No description provided for @homeAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'SCÉNARIO'**
  String get homeAppBarTitle;

  /// No description provided for @homeCameraTestTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Test caméra (holds)'**
  String get homeCameraTestTooltip;

  /// No description provided for @homeDeleteSessionTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cette séance ?'**
  String get homeDeleteSessionTitle;

  /// No description provided for @homeDeleteSessionContent.
  ///
  /// In fr, this message translates to:
  /// **'« {sessionName} » sera retirée de tes scénarios.'**
  String homeDeleteSessionContent(String sessionName);

  /// No description provided for @commonCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get commonDelete;

  /// No description provided for @commonContinue.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get commonContinue;

  /// No description provided for @commonAdd.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get commonAdd;

  /// No description provided for @homeLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de chargement des sessions :\n{error}'**
  String homeLoadError(String error);

  /// No description provided for @homeEmpty.
  ///
  /// In fr, this message translates to:
  /// **'Aucune session disponible.'**
  String get homeEmpty;

  /// No description provided for @homeMySessions.
  ///
  /// In fr, this message translates to:
  /// **'Mes séances'**
  String get homeMySessions;

  /// No description provided for @homeBuiltinSessions.
  ///
  /// In fr, this message translates to:
  /// **'Séances intégrées'**
  String get homeBuiltinSessions;

  /// No description provided for @homeHeaderTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisis ta séance'**
  String get homeHeaderTitle;

  /// No description provided for @homeHeaderSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pose ton téléphone, écoute, exécute.'**
  String get homeHeaderSubtitle;

  /// No description provided for @sessionStopTitle.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter la séance ?'**
  String get sessionStopTitle;

  /// No description provided for @sessionStopContent.
  ///
  /// In fr, this message translates to:
  /// **'La progression sera perdue.'**
  String get sessionStopContent;

  /// No description provided for @sessionStopConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter'**
  String get sessionStopConfirm;

  /// No description provided for @sessionVoiceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Voix'**
  String get sessionVoiceLabel;

  /// No description provided for @sessionAmbienceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Ambiance'**
  String get sessionAmbienceLabel;

  /// No description provided for @sessionBegRequestLabel.
  ///
  /// In fr, this message translates to:
  /// **'DEMANDÉ'**
  String get sessionBegRequestLabel;

  /// No description provided for @sessionBegSupplicateLabel.
  ///
  /// In fr, this message translates to:
  /// **'SUPPLIER'**
  String get sessionBegSupplicateLabel;

  /// No description provided for @sessionStateIdle.
  ///
  /// In fr, this message translates to:
  /// **'PRÊT'**
  String get sessionStateIdle;

  /// No description provided for @sessionStateRunning.
  ///
  /// In fr, this message translates to:
  /// **'EN COURS'**
  String get sessionStateRunning;

  /// No description provided for @sessionStatePaused.
  ///
  /// In fr, this message translates to:
  /// **'PAUSE'**
  String get sessionStatePaused;

  /// No description provided for @sessionStateFinished.
  ///
  /// In fr, this message translates to:
  /// **'TERMINÉ'**
  String get sessionStateFinished;

  /// No description provided for @sessionStateFailing.
  ///
  /// In fr, this message translates to:
  /// **'FAIL'**
  String get sessionStateFailing;

  /// No description provided for @sessionFailPhasePhrase.
  ///
  /// In fr, this message translates to:
  /// **'Phrase de fail'**
  String get sessionFailPhasePhrase;

  /// No description provided for @sessionFailPhaseBreath.
  ///
  /// In fr, this message translates to:
  /// **'Respiration'**
  String get sessionFailPhaseBreath;

  /// No description provided for @sessionFailPhasePunishment.
  ///
  /// In fr, this message translates to:
  /// **'Punition'**
  String get sessionFailPhasePunishment;

  /// No description provided for @sessionStartPrompt.
  ///
  /// In fr, this message translates to:
  /// **'Démarre la séance pour entendre les instructions.'**
  String get sessionStartPrompt;

  /// No description provided for @sessionFailButton.
  ///
  /// In fr, this message translates to:
  /// **'JE PEUX PAS'**
  String get sessionFailButton;

  /// No description provided for @sessionIntroBriefing.
  ///
  /// In fr, this message translates to:
  /// **'BRIEFING'**
  String get sessionIntroBriefing;

  /// No description provided for @sessionIntroReplay.
  ///
  /// In fr, this message translates to:
  /// **'Réécouter'**
  String get sessionIntroReplay;

  /// No description provided for @sessionIntroReady.
  ///
  /// In fr, this message translates to:
  /// **'JE SUIS PRÊTE'**
  String get sessionIntroReady;

  /// No description provided for @sessionPrepInPlace.
  ///
  /// In fr, this message translates to:
  /// **'EN PLACE'**
  String get sessionPrepInPlace;

  /// No description provided for @sessionPrepInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Pose ton téléphone, mets-toi en position.'**
  String get sessionPrepInstruction;

  /// No description provided for @sessionFinishedTitle.
  ///
  /// In fr, this message translates to:
  /// **'SÉANCE TERMINÉE'**
  String get sessionFinishedTitle;

  /// No description provided for @sessionFinishedDefaultEnd.
  ///
  /// In fr, this message translates to:
  /// **'Merci !'**
  String get sessionFinishedDefaultEnd;

  /// No description provided for @sessionFinishedBadgesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouveaux paliers de badges'**
  String get sessionFinishedBadgesTitle;

  /// No description provided for @sessionFinishedNoNewBadges.
  ///
  /// In fr, this message translates to:
  /// **'Pas de nouveau palier cette fois — la prochaine sera la bonne.'**
  String get sessionFinishedNoNewBadges;

  /// No description provided for @sessionFinishedEncore.
  ///
  /// In fr, this message translates to:
  /// **'J\'EN VEUX ENCORE…'**
  String get sessionFinishedEncore;

  /// No description provided for @sessionFinishedSaved.
  ///
  /// In fr, this message translates to:
  /// **'ENREGISTRÉE'**
  String get sessionFinishedSaved;

  /// No description provided for @sessionFinishedSaving.
  ///
  /// In fr, this message translates to:
  /// **'ENREGISTREMENT…'**
  String get sessionFinishedSaving;

  /// No description provided for @sessionFinishedSaveButton.
  ///
  /// In fr, this message translates to:
  /// **'ENREGISTRER CETTE SÉANCE'**
  String get sessionFinishedSaveButton;

  /// No description provided for @sessionFinishedSavedSnack.
  ///
  /// In fr, this message translates to:
  /// **'« {name} » enregistrée dans tes scénarios.'**
  String sessionFinishedSavedSnack(String name);

  /// No description provided for @sessionSaveDefaultName.
  ///
  /// In fr, this message translates to:
  /// **'Ma séance {day}/{month}'**
  String sessionSaveDefaultName(int day, int month);

  /// No description provided for @sessionSaveDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer la séance'**
  String get sessionSaveDialogTitle;

  /// No description provided for @sessionSaveDialogContent.
  ///
  /// In fr, this message translates to:
  /// **'Donne-lui un nom — elle apparaîtra dans la liste SCÉNARIO.'**
  String get sessionSaveDialogContent;

  /// No description provided for @sessionSaveDialogHint.
  ///
  /// In fr, this message translates to:
  /// **'Nom de la séance'**
  String get sessionSaveDialogHint;

  /// No description provided for @sessionSaveDialogConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get sessionSaveDialogConfirm;

  /// No description provided for @cameraTestEndButton.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get cameraTestEndButton;

  /// No description provided for @profileAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'PROFIL'**
  String get profileAppBarTitle;

  /// No description provided for @profileLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur :\n{error}'**
  String profileLoadError(String error);

  /// No description provided for @profileStatsSection.
  ///
  /// In fr, this message translates to:
  /// **'STATISTIQUES'**
  String get profileStatsSection;

  /// No description provided for @profileBadgesSection.
  ///
  /// In fr, this message translates to:
  /// **'BADGES'**
  String get profileBadgesSection;

  /// No description provided for @profileLevel.
  ///
  /// In fr, this message translates to:
  /// **'Niveau {level}'**
  String profileLevel(int level);

  /// No description provided for @profileReputationUnit.
  ///
  /// In fr, this message translates to:
  /// **'pts de réputation'**
  String get profileReputationUnit;

  /// No description provided for @profileStatSessionsCompleted.
  ///
  /// In fr, this message translates to:
  /// **'Sessions terminées'**
  String get profileStatSessionsCompleted;

  /// No description provided for @profileStatNoFailStreak.
  ///
  /// In fr, this message translates to:
  /// **'Streak sans fail'**
  String get profileStatNoFailStreak;

  /// No description provided for @profileStatDailyStreak.
  ///
  /// In fr, this message translates to:
  /// **'Streak quotidien'**
  String get profileStatDailyStreak;

  /// No description provided for @profileStatTotalTime.
  ///
  /// In fr, this message translates to:
  /// **'Temps cumulé'**
  String get profileStatTotalTime;

  /// No description provided for @profileStatThroatfucks.
  ///
  /// In fr, this message translates to:
  /// **'Throatfucks'**
  String get profileStatThroatfucks;

  /// No description provided for @profileStatBiffles.
  ///
  /// In fr, this message translates to:
  /// **'Biffles'**
  String get profileStatBiffles;

  /// No description provided for @profileStatHoldFullMax.
  ///
  /// In fr, this message translates to:
  /// **'Hold full max'**
  String get profileStatHoldFullMax;

  /// No description provided for @profileStatHoldThroatTotal.
  ///
  /// In fr, this message translates to:
  /// **'Hold throat (cumul)'**
  String get profileStatHoldThroatTotal;

  /// No description provided for @profileStatHoldFullTotal.
  ///
  /// In fr, this message translates to:
  /// **'Hold full (cumul)'**
  String get profileStatHoldFullTotal;

  /// No description provided for @profileStatEncores.
  ///
  /// In fr, this message translates to:
  /// **'Encores demandés'**
  String get profileStatEncores;

  /// No description provided for @profileStatQuickies.
  ///
  /// In fr, this message translates to:
  /// **'Sessions bâclées'**
  String get profileStatQuickies;

  /// No description provided for @profileStatModesUsed.
  ///
  /// In fr, this message translates to:
  /// **'Modes utilisés'**
  String get profileStatModesUsed;

  /// No description provided for @profileResetSection.
  ///
  /// In fr, this message translates to:
  /// **'ZONE DANGER'**
  String get profileResetSection;

  /// No description provided for @profileResetButton.
  ///
  /// In fr, this message translates to:
  /// **'Tout remettre à zéro'**
  String get profileResetButton;

  /// No description provided for @profileResetDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Tout remettre à zéro ?'**
  String get profileResetDialogTitle;

  /// No description provided for @profileResetDialogMessage.
  ///
  /// In fr, this message translates to:
  /// **'Cette action efface toutes tes statistiques, badges, progression carrière et points de spécialisation. Irréversible.'**
  String get profileResetDialogMessage;

  /// No description provided for @profileResetCancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get profileResetCancel;

  /// No description provided for @profileResetConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Tout effacer'**
  String get profileResetConfirm;

  /// No description provided for @profileResetDoneSnackbar.
  ///
  /// In fr, this message translates to:
  /// **'Profil remis à zéro.'**
  String get profileResetDoneSnackbar;

  /// No description provided for @careerAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'CARRIÈRE'**
  String get careerAppBarTitle;

  /// No description provided for @careerSpecializationTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Spécialisation'**
  String get careerSpecializationTooltip;

  /// No description provided for @careerLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur de chargement :\n{error}'**
  String careerLoadError(String error);

  /// No description provided for @careerHeaderTitle.
  ///
  /// In fr, this message translates to:
  /// **'Génération procédurale'**
  String get careerHeaderTitle;

  /// No description provided for @careerInstruction.
  ///
  /// In fr, this message translates to:
  /// **'Choisis un niveau. La durée et la difficulté en découlent.'**
  String get careerInstruction;

  /// No description provided for @careerLevelSection.
  ///
  /// In fr, this message translates to:
  /// **'Niveau'**
  String get careerLevelSection;

  /// No description provided for @careerMaxLevel.
  ///
  /// In fr, this message translates to:
  /// **'max {level}'**
  String careerMaxLevel(int level);

  /// No description provided for @careerQuickieToggle.
  ///
  /// In fr, this message translates to:
  /// **'Session bâclée'**
  String get careerQuickieToggle;

  /// No description provided for @careerQuickieSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'6 min — intense'**
  String get careerQuickieSubtitle;

  /// No description provided for @careerQuickieDescription.
  ///
  /// In fr, this message translates to:
  /// **'6 min, intense tout du long. Pour quand t\'as pas le temps.'**
  String get careerQuickieDescription;

  /// No description provided for @careerQuickieLockedSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Verrouillé jusqu\'au niveau {level} — il faut maîtriser les bases avant de bâcler.'**
  String careerQuickieLockedSubtitle(int level);

  /// No description provided for @careerIncludeHandToggle.
  ///
  /// In fr, this message translates to:
  /// **'Inclure la stimulation à la main'**
  String get careerIncludeHandToggle;

  /// No description provided for @careerIncludeHandSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Désactive aussi les coups de queue (biffle) — les deux nécessitent la main.'**
  String get careerIncludeHandSubtitle;

  /// No description provided for @careerIncludeHandLockedSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Verrouillé jusqu\'au niveau {level} — sans la main, le finish bas niveau devient trop dur.'**
  String careerIncludeHandLockedSubtitle(int level);

  /// No description provided for @careerIncludeHandMilestoneLocked.
  ///
  /// In fr, this message translates to:
  /// **'Verrouillé pour cette séance — le milestone d\'apprentissage utilise la main.'**
  String get careerIncludeHandMilestoneLocked;

  /// No description provided for @specPointsBannerTitle.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 point libre} other{{count} points libres}}'**
  String specPointsBannerTitle(int count);

  /// No description provided for @specPointsBannerSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tu as gagné des points de spécialisation. Investis-les avant de démarrer.'**
  String get specPointsBannerSubtitle;

  /// No description provided for @specPointsBannerCta.
  ///
  /// In fr, this message translates to:
  /// **'ALLOUER'**
  String get specPointsBannerCta;

  /// No description provided for @careerStartButton.
  ///
  /// In fr, this message translates to:
  /// **'DÉMARRER'**
  String get careerStartButton;

  /// No description provided for @careerCompletedSessions.
  ///
  /// In fr, this message translates to:
  /// **'Sessions complétées : {count}'**
  String careerCompletedSessions(int count);

  /// No description provided for @careerLevelLockedHint.
  ///
  /// In fr, this message translates to:
  /// **'Niveau 1 (termine une séance pour débloquer le suivant)'**
  String get careerLevelLockedHint;

  /// No description provided for @careerMilestonesPendingTitle.
  ///
  /// In fr, this message translates to:
  /// **'Apprentissages en attente'**
  String get careerMilestonesPendingTitle;

  /// No description provided for @careerMilestonesNextBadge.
  ///
  /// In fr, this message translates to:
  /// **'PROCHAIN'**
  String get careerMilestonesNextBadge;

  /// No description provided for @careerMilestonesBranchesPrefix.
  ///
  /// In fr, this message translates to:
  /// **'Branche : '**
  String get careerMilestonesBranchesPrefix;

  /// No description provided for @careerMilestonesBranchesPrefixPlural.
  ///
  /// In fr, this message translates to:
  /// **'Branches : '**
  String get careerMilestonesBranchesPrefixPlural;

  /// No description provided for @cameraTestAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'TEST CAMÉRA'**
  String get cameraTestAppBarTitle;

  /// No description provided for @cameraPreviewUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Aperçu indisponible'**
  String get cameraPreviewUnavailable;

  /// No description provided for @cameraStartSession.
  ///
  /// In fr, this message translates to:
  /// **'Lancer la session'**
  String get cameraStartSession;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In fr, this message translates to:
  /// **'Permission caméra refusée ou init impossible. Active la caméra dans les réglages Android.'**
  String get cameraPermissionDenied;

  /// No description provided for @cameraUnknownError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur inconnue.'**
  String get cameraUnknownError;

  /// No description provided for @cameraInitializing.
  ///
  /// In fr, this message translates to:
  /// **'Initialisation caméra…'**
  String get cameraInitializing;

  /// No description provided for @cameraRecalibrate.
  ///
  /// In fr, this message translates to:
  /// **'Recalibrer'**
  String get cameraRecalibrate;

  /// No description provided for @cameraCalibrate.
  ///
  /// In fr, this message translates to:
  /// **'Calibrer (10 s)'**
  String get cameraCalibrate;

  /// No description provided for @cameraAxisLabel.
  ///
  /// In fr, this message translates to:
  /// **'Axe : {axis}'**
  String cameraAxisLabel(String axis);

  /// No description provided for @cameraAxisHorizontal.
  ///
  /// In fr, this message translates to:
  /// **'horizontal'**
  String get cameraAxisHorizontal;

  /// No description provided for @cameraAxisVertical.
  ///
  /// In fr, this message translates to:
  /// **'vertical'**
  String get cameraAxisVertical;

  /// No description provided for @cameraLivePositionLabel.
  ///
  /// In fr, this message translates to:
  /// **'Position live : {position}'**
  String cameraLivePositionLabel(String position);

  /// No description provided for @cameraCalibrationTitle.
  ///
  /// In fr, this message translates to:
  /// **'Calibration'**
  String get cameraCalibrationTitle;

  /// No description provided for @cameraCalibrationInstructions.
  ///
  /// In fr, this message translates to:
  /// **'Pendant 10 secondes, fais 3 ou 4 mouvements lents et amples — de la position la plus haute (tip) à la plus basse (full). L\'app en déduira l\'axe et les bornes des 5 niveaux.'**
  String get cameraCalibrationInstructions;

  /// No description provided for @cameraCalibratingMessage.
  ///
  /// In fr, this message translates to:
  /// **'Calibration en cours… fais des mouvements lents et profonds.'**
  String get cameraCalibratingMessage;

  /// No description provided for @cameraCalibratedTitle.
  ///
  /// In fr, this message translates to:
  /// **'Calibration OK'**
  String get cameraCalibratedTitle;

  /// No description provided for @cameraCalibrationSummary.
  ///
  /// In fr, this message translates to:
  /// **'Axe : {axis} — range {range} ({samples} échantillons)'**
  String cameraCalibrationSummary(String axis, String range, int samples);

  /// No description provided for @cameraCalibratedHint.
  ///
  /// In fr, this message translates to:
  /// **'Tu peux lancer la session. Si la polarité est inversée (tip ↔ full), recalibre dans le bon sens.'**
  String get cameraCalibratedHint;

  /// No description provided for @cameraCalibrationFailedRange.
  ///
  /// In fr, this message translates to:
  /// **'Range trop faible ({range}). Refais des mouvements plus amples.'**
  String cameraCalibrationFailedRange(String range);

  /// No description provided for @cameraCalibrationFailed.
  ///
  /// In fr, this message translates to:
  /// **'Calibration échouée : {error}'**
  String cameraCalibrationFailed(String error);

  /// No description provided for @cameraReturnButton.
  ///
  /// In fr, this message translates to:
  /// **'Retour'**
  String get cameraReturnButton;

  /// No description provided for @specAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'SPÉCIALISATION'**
  String get specAppBarTitle;

  /// No description provided for @specLoadError.
  ///
  /// In fr, this message translates to:
  /// **'Erreur :\n{error}'**
  String specLoadError(String error);

  /// No description provided for @specNotEnoughPoints.
  ///
  /// In fr, this message translates to:
  /// **'Pas assez de points disponibles.'**
  String get specNotEnoughPoints;

  /// No description provided for @specRespecConfirmTitle.
  ///
  /// In fr, this message translates to:
  /// **'Recommencer la spé ?'**
  String get specRespecConfirmTitle;

  /// No description provided for @specRespecConfirmContent.
  ///
  /// In fr, this message translates to:
  /// **'Tous les points de spécialisation seront remis à zéro, tu perdras 1 niveau global et tu ne pourras pas respec à nouveau pendant 3 jours.'**
  String get specRespecConfirmContent;

  /// No description provided for @specRespecConfirmAction.
  ///
  /// In fr, this message translates to:
  /// **'Respec'**
  String get specRespecConfirmAction;

  /// No description provided for @specIntro.
  ///
  /// In fr, this message translates to:
  /// **'Investis tes points pour signaler au moteur ce que tu aimes. Plus tu investis dans une branche, plus le générateur te proposera ce style — sans déséquilibrer tes stats.'**
  String get specIntro;

  /// No description provided for @specPointsAvailableLabel.
  ///
  /// In fr, this message translates to:
  /// **'points disponibles'**
  String get specPointsAvailableLabel;

  /// No description provided for @specLevelLabel.
  ///
  /// In fr, this message translates to:
  /// **'Niveau {level}'**
  String specLevelLabel(int level);

  /// No description provided for @specSpentLabel.
  ///
  /// In fr, this message translates to:
  /// **'{spent} / {cap} dépensés'**
  String specSpentLabel(int spent, int cap);

  /// No description provided for @specPointsUnit.
  ///
  /// In fr, this message translates to:
  /// **'pts'**
  String get specPointsUnit;

  /// No description provided for @specRespecActiveLabel.
  ///
  /// In fr, this message translates to:
  /// **'Recommencer la spécialisation (-1 niveau)'**
  String get specRespecActiveLabel;

  /// No description provided for @specRespecCooldownLabel.
  ///
  /// In fr, this message translates to:
  /// **'Respec dans {hours}h'**
  String specRespecCooldownLabel(int hours);

  /// No description provided for @formatDurationSeconds.
  ///
  /// In fr, this message translates to:
  /// **'{s} s'**
  String formatDurationSeconds(int s);

  /// No description provided for @formatDurationMinutes.
  ///
  /// In fr, this message translates to:
  /// **'{m} min'**
  String formatDurationMinutes(int m);

  /// No description provided for @formatDurationMinutesSeconds.
  ///
  /// In fr, this message translates to:
  /// **'{m} min {s} s'**
  String formatDurationMinutesSeconds(int m, int s);

  /// No description provided for @formatDurationHours.
  ///
  /// In fr, this message translates to:
  /// **'{h} h'**
  String formatDurationHours(int h);

  /// No description provided for @formatDurationHoursMinutes.
  ///
  /// In fr, this message translates to:
  /// **'{h} h {mm}'**
  String formatDurationHoursMinutes(int h, String mm);

  /// No description provided for @settingsAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'RÉGLAGES'**
  String get settingsAppBarTitle;

  /// No description provided for @settingsLanguageSection.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get settingsLanguageSection;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Langue de l\'interface, des phrases coach et du contenu éditorial.'**
  String get settingsLanguageSubtitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Suivre le système'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageFrench.
  ///
  /// In fr, this message translates to:
  /// **'Français'**
  String get settingsLanguageFrench;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In fr, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @soundsAppBarTitle.
  ///
  /// In fr, this message translates to:
  /// **'SONS'**
  String get soundsAppBarTitle;

  /// No description provided for @soundsStopLoopTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Stop loop'**
  String get soundsStopLoopTooltip;

  /// No description provided for @soundsIdentitySection.
  ///
  /// In fr, this message translates to:
  /// **'Identité'**
  String get soundsIdentitySection;

  /// No description provided for @soundsIdentitySubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Le placeholder « {token} » dans les phrases est remplacé par un tirage aléatoire entre ton prénom (si saisi) et la liste de surnoms ci-dessous.'**
  String soundsIdentitySubtitle(String token);

  /// No description provided for @soundsFirstNameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Prénom (optionnel)'**
  String get soundsFirstNameLabel;

  /// No description provided for @soundsFirstNameHelper.
  ///
  /// In fr, this message translates to:
  /// **'Vide = pas de prénom dans le pool. Les voix réseau prononcent inégalement les prénoms.'**
  String get soundsFirstNameHelper;

  /// No description provided for @soundsTestSubstitution.
  ///
  /// In fr, this message translates to:
  /// **'Tester la substitution'**
  String get soundsTestSubstitution;

  /// No description provided for @soundsDefaultNicknames.
  ///
  /// In fr, this message translates to:
  /// **'Surnoms par défaut'**
  String get soundsDefaultNicknames;

  /// No description provided for @soundsCustomNicknames.
  ///
  /// In fr, this message translates to:
  /// **'Surnoms personnalisés'**
  String get soundsCustomNicknames;

  /// No description provided for @soundsNoCustomNicknames.
  ///
  /// In fr, this message translates to:
  /// **'Aucun surnom personnalisé pour l\'instant.'**
  String get soundsNoCustomNicknames;

  /// No description provided for @soundsAddNicknameLabel.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un surnom'**
  String get soundsAddNicknameLabel;

  /// No description provided for @soundsRemoveNicknameTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get soundsRemoveNicknameTooltip;

  /// No description provided for @soundsVoiceSection.
  ///
  /// In fr, this message translates to:
  /// **'Voix'**
  String get soundsVoiceSection;

  /// No description provided for @soundsVoiceSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisis la voix française et la vitesse. Le bouton « Tester » prononce une phrase d\'exemple.'**
  String get soundsVoiceSubtitle;

  /// No description provided for @soundsRateLabel.
  ///
  /// In fr, this message translates to:
  /// **'Vitesse'**
  String get soundsRateLabel;

  /// No description provided for @soundsTestVoice.
  ///
  /// In fr, this message translates to:
  /// **'Tester la voix'**
  String get soundsTestVoice;

  /// No description provided for @soundsNoVoiceDetected.
  ///
  /// In fr, this message translates to:
  /// **'Aucune voix française détectée sur cet appareil.'**
  String get soundsNoVoiceDetected;

  /// No description provided for @soundsAmbienceSection.
  ///
  /// In fr, this message translates to:
  /// **'Ambiance'**
  String get soundsAmbienceSection;

  /// No description provided for @soundsAmbienceSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pack d\'arrière-plan appliqué pendant les séances. Sélection partagée avec l\'écran de jeu. Touche un mode pour écouter.'**
  String get soundsAmbienceSubtitle;

  /// No description provided for @soundsPackLabel.
  ///
  /// In fr, this message translates to:
  /// **'Pack'**
  String get soundsPackLabel;

  /// No description provided for @soundsModeLabel.
  ///
  /// In fr, this message translates to:
  /// **'Mode {name}'**
  String soundsModeLabel(String name);

  /// No description provided for @soundsNoTrack.
  ///
  /// In fr, this message translates to:
  /// **'pas de track pour ce mode'**
  String get soundsNoTrack;

  /// No description provided for @soundsRhythmPositionsSection.
  ///
  /// In fr, this message translates to:
  /// **'Positions (rhythm)'**
  String get soundsRhythmPositionsSection;

  /// No description provided for @soundsRhythmPositionsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tonalité du bip selon la profondeur. Du plus aigu au plus grave.'**
  String get soundsRhythmPositionsSubtitle;

  /// No description provided for @soundsLickPositionsSection.
  ///
  /// In fr, this message translates to:
  /// **'Positions (lick)'**
  String get soundsLickPositionsSection;

  /// No description provided for @soundsLickPositionsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Mêmes positions, volume réduit pour le ressenti « plus léger ».'**
  String get soundsLickPositionsSubtitle;

  /// No description provided for @soundsLickPositionLabel.
  ///
  /// In fr, this message translates to:
  /// **'{name} · lick'**
  String soundsLickPositionLabel(String name);

  /// No description provided for @soundsLickPositionSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Position {name} en mode lick'**
  String soundsLickPositionSubtitle(String name);

  /// No description provided for @soundsHoldSection.
  ///
  /// In fr, this message translates to:
  /// **'Hold (position + couche overlay)'**
  String get soundsHoldSection;

  /// No description provided for @soundsHoldSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Bip de la position joué simultanément avec la couche hold (plus épaisse).'**
  String get soundsHoldSubtitle;

  /// No description provided for @soundsHoldButton.
  ///
  /// In fr, this message translates to:
  /// **'Hold {position}'**
  String soundsHoldButton(String position);

  /// No description provided for @soundsHoldPositionSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'{name} + hold layer'**
  String soundsHoldPositionSubtitle(String name);

  /// No description provided for @soundsSpecificSounds.
  ///
  /// In fr, this message translates to:
  /// **'Sons spécifiques'**
  String get soundsSpecificSounds;

  /// No description provided for @soundsBiffleOneShot.
  ///
  /// In fr, this message translates to:
  /// **'Biffle (one-shot)'**
  String get soundsBiffleOneShot;

  /// No description provided for @soundsBiffleOneShotSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Son court et percutant. Au loop, suit le BPM.'**
  String get soundsBiffleOneShotSubtitle;

  /// No description provided for @soundsBreath.
  ///
  /// In fr, this message translates to:
  /// **'Breath'**
  String get soundsBreath;

  /// No description provided for @soundsBreathSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Tonalité grave et longue, effet « libérateur ».'**
  String get soundsBreathSubtitle;

  /// No description provided for @soundsLoopsDemoSection.
  ///
  /// In fr, this message translates to:
  /// **'Loops démos'**
  String get soundsLoopsDemoSection;

  /// No description provided for @soundsLoopsDemoSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajuste le BPM, lance le loop, écoute, stoppe.'**
  String get soundsLoopsDemoSubtitle;

  /// No description provided for @soundsBpmLabel.
  ///
  /// In fr, this message translates to:
  /// **'BPM'**
  String get soundsBpmLabel;

  /// No description provided for @soundsLoopActive.
  ///
  /// In fr, this message translates to:
  /// **'EN COURS'**
  String get soundsLoopActive;

  /// No description provided for @soundsLoopRhythmHeadMid.
  ///
  /// In fr, this message translates to:
  /// **'Rhythm head→mid'**
  String get soundsLoopRhythmHeadMid;

  /// No description provided for @soundsLoopRhythmThroatFull.
  ///
  /// In fr, this message translates to:
  /// **'Rhythm throat→full'**
  String get soundsLoopRhythmThroatFull;

  /// No description provided for @soundsLoopLickTipHead.
  ///
  /// In fr, this message translates to:
  /// **'Lick tip→head'**
  String get soundsLoopLickTipHead;

  /// No description provided for @soundsLoopBiffle.
  ///
  /// In fr, this message translates to:
  /// **'Biffle'**
  String get soundsLoopBiffle;

  /// No description provided for @soundsPosDescTip.
  ///
  /// In fr, this message translates to:
  /// **'Très aigu, léger'**
  String get soundsPosDescTip;

  /// No description provided for @soundsPosDescHead.
  ///
  /// In fr, this message translates to:
  /// **'Aigu'**
  String get soundsPosDescHead;

  /// No description provided for @soundsPosDescMid.
  ///
  /// In fr, this message translates to:
  /// **'Médium'**
  String get soundsPosDescMid;

  /// No description provided for @soundsPosDescThroat.
  ///
  /// In fr, this message translates to:
  /// **'Grave'**
  String get soundsPosDescThroat;

  /// No description provided for @soundsPosDescFull.
  ///
  /// In fr, this message translates to:
  /// **'Très grave, lourd'**
  String get soundsPosDescFull;

  /// No description provided for @soundsDebugSection.
  ///
  /// In fr, this message translates to:
  /// **'Debug'**
  String get soundsDebugSection;

  /// No description provided for @soundsDebugSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Options techniques pour le développement.'**
  String get soundsDebugSubtitle;

  /// No description provided for @soundsDebugShowTimer.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le timer'**
  String get soundsDebugShowTimer;

  /// No description provided for @soundsDebugShowTimerSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Remplace l\'animation des mouvements par le compteur mm:ss pendant la séance.'**
  String get soundsDebugShowTimerSubtitle;

  /// No description provided for @soundsDebugShowStaminaBar.
  ///
  /// In fr, this message translates to:
  /// **'Afficher la barre d\'endurance'**
  String get soundsDebugShowStaminaBar;

  /// No description provided for @soundsDebugShowStaminaBarSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Affiche le profil d\'endurance projeté pendant une séance Carrière.'**
  String get soundsDebugShowStaminaBarSubtitle;

  /// No description provided for @soundsDebugShowHumiliationBar.
  ///
  /// In fr, this message translates to:
  /// **'Afficher la jauge d\'humiliation'**
  String get soundsDebugShowHumiliationBar;

  /// No description provided for @soundsDebugShowHumiliationBarSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Affiche le score d\'humiliation cumulé pendant la séance.'**
  String get soundsDebugShowHumiliationBarSubtitle;

  /// No description provided for @soundsDebugShowObedienceBar.
  ///
  /// In fr, this message translates to:
  /// **'Afficher le score d\'obéissance'**
  String get soundsDebugShowObedienceBar;

  /// No description provided for @soundsDebugShowObedienceBarSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Affiche le score 0–100 d\'obéissance (baisse à chaque fail, remonte avec les punitions).'**
  String get soundsDebugShowObedienceBarSubtitle;

  /// No description provided for @soundsDebugShowSalivaBar.
  ///
  /// In fr, this message translates to:
  /// **'Afficher la jauge de salive'**
  String get soundsDebugShowSalivaBar;

  /// No description provided for @soundsDebugShowSalivaBarSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Affiche la jauge 0–max de salive accumulée pendant la séance. Monte avec lick/rhythm/hold profond, descend avec breath/hand. Auto-déglutition à 75 quand la déglutition est autorisée.'**
  String get soundsDebugShowSalivaBarSubtitle;

  /// No description provided for @soundsDebugShowSessionControls.
  ///
  /// In fr, this message translates to:
  /// **'Afficher pause / stop'**
  String get soundsDebugShowSessionControls;

  /// No description provided for @soundsDebugShowSessionControlsSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Réservé au debug : en prod la séance se déroule sans interaction (téléphone posé), seul le bouton FAIL reste utile.'**
  String get soundsDebugShowSessionControlsSubtitle;

  /// No description provided for @soundsDebugShowModeBadge.
  ///
  /// In fr, this message translates to:
  /// **'Afficher mode / BPM / position'**
  String get soundsDebugShowModeBadge;

  /// No description provided for @soundsDebugShowModeBadgeSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Réservé au debug : en prod l\'animation suffit à indiquer ce qui se passe.'**
  String get soundsDebugShowModeBadgeSubtitle;

  /// No description provided for @debugBarLabelHumiliation.
  ///
  /// In fr, this message translates to:
  /// **'HUMIL.'**
  String get debugBarLabelHumiliation;

  /// No description provided for @debugBarLabelObedience.
  ///
  /// In fr, this message translates to:
  /// **'OBÉI.'**
  String get debugBarLabelObedience;

  /// No description provided for @debugBarLabelSaliva.
  ///
  /// In fr, this message translates to:
  /// **'SALIVE'**
  String get debugBarLabelSaliva;

  /// No description provided for @soundsDebugCameraHoldCheck.
  ///
  /// In fr, this message translates to:
  /// **'Vérif caméra des holds'**
  String get soundsDebugCameraHoldCheck;

  /// No description provided for @soundsDebugCameraHoldCheckSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Pendant les holds, la caméra avant vérifie que la position est tenue. Le coach lance un rappel court si tu dérives. Nécessite d\'avoir calibré la caméra (icône caméra de l\'écran SCÉNARIO).'**
  String get soundsDebugCameraHoldCheckSubtitle;

  /// No description provided for @soundsDebugSkipSession.
  ///
  /// In fr, this message translates to:
  /// **'Bouton « terminer en succès »'**
  String get soundsDebugSkipSession;

  /// No description provided for @soundsDebugSkipSessionSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Affiche un bouton dans la séance qui termine immédiatement comme un succès complet (badges, milestones, niveau). Pratique pour itérer sur le contenu sans tout jouer.'**
  String get soundsDebugSkipSessionSubtitle;

  /// No description provided for @sessionDebugFinishButton.
  ///
  /// In fr, this message translates to:
  /// **'DEBUG : terminer en succès'**
  String get sessionDebugFinishButton;

  /// No description provided for @soundsDebugScenarioButton.
  ///
  /// In fr, this message translates to:
  /// **'Debug — scénario carrière'**
  String get soundsDebugScenarioButton;

  /// No description provided for @soundsDebugScenarioSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Visualise une session générée sans la jouer : niveau, humil, obéi, milestones, unlocks, et simulation Supplier / fail.'**
  String get soundsDebugScenarioSubtitle;

  /// No description provided for @careerDebugTitle.
  ///
  /// In fr, this message translates to:
  /// **'Debug — Scénario carrière'**
  String get careerDebugTitle;

  /// No description provided for @careerDebugSectionParams.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get careerDebugSectionParams;

  /// No description provided for @careerDebugSectionScenario.
  ///
  /// In fr, this message translates to:
  /// **'Scénario'**
  String get careerDebugSectionScenario;

  /// No description provided for @careerDebugLevel.
  ///
  /// In fr, this message translates to:
  /// **'Niveau'**
  String get careerDebugLevel;

  /// No description provided for @careerDebugHumiliation.
  ///
  /// In fr, this message translates to:
  /// **'Humiliation'**
  String get careerDebugHumiliation;

  /// No description provided for @careerDebugObedience.
  ///
  /// In fr, this message translates to:
  /// **'Obéissance'**
  String get careerDebugObedience;

  /// No description provided for @careerDebugIncludeHand.
  ///
  /// In fr, this message translates to:
  /// **'Inclure la stimulation à la main'**
  String get careerDebugIncludeHand;

  /// No description provided for @careerDebugQuickie.
  ///
  /// In fr, this message translates to:
  /// **'Mode bâclée'**
  String get careerDebugQuickie;

  /// No description provided for @careerDebugIntense.
  ///
  /// In fr, this message translates to:
  /// **'Mode intense (post-Supplier)'**
  String get careerDebugIntense;

  /// No description provided for @careerDebugDurationOverride.
  ///
  /// In fr, this message translates to:
  /// **'Durée override'**
  String get careerDebugDurationOverride;

  /// No description provided for @careerDebugMilestoneBody.
  ///
  /// In fr, this message translates to:
  /// **'Milestone body'**
  String get careerDebugMilestoneBody;

  /// No description provided for @careerDebugMilestoneFinal.
  ///
  /// In fr, this message translates to:
  /// **'Milestone final'**
  String get careerDebugMilestoneFinal;

  /// No description provided for @careerDebugUnlocks.
  ///
  /// In fr, this message translates to:
  /// **'Unlocks'**
  String get careerDebugUnlocks;

  /// No description provided for @careerDebugUnlocksLoadCurrent.
  ///
  /// In fr, this message translates to:
  /// **'Acquis'**
  String get careerDebugUnlocksLoadCurrent;

  /// No description provided for @careerDebugUnlocksClear.
  ///
  /// In fr, this message translates to:
  /// **'Aucun'**
  String get careerDebugUnlocksClear;

  /// No description provided for @careerDebugUnlocksAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous'**
  String get careerDebugUnlocksAll;

  /// No description provided for @careerDebugAuto.
  ///
  /// In fr, this message translates to:
  /// **'Auto'**
  String get careerDebugAuto;

  /// No description provided for @careerDebugNone.
  ///
  /// In fr, this message translates to:
  /// **'Aucune'**
  String get careerDebugNone;

  /// No description provided for @careerDebugRegenerate.
  ///
  /// In fr, this message translates to:
  /// **'Régénérer'**
  String get careerDebugRegenerate;

  /// No description provided for @careerDebugShowTtsTexts.
  ///
  /// In fr, this message translates to:
  /// **'Afficher les textes TTS'**
  String get careerDebugShowTtsTexts;

  /// No description provided for @careerDebugStatStamina.
  ///
  /// In fr, this message translates to:
  /// **'Stamina fin'**
  String get careerDebugStatStamina;

  /// No description provided for @careerDebugStatHumilCap.
  ///
  /// In fr, this message translates to:
  /// **'Humil cap fin'**
  String get careerDebugStatHumilCap;

  /// No description provided for @careerDebugTagMilestoneBody.
  ///
  /// In fr, this message translates to:
  /// **'MILESTONE'**
  String get careerDebugTagMilestoneBody;

  /// No description provided for @careerDebugTagMilestoneFinal.
  ///
  /// In fr, this message translates to:
  /// **'MILESTONE FINAL'**
  String get careerDebugTagMilestoneFinal;

  /// No description provided for @careerDebugTagBoost.
  ///
  /// In fr, this message translates to:
  /// **'BOOST'**
  String get careerDebugTagBoost;

  /// No description provided for @careerDebugTagFinal.
  ///
  /// In fr, this message translates to:
  /// **'FINAL'**
  String get careerDebugTagFinal;

  /// No description provided for @careerDebugTagPostFinal.
  ///
  /// In fr, this message translates to:
  /// **'POST-FINAL'**
  String get careerDebugTagPostFinal;

  /// No description provided for @careerDebugTextOnly.
  ///
  /// In fr, this message translates to:
  /// **'TEXT-ONLY'**
  String get careerDebugTextOnly;

  /// No description provided for @careerDebugHumilReq.
  ///
  /// In fr, this message translates to:
  /// **'req'**
  String get careerDebugHumilReq;

  /// No description provided for @careerDebugStepActionsTitle.
  ///
  /// In fr, this message translates to:
  /// **'Step'**
  String get careerDebugStepActionsTitle;

  /// No description provided for @careerDebugSimulateFail.
  ///
  /// In fr, this message translates to:
  /// **'Simuler un fail ici'**
  String get careerDebugSimulateFail;

  /// No description provided for @careerDebugSimulateSupplier.
  ///
  /// In fr, this message translates to:
  /// **'Simuler un Supplier ici'**
  String get careerDebugSimulateSupplier;

  /// No description provided for @careerDebugClearFork.
  ///
  /// In fr, this message translates to:
  /// **'Effacer la branche'**
  String get careerDebugClearFork;

  /// No description provided for @careerDebugClearAnnotation.
  ///
  /// In fr, this message translates to:
  /// **'Effacer l\'annotation'**
  String get careerDebugClearAnnotation;

  /// No description provided for @careerDebugForkBanner.
  ///
  /// In fr, this message translates to:
  /// **'BRANCHE SUPPLIER'**
  String get careerDebugForkBanner;

  /// No description provided for @careerDebugForkFrom.
  ///
  /// In fr, this message translates to:
  /// **'Depuis'**
  String get careerDebugForkFrom;

  /// No description provided for @careerDebugForkSteps.
  ///
  /// In fr, this message translates to:
  /// **'steps'**
  String get careerDebugForkSteps;

  /// No description provided for @careerDebugFailSnapshotTitle.
  ///
  /// In fr, this message translates to:
  /// **'FAIL simulé'**
  String get careerDebugFailSnapshotTitle;

  /// No description provided for @careerDebugFailSnapshotNext.
  ///
  /// In fr, this message translates to:
  /// **'Reprend au step'**
  String get careerDebugFailSnapshotNext;

  /// No description provided for @careerDebugFailSnapshotNoNext.
  ///
  /// In fr, this message translates to:
  /// **'Plus de step jouable après ce fail (fin de séance).'**
  String get careerDebugFailSnapshotNoNext;

  /// No description provided for @positionTip.
  ///
  /// In fr, this message translates to:
  /// **'Bout'**
  String get positionTip;

  /// No description provided for @positionHead.
  ///
  /// In fr, this message translates to:
  /// **'Gland'**
  String get positionHead;

  /// No description provided for @positionMid.
  ///
  /// In fr, this message translates to:
  /// **'Milieu'**
  String get positionMid;

  /// No description provided for @positionThroat.
  ///
  /// In fr, this message translates to:
  /// **'Gorge'**
  String get positionThroat;

  /// No description provided for @positionFull.
  ///
  /// In fr, this message translates to:
  /// **'Au fond'**
  String get positionFull;

  /// No description provided for @modeShortRhythm.
  ///
  /// In fr, this message translates to:
  /// **'RYTHME'**
  String get modeShortRhythm;

  /// No description provided for @modeShortHold.
  ///
  /// In fr, this message translates to:
  /// **'HOLD'**
  String get modeShortHold;

  /// No description provided for @modeShortLick.
  ///
  /// In fr, this message translates to:
  /// **'LICK'**
  String get modeShortLick;

  /// No description provided for @modeShortBiffle.
  ///
  /// In fr, this message translates to:
  /// **'BIFFLE'**
  String get modeShortBiffle;

  /// No description provided for @modeShortBreath.
  ///
  /// In fr, this message translates to:
  /// **'BREATH'**
  String get modeShortBreath;

  /// No description provided for @modeShortBeg.
  ///
  /// In fr, this message translates to:
  /// **'BEG'**
  String get modeShortBeg;

  /// No description provided for @modeShortFreestyle.
  ///
  /// In fr, this message translates to:
  /// **'FREESTYLE'**
  String get modeShortFreestyle;

  /// No description provided for @modeShortHand.
  ///
  /// In fr, this message translates to:
  /// **'HAND'**
  String get modeShortHand;

  /// No description provided for @badgeTierBronze.
  ///
  /// In fr, this message translates to:
  /// **'Bronze'**
  String get badgeTierBronze;

  /// No description provided for @badgeTierSilver.
  ///
  /// In fr, this message translates to:
  /// **'Argent'**
  String get badgeTierSilver;

  /// No description provided for @badgeTierGold.
  ///
  /// In fr, this message translates to:
  /// **'Or'**
  String get badgeTierGold;

  /// No description provided for @badgeTierPlatinium.
  ///
  /// In fr, this message translates to:
  /// **'Platine'**
  String get badgeTierPlatinium;

  /// No description provided for @badgeNameMarathonien.
  ///
  /// In fr, this message translates to:
  /// **'Marathonienne'**
  String get badgeNameMarathonien;

  /// No description provided for @badgeNameThroatQueen.
  ///
  /// In fr, this message translates to:
  /// **'Throat Queen'**
  String get badgeNameThroatQueen;

  /// No description provided for @badgeNameIronLungs.
  ///
  /// In fr, this message translates to:
  /// **'Iron Lungs'**
  String get badgeNameIronLungs;

  /// No description provided for @badgeNameToutTerrain.
  ///
  /// In fr, this message translates to:
  /// **'Tout-terrain'**
  String get badgeNameToutTerrain;

  /// No description provided for @badgeNameSansBroncher.
  ///
  /// In fr, this message translates to:
  /// **'Sans broncher'**
  String get badgeNameSansBroncher;

  /// No description provided for @badgeNameReguliere.
  ///
  /// In fr, this message translates to:
  /// **'Régulière'**
  String get badgeNameReguliere;

  /// No description provided for @badgeNameJamaisRassasiee.
  ///
  /// In fr, this message translates to:
  /// **'Jamais rassasiée'**
  String get badgeNameJamaisRassasiee;

  /// No description provided for @badgeNameVideCouilles.
  ///
  /// In fr, this message translates to:
  /// **'Vide-Couilles'**
  String get badgeNameVideCouilles;

  /// No description provided for @badgeNameBouchePleine.
  ///
  /// In fr, this message translates to:
  /// **'Bouche pleine'**
  String get badgeNameBouchePleine;

  /// No description provided for @badgeNameRepeinte.
  ///
  /// In fr, this message translates to:
  /// **'Repeinte'**
  String get badgeNameRepeinte;

  /// No description provided for @badgeNameGobeuse.
  ///
  /// In fr, this message translates to:
  /// **'Gobeuse'**
  String get badgeNameGobeuse;

  /// No description provided for @badgeNameNettoyeuse.
  ///
  /// In fr, this message translates to:
  /// **'Nettoyeuse'**
  String get badgeNameNettoyeuse;

  /// No description provided for @badgeNameSuppliante.
  ///
  /// In fr, this message translates to:
  /// **'Suppliante'**
  String get badgeNameSuppliante;

  /// No description provided for @badgeUnitMarathonien.
  ///
  /// In fr, this message translates to:
  /// **'minutes cumulées'**
  String get badgeUnitMarathonien;

  /// No description provided for @badgeUnitThroatQueen.
  ///
  /// In fr, this message translates to:
  /// **'throatfucks cumulés'**
  String get badgeUnitThroatQueen;

  /// No description provided for @badgeUnitIronLungs.
  ///
  /// In fr, this message translates to:
  /// **'secondes du plus long hold full'**
  String get badgeUnitIronLungs;

  /// No description provided for @badgeUnitToutTerrain.
  ///
  /// In fr, this message translates to:
  /// **'modes différents utilisés'**
  String get badgeUnitToutTerrain;

  /// No description provided for @badgeUnitSansBroncher.
  ///
  /// In fr, this message translates to:
  /// **'séances complètes consécutives sans fail'**
  String get badgeUnitSansBroncher;

  /// No description provided for @badgeUnitReguliere.
  ///
  /// In fr, this message translates to:
  /// **'jours consécutifs avec séance'**
  String get badgeUnitReguliere;

  /// No description provided for @badgeUnitJamaisRassasiee.
  ///
  /// In fr, this message translates to:
  /// **'fois où tu as redemandé \"encore\"'**
  String get badgeUnitJamaisRassasiee;

  /// No description provided for @badgeUnitVideCouilles.
  ///
  /// In fr, this message translates to:
  /// **'sessions bâclées terminées'**
  String get badgeUnitVideCouilles;

  /// No description provided for @badgeUnitBouchePleine.
  ///
  /// In fr, this message translates to:
  /// **'finals dans la bouche'**
  String get badgeUnitBouchePleine;

  /// No description provided for @badgeUnitRepeinte.
  ///
  /// In fr, this message translates to:
  /// **'finals sur le visage'**
  String get badgeUnitRepeinte;

  /// No description provided for @badgeUnitGobeuse.
  ///
  /// In fr, this message translates to:
  /// **'finals sur la langue'**
  String get badgeUnitGobeuse;

  /// No description provided for @badgeUnitNettoyeuse.
  ///
  /// In fr, this message translates to:
  /// **'post-finals à lécher'**
  String get badgeUnitNettoyeuse;

  /// No description provided for @badgeUnitSuppliante.
  ///
  /// In fr, this message translates to:
  /// **'suppliques post-orgasme'**
  String get badgeUnitSuppliante;

  /// No description provided for @careerLevelTitleDebutante.
  ///
  /// In fr, this message translates to:
  /// **'Débutante'**
  String get careerLevelTitleDebutante;

  /// No description provided for @careerLevelTitleApprentieSuceuse.
  ///
  /// In fr, this message translates to:
  /// **'Apprentie Suceuse'**
  String get careerLevelTitleApprentieSuceuse;

  /// No description provided for @careerLevelTitlePetiteSalopeConfirmee.
  ///
  /// In fr, this message translates to:
  /// **'Petite Salope Confirmée'**
  String get careerLevelTitlePetiteSalopeConfirmee;

  /// No description provided for @careerLevelTitleBoucheAPipe.
  ///
  /// In fr, this message translates to:
  /// **'Bouche à Pipe'**
  String get careerLevelTitleBoucheAPipe;

  /// No description provided for @careerLevelTitleAvaleuse.
  ///
  /// In fr, this message translates to:
  /// **'Avaleuse'**
  String get careerLevelTitleAvaleuse;

  /// No description provided for @careerLevelTitleThroatQueen.
  ///
  /// In fr, this message translates to:
  /// **'Throat Queen'**
  String get careerLevelTitleThroatQueen;

  /// No description provided for @careerLevelTitleReineDuSloppy.
  ///
  /// In fr, this message translates to:
  /// **'Reine du Sloppy'**
  String get careerLevelTitleReineDuSloppy;

  /// No description provided for @careerLevelTitleTrouABiteOfficiel.
  ///
  /// In fr, this message translates to:
  /// **'Trou à Bite Officiel'**
  String get careerLevelTitleTrouABiteOfficiel;

  /// No description provided for @careerLevelTitleVideCouillesPro.
  ///
  /// In fr, this message translates to:
  /// **'Vide-Couilles Pro'**
  String get careerLevelTitleVideCouillesPro;

  /// No description provided for @careerLevelTitleReineDesPutes.
  ///
  /// In fr, this message translates to:
  /// **'Reine des Putes'**
  String get careerLevelTitleReineDesPutes;

  /// No description provided for @specBranchEnduranceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Endurance'**
  String get specBranchEnduranceLabel;

  /// No description provided for @specBranchEnduranceDesc.
  ///
  /// In fr, this message translates to:
  /// **'Tenir longtemps. Plus de holds, durées rallongées.'**
  String get specBranchEnduranceDesc;

  /// No description provided for @specBranchProfondeurLabel.
  ///
  /// In fr, this message translates to:
  /// **'Profondeur'**
  String get specBranchProfondeurLabel;

  /// No description provided for @specBranchProfondeurDesc.
  ///
  /// In fr, this message translates to:
  /// **'Aller chercher loin. Biais throat / full.'**
  String get specBranchProfondeurDesc;

  /// No description provided for @specBranchRythmeBiffleLabel.
  ///
  /// In fr, this message translates to:
  /// **'Rythme & Biffle'**
  String get specBranchRythmeBiffleLabel;

  /// No description provided for @specBranchRythmeBiffleDesc.
  ///
  /// In fr, this message translates to:
  /// **'BPM élevés, coups de queue plus fréquents.'**
  String get specBranchRythmeBiffleDesc;

  /// No description provided for @specBranchObeissanceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Obéissance'**
  String get specBranchObeissanceLabel;

  /// No description provided for @specBranchObeissanceDesc.
  ///
  /// In fr, this message translates to:
  /// **'Beg insistants, supplique soutenue.'**
  String get specBranchObeissanceDesc;

  /// No description provided for @specBranchSloppyLabel.
  ///
  /// In fr, this message translates to:
  /// **'Sloppy'**
  String get specBranchSloppyLabel;

  /// No description provided for @specBranchSloppyDesc.
  ///
  /// In fr, this message translates to:
  /// **'Lick humide, biffle bas, plus de bave.'**
  String get specBranchSloppyDesc;

  /// No description provided for @specBranchResilienceLabel.
  ///
  /// In fr, this message translates to:
  /// **'Résilience'**
  String get specBranchResilienceLabel;

  /// No description provided for @specBranchResilienceDesc.
  ///
  /// In fr, this message translates to:
  /// **'Encaisser les fails. Punitions plus dures.'**
  String get specBranchResilienceDesc;

  /// No description provided for @coachPickerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un coach'**
  String get coachPickerTitle;

  /// No description provided for @coachPickerSection.
  ///
  /// In fr, this message translates to:
  /// **'COACH'**
  String get coachPickerSection;

  /// No description provided for @coachPickerTierLabel.
  ///
  /// In fr, this message translates to:
  /// **'PALIER {tier}'**
  String coachPickerTierLabel(int tier);

  /// No description provided for @coachBadgePrincipal.
  ///
  /// In fr, this message translates to:
  /// **'PRINCIPAL'**
  String get coachBadgePrincipal;

  /// No description provided for @coachBadgePalierAcquis.
  ///
  /// In fr, this message translates to:
  /// **'PALIER ACQUIS'**
  String get coachBadgePalierAcquis;

  /// No description provided for @coachBadgeFreeTraining.
  ///
  /// In fr, this message translates to:
  /// **'ENTRAÎNEMENT LIBRE'**
  String get coachBadgeFreeTraining;

  /// No description provided for @coachBadgeLocked.
  ///
  /// In fr, this message translates to:
  /// **'VERROUILLÉ'**
  String get coachBadgeLocked;

  /// No description provided for @coachRequiresHands.
  ///
  /// In fr, this message translates to:
  /// **'Mains obligatoires'**
  String get coachRequiresHands;

  /// No description provided for @coachSummaryPrincipal.
  ///
  /// In fr, this message translates to:
  /// **'{title} · Principal palier {tier}'**
  String coachSummaryPrincipal(String title, int tier);

  /// No description provided for @coachSummaryFree.
  ///
  /// In fr, this message translates to:
  /// **'{title} · entraînement libre'**
  String coachSummaryFree(String title);

  /// No description provided for @coachFreeTrainingDialogTitle.
  ///
  /// In fr, this message translates to:
  /// **'Entraînement libre'**
  String get coachFreeTrainingDialogTitle;

  /// No description provided for @coachFreeTrainingDialogBody.
  ///
  /// In fr, this message translates to:
  /// **'Tu vas t\'entraîner avec {coachName}. Tu progresseras sur tes compétences, mais ta jauge de palier n\'avancera pas.'**
  String coachFreeTrainingDialogBody(String coachName);

  /// No description provided for @coachFreeTrainingDialogHint.
  ///
  /// In fr, this message translates to:
  /// **'Pour avancer dans ton palier, choisis {principalName}.'**
  String coachFreeTrainingDialogHint(String principalName);

  /// No description provided for @coachFreeTrainingDialogChoosePrincipal.
  ///
  /// In fr, this message translates to:
  /// **'Choisir {principalName}'**
  String coachFreeTrainingDialogChoosePrincipal(String principalName);

  /// No description provided for @coachFreeTrainingDialogContinueAnyway.
  ///
  /// In fr, this message translates to:
  /// **'Continuer quand même'**
  String get coachFreeTrainingDialogContinueAnyway;

  /// No description provided for @coachFreeTrainingBannerTitle.
  ///
  /// In fr, this message translates to:
  /// **'Session libre avec {coachName}'**
  String coachFreeTrainingBannerTitle(String coachName);

  /// No description provided for @coachFreeTrainingBannerBodyWithPrincipal.
  ///
  /// In fr, this message translates to:
  /// **'Tu progresses sur tes compétences. Ton palier n\'avance pas — pour ça, choisis {principalName}.'**
  String coachFreeTrainingBannerBodyWithPrincipal(String principalName);

  /// No description provided for @coachFreeTrainingBannerBodyNoPrincipal.
  ///
  /// In fr, this message translates to:
  /// **'Tu progresses sur tes compétences. Ton palier n\'avance pas.'**
  String get coachFreeTrainingBannerBodyNoPrincipal;

  /// No description provided for @coachFreeTrainingBannerSwitchAction.
  ///
  /// In fr, this message translates to:
  /// **'CHANGER'**
  String get coachFreeTrainingBannerSwitchAction;

  /// No description provided for @coachErrorLockedTier.
  ///
  /// In fr, this message translates to:
  /// **'Ce coach est encore verrouillé — atteins le palier {tier} pour le débloquer.'**
  String coachErrorLockedTier(int tier);

  /// No description provided for @coachErrorRequiresHands.
  ///
  /// In fr, this message translates to:
  /// **'{coachName} a besoin que tu actives la main dans les options.'**
  String coachErrorRequiresHands(String coachName);

  /// No description provided for @coachErrorMinLevel.
  ///
  /// In fr, this message translates to:
  /// **'{coachName} demande le niveau {minLevel} minimum.'**
  String coachErrorMinLevel(String coachName, int minLevel);

  /// No description provided for @coachErrorMissingSpecialization.
  ///
  /// In fr, this message translates to:
  /// **'Ce coach demande au moins 1 point dans une spécialisation que tu n\'as pas investie.'**
  String get coachErrorMissingSpecialization;

  /// No description provided for @coachErrorInsufficientBranchPoints.
  ///
  /// In fr, this message translates to:
  /// **'{coachName} demande : {requirements}. Investis tes points de spécialisation.'**
  String coachErrorInsufficientBranchPoints(
      String coachName, String requirements);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
