import 'dart:math';

import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/format_helpers.dart';
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../screens/session_screen.dart';
import '../../services/ambience_engine.dart';
import '../../services/beep_engine.dart';
import '../../services/camera_motion_service.dart';
import '../../services/coach_phrases_loader.dart';
import '../../services/punishment_loader.dart';
import '../../services/random_comments_loader.dart';
import '../../services/stats_service.dart';
import '../../services/tts_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/enum_labels.dart';
import '../../main.dart' show coachService, milestoneService;
import '../models/career_level.dart';
import '../models/coach.dart';
import '../models/level_milestone.dart';
import '../models/phrase_bank.dart';
import '../models/specialization.dart';
import '../models/unlock_key.dart';
import '../services/career_progress_service.dart';
import '../services/career_session_generator.dart';
import '../services/phrase_bank_loader.dart';
import '../services/specialization_service.dart';
import '../widgets/free_spec_points_banner.dart';
import '../widgets/free_training_banner.dart';
import 'coach_picker_screen.dart';
import 'specialization_screen.dart';

class CareerScreen extends StatefulWidget {
  final TtsService tts;
  final BeepEngine beep;
  final AmbienceEngine ambience;
  final UserProfileService userProfile;

  const CareerScreen({
    super.key,
    required this.tts,
    required this.beep,
    required this.ambience,
    required this.userProfile,
  });

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  // Pas `final` : on réassigne ce Future à chaque retour de séance pour
  // refléter le nouveau `maxLevel` débloqué. `late final` jetait un
  // LateInitializationError sur la 2ᵉ assignation, ce qui faisait taire
  // le reload et le slider restait coincé sur l'ancien plafond.
  late Future<_CareerBundle> _bundleFuture;
  final CareerProgressService _progress = CareerProgressService();
  final StatsService _stats = StatsService();
  final SpecializationService _specService = SpecializationService();

  int? _selectedLevel;
  bool? _includeHandOverride;
  bool _quickie = false;

  /// Niveau global minimum à partir duquel l'utilisatrice peut désactiver
  /// le mode hand. En dessous, le toggle est forcé à ON pour garder le
  /// finish abordable (le hand head 50 BPM est la seule baseline req 0).
  static const int _includeHandUnlockLevel = 4;

  /// Niveau global minimum à partir duquel le mode « Session bâclée » est
  /// disponible. En dessous, le toggle est désactivé — bâcler avant de
  /// connaître les bases ne fait pas sens pédagogiquement, et l'intensity
  /// floor 0.65 du quickie pousse la débutante au-delà de ce qu'elle est
  /// prête à encaisser.
  static const int _quickieUnlockLevel = 5;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_CareerBundle> _loadBundle() async {
    final results = await Future.wait([
      PhraseBankLoader().load(),
      PunishmentLoader().load(),
      RandomCommentsLoader().load(),
      _progress.getMaxLevel(),
      _progress.getLastChosenLevel(),
      _progress.getCompletedSessions(),
      _progress.getIncludeHand(),
      _specService.load(),
    ]);
    final maxLevel = results[3] as int;
    // Synchronise le palier de coach avec le niveau global avant que
    // l'écran ne lise `currentTier` / `selectedCoach` pour son rendu.
    await coachService.syncFromCareerLevel(maxLevel);
    return _CareerBundle(
      bank: results[0] as PhraseBank,
      punishments: results[1] as PunishmentBundle,
      comments: results[2] as RandomCommentsBundle,
      maxLevel: maxLevel,
      lastChosenLevel: results[4] as int,
      completedSessions: results[5] as int,
      includeHand: results[6] as bool,
      specialization: results[7] as SpecializationAllocation,
    );
  }

  Coach _resolveCoach(_CareerBundle bundle) {
    final selected = coachService.selectedCoach;
    if (selected != null) return selected;
    final principal = coachService.currentTierPrincipal;
    if (principal != null) return principal;
    return coachService.coaches.first;
  }

  Future<void> _openCoachPicker(_CareerBundle bundle) async {
    final picked = await Navigator.of(context).push<Coach?>(
      MaterialPageRoute(
        builder: (_) => CoachPickerScreen(
          service: coachService,
          playerMaxLevel: bundle.maxLevel,
          handsEnabled: _includeHandOverride ?? bundle.includeHand,
          specialization: bundle.specialization,
        ),
      ),
    );
    if (picked != null && mounted) setState(() {});
  }

  Future<void> _start(_CareerBundle bundle) async {
    final level = _selectedLevel ?? bundle.lastChosenLevel;
    final clamped = level.clamp(1, bundle.maxLevel);
    await _progress.setLastChosenLevel(clamped);

    // Override forcé à true si on est sous le seuil de déblocage : même si
    // une persistance antérieure (avant le verrou) avait stocké false, on
    // ne laisse pas démarrer une session sans hand à bas niveau. La règle
    // `requiresHands` côté milestone (cf. plus bas) peut aussi forcer le
    // toggle quand un milestone scripté en a besoin (intro_basics,
    // intro_biffle…).
    final baseIncludeHand = bundle.maxLevel < _includeHandUnlockLevel
        ? true
        : (_includeHandOverride ?? bundle.includeHand);

    final activeCoach = _resolveCoach(bundle);
    final coachAdvances = coachService.advancesTier(activeCoach);
    // Compose la bank du coach par-dessus la globale : tirage prioritaire
    // sur les phrases du coach, fallback transparent sur la PhraseBank
    // commune pour les cases vides.
    final coachBank = activeCoach.toPhraseBank(fallback: bundle.bank, specialization: bundle.specialization);
    _installCoachNameResolver(activeCoach);

    // Force quickie=false sous le seuil de déblocage — sécurité au cas où
    // une persistance antérieure (avant le verrou) ou un toggle en RAM ne
    // soit pas réinitialisé par le widget.
    final quickie =
        bundle.maxLevel < _quickieUnlockLevel ? false : _quickie;
    final humiliationScore = await _stats.getHumiliationLevel();
    final obedienceScore = await _stats.getObedienceLevel();
    // Insère la milestone d'apprentissage en attente pour ce niveau (si
    // toutes les conditions sont réunies : niveau atteint, requires acquittés,
    // pas déjà acquittée). Pas en mode bâclée (pédagogie incompatible).
    //
    // Deux canaux distincts : la milestone **body** (insérée dans le corps
    // de séance) et la milestone **final** (qui remplace la phase finish
    // = boosts + step finisher). Les deux peuvent coexister sur une même
    // séance — l'utilisatrice apprend une compétence en milieu de séance,
    // puis une autre en apothéose.
    final milestone = quickie
        ? null
        : milestoneService.pendingForLevel(
            clamped,
            allocation: bundle.specialization,
          );
    final finalMilestone = quickie
        ? null
        : milestoneService.pendingFinalForLevel(
            clamped,
            allocation: bundle.specialization,
          );
    // Force includeHand=true si le milestone pending l'exige (séquence
    // scriptée comportant du hand/biffle). Sinon respecte la préférence
    // utilisatrice. Persistance volontairement avec la valeur effective
    // (post-force) pour que le toggle reste cohérent avec ce qui a joué.
    final includeHand = ((milestone?.requiresHands ?? false) ||
            (finalMilestone?.requiresHands ?? false))
        ? true
        : baseIncludeHand;
    await _progress.setIncludeHand(includeHand);
    // Le générateur ne reçoit QUE les unlocks déjà acquis. On ne propage
    // pas les unlocks de la milestone insérée : sinon le générateur peut
    // produire un step utilisant le mode débloqué AVANT la milestone
    // scriptée (ex: un `beg` avant l'intro_beg_libre), ce qui casse la
    // dramaturgie pédagogique. La milestone elle-même pose ses propres
    // steps en dur — elle n'a pas besoin de l'unlock côté générateur.
    // Pour les milestones de **placement final** (intro_final_*), pas
    // besoin de propager non plus : la séquence remplace `_pickFinal`
    // entièrement (le générateur ne consulte pas `finalXxx` quand
    // `finalMilestone != null`).
    final unlockedKeys = milestoneService.acquiredUnlockKeys();
    final levelCfg = CareerLevel.forLevel(clamped);
    // Gating bouton encore : niveau ≥ 5, ET (milestone unlock + minimum
    // d'engagement) OU obédiance lifetime ≥ 80 (voie alternative). Évalué
    // au start — si l'utilisatrice acquiert l'unlock pendant la session,
    // elle pourra utiliser l'encore à la session suivante. Acceptable, on
    // ne veut pas non plus brancher l'encore dynamiquement.
    final canEncore = _canEncore(
      level: clamped,
      humiliationScore: humiliationScore,
      obedienceScore: obedienceScore,
    );
    final result = CareerSessionGenerator().generate(
      level: clamped,
      bank: coachBank,
      includeHand: includeHand,
      quickie: quickie,
      specialization: bundle.specialization,
      humiliationScore: humiliationScore,
      obedience: obedienceScore,
      milestone: milestone,
      finalMilestone: finalMilestone,
      unlockedKeys: unlockedKeys,
      milestoneTextResolver: milestoneService.getStepText,
      coachModeWeights: activeCoach.modeWeights,
    );

    final introText = coachBank.pickIntro(Random());

    // Unlocks provisoires de la session : la milestone insérée débloque
    // visuellement ses compétences pour l'UI (bouton Supplier surtout)
    // dès le démarrage, sans attendre le markCompleted final. Le
    // générateur, lui, n'a pas reçu ces unlocks (cf. plus haut), donc
    // pas de risque d'incohérence. Union des unlocks de la body et de
    // la final milestone (les deux peuvent coexister).
    milestoneService.setSessionUnlocks(<UnlockKey>{
      ...?milestone?.unlocks,
      ...?finalMilestone?.unlocks,
    });

    final camService = CameraMotionService();
    final verifier = await camService.buildVerifierIfEnabled(widget.tts);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          session: result.session,
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
          punishmentBundle: bundle.punishments,
          randomComments: activeCoach.composeRandomComments(bundle.comments),
          isCareer: true,
          isQuickie: quickie,
          careerLevel: clamped,
          staminaProfile: result.staminaProfile,
          introText: introText,
          phraseBank: coachBank,
          excitationMax: levelCfg.excitationTarget,
          excitationBarMax: levelCfg.minFinal,
          holdVerifier: verifier,
          canSave: true,
          coachAdvancesTier: coachAdvances,
          specialization: bundle.specialization,
          onRequestUpgrade: (ctrl) => _handleUpgrade(ctrl, bundle, clamped),
          onRequestEncore: !canEncore
              ? null
              : (ctrl) => _handleEncore(
                    context: context,
                    bundle: bundle,
                    previousController: ctrl,
                    level: clamped,
                    previousMax: ctrl.excitation.maxValue,
                    includeHand: includeHand,
                    quickie: quickie,
                  ),
          onMilestoneRetry: (ctrl) => _handleMilestoneRetry(
            ctrl,
            bundle,
            clamped,
          ),
        ),
      ),
    );

    if (verifier != null) camService.stopSessionDetection();
    widget.tts.setNameResolver(null);
    // Reset des unlocks provisoires : la session est terminée. Si la
    // milestone a été acquittée, son unlock est déjà persisté dans
    // `_completed` via `markCompleted` ; sinon, on retire l'illusion.
    milestoneService.setSessionUnlocks(const {});

    // De retour de la séance, recharger pour refléter un éventuel
    // nouveau max débloqué.
    setState(() {
      _bundleFuture = _loadBundle();
      _selectedLevel = null;
    });
  }

  /// Pose un override sur le `TtsService` pour que `{name}` et `{coach}`
  /// soient résolus avec les pools du coach. On pose le resolver dès que
  /// le coach a au moins un pool renseigné (nicknames pour `{name}`, ou
  /// coachNicknames pour `{coach}`) — sinon on laisse le resolver user
  /// par défaut (qui gère lui aussi `{name}` + strip 1/2 et `{coach}`
  /// purement effacé).
  void _installCoachNameResolver(Coach coach) {
    if (coach.phrases.nicknames.isEmpty &&
        coach.phrases.coachNicknames.isEmpty) {
      widget.tts.setNameResolver(null);
      return;
    }
    final resolver = coach.buildTextResolver(
      userPrenom: widget.userProfile.prenom,
      userNicknames: widget.userProfile.activePool,
      userFallback: widget.userProfile.activePool,
    );
    widget.tts.setNameResolver(resolver);
  }

  /// Action « Supplier » : régénère la suite de la séance à un palier
  /// supérieur, démarrée par un beg insistant.
  ///
  /// On saute deux niveaux pour que l'effet soit clairement perceptible
  /// (un seul niveau passait souvent inaperçu côté contenu généré). Le
  /// flag `intense` du générateur supprime aussi le soft intro et applique
  /// un plancher de difficulté pour que la suite tape immédiatement.
  ///
  /// Le Supplier ne bump **plus** le max persistant. La règle de level-up
  /// reste : terminer une session standard, sans fail, au niveau max.
  /// Supplier est juste un boost de difficulté en cours de séance.
  /// Conditions d'apparition du bouton « J'en veux encore » sur l'écran
  /// de fin de session :
  /// - **niveau ≥ 5** (cap absolu — pas d'encore aux premiers paliers)
  /// - ET (a) milestone `intro_encore` acquittée ET (humil ≥ 30 OU obed ≥ 50)
  ///   pour la voie pédagogique normale,
  /// - OU (b) `obed ≥ 80` pour la voie alternative — la salope a démontré
  ///   sa docilité, on lui ouvre l'encore sans milestone.
  ///
  /// Évalué au start de session (et au start de la session-encore enchaînée
  /// pour ré-évaluer après d'éventuels fails). Pas branché dynamiquement à
  /// l'écran finished — si l'utilisatrice a juste passé le seuil pendant
  /// la séance, elle l'aura à la suivante. C'est cohérent avec le reste du
  /// gating (humil et obed sont des thermomètres lents).
  bool _canEncore({
    required int level,
    required double humiliationScore,
    required double obedienceScore,
  }) {
    if (level < 5) return false;
    if (obedienceScore >= 80.0) return true;
    final hasMilestone =
        milestoneService.acquiredUnlockKeys().contains(UnlockKey.encore);
    if (!hasMilestone) return false;
    return humiliationScore >= 30.0 || obedienceScore >= 50.0;
  }

  Future<void> _handleUpgrade(
    SessionController ctrl,
    _CareerBundle bundle,
    int currentLevel,
  ) async {
    const begDuration = 12;
    const levelJump = 2;
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    if (remaining < begDuration + 30) return;

    final newLevel = currentLevel + levelJump;
    final activeCoach = _resolveCoach(bundle);
    final coachBank = activeCoach.toPhraseBank(fallback: bundle.bank, specialization: bundle.specialization);

    final genDuration = remaining - begDuration;
    final humiliationScore = await _stats.getHumiliationLevel();
    // Pour Supplier on utilise l'obédiance courante du contrôleur (live),
    // pas la valeur persistée — la séance est en cours, le score a déjà
    // été pénalisé par d'éventuels fails de cette session.
    final obedienceScore = ctrl.obedience.score;
    final newGen = CareerSessionGenerator().generate(
      durationSeconds: genDuration,
      level: newLevel,
      bank: coachBank,
      includeHand: bundle.includeHand,
      specialization: bundle.specialization,
      intense: true,
      humiliationScore: humiliationScore,
      obedience: obedienceScore,
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      coachModeWeights: activeCoach.modeWeights,
    );

    final rng = Random();
    final insistText = coachBank.pickFor(
      SessionMode.beg,
      'insistent',
      rng,
    );
    final beg = SessionStep(
      time: 0,
      text: insistText,
      mode: SessionMode.beg,
      from: Position.full,
      duration: begDuration,
    );

    await ctrl.requestUpgrade(
      insistentBeg: beg,
      upcomingSteps: newGen.session.steps,
      upcomingDurationSeconds: newGen.session.durationSeconds,
    );
  }

  /// Retry milestone : appelé par `SessionController.triggerFail` quand
  /// l'utilisatrice rate dans la fenêtre milestone et qu'un retry est
  /// encore disponible (cumul persistant `count < milestone.maxRetry`).
  /// Régénère une suite qui réinsère la milestone tout de suite, avec
  /// les unlocks acquis seulement (plan pessimiste, pas optimiste).
  /// Retourne `true` si le retry a été pris en charge.
  Future<bool> _handleMilestoneRetry(
    SessionController ctrl,
    _CareerBundle bundle,
    int level,
  ) async {
    final milestoneId = ctrl.session.milestoneId;
    if (milestoneId == null) return false;
    final milestone = milestoneService.findById(milestoneId);
    if (milestone == null) return false;
    final used = milestoneService.getRetryCount(milestoneId);
    if (used >= milestone.maxRetry) return false;
    await milestoneService.incrementRetryCount(milestoneId);

    const begDuration = 6;
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    final retryDuration = remaining + milestone.durationSeconds;

    final activeCoach = _resolveCoach(bundle);
    final coachBank = activeCoach.toPhraseBank(fallback: bundle.bank, specialization: bundle.specialization);
    final humiliationScore = await _stats.getHumiliationLevel();
    // Retry milestone : utilise l'obédiance live (un fail vient de la faire
    // descendre, le générateur doit en tenir compte pour adapter le ton).
    final obedienceScore = ctrl.obedience.score;

    final newGen = CareerSessionGenerator().generate(
      durationSeconds: retryDuration,
      level: level,
      bank: coachBank,
      includeHand: bundle.includeHand,
      specialization: bundle.specialization,
      humiliationScore: humiliationScore,
      obedience: obedienceScore,
      milestone: milestone,
      // Plan pessimiste : pour le retry, on ne suppose plus que la
      // milestone est acquittée — son unlock n'est pas dans le set, le
      // reste de la session ne réutilise donc pas la compétence ratée.
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      milestoneTextResolver: milestoneService.getStepText,
      coachModeWeights: activeCoach.modeWeights,
    );

    final rng = Random();
    final retryText = coachBank.pickFor(
      SessionMode.beg,
      'soft',
      rng,
    );
    final beg = SessionStep(
      time: 0,
      text: retryText,
      mode: SessionMode.beg,
      duration: begDuration,
    );

    await ctrl.requestUpgrade(
      insistentBeg: beg,
      upcomingSteps: newGen.session.steps,
      upcomingDurationSeconds: newGen.session.durationSeconds,
    );
    return true;
  }

  /// Action « J'en veux encore » depuis l'écran finished. Régénère une
  /// session au même niveau et même durée mais avec une cible d'excitation
  /// montée de +20. Comptabilise l'encore (badge JamaisRassasiee).
  /// Push remplace l'écran courant — le SessionController précédent est
  /// disposed.
  Future<void> _handleEncore({
    required BuildContext context,
    required _CareerBundle bundle,
    required SessionController previousController,
    required int level,
    required double previousMax,
    required bool includeHand,
    required bool quickie,
  }) async {
    // Détache l'ancien controller des services audio partagés AVANT que
    // pushReplacement ne déclenche son dispose() — sinon un `tts.stop()` /
    // `beep.stop()` fire-and-forget couperait la première phrase et le
    // premier loop de la nouvelle session.
    await previousController.detachAudio();

    await _stats.recordEncoreAsked();

    final activeCoach = _resolveCoach(bundle);
    final coachAdvances = coachService.advancesTier(activeCoach);
    final coachBank = activeCoach.toPhraseBank(fallback: bundle.bank, specialization: bundle.specialization);
    _installCoachNameResolver(activeCoach);

    final newTarget = previousMax + 20.0;
    final encoreOpening = coachBank.pickEncore(Random()) ??
        CoachPhrasesService.instance.current.encoreFallback;

    // recordEncoreAsked() vient de bumper le score persistant (+1).
    // On relit la valeur post-bump pour que la nouvelle session démarre
    // avec l'acceptance accrue.
    final humiliationScore = await _stats.getHumiliationLevel();
    // Encore = nouvelle session : on relit l'obédiance persistée. La
    // session précédente a été persistée par `_finish` du contrôleur
    // précédent, donc cette lecture reflète bien la fin de la session
    // d'avant.
    final obedienceScore = await _stats.getObedienceLevel();
    // On ré-évalue le gating encore pour la chaîne suivante : un fail
    // pendant cet encore peut faire descendre l'obédiance assez bas pour
    // refermer le bouton.
    final canChainEncore = _canEncore(
      level: level,
      humiliationScore: humiliationScore,
      obedienceScore: obedienceScore,
    );
    final result = CareerSessionGenerator().generate(
      level: level,
      bank: coachBank,
      includeHand: includeHand,
      excitationTarget: newTarget,
      openingPhrase: encoreOpening,
      quickie: quickie,
      specialization: bundle.specialization,
      humiliationScore: humiliationScore,
      obedience: obedienceScore,
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      coachModeWeights: activeCoach.modeWeights,
    );

    final camService = CameraMotionService();
    final verifier = await camService.buildVerifierIfEnabled(widget.tts);

    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          session: result.session,
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
          punishmentBundle: bundle.punishments,
          randomComments: activeCoach.composeRandomComments(bundle.comments),
          isCareer: true,
          isQuickie: quickie,
          careerLevel: level,
          staminaProfile: result.staminaProfile,
          // Pas d'introText : on saute le panel d'intro et le décompte.
          // L'opening phrase est déjà jointe au step #0 de la session.
          phraseBank: coachBank,
          excitationMax: newTarget,
          // Bar visuelle : on translate `minFinal` du niveau du même +20
          // que le moteur, pour que la barre encore atteigne 100 % juste
          // au-dessus du seuil de finish initial.
          excitationBarMax:
              CareerLevel.forLevel(level).minFinal + (newTarget - 100.0),
          autoStart: true,
          holdVerifier: verifier,
          canSave: true,
          coachAdvancesTier: coachAdvances,
          specialization: bundle.specialization,
          onRequestUpgrade: (ctrl) => _handleUpgrade(ctrl, bundle, level),
          onRequestEncore: !canChainEncore
              ? null
              : (ctrl) => _handleEncore(
                    context: context,
                    bundle: bundle,
                    previousController: ctrl,
                    level: level,
                    previousMax: ctrl.excitation.maxValue,
                    includeHand: includeHand,
                    quickie: quickie,
                  ),
        ),
      ),
    );

    if (verifier != null) camService.stopSessionDetection();
    widget.tts.setNameResolver(null);

    // Reload du bundle après le retour de la séance encore : le `_start`
    // initial avait déjà reloadé au moment du pushReplacement, mais à ce
    // moment la session encore venait juste de démarrer (max non encore
    // bumpé). Ici on est de retour pour de bon → on relit prefs à jour.
    if (!mounted) return;
    setState(() {
      _bundleFuture = _loadBundle();
      _selectedLevel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.careerAppBarTitle),
        actions: [
          IconButton(
            tooltip: t.careerSpecializationTooltip,
            icon: const Icon(Icons.star_outline),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SpecializationScreen(),
                ),
              );
              if (!mounted) return;
              setState(() {
                _bundleFuture = _loadBundle();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<_CareerBundle>(
        future: _bundleFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t.careerLoadError(snapshot.error.toString()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          final bundle = snapshot.data!;
          final level = (_selectedLevel ?? bundle.lastChosenLevel)
              .clamp(1, bundle.maxLevel);
          final cfg = CareerLevel.forLevel(level);
          final durationLabel = _quickie
              ? t.careerQuickieSubtitle
              : formatDurationCompact(context, cfg.durationSeconds);
          final activeCoach = _resolveCoach(bundle);
          final principal = coachService.currentTierPrincipal;
          final isFreeTraining = !coachService.advancesTier(activeCoach);
          final freeSpecPoints =
              SpecializationService.totalPointsForLevel(bundle.maxLevel) -
                  bundle.specialization.totalSpent;
          final hasPendingSpecPoints = freeSpecPoints > 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _SectionLabel(
                title: t.coachPickerSection,
                trailing: t.coachPickerTierLabel(coachService.currentTier),
              ),
              const SizedBox(height: 8),
              _CoachSummaryCard(
                coach: activeCoach,
                isPrincipal: !isFreeTraining,
                onTap: () => _openCoachPicker(bundle),
              ),
              if (isFreeTraining) ...[
                const SizedBox(height: 10),
                FreeTrainingBanner(
                  coachName: activeCoach.name,
                  principalName: principal?.name,
                  onSwitchToPrincipal: principal == null
                      ? null
                      : () async {
                          await coachService.selectCoach(principal);
                          if (mounted) setState(() {});
                        },
                ),
              ],
              const SizedBox(height: 24),
              Text(
                t.careerHeaderTitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.careerInstruction,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              if (hasPendingSpecPoints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FreeSpecPointsBanner(
                    count: freeSpecPoints,
                    onAllocate: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SpecializationScreen(),
                        ),
                      );
                      if (!mounted) return;
                      setState(() => _bundleFuture = _loadBundle());
                    },
                  ),
                ),
              _SectionLabel(
                title: t.careerLevelSection,
                trailing: t.careerMaxLevel(bundle.maxLevel),
              ),
              const SizedBox(height: 8),
              _LevelPicker(
                value: level,
                max: bundle.maxLevel,
                onChanged: (v) => setState(() => _selectedLevel = v),
              ),
              const SizedBox(height: 8),
              _LevelTitleCard(
                title: localizedCareerLevelTitle(context, cfg.level),
                durationLabel: durationLabel,
              ),
              const SizedBox(height: 12),
              _PendingMilestonesList(
                level: level,
                allocation: bundle.specialization,
              ),
              const SizedBox(height: 24),
              () {
                final quickieLocked = bundle.maxLevel < _quickieUnlockLevel;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.careerQuickieToggle,
                    style: TextStyle(
                      fontSize: 14,
                      color: quickieLocked
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    quickieLocked
                        ? t.careerQuickieLockedSubtitle(_quickieUnlockLevel)
                        : t.careerQuickieDescription,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  value: quickieLocked ? false : _quickie,
                  onChanged: quickieLocked
                      ? null
                      : (v) => setState(() => _quickie = v),
                );
              }(),
              () {
                final pendingMilestone = milestoneService.pendingForLevel(
                  level,
                  allocation: bundle.specialization,
                );
                final milestoneLocksHand =
                    pendingMilestone?.requiresHands ?? false;
                final levelLocksHand =
                    bundle.maxLevel < _includeHandUnlockLevel;
                final locked = levelLocksHand || milestoneLocksHand;
                final subtitle = milestoneLocksHand
                    ? t.careerIncludeHandMilestoneLocked
                    : levelLocksHand
                        ? t.careerIncludeHandLockedSubtitle(
                            _includeHandUnlockLevel)
                        : t.careerIncludeHandSubtitle;
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.careerIncludeHandToggle,
                    style: TextStyle(
                      fontSize: 14,
                      color: locked
                          ? AppTheme.textMuted
                          : AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  // Forcé à ON quand le niveau est sous le seuil OU quand
                  // le milestone pending l'exige (intro_basics, intro_biffle).
                  value: locked
                      ? true
                      : (_includeHandOverride ?? bundle.includeHand),
                  onChanged: locked
                      ? null
                      : (v) => setState(() => _includeHandOverride = v),
                );
              }(),
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
                  onPressed:
                      hasPendingSpecPoints ? null : () => _start(bundle),
                  child: Text(
                    t.careerStartButton,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  t.careerCompletedSessions(bundle.completedSessions),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppTheme.accent,
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              letterSpacing: 1,
            ),
          ),
      ],
    );
  }
}

class _LevelPicker extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const _LevelPicker({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (max <= 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_open, color: AppTheme.accent, size: 18),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context).careerLevelLockedHint,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppTheme.accent,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ $max',
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textMuted,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: max.toDouble(),
            divisions: max - 1,
            label: value.toString(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _LevelTitleCard extends StatelessWidget {
  final String title;
  final String durationLabel;

  const _LevelTitleCard({
    required this.title,
    required this.durationLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_outlined,
              color: AppTheme.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  durationLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
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

class _PendingMilestonesList extends StatelessWidget {
  final int level;
  final SpecializationAllocation? allocation;

  const _PendingMilestonesList({
    required this.level,
    required this.allocation,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final pending = milestoneService.allPendingForLevel(
      level,
      allocation: allocation,
    );
    if (pending.isEmpty) return const SizedBox.shrink();
    final next = pending.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            t.careerMilestonesPendingTitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final m in pending) ...[
          _PendingMilestoneCard(
            milestone: m,
            isNext: identical(m, next),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PendingMilestoneCard extends StatelessWidget {
  final LevelMilestone milestone;
  final bool isNext;

  const _PendingMilestoneCard({
    required this.milestone,
    required this.isNext,
  });

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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isNext
              ? AppTheme.accent.withValues(alpha: 0.6)
              : AppTheme.accent.withValues(alpha: 0.15),
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.displayLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
          if (isNext) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.careerMilestonesNextBadge,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachSummaryCard extends StatelessWidget {
  final Coach coach;
  final bool isPrincipal;
  final VoidCallback onTap;

  const _CoachSummaryCard({
    required this.coach,
    required this.isPrincipal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final accent = isPrincipal ? AppTheme.accent : const Color(0xFFE8B33A);
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Icon(
                  isPrincipal ? Icons.star : Icons.tune,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coach.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      isPrincipal
                          ? t.coachSummaryPrincipal(coach.title, coach.tier)
                          : t.coachSummaryFree(coach.title),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _CareerBundle {
  final PhraseBank bank;
  final PunishmentBundle punishments;
  final RandomCommentsBundle comments;
  final int maxLevel;
  final int lastChosenLevel;
  final int completedSessions;
  final bool includeHand;
  final SpecializationAllocation specialization;

  const _CareerBundle({
    required this.bank,
    required this.punishments,
    required this.comments,
    required this.maxLevel,
    required this.lastChosenLevel,
    required this.completedSessions,
    required this.includeHand,
    required this.specialization,
  });
}
