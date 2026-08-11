import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/format_helpers.dart';
import '../../models/posture.dart';
import '../../screens/session_screen.dart';
import '../../services/ambience_engine.dart';
import '../../services/beep_engine.dart';
import '../../services/camera_motion_service.dart';
import '../../services/capability_service.dart';
import '../../services/coach_phrases_loader.dart';
import '../../services/punishment_loader.dart';
import '../../services/random_comments_loader.dart';
import '../../services/stats_service.dart';
import '../../services/tts_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/enum_labels.dart';
import '../../main.dart' show coachService, milestoneService;
import '../services/coach_service.dart' show CoachSelectionStatus;
import '../models/career_generation_inputs.dart';
import '../models/challenge.dart';
import '../models/coach.dart';
import '../models/level_milestone.dart';
import '../services/career_difficulty_resolver.dart';
import '../services/career_encore_gate.dart';
import '../services/career_progress_service.dart';
import '../services/challenge_service.dart';
import '../services/debug_settings_service.dart';
import '../services/generation/career_session_generator.dart';
import '../services/phrase_bank_loader.dart';
import '../services/specialization_service.dart';
import '../widgets/coach_portrait.dart';
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
  final ChallengeService _challengeService = ChallengeService();

  SessionLengthChoice? _selectedLengthChoice;
  bool? _includeHandOverride;
  bool _challengesEnabled = false;
  bool _challengeTutorialSeen = false;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
    // Phase 1 défis — hydrate le toggle et le flag tutoriel depuis
    // SharedPreferences. setState gardé par `mounted` pour ne pas casser si
    // l'utilisatrice quitte l'écran avant la fin de la lecture.
    _challengeService.isEnabled().then((v) {
      if (mounted) setState(() => _challengesEnabled = v);
    });
    _challengeService.tutorialSeen().then((v) {
      if (mounted) setState(() => _challengeTutorialSeen = v);
    });
  }

  Future<_CareerBundle> _loadBundle() async {
    final results = await Future.wait([
      PhraseBankLoader().load(),
      PunishmentLoader().load(),
      RandomCommentsLoader().load(),
      _progress.getCompletedSessions(),
      _progress.getIncludeHand(),
      _specService.load(),
      _stats.getHumiliationLevel(),
      _stats.getObedienceLevel(),
      CapabilityService().snapshotProfile(),
      _challengeService.isEnabled(),
      _challengeService.tutorialSeen(),
      _progress.getLastLengthChoice(),
      _stats.getTotalSeconds(),
      DebugSettingsService().getScriptedBreaks(),
    ]);
    final capabilityProfile = results[8] as CapabilityProfile;
    final totalSeconds = results[12] as int;
    final completedSessions = results[3] as int;
    // Level synthétique dérivé de `completedSessions` (cf.
    // `CareerDifficultyResolver.synthLevelFor`). Passé au reconcile pour
    // gater les milestones de mode entier (freestyle level 7, biffleBasic
    // level 5…) qui ne doivent pas être auto-acquittées sur la base
    // d'une capacité prouvée si la joueuse n'a pas atteint le palier.
    final synthLevel =
        CareerDifficultyResolver.synthLevelFor(completedSessions);
    // Réparation à froid : consolide les milestones-parents dont un enfant
    // déjà complété dépend mais qui sont restées « à faire » (acquittement
    // par défi sur un unlock provisoire non consolidé — cf.
    // `MilestoneService.consolidatePrerequisites`). Sans ça, le tutoriel
    // `intro_basics` est ré-inséré tant qu'il n'est pas consolidé alors que
    // ses enfants sont faits. Avant le reconcile : back-filler `basics`
    // permet ensuite à `reconcileFromCapability` d'acquitter correctement.
    await milestoneService.consolidatePrerequisites();
    // Rattrapage à froid : acquitte les milestones que le profil de
    // capacités prouve déjà (cas typique : la cascade transitive du défi
    // a été livrée après que la joueuse l'ait joué — sans rattrapage,
    // ses unlocks restent figés à leur état pré-cascade et les sessions
    // suivantes proposent des actions plus shallow que ce qu'elle sait
    // tenir). Idempotent. En parallèle : sync du palier coach avec le
    // temps cumulé — les deux opérations sont indépendantes
    // (MilestoneService vs CoachService).
    await Future.wait([
      milestoneService.reconcileFromCapability(capabilityProfile,
          playerLevel: synthLevel),
      coachService.syncFromTotalSeconds(totalSeconds),
    ]);
    return _CareerBundle(
      bank: results[0] as PhraseBank,
      punishments: results[1] as PunishmentBundle,
      comments: results[2] as RandomCommentsBundle,
      completedSessions: completedSessions,
      includeHand: results[4] as bool,
      specialization: results[5] as SpecializationAllocation,
      humiliationScore: results[6] as double,
      obedienceScore: results[7] as double,
      capabilityProfile: capabilityProfile,
      challengesEnabled: results[9] as bool,
      challengeTutorialSeen: results[10] as bool,
      lastLengthChoice: results[11] as SessionLengthChoice,
      totalSeconds: totalSeconds,
      synthLevel: CareerDifficultyResolver.synthLevelFor(completedSessions),
      scriptedBreaks: results[13] as bool,
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
          playerTotalSeconds: bundle.totalSeconds,
          handsEnabled: _includeHandOverride ?? bundle.includeHand,
          tts: widget.tts,
          userProfile: widget.userProfile,
        ),
      ),
    );
    if (picked != null && mounted) setState(() {});
  }

  Future<void> _start(_CareerBundle bundle) async {
    final t = AppLocalizations.of(context);
    // Phase 19.12 : `level` passé au générateur = synthLevel dérivé des
    // sessions (sert au titre de session + fallback Custom — le
    // générateur recalcule la config via `resolveForCareer` à partir
    // de `sessionsCompleted` + `lengthChoice`).
    final clamped = bundle.synthLevel;
    // Même fallback que `build` (cf. resolveSessionLengthChoice) — sinon
    // un choix persisté désormais lock (ex. `longue` choisie sous l'ancienne
    // gate ≥1 séance OU ≥10 min) lancerait quand même une séance 45 min
    // alors que le picker affiche courte.
    final persistedChoice = _selectedLengthChoice ?? bundle.lastLengthChoice;
    final lengthChoice = resolveSessionLengthChoice(
      persisted: persistedChoice,
      bacheeUnlocked: isSessionLengthBacheeUnlocked(bundle.totalSeconds),
      moyenneUnlocked: isSessionLengthMoyenneUnlocked(
        totalSeconds: bundle.totalSeconds,
        completedSessions: bundle.completedSessions,
      ),
      longueUnlocked: isSessionLengthLongueUnlocked(bundle.totalSeconds),
      aleatoireUnlocked: isSessionLengthAleatoireUnlocked(bundle.totalSeconds),
    );
    // Ne persister que sur action utilisateur explicite (= elle a tap une
    // carte). Sans ce garde, le fallback à courte écraserait silencieusement
    // un choix `longue` original quand totalSeconds redescend (reset stats /
    // debug) — la joueuse perdrait sa préférence pour de bon.
    if (_selectedLengthChoice != null) {
      await _progress.setLastLengthChoice(lengthChoice);
    }
    // Tirage du palier effectif quand le choix utilisatrice est `aleatoire`
    // (sinon `effectiveLengthChoice == lengthChoice`, identité). C'est
    // `effectiveLengthChoice` qui pilote toute la suite (durée, body
    // milestones, défis…) ; `lengthChoice` n'est conservé que pour la
    // persistance (la joueuse a choisi « surprise ») et pour décider de
    // masquer le timer côté SessionScreen.
    final isAleatoire = lengthChoice == SessionLengthChoice.aleatoire;
    final effectiveLengthChoice =
        lengthChoice.resolveAleatoireIfNeeded(Random());

    // Phase 19.12 : la règle `requiresHands` des milestones reste, mais
    // plus de gate par niveau — le toggle hand respecte simplement le
    // choix utilisatrice (préférence persistée) sauf override forcé en
    // aval par une milestone scriptée qui en a besoin.
    final baseIncludeHand = _includeHandOverride ?? bundle.includeHand;

    final activeCoach = _resolveCoach(bundle);
    // À partir du tier 2 (Hélène), on ne démarre pas tant que l'utilisatrice
    // n'a pas posé un prénom : les coachs supérieurs s'adressent à elle de
    // manière personnelle, et entendre « salope » sans aucun prénom dilue
    // la tension dramaturgique recherchée. Lina (tier 1) reste accessible
    // sans prénom — le bizutage de découverte tolère l'anonymat.
    if (activeCoach.tier >= 2 &&
        (widget.userProfile.prenom == null ||
            widget.userProfile.prenom!.trim().isEmpty)) {
      final ok = await _promptForPrenom(activeCoach);
      if (!ok || !mounted) return;
    }
    final coachAdvances = coachService.advancesTier(activeCoach);
    // Compose la bank du coach par-dessus la globale : tirage prioritaire
    // sur les phrases du coach, fallback transparent sur la PhraseBank
    // commune pour les cases vides.
    final coachBank = activeCoach.toPhraseBank(
        fallback: bundle.bank, specialization: bundle.specialization);
    _installCoachNameResolver(activeCoach);
    await _applyCoachVoicePreset(activeCoach);

    // Phase 19.12 : la bâclée est toujours accessible — plus de gate
    // par niveau. Le palier « bachee » du picker active automatiquement
    // `quickie:true` côté générateur (intensityFloor 0.65 + 6 min).
    //
    // Le palier `aleatoire` n'inclut pas `bachee` dans son pool de tirage
    // (cf. `SessionLengthChoice.aleatoireDrawPool`), donc en mode aléatoire
    // `isBachee == false` par construction.
    final isBachee = effectiveLengthChoice == SessionLengthChoice.bachee;
    final quickie = isBachee;
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
    //
    // Phase 19.5 : le nombre cible de body milestones vient du palier de
    // durée (cf. `SessionLengthChoice.maxBodyMilestones`). Bâclée = 0 body
    // (pas de pédagogie sur 6 min), courte = 1, moyenne/longue = 2. La
    // disponibilité réelle dépend du catalogue pending.
    final bodyCount = effectiveLengthChoice.maxBodyMilestones;
    final anatomy = widget.userProfile.anatomy;
    // Tête de la file showcase : la prochaine séance honore le dernier
    // point spé dépensé (cf. `SpecializationService.invest`). Lue ici
    // pour être passée au tri des candidates et à l'incrémentation
    // d'aging. Bâclée ne consomme rien (pas de pédagogie).
    final showcaseBranch = isBachee ? null : await _specService.peekShowcase();
    final insertedBodies = bodyCount == 0
        ? const <LevelMilestone>[]
        : milestoneService.pendingForList(
            count: bodyCount,
            humiliationScore: humiliationScore,
            obedience: obedienceScore,
            playerLevel: bundle.synthLevel,
            allocation: bundle.specialization,
            capabilityProfile: bundle.capabilityProfile,
            anatomy: anatomy,
            showcaseBranch: showcaseBranch,
          );
    final finalCandidates = isBachee
        ? const <LevelMilestone>[]
        : milestoneService.allPendingFor(
            humiliationScore: humiliationScore,
            obedience: obedienceScore,
            playerLevel: bundle.synthLevel,
            allocation: bundle.specialization,
            capabilityProfile: bundle.capabilityProfile,
            anatomy: anatomy,
            placement: MilestonePlacement.finalApotheose,
          );
    final finalMilestone =
        finalCandidates.isEmpty ? null : finalCandidates.first;
    // Vieillit les candidates non choisies de cette session — aging du tri
    // composite, cf. `MilestoneService.allPendingFor`. Pour les bodies, on
    // ré-évalue `allPendingFor` (avant les picks de `pendingForList`, qui
    // a sa propre logique d'exclusion mutuelle) et on retire les ids
    // effectivement insérés. Pas de comptage en bâclée.
    if (!isBachee) {
      // L'aging ne consomme pas le boost showcase — l'objectif est de
      // comparer les candidates dans leur tri naturel (sinon une session
      // sans milestone disponible pour la branche showcase ne ferait
      // vieillir personne d'autre comme attendu).
      final bodyAll = milestoneService.allPendingFor(
        humiliationScore: humiliationScore,
        obedience: obedienceScore,
        playerLevel: bundle.synthLevel,
        allocation: bundle.specialization,
        capabilityProfile: bundle.capabilityProfile,
        anatomy: anatomy,
      );
      final insertedIds = insertedBodies.map((m) => m.id).toSet();
      final notChosen = <LevelMilestone>[
        ...bodyAll.where((m) => !insertedIds.contains(m.id)),
        if (finalCandidates.length > 1) ...finalCandidates.skip(1),
      ];
      if (notChosen.isNotEmpty) {
        await milestoneService.incrementCandidacyAge(notChosen);
      }
    }
    // Consomme la tête de la file showcase si une milestone effectivement
    // insérée touche la branche en tête. Si rien ne matche (toutes les
    // milestones de la branche sont acquises ou bloquées par capability /
    // anatomy / humil), on garde la dette pour la prochaine séance.
    if (showcaseBranch != null &&
        insertedBodies.any((m) => m.branches.contains(showcaseBranch))) {
      await _specService.consumeShowcase(showcaseBranch);
    }
    // Force includeHand=true si une milestone pending l'exige (séquence
    // scriptée comportant du hand/biffle). Sinon respecte la préférence
    // utilisatrice. Persistance volontairement avec la valeur effective
    // (post-force) pour que le toggle reste cohérent avec ce qui a joué.
    final includeHand = (insertedBodies.any((m) => m.requiresHands) ||
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
    // Phase 19.5.b — construit N défis pour compléter le total
    // d'events visé par le palier. Quand le catalogue de milestones est
    // épuisé (insertedBodies < maxBody), les défis comblent : longue avec
    // 0 milestone = 4 défis ; moyenne avec 1 milestone = 2 défis. Les
    // axes déjà couverts (milestones + défis précédents) sont exclus pour
    // éviter l'empilement (spec § 5.5).
    final challenges = <Challenge>[];
    if (_challengesEnabled) {
      final targetCount =
          effectiveLengthChoice.targetChallengesFor(insertedBodies.length);
      final excludedAxes = <CapabilityAxis>{};
      // Anti-répétition inter-sessions : exclure d'abord les axes pickés à
      // la session précédente. Sur un profil jeune (3 axes prouvés) sans
      // cette exclusion, `pickOverloadAxis` retombe sur les mêmes 3 axes
      // dans le même ordre 2 séances de suite (cf. retour stefsub v0.5.0).
      // Non bloquant : si la pool restante est trop petite pour atteindre
      // `targetCount`, on retire ce filtre dans le 2ᵉ essai du pick.
      final lastSessionAxes = await _challengeService.lastSessionAxes();
      // Premier défi seulement : le tutoriel est forcé sur l'axe hold
      // throat (cf. _buildTutorialChallenge), on ne le répète pas pour
      // les défis suivants.
      var isFirst = true;
      for (var i = 0; i < targetCount; i++) {
        final isTuto = isFirst && !_challengeTutorialSeen;
        // 1er essai : exclusion stricte (axes session courante + signature
        // visuelle + axes de la session précédente). Pas d'anti-repeat pour
        // le tuto, qui est de toute façon forcé sur holdThroatStreak.
        final strictExcluded = isTuto
            ? excludedAxes
            : <CapabilityAxis>{...excludedAxes, ...lastSessionAxes};
        var next = await _challengeService.buildForSession(
          profile: bundle.capabilityProfile,
          ceilings: const {},
          excludeAxes: strictExcluded,
          rng: Random(),
          isTutorial: isTuto,
          // Cascade showcase (spec § 5.1) : si la file showcase a une
          // tête non-encore-consommée par une milestone insérée, le défi
          // tente de l'honorer en priorité (axe pilotant de la branche).
          // Appliqué seulement au premier défi pour ne pas saturer.
          showcaseBranch: isFirst ? showcaseBranch : null,
          // Gating par unlock : les défis « modèle gorge » (apnée /
          // engagement) exigent des unlocks préalables (cf. spec § bug 5).
          unlocks: unlockedKeys,
        );
        // 2ᵉ essai : on retombe sur l'ancien tirage (pool restreinte
        // accepte la répétition inter-sessions plutôt que de générer
        // moins de défis que prévu).
        if (next == null && !isTuto && lastSessionAxes.isNotEmpty) {
          next = await _challengeService.buildForSession(
            profile: bundle.capabilityProfile,
            ceilings: const {},
            excludeAxes: excludedAxes,
            rng: Random(),
            isTutorial: false,
            showcaseBranch: isFirst ? showcaseBranch : null,
            unlocks: unlockedKeys,
          );
        }
        if (next == null) break;
        challenges.add(next);
        excludedAxes.add(next.axis);
        // Étend l'exclusion aux autres axes qui produiraient un défi
        // visuellement identique (même mode/from/to/kind) — sans ça une
        // joueuse avec plusieurs axes hold throat (holdThroatStreak,
        // gorgeApneeStreak, gorgeEngagementStreak) verrait deux défis
        // « hold throat » dont seule la durée diffère. Cf. retour stefsub
        // v0.5.0.
        excludedAxes
            .addAll(ChallengeService.axesSharingVisualSignature(next.axis));
        isFirst = false;
      }
      // Persiste les axes pickés pour la session suivante. Tutoriel inclus :
      // sans ça, si la séance N+1 a aussi un défi, on revoit holdThroatStreak
      // en 1ᵉʳ pick non-tuto (le tuto est consommé une fois pour toutes via
      // `markTutorialSeen`).
      unawaited(_challengeService
          .recordSessionChallenges(challenges.map((c) => c.axis)));
    }
    final result = CareerSessionGenerator().generate(
      level: clamped,
      bank: coachBank,
      lengthChoice: effectiveLengthChoice,
      // Phase 19.6 : déclenche resolveForCareer côté générateur (cap /
      // regen / boosts dérivés des sessions au lieu du level).
      sessionsCompleted: bundle.completedSessions,
      includeHand: includeHand,
      quickie: quickie,
      specialization: activeCoach.effectiveAllocation(bundle.specialization),
      // Session normale : on démarre sans chauffe (sessionScore = 0).
      humiliationCareer: humiliationScore,
      humiliationSession: 0.0,
      obedience: obedienceScore,
      unlockedKeys: unlockedKeys,
      coachModeWeights: activeCoach.modeWeights,
      sessionName: t.careerSessionName(clamped),
      sessionNameQuickie: t.careerSessionNameQuickie(clamped),
      anatomy: widget.userProfile.anatomy,
      milestones: MilestonePlan(
        bodies: insertedBodies,
        finalMilestone: finalMilestone,
        textResolver: milestoneService.getStepText,
      ),
      // 2ᵉ enveloppe : profil de capacités persisté. Pas de
      // `sessionCeilings` ici — la séance démarre, aucun fail n'a encore
      // figé de plafond.
      capability: CapabilityInputs(profile: bundle.capabilityProfile),
      challenge: ChallengeInputs(challenges: challenges),
      scriptedBreaks: bundle.scriptedBreaks,
    );

    var introText = coachBank.pickIntro(Random());
    // Break scénarisé (issue #77) : si le générateur a imposé une posture de
    // départ, l'annoncer dans le briefing d'intro. Sinon la joueuse (yeux
    // fermés, téléphone posé sur le côté) ne saurait jamais s'y mettre — seuls
    // les *changements* de posture aux breaks étaient vocalisés jusqu'ici. Si
    // l'intro est vide (coach sans `intros`), la consigne devient le briefing
    // à elle seule (le panel « Je suis prête » s'affiche pour la poser).
    final initialPose = result.session.initialPose;
    if (initialPose != Posture.free) {
      final postureLine = coachBank.pickPostureChange(initialPose, Random());
      if (postureLine != null && postureLine.isNotEmpty) {
        introText = (introText == null || introText.isEmpty)
            ? postureLine
            : '$introText $postureLine';
      }
    }

    // Unlocks provisoires de la session : chaque milestone insérée
    // débloque visuellement ses compétences pour l'UI (bouton Supplier
    // surtout) dès le démarrage, sans attendre le markCompleted final.
    // Le générateur, lui, n'a pas reçu ces unlocks (cf. plus haut), donc
    // pas de risque d'incohérence. Union des unlocks de toutes les body
    // (1 ou 2) et de la final milestone.
    milestoneService.setSessionUnlocks(<UnlockKey>{
      for (final m in insertedBodies) ...m.unlocks,
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
          // 2ᵉ enveloppe de difficulté : axe surchargé de la séance + snapshot
          // du profil — consommés par le coach (Phase 4 : phrases attempt/
          // record/tapout) côté SessionController.
          capabilityOverloadAxis: result.overloadAxis,
          capabilityProfile: bundle.capabilityProfile,
          // Phase 5 : punitions carrière générées par le `SessionController`
          // ont besoin du même set d'unlocks et du même toggle hand que le
          // générateur initial pour filtrer leur palette.
          unlockedKeys: unlockedKeys,
          includeHand: includeHand,
          introText: introText,
          phraseBank: coachBank,
          holdVerifier: verifier,
          canSave: true,
          coachAdvancesTier: coachAdvances,
          specialization: bundle.specialization,
          specializationService: _specService,
          miniPunishmentRate: activeCoach.miniPunishmentRate,
          coachTag: activeCoach.slug,
          onRequestUpgrade: (ctrl) => _handleUpgrade(ctrl, bundle, clamped),
          onRequestEncore: !canEncore
              ? null
              : (ctrl) => _handleEncore(
                    context: context,
                    bundle: bundle,
                    previousController: ctrl,
                    level: clamped,
                    encoreChainIndex: 1,
                    includeHand: includeHand,
                    quickie: quickie,
                    hideTimer: isAleatoire,
                  ),
          onMilestoneRetry: (ctrl) => _handleMilestoneRetry(
            ctrl,
            bundle,
            clamped,
          ),
          onPostChallengeRegen: (ctrl) => _handlePostChallengeRegen(
            ctrl,
            bundle,
            clamped,
            includeHand,
          ),
          onChallengeOutcome: (ch, _) {
            // Compteur d'essais par axe — fait monter la cible « franchissements »
            // (cf. `crossingsTargetForAttempts`) du prochain défi sur le
            // même axe. Fire-and-forget : la persistance n'a pas besoin
            // de bloquer la fin du défi.
            unawaited(_challengeService.incrementAttempts(ch.axis));
          },
          anatomy: anatomy,
          hideTimerOverride: isAleatoire,
        ),
      ),
    );

    if (verifier != null) camService.stopSessionDetection();
    widget.tts.setNameResolver(null);
    await widget.tts.takeVoiceLead(widget.tts.restoreDefaultVoicePreset);
    // Reset des unlocks provisoires : la session est terminée. Si la
    // milestone a été acquittée, son unlock est déjà persisté dans
    // `_completed` via `markCompleted` ; sinon, on retire l'illusion.
    milestoneService.setSessionUnlocks(const {});

    // Phase 1 défis — pose le flag tutorial_seen après le 1ᵉʳ défi joué
    // (peu importe l'outcome : succès, fail, ou skip — la joueuse a vu
    // les boutons et le flow, c'est l'objet de la pédagogie tutoriel).
    // En multi-défi, seul le 1ᵉʳ peut être tutoriel (cf. boucle ci-dessus).
    if (challenges.isNotEmpty && challenges.first.isTutorial) {
      await _challengeService.markTutorialSeen();
      if (mounted) setState(() => _challengeTutorialSeen = true);
    }

    // De retour de la séance, recharger pour refléter un éventuel
    // nouveau max débloqué.
    setState(() {
      _bundleFuture = _loadBundle();
      _selectedLengthChoice = null;
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

  /// Ouvre un dialog modal qui force la saisie d'un prénom. Retourne
  /// `true` si l'utilisatrice a validé un prénom non vide (alors persisté
  /// via `UserProfileService.setPrenom`), `false` si elle a annulé. Sert
  /// de gate avant de démarrer une séance avec un coach tier ≥ 2 — la
  /// session ne se lance pas tant qu'on n'a pas de prénom à utiliser.
  Future<bool> _promptForPrenom(Coach coach) async {
    final controller = TextEditingController();
    final t = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(t.coachPrenomGateTitle(coach.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.coachPrenomGateBody(coach.name),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: t.coachPrenomGateField,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.of(ctx).pop(true);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: Text(t.coachPrenomGateConfirm),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await widget.userProfile.setPrenom(controller.text.trim());
      return true;
    }
    return false;
  }

  /// Applique le preset vocal du coach (voix + rate + pitch) au moteur TTS.
  /// No-op si le coach n'a pas de preset déclaré dans son JSON. La sortie
  /// de session restaure les valeurs par défaut via
  /// `TtsService.restoreDefaultVoicePreset`.
  ///
  /// Sous `takeVoiceLead` : le sélecteur de coach s'ouvre depuis cet écran,
  /// et le réglage de voix qu'il porte peut avoir laissé une écriture en
  /// vol quand « Commencer » est tapé deux gestes plus loin. La séance
  /// prend la main plutôt que d'attendre son tour.
  Future<void> _applyCoachVoicePreset(Coach coach) {
    final preset = coach.voicePreset;
    if (preset.isEmpty) {
      // Pas de preset : on s'assure quand même que les défauts sont en
      // place — au cas où un coach précédent en aurait posé un et qu'on
      // soit revenu sur ce coach sans passer par un restoreDefaults.
      return widget.tts.takeVoiceLead(widget.tts.restoreDefaultVoicePreset);
    }
    return widget.tts.takeVoiceLead(
      () => widget.tts.applyCoachVoicePreset(
        coachId: coach.id,
        voiceName: preset.voiceName,
        voiceLocale: preset.voiceLocale,
        rate: preset.rate,
        pitch: preset.pitch,
        skipPreferredVoices: preset.skipPreferredVoices,
      ),
    );
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
    return CareerEncoreGate.canEncore(
      level: level,
      humiliationScore: humiliationScore,
      obedienceScore: obedienceScore,
      milestoneService: milestoneService,
    );
  }

  Future<void> _handleUpgrade(
    SessionController ctrl,
    _CareerBundle bundle,
    int currentLevel,
  ) async {
    final t = AppLocalizations.of(context);
    // « Utilise-moi » : beg d'engagement fixe (« supplie-moi de t'utiliser… »),
    // durée ≈ temps d'énoncé + 1 s — à peine le temps de le dire avant que
    // l'escalade non-stop démarre. Estimée depuis le nombre de mots (TTS lent).
    final begPhrase = t.careerUseMeBegPhrase;
    final begWordCount =
        begPhrase.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final begDuration = (begWordCount * 0.6).ceil() + 1;
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    if (remaining < begDuration + 30) return;

    // Plus de saut de niveau : la difficulté supplémentaire passe par
    // `intense: true` (boost comforts + intensityFloor + BPM cap finish +
    // bump tier des phrases) — cf. `SessionConfig.intense` et
    // `CapabilityClamps.capabilityCapFor`.
    final newLevel = currentLevel;
    final activeCoach = _resolveCoach(bundle);
    final coachBank = activeCoach.toPhraseBank(
        fallback: bundle.bank, specialization: bundle.specialization);

    final genDuration = remaining - begDuration;
    final humiliationCareer = await _stats.getHumiliationLevel();
    // Pour Supplier on utilise l'obédiance courante du contrôleur (live),
    // pas la valeur persistée — la séance est en cours, le score a déjà
    // été pénalisé par d'éventuels fails de cette session.
    final obedienceScore = ctrl.obedience.score;
    // sessionScore live : la séance est en cours, on transmet la chauffe
    // déjà accumulée pour que la régénération reflète la difficulté
    // actuelle, pas un démarrage à froid.
    final humiliationSession = ctrl.humiliation.sessionScore;
    final newGen = CareerSessionGenerator().generate(
      durationSeconds: genDuration,
      level: newLevel,
      bank: coachBank,
      includeHand: bundle.includeHand,
      specialization: activeCoach.effectiveAllocation(bundle.specialization),
      intense: true,
      useMe: true,
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedienceScore,
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      coachModeWeights: activeCoach.modeWeights,
      sessionName: t.careerSessionName(newLevel),
      sessionNameQuickie: t.careerSessionNameQuickie(newLevel),
      anatomy: widget.userProfile.anatomy,
      // 2ᵉ enveloppe : profil persisté + plafonds figés sur les fails déjà
      // subis cette séance (live, comme l'obédiance ci-dessus) → la régen
      // « niveau supérieur » respecte quand même ce que la joueuse vient
      // de prouver ne pas tenir.
      capability: CapabilityInputs(
        profile: bundle.capabilityProfile,
        sessionCeilings: ctrl.capabilitySessionCeilings,
      ),
    );

    final beg = SessionStep(
      time: 0,
      text: begPhrase,
      mode: SessionMode.beg,
      from: Position.full,
      duration: begDuration,
    );

    await ctrl.requestUpgrade(
      insistentBeg: beg,
      upcomingSession: newGen.session,
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
    final t = AppLocalizations.of(context);
    // Cible la milestone effectivement ratée : sur les séances ≥ 18 min
    // avec 2 body, le fail peut tomber dans l'une OU l'autre fenêtre.
    final milestoneId = ctrl.currentMilestoneIdInWindow;
    if (milestoneId == null) return false;
    final milestone = milestoneService.findById(milestoneId);
    if (milestone == null) return false;
    // Pas de retry V1 pour le final (apothéose = on rate la séance).
    if (milestone.placement != MilestonePlacement.body) return false;
    final used = milestoneService.getRetryCount(milestoneId);
    if (used >= milestone.maxRetry) return false;
    await milestoneService.incrementRetryCount(milestoneId);

    const begDuration = 6;
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    final retryDuration = remaining + milestone.durationSeconds;

    final activeCoach = _resolveCoach(bundle);
    final coachBank = activeCoach.toPhraseBank(
        fallback: bundle.bank, specialization: bundle.specialization);
    final humiliationCareer = await _stats.getHumiliationLevel();
    // Retry milestone : utilise l'obédiance live (un fail vient de la faire
    // descendre, le générateur doit en tenir compte pour adapter le ton).
    final obedienceScore = ctrl.obedience.score;
    // sessionScore live : un fail vient de la faire baisser. Le retry
    // doit refléter cet état (cap effectif descendu) sans pour autant
    // rebaser à zéro la chauffe accumulée avant l'échec.
    final humiliationSession = ctrl.humiliation.sessionScore;

    final newGen = CareerSessionGenerator().generate(
      durationSeconds: retryDuration,
      level: level,
      bank: coachBank,
      includeHand: bundle.includeHand,
      specialization: activeCoach.effectiveAllocation(bundle.specialization),
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedienceScore,
      // Plan pessimiste : pour le retry, on ne suppose plus que la
      // milestone est acquittée — son unlock n'est pas dans le set, le
      // reste de la session ne réutilise donc pas la compétence ratée.
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      coachModeWeights: activeCoach.modeWeights,
      sessionName: t.careerSessionName(level),
      sessionNameQuickie: t.careerSessionNameQuickie(level),
      anatomy: widget.userProfile.anatomy,
      // Retry V1 : on régénère avec une seule body (la milestone ratée).
      // Si la séance d'origine en avait deux, l'autre est perdue sur le
      // retry — V2 pourrait préserver l'autre si elle n'a pas encore été
      // jouée, mais ça complexifie la dramaturgie.
      milestones: MilestonePlan(
        bodies: [milestone],
        textResolver: milestoneService.getStepText,
      ),
      // 2ᵉ enveloppe : profil persisté + plafonds figés par le fail qui
      // vient de déclencher ce retry (figés par `triggerFail` AVANT le
      // callback, cf. SessionController) → le retry ne re-pousse pas
      // l'axe qui a craqué.
      capability: CapabilityInputs(
        profile: bundle.capabilityProfile,
        sessionCeilings: ctrl.capabilitySessionCeilings,
      ),
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
      upcomingSession: newGen.session,
    );
    return true;
  }

  /// Régénération post-défi : un défi vient d'acquitter au moins une
  /// milestone, le set d'unlocks s'est élargi (la mise à jour runtime de
  /// `_unlockedKeys` est déjà faite par le contrôleur dans
  /// `_finalizeChallengeAcquittals`). On régénère le reste de la séance
  /// pour que le générateur consomme la compétence fraîchement débloquée
  /// — sans regen, la timeline restante reste celle composée au start
  /// avec l'ancien set, et le succès du défi ne « débloque » rien de
  /// visible avant la séance suivante.
  ///
  /// Transition silencieuse : pas de beg insistant ni de phrase, le breath
  /// de 10s post-défi sert lui-même de pont. Skip si :
  /// - aucun profil de capacités (sessions hors carrière — ne devrait pas
  ///   arriver, mais robustesse) ;
  /// - moins de 30 s restantes après la fin du breath (pas assez de matière
  ///   pour reposer une suite cohérente).
  Future<void> _handlePostChallengeRegen(
    SessionController ctrl,
    _CareerBundle bundle,
    int level,
    bool includeHand,
  ) async {
    final t = AppLocalizations.of(context);
    final breathEnd = ctrl.postChallengeBreathUntilSec ?? ctrl.elapsedSeconds;
    final remaining = ctrl.session.durationSeconds - breathEnd;
    if (remaining < 30) return;

    final activeCoach = _resolveCoach(bundle);
    final coachBank = activeCoach.toPhraseBank(
        fallback: bundle.bank, specialization: bundle.specialization);
    final humiliationCareer = await _stats.getHumiliationLevel();
    // Live (post-défi) : la chauffe accumulée pendant le défi est sur le
    // sessionScore du contrôleur ; l'obédiance a pu monter via les bumps
    // d'outcome (`_applyChallengeOutcome` ne tourne qu'à `_finish`, donc
    // ici on a la valeur d'avant les bumps — acceptable, la chauffe
    // sessionScore reste la source principale de difficulté intra-séance).
    final humiliationSession = ctrl.humiliation.sessionScore;
    final obedienceScore = ctrl.obedience.score;
    // Nouveau set d'unlocks (élargi par `_finalizeChallengeAcquittals`).
    final newUnlocks = milestoneService.acquiredUnlockKeys();

    final newGen = CareerSessionGenerator().generate(
      durationSeconds: remaining,
      level: level,
      bank: coachBank,
      includeHand: includeHand,
      specialization: activeCoach.effectiveAllocation(bundle.specialization),
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedienceScore,
      unlockedKeys: newUnlocks,
      coachModeWeights: activeCoach.modeWeights,
      sessionName: t.careerSessionName(level),
      sessionNameQuickie: t.careerSessionNameQuickie(level),
      anatomy: widget.userProfile.anatomy,
      capability: CapabilityInputs(
        profile: bundle.capabilityProfile,
        sessionCeilings: ctrl.capabilitySessionCeilings,
      ),
      // Pas de `milestones` ni de `challenge` : les milestones de la séance
      // ont déjà été insérées et le défi vient de tourner — on régénère le
      // reste comme une suite « normale » qui consomme librement les
      // nouveaux unlocks (le défi peut acquitter en cascade plusieurs
      // milestones d'un coup, cf. § 5.4 spec).
    );

    await ctrl.requestPostChallengeRegen(upcomingSession: newGen.session);
  }

  /// Action « J'en veux encore » depuis l'écran finished. Régénère une
  /// session au même niveau et même durée, avec un finish plus dense :
  /// `encoreChainIndex * 2` boosts en plus, BPM cap relevé, final allongé.
  /// Comptabilise l'encore (badge JamaisRassasiee). Push remplace l'écran
  /// courant — le SessionController précédent est disposed.
  Future<void> _handleEncore({
    required BuildContext context,
    required _CareerBundle bundle,
    required SessionController previousController,
    required int level,
    required int encoreChainIndex,
    required bool includeHand,
    required bool quickie,
    required bool hideTimer,
  }) async {
    final t = AppLocalizations.of(context);
    // Capture la chauffe (`sessionScore` d'humiliation) ET les plafonds de
    // capacité figés sur les fails de la séance, AVANT de détacher /
    // disposer le previousController : sinon les valeurs sont perdues et la
    // session-encore démarre froide. C'est exactement le levier qui fait
    // qu'on « repart d'où on était » au lieu de tout réinitialiser.
    final previousSessionHumiliation =
        previousController.humiliation.sessionScore;
    final previousSessionCeilings =
        previousController.capabilitySessionCeilings;

    // Détache l'ancien controller des services audio partagés AVANT que
    // pushReplacement ne déclenche son dispose() — sinon un `tts.stop()` /
    // `beep.stop()` fire-and-forget couperait la première phrase et le
    // premier loop de la nouvelle session.
    await previousController.detachAudio();

    await _stats.recordEncoreAsked();

    final activeCoach = _resolveCoach(bundle);
    final coachAdvances = coachService.advancesTier(activeCoach);
    final coachBank = activeCoach.toPhraseBank(
        fallback: bundle.bank, specialization: bundle.specialization);
    _installCoachNameResolver(activeCoach);
    await _applyCoachVoicePreset(activeCoach);

    final encoreOpening = coachBank.pickEncore(Random()) ??
        CoachPhrasesService.instance.current.encoreFallback;

    // Lecture post-_finish du contrôleur précédent : le delta career a
    // déjà été persisté. La sessionScore conservée (`previousSessionHumiliation`)
    // est passée séparément pour démarrer la session-encore avec la
    // chauffe d'avant.
    final humiliationCareer = await _stats.getHumiliationLevel();
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
      humiliationScore: humiliationCareer,
      obedienceScore: obedienceScore,
    );
    // Snapshot des unlocks au démarrage de l'encore — partagé entre le
    // générateur de session et le `SessionController` (qui les repasse au
    // générateur de punition carrière en cas de fail, Phase 5).
    final encoreUnlockedKeys = milestoneService.acquiredUnlockKeys();
    final result = CareerSessionGenerator().generate(
      level: level,
      bank: coachBank,
      includeHand: includeHand,
      encoreChainIndex: encoreChainIndex,
      openingPhrase: encoreOpening,
      quickie: quickie,
      // Le bouton « J'en veux encore » est une escalade explicite : on
      // bascule la séance suivante en mode `intense` — plancher de
      // difficulté solide, comforts boostés (cf. `CapabilityClamps`),
      // first step direct sur `to: full` (borné milestone), BPM cap
      // finish relevé, tier des phrases bumpé. L'`encoreChainIndex`
      // continue de scaler en plus (boosts, BPM, durée finale, plancher).
      intense: true,
      specialization: activeCoach.effectiveAllocation(bundle.specialization),
      humiliationCareer: humiliationCareer,
      humiliationSession: previousSessionHumiliation,
      obedience: obedienceScore,
      unlockedKeys: encoreUnlockedKeys,
      coachModeWeights: activeCoach.modeWeights,
      sessionName: t.careerSessionName(level),
      sessionNameQuickie: t.careerSessionNameQuickie(level),
      anatomy: widget.userProfile.anatomy,
      // 2ᵉ enveloppe : profil persisté + plafonds figés par les fails de la
      // séance qu'on prolonge (l'encore est une continuation — comme on lui
      // repasse la chauffe `seedHumiliationSession`, on lui repasse les
      // plafonds de capacité). Le nouveau contrôleur repart sinon sur un
      // tracker vide.
      capability: CapabilityInputs(
        profile: bundle.capabilityProfile,
        sessionCeilings: previousSessionCeilings,
      ),
      scriptedBreaks: bundle.scriptedBreaks,
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
          capabilityOverloadAxis: result.overloadAxis,
          capabilityProfile: bundle.capabilityProfile,
          // Phase 5 — punitions carrière côté SessionController utilisent
          // les mêmes unlocks et le même toggle hand que le générateur
          // principal.
          unlockedKeys: encoreUnlockedKeys,
          includeHand: includeHand,
          // Pas d'introText : on saute le panel d'intro et le décompte.
          // L'opening phrase est déjà jointe au step #0 de la session.
          phraseBank: coachBank,
          autoStart: true,
          holdVerifier: verifier,
          canSave: true,
          coachAdvancesTier: coachAdvances,
          specialization: bundle.specialization,
          miniPunishmentRate: activeCoach.miniPunishmentRate,
          coachTag: activeCoach.slug,
          // Conserve la chauffe accumulée par la session précédente : on
          // « repart d'où on était » côté humiliation intra-session.
          seedHumiliationSession: previousSessionHumiliation,
          onRequestUpgrade: (ctrl) => _handleUpgrade(ctrl, bundle, level),
          onRequestEncore: !canChainEncore
              ? null
              : (ctrl) => _handleEncore(
                    context: context,
                    bundle: bundle,
                    previousController: ctrl,
                    level: level,
                    encoreChainIndex: encoreChainIndex + 1,
                    includeHand: includeHand,
                    quickie: quickie,
                    hideTimer: hideTimer,
                  ),
          onPostChallengeRegen: (ctrl) => _handlePostChallengeRegen(
            ctrl,
            bundle,
            level,
            includeHand,
          ),
          onChallengeOutcome: (ch, _) {
            unawaited(_challengeService.incrementAttempts(ch.axis));
          },
          anatomy: widget.userProfile.anatomy,
          hideTimerOverride: hideTimer,
        ),
      ),
    );

    if (verifier != null) camService.stopSessionDetection();
    widget.tts.setNameResolver(null);
    await widget.tts.takeVoiceLead(widget.tts.restoreDefaultVoicePreset);

    // Reload du bundle après le retour de la séance encore : le `_start`
    // initial avait déjà reloadé au moment du pushReplacement, mais à ce
    // moment la session encore venait juste de démarrer (max non encore
    // bumpé). Ici on est de retour pour de bon → on relit prefs à jour.
    if (!mounted) return;
    setState(() {
      _bundleFuture = _loadBundle();
      _selectedLengthChoice = null;
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
          // Phase 19.12 : difficulté + titre dérivent exclusivement de
          // `sessionsCompleted` + `lengthChoice` via le resolver.
          // Gating retabli post-playtest (cf. premier retour test 0.6 —
          // une débutante se retrouvait sur 25-45 min ou bâclée intense
          // sans repère). Constantes définies plus bas.
          final isBacheeUnlocked =
              isSessionLengthBacheeUnlocked(bundle.totalSeconds);
          final isMoyenneUnlocked = isSessionLengthMoyenneUnlocked(
            totalSeconds: bundle.totalSeconds,
            completedSessions: bundle.completedSessions,
          );
          final isLongueUnlocked =
              isSessionLengthLongueUnlocked(bundle.totalSeconds);
          final isAleatoireUnlocked =
              isSessionLengthAleatoireUnlocked(bundle.totalSeconds);
          final persistedChoice =
              _selectedLengthChoice ?? bundle.lastLengthChoice;
          // Fallback sur courte si la choice persistée n'est plus
          // sélectionnable (ex. joueuse reset stats → bachee redevient
          // lockée alors qu'elle l'avait sélectionnée auparavant).
          // Délégué à `resolveSessionLengthChoice` pour que `_start` y
          // passe aussi (sinon la chaîne `_start → générateur` lit la
          // valeur brute et peut lancer une séance que le picker cache).
          final lengthChoice = resolveSessionLengthChoice(
            persisted: persistedChoice,
            bacheeUnlocked: isBacheeUnlocked,
            moyenneUnlocked: isMoyenneUnlocked,
            longueUnlocked: isLongueUnlocked,
            aleatoireUnlocked: isAleatoireUnlocked,
          );
          // `aleatoire` est un méta-choix : son `durationSeconds = 0` casse
          // `resolveForCareer` (palier sans correspondance) et le label de
          // durée. Pour le rendu du picker on retombe sur le palier de tirage
          // moyen (la moyenne) — ça donne une difficulté affichée
          // représentative ; la valeur effective sera tirée dans `_start`.
          final lengthForDisplay = lengthChoice == SessionLengthChoice.aleatoire
              ? SessionLengthChoice.moyenne
              : lengthChoice;
          final cfg = CareerDifficultyResolver.resolveForCareer(
            sessionsCompleted: bundle.completedSessions,
            lengthChoice: lengthForDisplay,
          );
          final durationLabel = lengthChoice == SessionLengthChoice.aleatoire
              ? lengthChoice.localizedDuration(context)
              : formatDurationCompact(context, lengthChoice.durationSeconds);
          final activeCoach = _resolveCoach(bundle);
          final principal = coachService.currentTierPrincipal;
          final isFreeTraining = !coachService.advancesTier(activeCoach);
          final freeSpecPoints = SpecializationService.totalPointsForSeconds(
                bundle.totalSeconds,
              ) -
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
                          // Passe par `evaluate` pour respecter
                          // `lockedTier` et `minPlayerSeconds` (refonte
                          // 0.5.0 : `requiresHands` n'est plus sur le
                          // coach, donc plus jamais bloqué côté hand).
                          final status = coachService.evaluate(
                            principal,
                            playerTotalSeconds: await _stats.getTotalSeconds(),
                          );
                          if (status ==
                                  CoachSelectionStatus.selectedAdvancing ||
                              status ==
                                  CoachSelectionStatus.selectedFreeTraining) {
                            await coachService.selectCoach(principal);
                            if (mounted) setState(() {});
                          }
                        },
                ),
              ],
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
                      // Bloc explicite : `() => x = future()` retourne le
                      // Future, ce que setState refuse (cf. issue #63).
                      setState(() {
                        _bundleFuture = _loadBundle();
                      });
                    },
                  ),
                ),
              _SectionLabel(
                title: t.careerDurationSection,
              ),
              const SizedBox(height: 8),
              _DurationPicker(
                value: lengthChoice,
                isBacheeUnlocked: isBacheeUnlocked,
                isMoyenneUnlocked: isMoyenneUnlocked,
                isLongueUnlocked: isLongueUnlocked,
                isAleatoireUnlocked: isAleatoireUnlocked,
                onChanged: (v) => setState(() => _selectedLengthChoice = v),
              ),
              const SizedBox(height: 8),
              _LevelTitleCard(
                title: localizedCareerLevelTitle(context, cfg.level),
                durationLabel: durationLabel,
              ),
              const SizedBox(height: 12),
              // Phase 19.11 — barre de temps cumulé segmentée par tier
              // coach. Remplace progressivement la valorisation par level
              // au profit de l'investissement (= temps + sessions).
              _InvestmentBar(
                totalSeconds: bundle.totalSeconds,
                sessionsCompleted: bundle.completedSessions,
                coaches: coachService.coaches,
              ),
              const SizedBox(height: 24),
              // Switch « Défis intra-séance » (Phase 1). Visible dès la
              // première séance — l'utilisatrice doit pouvoir l'activer si
              // elle veut accélérer sa progression. Le tutoriel scripté
              // garantit la pédagogie au 1ᵉʳ défi.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.careerChallengesToggle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  t.careerChallengesDescription,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
                value: _challengesEnabled,
                onChanged: (v) async {
                  setState(() => _challengesEnabled = v);
                  await _challengeService.setEnabled(v);
                },
              ),
              // Switch « stimulation à la main » (Phase 19.12 : plus de
              // gate par niveau, toujours visible). Si une milestone
              // pending impose les mains, on force ON + désactive le
              // toggle pour que le label « Verrouillé pour cette séance »
              // soit cohérent avec le comportement (sinon l'utilisatrice
              // pouvait désactiver malgré le message — confus côté UX,
              // retour playtest 0.6).
              () {
                final pendingMilestone = milestoneService.pendingFor(
                  humiliationScore: bundle.humiliationScore,
                  obedience: bundle.obedienceScore,
                  playerLevel: bundle.synthLevel,
                  allocation: bundle.specialization,
                  capabilityProfile: bundle.capabilityProfile,
                );
                final milestoneLocksHand =
                    pendingMilestone?.requiresHands ?? false;
                final subtitle = milestoneLocksHand
                    ? t.careerIncludeHandMilestoneLocked
                    : t.careerIncludeHandSubtitle;
                final value = milestoneLocksHand
                    ? true
                    : (_includeHandOverride ?? bundle.includeHand);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.careerIncludeHandToggle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  value: value,
                  onChanged: milestoneLocksHand
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
                  onPressed: hasPendingSpecPoints ? null : () => _start(bundle),
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

/// Picker de durée de séance — 5 paliers (bâclée/courte/moyenne/longue/
/// aléatoire).
///
/// Remplace `_LevelPicker` (Phase 19.4). Depuis le retour playtest 0.6,
/// les paliers sont gatés par investissement (totalSeconds + sessions),
/// et les paliers non débloqués sont **cachés** plutôt que grisés
/// (révélation progressive par surprise, pas de carrot dangling). Les
/// 4 flags `is*Unlocked` sont donc load-bearing — ne pas les supposer
/// constants.
///
/// Seuils de déverrouillage des paliers :
/// - Bâclée : 30 min de jeu cumulé (intense dès le départ → on attend
///   un peu d'acclimatation). Pas de bypass session : l'asymétrie avec
///   Moyenne est intentionnelle — Bâclée est un format « pression
///   maximale immédiate » qui demande un repère d'endurance, pas juste
///   une preuve de format tenu.
/// - Moyenne : 10 min de jeu OU 1 séance complétée (on évite qu'une
///   débutante se lance sur 25 min avant d'avoir testé une courte).
/// - Longue : 1 h de jeu cumulé (≈ avoir tenu au moins une Moyenne
///   entière ou plusieurs Courtes ; pas de bypass session pour éviter
///   qu'une Bâclée de 6 min ne déverrouille un format 45 min).
/// - Aléatoire : 3 h de jeu cumulé. Le palier tire au sort la durée
///   effective parmi courte/moyenne/longue à chaque démarrage (timer
///   masqué pendant la séance). On veut que la joueuse ait *vécu* les
///   trois formats au moins une fois statistiquement — pas juste les
///   avoir débloqués sur le papier — avant de pouvoir tomber sur 45 min
///   surprise.
const int kSessionLengthBacheeUnlockTotalSeconds = 1800;
const int kSessionLengthMoyenneUnlockTotalSeconds = 600;
const int kSessionLengthLongueUnlockTotalSeconds = 3600;
const int kSessionLengthAleatoireUnlockTotalSeconds = 10800;

/// Vrai si la palier « Bâclée » est sélectionnable pour la joueuse.
@visibleForTesting
bool isSessionLengthBacheeUnlocked(int totalSeconds) {
  return totalSeconds >= kSessionLengthBacheeUnlockTotalSeconds;
}

/// Vrai si le palier « Moyenne » (25 min) est sélectionnable. Le « OU »
/// est volontaire : une joueuse qui a complété une séance courte a prouvé
/// qu'elle tenait le format, peu importe le wallclock cumulé.
@visibleForTesting
bool isSessionLengthMoyenneUnlocked({
  required int totalSeconds,
  required int completedSessions,
}) {
  return completedSessions >= 1 ||
      totalSeconds >= kSessionLengthMoyenneUnlockTotalSeconds;
}

/// Vrai si le palier « Longue » (45 min) est sélectionnable. Pas de
/// bypass par séance complétée : une Bâclée de 6 min ne suffit pas à
/// faire signer pour 45 min — il faut avoir tenu un volume comparable
/// (≈ une Moyenne entière ou plusieurs Courtes).
@visibleForTesting
bool isSessionLengthLongueUnlocked(int totalSeconds) {
  return totalSeconds >= kSessionLengthLongueUnlockTotalSeconds;
}

/// Vrai si le palier « Aléatoire » est sélectionnable. Cf. le bloc de
/// commentaire au-dessus pour le pourquoi du seuil (3 h cumulées).
@visibleForTesting
bool isSessionLengthAleatoireUnlocked(int totalSeconds) {
  return totalSeconds >= kSessionLengthAleatoireUnlockTotalSeconds;
}

/// Résout le choix de durée effectif en clamp ant à `courte` quand le
/// palier persisté n'est plus déverrouillé. Helper partagé entre `build`
/// (pour le rendu du picker) et `_start` (pour la génération + persistance),
/// sinon `_start` lit `bundle.lastLengthChoice` brut et peut lancer une
/// séance à une durée que le picker cache (bug détecté en review PR #249).
///
/// Switch **exhaustif** sur tous les cas de `SessionLengthChoice` — pas
/// de `_` catch-all : ajouter une 5ᵉ valeur d'enum déclenche une erreur
/// de compilation explicite et force le maintenant à choisir.
@visibleForTesting
SessionLengthChoice resolveSessionLengthChoice({
  required SessionLengthChoice persisted,
  required bool bacheeUnlocked,
  required bool moyenneUnlocked,
  required bool longueUnlocked,
  required bool aleatoireUnlocked,
}) {
  return switch (persisted) {
    SessionLengthChoice.bachee =>
      bacheeUnlocked ? persisted : SessionLengthChoice.courte,
    SessionLengthChoice.moyenne =>
      moyenneUnlocked ? persisted : SessionLengthChoice.courte,
    SessionLengthChoice.longue =>
      longueUnlocked ? persisted : SessionLengthChoice.courte,
    SessionLengthChoice.aleatoire =>
      aleatoireUnlocked ? persisted : SessionLengthChoice.courte,
    SessionLengthChoice.courte => persisted,
  };
}

class _DurationPicker extends StatelessWidget {
  final SessionLengthChoice value;
  final bool isBacheeUnlocked;
  final bool isMoyenneUnlocked;
  final bool isLongueUnlocked;
  final bool isAleatoireUnlocked;
  final ValueChanged<SessionLengthChoice> onChanged;

  const _DurationPicker({
    required this.value,
    required this.isBacheeUnlocked,
    required this.isMoyenneUnlocked,
    required this.isLongueUnlocked,
    required this.isAleatoireUnlocked,
    required this.onChanged,
  });

  bool _isUnlocked(SessionLengthChoice c) {
    switch (c) {
      case SessionLengthChoice.bachee:
        return isBacheeUnlocked;
      case SessionLengthChoice.moyenne:
        return isMoyenneUnlocked;
      case SessionLengthChoice.longue:
        return isLongueUnlocked;
      case SessionLengthChoice.aleatoire:
        return isAleatoireUnlocked;
      case SessionLengthChoice.courte:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Révélation progressive : on cache purement et simplement les paliers
    // pas encore déverrouillés. Pas d'annonce du seuil — la joueuse les
    // découvre au moment où ils apparaissent (effet de surprise plutôt
    // que carrot dangling).
    final visible =
        SessionLengthChoice.values.where(_isUnlocked).toList(growable: false);
    // Defensive : `value` doit toujours être visible pour qu'une carte soit
    // highlighted. Le caller doit clamp via `resolveSessionLengthChoice`
    // avant de passer la valeur — sans ce clamp, le Row rend 0 carte
    // sélectionnée silencieusement (pas de crash, pas de visuel).
    assert(
        visible.contains(value),
        '_DurationPicker.value ($value) doit être dans visible ($visible) — '
        'utiliser `resolveSessionLengthChoice` côté caller');
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          Expanded(
            child: _DurationChoiceCard(
              label: visible[i].localizedLabel(context),
              duration: visible[i].localizedDuration(context),
              selected: visible[i] == value,
              onTap: () => onChanged(visible[i]),
            ),
          ),
          if (i != visible.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DurationChoiceCard extends StatelessWidget {
  final String label;
  final String duration;
  final bool selected;
  final VoidCallback onTap;

  const _DurationChoiceCard({
    required this.label,
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = AppTheme.accent;
    final bg = selected ? accent.withValues(alpha: 0.18) : AppTheme.surface;
    final borderColor = selected ? accent : accent.withValues(alpha: 0.25);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              duration,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
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

/// Barre de temps cumulé segmentée par tiers coach (Phase 19.11). Affiche :
/// - le temps total joué (« 10 h 23 min »)
/// - les sessions complétées (« 23 séances »)
/// - une barre horizontale avec marqueurs pour chaque seuil tier coach
///   (Lina à 0, Hélène à 1 h, Jade à 3 h, etc.) et un curseur sur la
///   position actuelle
/// - une ligne de teaser sur le prochain coach à débloquer
///   (« Prochain coach : Morgan (1 h 47 min) ») ou un message si tous
///   sont débloqués
class _InvestmentBar extends StatelessWidget {
  final int totalSeconds;
  final int sessionsCompleted;
  final List<Coach> coaches;

  const _InvestmentBar({
    required this.totalSeconds,
    required this.sessionsCompleted,
    required this.coaches,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    // Principal coachs triés par seuil, ie. les jalons de la barre.
    final principals = [...coaches.where((c) => c.isPrincipal)]..sort((a, b) =>
        a.requirements.minPlayerSeconds
            .compareTo(b.requirements.minPlayerSeconds));

    // Prochain coach non encore débloqué = premier dont le seuil est
    // strictement supérieur à totalSeconds.
    Coach? nextCoach;
    for (final c in principals) {
      if (c.requirements.minPlayerSeconds > totalSeconds) {
        nextCoach = c;
        break;
      }
    }

    // Révélation progressive : la barre s'ancre sur le **prochain** coach
    // à débloquer (= tier+1). On ne montre pas la progression vers les
    // paliers supérieurs encore inconnus (Nyx à 25 h démoralise une
    // débutante à 0 s). Une fois tous débloqués (`nextCoach == null`), on
    // ancre sur le dernier palier pour matérialiser la complétion totale.
    final visiblePrincipals = nextCoach == null
        ? principals
        : principals
            .where((c) =>
                c.requirements.minPlayerSeconds <=
                nextCoach!.requirements.minPlayerSeconds)
            .toList();

    final lastSeuil = visiblePrincipals.isEmpty
        ? 1
        : visiblePrincipals.last.requirements.minPlayerSeconds;
    final barMaxSeconds = lastSeuil;
    final clampedSeconds = totalSeconds.clamp(0, barMaxSeconds);
    final progress = barMaxSeconds == 0 ? 0.0 : clampedSeconds / barMaxSeconds;

    final timeLabel = formatDurationCompact(context, totalSeconds);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                timeLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· ${t.careerInvestmentSessions(sessionsCompleted)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return SizedBox(
                height: 24,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Track de fond
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppTheme.textMuted.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    // Progression
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    // Marqueurs tiers (jalons) — bornés à `visiblePrincipals`
                    // pour rester cohérent avec l'ancrage de la barre sur
                    // le prochain coach.
                    for (final c in visiblePrincipals)
                      _TierMarker(
                        leftPx: barMaxSeconds == 0
                            ? 0
                            : (w *
                                    c.requirements.minPlayerSeconds /
                                    barMaxSeconds)
                                .clamp(0.0, w),
                        unlocked:
                            c.requirements.minPlayerSeconds <= totalSeconds,
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            nextCoach == null
                ? t.careerInvestmentAllUnlocked
                : t.careerInvestmentNextCoach(
                    nextCoach.name,
                    formatDurationCompact(
                      context,
                      nextCoach.requirements.minPlayerSeconds - totalSeconds,
                    ),
                  ),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierMarker extends StatelessWidget {
  final double leftPx;
  final bool unlocked;

  const _TierMarker({required this.leftPx, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: leftPx - 4, // centre la pastille sur le seuil
      child: Container(
        width: 8,
        height: 12,
        decoration: BoxDecoration(
          color: unlocked
              ? AppTheme.accent
              : AppTheme.textMuted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
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
              CoachPortrait(
                coach: coach,
                height: 64,
                width: 46,
                borderRadius: BorderRadius.circular(10),
                accent: accent,
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
  final int completedSessions;
  final bool includeHand;
  final SpecializationAllocation specialization;

  /// Niveau synthétique (Phase 19.12) dérivé de `completedSessions` via
  /// `CareerDifficultyResolver.resolveForCareer`. Remplace le `maxLevel`
  /// retiré : sert au titre level affiché et aux call sites internes
  /// qui consomment encore un `level` int (filtre milestone `minLevel`,
  /// nom de session…).
  final int synthLevel;

  /// Humiliation lifetime persistée (`StatsService.getHumiliationLevel`).
  /// Sert au filtre de candidature des milestones (`pendingFor`) au build
  /// de l'écran et au _start.
  final double humiliationScore;

  /// Obédiance lifetime persistée — module la tolérance d'humil pour le
  /// filtre milestone (`humilTolerance = 1 + obedience/50`).
  final double obedienceScore;

  /// Profil de capacités persisté (2ᵉ enveloppe de difficulté, carrière
  /// uniquement). Passé tel quel aux `generate(...)` pour borner les steps
  /// au `comfort` (= `best` naïf en Phase 2) de chaque axe pilotant. Vide
  /// (mais non null) pour une joueuse neuve → aucun gating capacité.
  final CapabilityProfile capabilityProfile;

  /// Toggle Phase 1 défis (`challenges.enabled`). Quand `true`, un défi
  /// intra-séance est généré et inséré vers 60 % de la durée.
  final bool challengesEnabled;

  /// Flag posé après le 1ᵉʳ défi terminé. Quand `false`, le défi suivant
  /// est forcé en tutoriel scripté (hold throat 5 s, axe robuste).
  final bool challengeTutorialSeen;

  /// Dernier palier de durée choisi (Phase 19.4). Défaut `courte` quand
  /// rien n'est encore persisté.
  final SessionLengthChoice lastLengthChoice;

  /// Temps total cumulé (en secondes) persisté dans le `StatsService`.
  /// Sert au déblocage des coachs par investissement (Phase 19.10).
  final int totalSeconds;

  /// Préférence utilisateur `pref.scripted_breaks` (issue #77), on par défaut.
  /// Quand `true`, les postures imposées + breaks scénarisés sont activés.
  /// Passé à `generate(scriptedBreaks:)` sur les deux entrées qui construisent
  /// un contrôleur frais (`_start`, `_handleEncore`) — pas aux régens
  /// mi-séance, qui swappent `_session` en vol et repartent sans break (cf.
  /// reset d'état dans `requestUpgrade`).
  final bool scriptedBreaks;

  const _CareerBundle({
    required this.bank,
    required this.punishments,
    required this.comments,
    required this.completedSessions,
    required this.includeHand,
    required this.specialization,
    required this.humiliationScore,
    required this.obedienceScore,
    required this.capabilityProfile,
    required this.challengesEnabled,
    required this.challengeTutorialSeen,
    required this.lastLengthChoice,
    required this.totalSeconds,
    required this.synthLevel,
    required this.scriptedBreaks,
  });
}
