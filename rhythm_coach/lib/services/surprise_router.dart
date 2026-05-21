import 'package:flutter/material.dart';

import '../career/models/coach.dart';
import '../career/services/career_difficulty_resolver.dart';
import '../career/services/career_encore_gate.dart';
import '../career/services/career_progress_service.dart';
import '../career/services/generation/career_session_generator.dart';
import '../career/services/phrase_bank_loader.dart';
import '../career/services/specialization_service.dart';
import '../controllers/session_controller.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show coachService, milestoneService;
import '../screens/session_screen.dart';
import '../services/ambience_engine.dart';
import '../services/beep_engine.dart';
import '../services/camera_motion_service.dart';
import '../services/punishment_loader.dart';
import '../services/random_comments_loader.dart';
import '../services/stats_service.dart';
import '../services/surprise_alert_service.dart';
import '../services/tts_service.dart';

class _SurpriseBundle {
  final PhraseBank bank;
  final PunishmentBundle punishments;
  final RandomCommentsBundle comments;
  final SpecializationAllocation specialization;
  final int synthLevel;
  final bool includeHand;

  _SurpriseBundle({
    required this.bank,
    required this.punishments,
    required this.comments,
    required this.specialization,
    required this.synthLevel,
    required this.includeHand,
  });
}

/// Lance une session courte « surprise » sur tap d'une notification.
/// Replique condensée du flow `_CareerScreenState._start` : charge les
/// persistances carrière, génère via `CareerSessionGenerator(quickie: true,
/// durationSeconds: <random 60-240>)`, push `SessionScreen` avec
/// démarrage auto.
///
/// La session est traitée comme une « bâclée » côté stats (alimente le
/// badge VideCouilles), mais avec `coachAdvancesTier: false` pour ne pas
/// faire progresser le coach via cette voie ponctuelle.
class SurpriseRouter {
  SurpriseRouter._();

  static Future<void> launchSession({
    required BuildContext context,
    required TtsService tts,
    required BeepEngine beep,
    required AmbienceEngine ambience,
  }) async {
    final progress = CareerProgressService();
    final stats = StatsService();
    final specService = SpecializationService();

    final results = await Future.wait([
      PhraseBankLoader().load(),
      PunishmentLoader().load(),
      RandomCommentsLoader().load(),
      progress.getCompletedSessions(),
      progress.getIncludeHand(),
      specService.load(),
      stats.getHumiliationLevel(),
      stats.getObedienceLevel(),
      stats.getTotalSeconds(),
      SurpriseAlertService.instance.pickRandomDurationSeconds(),
    ]);
    final bank = results[0] as PhraseBank;
    final punishments = results[1] as PunishmentBundle;
    final comments = results[2] as RandomCommentsBundle;
    final sessions = results[3] as int;
    final persistedIncludeHand = results[4] as bool;
    final specialization = results[5] as SpecializationAllocation;
    final humiliationCareer = results[6] as double;
    final obedienceScore = results[7] as double;
    final totalSeconds = results[8] as int;
    final durationSeconds = results[9] as int;

    if (!context.mounted) return;

    await coachService.syncFromTotalSeconds(totalSeconds);

    // Phase 19.12 : plus de gate hand par niveau — respecte le choix
    // persisté de la joueuse.
    final includeHand = persistedIncludeHand;
    // SynthLevel proxy pour le générateur (Custom path : pas de
    // `lengthChoice` ni `sessionsCompleted` passé, on retombe sur
    // `resolve(level)` legacy).
    final synthLevel = CareerDifficultyResolver.synthLevelFor(sessions);

    final bundle = _SurpriseBundle(
      bank: bank,
      punishments: punishments,
      comments: comments,
      specialization: specialization,
      synthLevel: synthLevel,
      includeHand: includeHand,
    );

    if (!context.mounted) return;
    await _pushSurpriseSession(
      context: context,
      bundle: bundle,
      tts: tts,
      beep: beep,
      ambience: ambience,
      durationSeconds: durationSeconds,
      humiliationCareer: humiliationCareer,
      humiliationSession: 0.0,
      obedienceScore: obedienceScore,
      replace: false,
    );
  }

  static Future<void> _pushSurpriseSession({
    required BuildContext context,
    required _SurpriseBundle bundle,
    required TtsService tts,
    required BeepEngine beep,
    required AmbienceEngine ambience,
    required int durationSeconds,
    required double humiliationCareer,
    required double humiliationSession,
    required double obedienceScore,
    required bool replace,
  }) async {
    final activeCoach = _resolveCoach();
    final coachBank = activeCoach.toPhraseBank(
      fallback: bundle.bank,
      specialization: bundle.specialization,
    );

    final result = CareerSessionGenerator().generate(
      durationSeconds: durationSeconds,
      level: bundle.synthLevel,
      bank: coachBank,
      includeHand: bundle.includeHand,
      // quickie=true : intensityFloor 0.65, intro raccourcie, pas de
      // pré-finition. Cohérent avec le ton « réveil rapide ».
      quickie: true,
      specialization: bundle.specialization,
      humiliationCareer: humiliationCareer,
      humiliationSession: humiliationSession,
      obedience: obedienceScore,
      unlockedKeys: milestoneService.acquiredUnlockKeys(),
      coachModeWeights: activeCoach.modeWeights,
      encoreChainIndex: humiliationSession > 0 ? 1 : 0,
    );

    final canEncore = CareerEncoreGate.canEncore(
      level: bundle.synthLevel,
      humiliationScore: humiliationCareer,
      obedienceScore: obedienceScore,
      milestoneService: milestoneService,
    );

    final camService = CameraMotionService();
    final verifier = await camService.buildVerifierIfEnabled(tts);

    if (!context.mounted) return;

    final route = MaterialPageRoute<void>(
      builder: (_) => SessionScreen(
        session: result.session,
        tts: tts,
        beep: beep,
        ambience: ambience,
        punishmentBundle: bundle.punishments,
        randomComments: activeCoach.composeRandomComments(bundle.comments),
        isCareer: true,
        isQuickie: true,
        careerLevel: bundle.synthLevel,
        staminaProfile: result.staminaProfile,
        phraseBank: coachBank,
        autoStart: true,
        holdVerifier: verifier,
        canSave: false,
        // Pas de progression de coach via une session surprise.
        coachAdvancesTier: false,
        specialization: bundle.specialization,
        seedHumiliationSession: humiliationSession,
        // « Merci » de fin = quitter directement l'app (au lieu de
        // revenir à l'écran précédent). La joueuse a été happée par une
        // notif, on la laisse retomber sur son téléphone.
        closeAppOnEnd: true,
        onRequestEncore: !canEncore
            ? null
            : (ctrl) => _handleEncore(
                  context: context,
                  previousController: ctrl,
                  tts: tts,
                  beep: beep,
                  ambience: ambience,
                  bundle: bundle,
                ),
      ),
    );

    if (replace) {
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }

    if (verifier != null) camService.stopSessionDetection();
    tts.setNameResolver(null);
    await tts.restoreDefaultVoicePreset();
  }

  static Future<void> _handleEncore({
    required BuildContext context,
    required SessionController previousController,
    required TtsService tts,
    required BeepEngine beep,
    required AmbienceEngine ambience,
    required _SurpriseBundle bundle,
  }) async {
    final stats = StatsService();
    final previousSessionHumiliation =
        previousController.humiliation.sessionScore;
    await previousController.detachAudio();
    await stats.recordEncoreAsked();

    final humiliationCareer = await stats.getHumiliationLevel();
    final obedienceScore = await stats.getObedienceLevel();
    final durationSeconds =
        await SurpriseAlertService.instance.pickRandomDurationSeconds();

    if (!context.mounted) return;
    await _pushSurpriseSession(
      context: context,
      bundle: bundle,
      tts: tts,
      beep: beep,
      ambience: ambience,
      durationSeconds: durationSeconds,
      humiliationCareer: humiliationCareer,
      humiliationSession: previousSessionHumiliation,
      obedienceScore: obedienceScore,
      replace: true,
    );
  }

  static Coach _resolveCoach() {
    final selected = coachService.selectedCoach;
    if (selected != null) return selected;
    return coachService.coaches.first;
  }

  /// Liste des bodies localisés à passer à `SurpriseAlertService.arm()`.
  /// Centralisé ici pour pouvoir étendre facilement (ajouter une 4e
  /// variante : ajouter une clé ARB et l'inclure ici).
  static List<String> resolveBodyVariants(AppLocalizations t) {
    return [
      t.surpriseNotifBody1,
      t.surpriseNotifBody2,
      t.surpriseNotifBody3,
    ];
  }
}
