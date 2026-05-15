import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
import '../widgets/mode_badge_row.dart';
import '../widgets/movement_animation.dart';
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

  /// Vrai pour une session générée par le mode Carrière. Active la
  /// persistance "session complétée" et l'overlay debug `StaminaBar`.
  final bool isCareer;

  /// Vrai pour les sessions bâclées (toggle "Session bâclée" en Carrière).
  /// À la fin, déclenche `StatsService.recordQuickieCompleted()` →
  /// alimente le badge VideCouilles. N'a d'effet que si `isCareer = true`.
  final bool isQuickie;

  /// Profil d'endurance projeté seconde par seconde, fourni par le
  /// générateur. Consommé par l'overlay debug uniquement.
  final List<double>? staminaProfile;

  /// Callback de l'action « Supplier » (mode Carrière). Reçoit le
  /// controller pour pouvoir appeler `requestUpgrade(...)` après avoir
  /// régénéré une suite plus dure. Si null, le bouton n'est pas affiché.
  final Future<void> Function(SessionController controller)? onRequestUpgrade;

  /// Callback de l'action « Termine-moi » (mode Custom). Reçoit le
  /// controller pour appeler `requestUpgrade(...)` avec une mini-session
  /// « boosts + final » qui clôt la séance. Si null, le bouton n'est pas
  /// affiché (carrière, scénario, …).
  final Future<void> Function(SessionController controller)? onRequestFinishNow;

  /// Mode « non-stop » (Custom) : quand la séance se termine, on appelle
  /// automatiquement [onRequestEncore] après un court délai (le temps que
  /// le chime sonne) pour enchaîner le cycle suivant — sauf si l'utilisateur
  /// a déclenché « Termine-moi ». Le bouton « encore » de l'écran de fin
  /// reste là (= « continuer tout de suite »).
  final bool autoContinueOnFinish;

  /// Texte d'introduction lu par la coach avant le démarrage effectif
  /// (mode Carrière). Si non null, l'écran affiche d'abord la phase
  /// d'intro avec un bouton « Je suis prête ».
  final String? introText;

  /// Banque de phrases optionnelle (mode Carrière). Sert au TTS
  /// d'annonce des seuils de progression. Null pour les sessions statiques.
  final PhraseBank? phraseBank;

  /// Texte du bouton de fin (état finished). Si null, utilise la valeur
  /// localisée par défaut (« Merci ! » en FR).
  /// Permet de personnaliser pour les sessions statiques (« Retour »…).
  final String? endButtonLabel;

  /// Callback déclenché par le bouton « J'en veux encore… » de l'écran
  /// finished. Si null, le bouton n'apparaît pas (sessions statiques).
  final Future<void> Function(SessionController controller)? onRequestEncore;

  /// Callback consommé par `SessionController.onMilestoneRetry` quand un
  /// fail tombe dans la fenêtre milestone et qu'un retry est encore
  /// disponible. Doit retourner `true` si le retry a été géré (le
  /// controller saute alors le flow fail standard). Null = pas de retry,
  /// flow fail standard à chaque fail.
  final Future<bool> Function(SessionController controller)? onMilestoneRetry;

  /// Si true, démarre la session automatiquement (sans bouton play et
  /// sans décompte d'intro). Utilisé pour les sessions « encore » qui
  /// enchaînent directement depuis l'écran finished précédent.
  final bool autoStart;

  /// Vérification caméra des holds, optionnelle. Si fourni, le controller
  /// s'en sert pour armer/désarmer pendant les steps `mode: hold`. Null =
  /// fonctionnement classique.
  final HoldVerifier? holdVerifier;

  /// Si true, l'écran finished affiche un bouton « Sauvegarder cette
  /// séance » qui sérialise `controller.session` (donc avec d'éventuels
  /// upgrades Supplier intégrés) en JSON dans Documents/saved_sessions/,
  /// pour la rejouer plus tard depuis l'écran SCÉNARIO.
  final bool canSave;

  /// Niveau de la session carrière (utilisé pour décider d'un éventuel
  /// level-up à la complétion). Null pour sessions hors carrière.
  final int? careerLevel;

  /// Axe de capacité surchargé sur cette séance (mode carrière). Null sinon.
  /// Transmis tel quel au [SessionController] pour les phrases `record` du
  /// coach (Phase 4 — on annonce l'exploit qu'on a poussé exprès).
  final CapabilityAxis? capabilityOverloadAxis;

  /// Snapshot du profil de capacités au début de la séance (mode carrière).
  /// Null sinon. Transmis au [SessionController] pour l'attribution du tap-out
  /// (phrase `tapout`) et la détection des records (phrase `record`).
  final CapabilityProfile? capabilityProfile;

  /// `UnlockKey` acquittés à l'ouverture de la séance — transmis tel quel au
  /// [SessionController] qui les passe au `CareerSessionGenerator` pour
  /// générer des punitions carrière contextuelles (Phase 5). Null hors
  /// carrière → set vide côté contrôleur → pas de génération de punition.
  final Set<UnlockKey>? unlockedKeys;

  /// Toggle joueuse « inclure le mode hand » — mirroir de la valeur passée au
  /// `CareerSessionGenerator.generate(...)` pour le tirage initial. Transmis
  /// tel quel au [SessionController] pour exclure les compositions de
  /// punition impliquant la main (`biffle_burst`) quand la joueuse a
  /// désactivé hand. Default `true` → comportement historique inchangé hors
  /// carrière.
  final bool includeHand;

  /// Si false, la session ne peut pas faire progresser le niveau global
  /// même si toutes les autres conditions sont réunies. Utilisé pour
  /// gater le level-up sur le système de coachs : seules les sessions
  /// menées avec le Coach Principal du palier courant comptent.
  /// Default true → comportement historique inchangé pour les écrans
  /// (mode scénario, démos…) qui n'ont pas la notion de coach.
  final bool coachAdvancesTier;

  /// Allocation de spécialisation. Consommée par le SessionController pour
  /// la génération de punition carrière contextuelle. Null = hors carrière.
  final SpecializationAllocation? specialization;

  /// Probabilité par minute qu'une mini-punition inopinée se déclenche en
  /// cours de séance (cf. `Coach.miniPunishmentRate`, dérivé de l'archétype
  /// du coach). 0 = jamais — valeur des écrans sans notion de coach.
  final double miniPunishmentRate;

  /// Slug court du coach actif (`lina`, `victoria`, …), extrait de l'`id`
  /// `coach_NN_<slug>` par le caller. Sert à la sélection priorisée des
  /// fonds taggés au nom de la coach (cf. `BackgroundsService.pickForContext`
  /// et `BackgroundTagVocabulary`). Null = pas de coach (voix par défaut,
  /// scénarios, démos).
  final String? coachTag;

  /// Valeur initiale du `sessionScore` d'humiliation au start. Vaut 0
  /// pour une session normale. Sur encore enchaîné, le caller transmet
  /// le `sessionScore` final de la session précédente pour conserver
  /// la chauffe accumulée (cf. modèle 2 thermomètres).
  final double seedHumiliationSession;

  /// Si true, le bouton « Merci » de fin de session minimise l'app (via
  /// `SystemNavigator.pop`) au lieu de revenir à l'écran précédent.
  /// Utilisé pour les sessions surprise déclenchées par notif : la
  /// joueuse a tapé pour une parenthèse — elle attend de retomber sur
  /// son téléphone, pas sur l'arborescence carrière.
  final bool closeAppOnEnd;

  /// Profil anatomique de la joueuse. Sert à révéler la 6ᵉ ligne du
  /// ladder visuel (zone balls) seulement quand la joueuse a la zone
  /// **et** qu'elle a acquitté la milestone d'introduction
  /// (`UnlockKey.lickBalls`). `null` = profil hérité (tout disponible,
  /// mais la zone reste masquée tant que l'unlock n'a pas été acquis).
  final AnatomyProfile? anatomy;

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
    this.miniPunishmentRate = 0.0,
    this.coachTag,
    this.seedHumiliationSession = 0.0,
    this.closeAppOnEnd = false,
    this.anatomy,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  late final SessionController _controller;
  bool _careerRecorded = false;

  /// Nombre de lignes du ladder visuel (`MovementAnimation`). Snapshot
  /// au start : on n'élargit pas dynamiquement si la milestone `lickBalls`
  /// est acquittée pendant la séance (cf. PR2 plan balls — la révélation
  /// vaut pour la **prochaine** séance). 6 lignes seulement quand la
  /// joueuse a la zone ET a déjà appris à la lécher.
  late final int _positionRowCount;

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
      miniPunishmentRate: widget.miniPunishmentRate,
      coachTag: widget.coachTag,
      seedHumiliationSession: widget.seedHumiliationSession,
      // Profil de capacités : suivi uniquement en carrière (Custom = sandbox,
      // scénarios JSON = hors carrière).
      trackCapabilities: widget.isCareer,
      careerLevel: widget.careerLevel ?? 0,
      capabilityOverloadAxis: widget.capabilityOverloadAxis,
      capabilityProfile: widget.capabilityProfile,
      unlockedKeys: widget.unlockedKeys ?? const {},
      includeHand: widget.includeHand,
      isQuickie: widget.isQuickie,
    );
    _controller.onMilestoneRetry = widget.onMilestoneRetry;
    final anatomy = widget.anatomy ?? AnatomyProfile.defaults;
    final ballsRevealed = anatomy.hasBalls &&
        milestoneService.acquiredUnlockKeys().contains(UnlockKey.lickBalls);
    _positionRowCount = ballsRevealed ? 6 : 5;
    if (widget.isCareer) {
      _controller.addListener(_onCareerStateChanged);
    }
    WidgetsBinding.instance.addObserver(this);
    // Si l'utilisatrice a activé le toggle « Vérif caméra des holds » mais
    // que le caller n'a pas pu construire le verifier (perm refusée,
    // calibration manquante, etc. — `buildVerifierIfEnabled` retourne null
    // silencieusement), on l'avertit ici plutôt que de la laisser jouer
    // une session sans le feedback qu'elle a explicitement demandé.
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
    // Pousse l'AppLocalizations dans le controller pour qu'il puisse
    // résoudre une annonce TTS d'unlock par défaut depuis l'ARB côté
    // _finish(). En initState le widget Localizations n'est pas encore
    // accessible — didChangeDependencies est le 1er hook après le mount
    // qui peut lire le contexte localisé, et il rejoue à chaque changement
    // de locale (rebuild MaterialApp via LocaleService).
    _controller.setAppLocalizations(AppLocalizations.of(context));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.isCareer) {
      _controller.removeListener(_onCareerStateChanged);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Quand l'app passe en arrière-plan (home, lock, autre app), on coupe
    // bips/ambiance/TTS pour ne pas laisser tourner du son. La reprise est
    // manuelle : à son retour, l'utilisatrice doit appuyer sur play.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller.pause();
    }
  }

  void _onCareerStateChanged() {
    if (_controller.isFinished && !_careerRecorded) {
      _careerRecorded = true;
      // Règle de level-up : il faut avoir terminé une session **standard**
      // (pas bâclée) **au niveau max actuel**, **sans aucun fail**. Toute
      // autre complétion (en dessous du max, ou bâclée, ou avec fail) ne
      // débloque pas de palier mais reste comptée dans `completed`.
      // Fire-and-forget : la prochaine ouverture de CareerScreen reload
      // les prefs.
      _recordCareerCompletion();
      if (widget.isQuickie) {
        StatsService().recordQuickieCompleted();
      }
    }
  }

  Future<void> _recordCareerCompletion() async {
    final progress = CareerProgressService();
    final currentMax = await progress.getMaxLevel();
    final level = widget.careerLevel ?? 0;
    final atMaxLevel = level >= currentMax;
    // Level-up gaté par milestone : on n'autorise un palier qu'après
    // l'acquittement d'une milestone candidate au niveau courant (ou si
    // aucune ne l'était — catalogue épuisé, pas de piège). On consulte
    // pendingFor avec les scores post-finish (≈ ceux que la séance suivante
    // verra au start) pour rester cohérent avec ce que `pendingFor` choisirait
    // la prochaine fois. Skip si le caller a déjà bloqué le palier (quickie /
    // fail / niveau insuffisant / coach hors palier).
    final cleanSession = !_controller.hadFailThisSession;
    bool hasPendingAtCurrentLevel = false;
    if (atMaxLevel &&
        cleanSession &&
        !widget.isQuickie &&
        widget.coachAdvancesTier) {
      final pending = milestoneService.pendingFor(
        humiliationScore: _controller.humiliation.careerScore,
        obedience: _controller.obedience.score,
        playerLevel: currentMax,
        allocation: widget.specialization,
        capabilityProfile: widget.capabilityProfile,
      );
      hasPendingAtCurrentLevel = pending != null;
    }
    final gateOk = progress.canLevelUp(
      cleanSession: cleanSession,
      isQuickie: widget.isQuickie,
      milestoneAcquittedThisSession: _controller.milestoneAcquittedThisSession,
      hasPendingAtCurrentLevel: hasPendingAtCurrentLevel,
    );
    final levelUp = atMaxLevel && widget.coachAdvancesTier && gateOk;
    await progress.recordSessionCompleted(levelUp: levelUp);
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
  });

  @override
  State<_SessionScreenContent> createState() => _SessionScreenContentState();
}

class _SessionScreenContentState extends State<_SessionScreenContent> {
  double _volume = 1.0;
  bool _showStaminaBar = false;
  bool _showTimer = false;
  bool _showHumiliationBar = false;
  bool _showObedienceBar = false;
  bool _showSalivaBar = false;
  bool _showSessionControls = false;
  bool _showModeBadge = false;
  bool _showSkipSessionButton = false;
  bool _showBackgroundMedia = true;
  bool _showRemainingTime = false;
  bool _upgradeRequested = false;
  bool _upgradeInFlight = false;
  bool _finishNowInFlight = false;
  bool _finishNowDone = false;

  /// Secondes restantes minimum pour que « Termine-moi » soit actif : en
  /// dessous, la mini-session de finish n'aurait plus la place de jouer une
  /// vraie apothéose (le contrôleur passe directement en `finished`).
  static const int _finishNowMinRemainingSeconds = 75;

  /// True tant que l'utilisateur n'a pas validé « Je suis prête » sur l'écran
  /// d'intro. Reste à false si aucun introText n'a été fourni.
  bool _introPending = false;

  /// Texte d'intro avec les `{name}` déjà résolus. Stocké au boot pour que
  /// l'affichage corresponde exactement à ce qui sera lu — sinon, comme le
  /// resolver retire un surnom à chaque appel, l'écrit et le TTS divergent.
  String? _resolvedIntroText;

  /// Compte à rebours en secondes affiché entre la validation de l'intro
  /// et le démarrage effectif de la séance. `null` = pas de compte à
  /// rebours en cours.
  int? _prepCountdown;
  Timer? _prepTimer;

  static const int _prepDurationSeconds = 7;

  /// Délai après la fin de séance avant d'enchaîner le cycle suivant en
  /// mode non-stop — laisse le `finale_chime` + le post-final sonner.
  static const Duration _autoContinueDelay = Duration(seconds: 4);

  /// Controller mémorisé pour le listener d'auto-enchaînement (mode
  /// non-stop). Null si `autoContinueOnFinish == false`.
  SessionController? _autoChainCtrl;

  /// True dès qu'un auto-enchaînement a été programmé pour cette séance —
  /// évite les doubles déclenchements.
  bool _autoChainScheduled = false;

  @override
  void initState() {
    super.initState();
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
      setState(() => _showTimer = value);
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
    debug.getShowBackgroundMedia().then((value) {
      if (!mounted) return;
      setState(() => _showBackgroundMedia = value);
    });
    debug.getShowSessionRemainingTime().then((value) {
      if (!mounted) return;
      setState(() => _showRemainingTime = value);
    });
    if (widget.introText != null && widget.introText!.trim().isNotEmpty) {
      _introPending = true;
      _resolvedIntroText = widget.tts.resolveText(widget.introText!);
      WidgetsBinding.instance.addPostFrameCallback((_) => _speakIntro());
    } else if (widget.autoStart) {
      // Mode « encore » : on enchaîne directement sans intro ni décompte.
      // L'opening phrase est déjà le texte du step #0 de la session.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<SessionController>().start();
      });
    }
  }

  @override
  void dispose() {
    _prepTimer?.cancel();
    _autoChainCtrl?.removeListener(_maybeAutoChain);
    super.dispose();
  }

  /// Listener du controller en mode non-stop : à la fin de séance, programme
  /// l'enchaînement automatique du cycle suivant via [onRequestEncore] —
  /// sauf si l'utilisateur a tapé « Termine-moi » (`_finishNowDone`).
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
    // Le texte est déjà résolu (cf. initState) ; speak retombera sur un
    // pass-through pour le placeholder absent. Garantit que ce qui est lu
    // correspond exactement à ce qui est affiché.
    await widget.tts.speak(text);
  }

  Future<void> _onIntroReady() async {
    if (!_introPending) return;
    // Coupe l'intro tout de suite via un nouveau speak court qui
    // marque le début de la phase de préparation. QUEUE_FLUSH efface
    // l'intro restante et dit clairement « En place » à l'utilisatrice.
    await widget.tts.stop();
    if (!mounted) return;
    setState(() {
      _introPending = false;
      _prepCountdown = _prepDurationSeconds;
    });
    // Annonce courte pour signaler le décompte sans avoir à regarder l'écran.
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
    // Pas de tts.stop() ici : le speak du step à t=0 lancé par start()
    // flush automatiquement l'annonce du décompte via QUEUE_FLUSH. Un
    // stop préalable fait perdre le speak suivant sur Android (race).
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

  /// Ouvre un dialog pour nommer la session, puis l'écrit sur disque.
  /// Capture `controller.session` au moment du clic — donc avec un
  /// éventuel upgrade Supplier déjà intégré (cf. requestUpgrade qui
  /// remplace `_session` en place). Retourne le nom enregistré ou null
  /// si l'utilisateur a annulé.
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

  Future<bool> _confirmExit(BuildContext context) async {
    final ctrl = context.read<SessionController>();
    if (ctrl.isIdle || ctrl.isFinished) return true;

    final t = AppLocalizations.of(context);
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t.sessionStopTitle),
        content: Text(t.sessionStopContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.commonContinue),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
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
    return PopScope(
      canPop: ctrl.isIdle || ctrl.isFinished,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        // Pas d'AppBar pendant le décompte de mise en place : le visuel
        // doit être vraiment centré sur l'écran (sans décalage du titre)
        // et l'utilisatrice n'a aucune interaction à faire à ce moment.
        appBar: inPrep
            ? null
            : AppBar(
                title: Text(ctrl.session.name),
                actions: [
                  if (_showRemainingTime &&
                      (ctrl.isRunning || ctrl.isPaused || ctrl.isFailing) &&
                      ctrl.session.durationSeconds > 0)
                    _RemainingTimeChip(
                      remainingSeconds:
                          (ctrl.session.durationSeconds - ctrl.elapsedSeconds)
                              .clamp(0, ctrl.session.durationSeconds),
                    ),
                ],
              ),
        body: Stack(
          children: [
            // Background d'ambiance derrière toute l'UI. Subtil, animé,
            // n'intercepte aucun tap (IgnorePointer interne). Le toggle
            // utilisateur `showBackgroundMedia` (page SONS) court-circuite
            // les médias et ne rend que le dégradé.
            Positioned.fill(
                child: SessionBackground(mediaEnabled: _showBackgroundMedia)),
            SafeArea(
              child: _introPending
                  ? _IntroPanel(
                      text: _resolvedIntroText!,
                      onReady: _onIntroReady,
                      onReplay: _speakIntro,
                    )
                  : (inPrep
                      ? _PrepCountdownPanel(seconds: _prepCountdown!)
                      : (ctrl.isFinished
                          ? (ctrl.hasPendingBadges
                              // Phase 1 : juste après le post-final. On garde
                              // l'écran de séance (animation, timer, ambiance)
                              // visible, et on superpose un overlay centré avec
                              // les boutons MERCI / ENCORE / SAUVEGARDER. Tap
                              // MERCI → révélation des badges → bascule sur le
                              // panel complet (phase 2) au prochain rebuild
                              // (notifyListeners de revealBadgeUnlocks).
                              ? Stack(
                                  children: [
                                    Positioned.fill(
                                      child: _buildRunningView(ctrl),
                                    ),
                                    Positioned.fill(
                                      child: _FinishedOverlay(
                                        endButtonLabel: widget.endButtonLabel ??
                                            t.sessionFinishedDefaultEnd,
                                        onThanks: ctrl.revealBadgeUnlocks,
                                        onEncore: (widget.onRequestEncore ==
                                                    null ||
                                                _finishNowDone)
                                            ? null
                                            : () =>
                                                widget.onRequestEncore!(ctrl),
                                        onSave: widget.canSave
                                            ? () => _handleSave(ctrl)
                                            : null,
                                      ),
                                    ),
                                  ],
                                )
                              // Phase 2 : badges révélés. Panel complet avec
                              // détails badges + points spé + bouton de sortie.
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
                                  onEncore: (widget.onRequestEncore == null ||
                                          _finishNowDone)
                                      ? null
                                      : () => widget.onRequestEncore!(ctrl),
                                  onSave: widget.canSave
                                      ? () => _handleSave(ctrl)
                                      : null,
                                  elapsedSeconds: ctrl.elapsedSeconds,
                                ))
                          : Stack(
                              children: [
                                Positioned.fill(child: _buildRunningView(ctrl)),
                                // Overlay flou + bouton play centré quand la
                                // séance est en pause. Couvre l'intégralité de
                                // l'écran de jeu, peu importe le mode prod /
                                // debug — la reprise est toujours à un tap.
                                if (ctrl.isPaused)
                                  Positioned.fill(
                                    child: _PausedOverlay(
                                      onResume: ctrl.resume,
                                    ),
                                  ),
                              ],
                            ))),
            ),
            // Halo blanc crémeux du final : par-dessus tout le reste (sauf
            // l'AppBar), s'allume pile quand le `finale_chime` retentit et
            // que la séance tourne encore — quelques giclées irrégulières +
            // pulses de vibration, puis une brume qui se résorbe.
            // Démonté dès qu'on bascule sur le panel de fin Phase 2 (badges
            // révélés) : sinon les résidus blancs restent posés par-dessus
            // et masquent le texte blanc du `_FinishedPanel` (issue #42).
            // La Phase 1 (`_FinishedOverlay`) garde l'overlay : ses boutons
            // ont déjà un voile sombre derrière eux et restent lisibles.
            if (!ctrl.isFinished || ctrl.hasPendingBadges)
              Positioned.fill(
                child: SessionFinaleOverlay(
                  active: ctrl.isRunning && ctrl.finaleChimeStarted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunningView(SessionController ctrl) {
    final showBar = _showStaminaBar && widget.staminaProfile != null;
    // Quand la stamina bar est affichée, on compresse la mise en page
    // pour absorber l'overflow bas (~19 px) sur les petits écrans.
    // On rogne sur la hauteur de l'animation et les espacements
    // verticaux — les Spacer absorbent l'élasticité.
    final animHeight = showBar ? 130.0 : 160.0;
    // Le contenu est wrappé dans un IntrinsicHeight pour qu'on puisse
    // garder les Spacer + permettre un scroll si toutes les barres debug
    // sont activées (sinon overflow ~50 px sur petits écrans).
    return LayoutBuilder(
      builder: (ctx, constraints) => SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: showBar ? 6 : 16,
              ),
              child: Column(
                children: [
                  _StateBadge(state: ctrl.state),
                  SizedBox(height: showBar ? 6 : 12),
                  if (ctrl.isFailing)
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
                  const Spacer(),
                  if (_showTimer)
                    TimerDisplay(
                        elapsed: ctrl.elapsed, total: ctrl.session.duration)
                  else if (ctrl.hasConfig)
                    MovementAnimation(
                      mode: ctrl.currentMode,
                      from: ctrl.currentFrom,
                      to: ctrl.currentTo,
                      bpm: ctrl.currentBpm,
                      height: animHeight,
                      beepEngine: widget.beep,
                      positionRowCount: widget.positionRowCount,
                    )
                  else
                    SizedBox(height: animHeight),
                  SizedBox(height: showBar ? 12 : 24),
                  _CurrentInstruction(
                    // `currentDisplayText` retourne déjà la version résolue
                    // (`{name}` substitué) du dernier texte parlé / phrase de fail.
                    // Le contrôleur résout une fois au speak, donc l'affichage reste
                    // stable entre rebuilds et matche exactement la voix.
                    text: ctrl.currentDisplayText,
                  ),
                  const Spacer(),
                  if (_showSessionControls) ...[
                    _ControlsRow(controller: ctrl),
                    SizedBox(height: showBar ? 10 : 16),
                  ],
                  // L'état pause est signalé par l'overlay flou plein écran
                  // monté un cran au-dessus (cf. `_PausedOverlay` dans `body`).
                  if (widget.isCareer && widget.onRequestUpgrade != null)
                    ListenableBuilder(
                      listenable: milestoneService,
                      builder: (context, _) {
                        // Le bouton « Supplier » n'apparaît qu'après que la milestone
                        // `intro_beg_libre` (niveau 3) ait été acquittée. Avant ça,
                        // l'utilisatrice n'a pas appris à supplier — afficher le
                        // bouton serait incohérent. Le ChangeNotifier déclenche un
                        // rebuild quand le déblocage arrive en cours de séance.
                        if (!milestoneService.hasUnlock(UnlockKey.begLibre)) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SupplierButton(
                              enabled: ctrl.isRunning &&
                                  !_upgradeRequested &&
                                  !_upgradeInFlight,
                              used: _upgradeRequested,
                              onPressed: _onUpgrade,
                            ),
                            SizedBox(height: showBar ? 8 : 12),
                          ],
                        );
                      },
                    ),
                  if (widget.onRequestFinishNow != null && !_finishNowDone) ...[
                    _FinishNowButton(
                      enabled: ctrl.isRunning &&
                          !_finishNowInFlight &&
                          (ctrl.session.durationSeconds -
                                  ctrl.elapsedSeconds) >=
                              _finishNowMinRemainingSeconds,
                      onPressed: _onFinishNow,
                    ),
                    SizedBox(height: showBar ? 8 : 12),
                  ],
                  _FailButton(controller: ctrl),
                  if (_showSkipSessionButton &&
                      (ctrl.isRunning || ctrl.isPaused)) ...[
                    SizedBox(height: showBar ? 8 : 12),
                    Builder(
                      builder: (ctx) => OutlinedButton.icon(
                        onPressed: () => ctrl.debugFinishSuccess(),
                        icon: const Icon(Icons.fast_forward, size: 18),
                        label: Text(
                            AppLocalizations.of(ctx).sessionDebugFinishButton),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.greenAccent,
                          side: const BorderSide(color: Colors.greenAccent),
                          minimumSize: const Size.fromHeight(36),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: showBar ? 10 : 16),
                  _VolumesBlock(
                    ttsVolume: _volume,
                    ambienceVolume: ctrl.ambienceVolume,
                    onTtsVolume: (v) {
                      setState(() => _volume = v);
                      widget.tts.setVolume(v);
                    },
                    onAmbienceVolume: ctrl.setAmbienceVolume,
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

/// Affiche la phase courante du flow fail (phrase / respiration / punition)
/// avec le nom de la punition quand on y est.
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
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Text(
        text!,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 16,
          color: AppTheme.textSecondary,
          height: 1.4,
        ),
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
    // Pendant un fail le bouton play/pause est désactivé : le controller
    // gère lui-même l'enchaînement.
    final disabledByFail = controller.isFailing;
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

/// Overlay plein écran affiché quand `SessionController.isPaused` est vrai.
/// Combine un fond grisé + flou Gaussien sur l'écran de jeu (pour signaler
/// sans ambiguïté que la séance est suspendue) avec un gros bouton play
/// circulaire centré. Tap n'importe où → resume. Le `BackdropFilter` se
/// nourrit du `Stack` parent (running view en `Positioned.fill` derrière).
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

/// Gros bouton rouge plein-largeur. Actif uniquement quand la session
/// tourne et que les punitions sont chargées.
class _FailButton extends StatelessWidget {
  static const Color _failColor = Color(0xFFEF5350);
  static const Color _failColorDark = Color(0xFF8A1A1A);

  final SessionController controller;
  const _FailButton({required this.controller});

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
            padding: const EdgeInsets.symmetric(vertical: 18),
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
    );
  }
}

/// Bouton « SUPPLIER » du mode Carrière. Cliqué une seule fois par séance,
/// déclenche un beg insistant + régénère la suite à un niveau supérieur.
class _SupplierButton extends StatelessWidget {
  static const Color _color = Color(0xFFCE93D8);
  static const Color _colorMuted = Color(0xFF4A2C5C);

  final bool enabled;
  final bool used;
  final VoidCallback onPressed;

  const _SupplierButton({
    required this.enabled,
    required this.used,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = used ? t.sessionBegRequestLabel : t.sessionBegSupplicateLabel;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: enabled ? _color : _colorMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.front_hand,
                  color: enabled ? Colors.black : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: enabled ? Colors.black : Colors.white38,
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

/// Bouton « TERMINE-MOI » du mode Custom. Régénère une mini-session de
/// finition (boosts + final + chime) qui clôt la séance pour de bon.
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

/// Bloc volumes de l'écran de jeu : TTS + ambiance. Le reste (vitesse,
/// voix, sélection d'ambiance) est dans l'écran SONS.
class _VolumesBlock extends StatelessWidget {
  final double ttsVolume;
  final double ambienceVolume;
  final ValueChanged<double> onTtsVolume;
  final ValueChanged<double> onAmbienceVolume;

  const _VolumesBlock({
    required this.ttsVolume,
    required this.ambienceVolume,
    required this.onTtsVolume,
    required this.onAmbienceVolume,
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
        const SizedBox(height: 4),
        _LabeledSlider(
          label: t.sessionAmbienceLabel,
          value: ambienceVolume,
          min: 0.0,
          max: AmbienceEngine.maxVolume,
          onChanged: onAmbienceVolume,
        ),
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

/// Panneau d'introduction affiché avant le démarrage d'une séance Carrière.
/// Pendant l'affichage, le TTS lit le texte ; l'utilisateur valide via le
/// bouton « JE SUIS PRÊTE » pour enchaîner sur la séance.
class _IntroPanel extends StatelessWidget {
  final String text;
  final VoidCallback onReady;
  final Future<void> Function() onReplay;

  const _IntroPanel({
    required this.text,
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

/// Compte à rebours visuel entre la validation de l'intro et le démarrage
/// effectif de la séance. Donne le temps de poser le téléphone et de se
/// mettre en position.
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

/// Overlay affiché en phase 1 (juste après `_finish`, badges encore
/// cachés). Ne couvre pas l'écran : il se superpose à l'animation /
/// timer / ambiance qui restent visibles dessous. Volontairement
/// minimaliste — on veut que la dramaturgie de fin (chime + dernière
/// phrase) s'enchaîne sans rupture visuelle, et que les boutons
/// MERCI / ENCORE soient juste là, en plein milieu, pour valider la
/// sortie quand l'utilisatrice est prête. Tap MERCI → révélation des
/// badges → bascule sur le `_FinishedPanel` complet.
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
            // Voile sombre derrière les boutons : laisse l'animation visible
            // mais améliore la lisibilité — sinon le texte des boutons se
            // fond dans la silhouette / orbe en arrière-plan.
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

/// Panneau affiché quand la séance est terminée. Deux boutons :
/// fermeture (« Merci ! » ou un libellé custom) et, si fourni en
/// callback, relance d'une nouvelle session-encore plus intense
/// (« J'en veux encore… »). Affiche aussi les nouveaux paliers de
/// badges débloqués pendant la séance.
class _FinishedPanel extends StatefulWidget {
  final List<BadgeUnlock> badgeUnlocks;
  final List<LevelMilestone> milestoneUnlocks;
  final bool hasPendingBadges;
  final Future<void> Function() onRevealBadges;
  final String endButtonLabel;
  final VoidCallback onEnd;
  final Future<void> Function()? onEncore;

  /// Si non null, affiche un bouton « Sauvegarder cette séance ». Le
  /// callback retourne le nom donné, ou null si l'utilisateur a annulé.
  final Future<String?> Function()? onSave;

  /// Durée totale écoulée pendant la séance (timeline incluant les sauts
  /// post-fail). Affichée en haut du panel.
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

  /// True tant que l'utilisateur n'a pas tapé MERCI : on cache les
  /// badges. Au tap, on déclenche `onRevealBadges` qui annonce les
  /// paliers via TTS et fait passer le panel en mode « affichage des
  /// badges + boutons de sortie/encore ». Initialisé d'après l'état
  /// du controller : pas de badges en attente → on est déjà en post-
  /// merci, on affiche directement la suite.
  late bool _badgesHidden = widget.hasPendingBadges;

  @override
  void initState() {
    super.initState();
    _refreshSpecPoints();
  }

  Future<void> _refreshSpecPoints() async {
    final maxLevel = await CareerProgressService().getMaxLevel();
    final available = await SpecializationService().availablePoints(maxLevel);
    if (!mounted) return;
    setState(() => _availableSpecPoints = available);
  }

  Future<void> _handleThanks() async {
    if (_badgesHidden) {
      setState(() => _badgesHidden = false);
      await widget.onRevealBadges();
      return;
    }
    // Tant que des points de spécialisation restent à attribuer, on ne
    // laisse pas quitter l'écran : tap suivant = écran d'attribution.
    // L'utilisateur revient ici (panel finished) une fois les points
    // alloués → `_refreshSpecPoints` rafraîchit le state et `setState`
    // rebuild le bouton (qui devient le bouton de sortie).
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
            // En phase 2 (badges révélés) avec des points en attente, on
            // remplace le bouton de sortie par un CTA d'attribution. Tant
            // que les points ne sont pas tous alloués, l'utilisateur ne
            // peut pas quitter l'écran de fin (ni enchaîner un encore).
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

/// Bloc affiché sur l'écran de fin : liste les nouveaux paliers de badges
/// débloqués pendant la séance. Si aucun, affiche un message neutre — pas
/// de honte, c'est juste qu'il n'y a rien de neuf à célébrer.
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

/// Bloc affiché sur l'écran de fin : liste les milestones acquittées
/// pendant cette séance. Caché si la liste est vide (pas d'état neutre :
/// les apprentissages sont des événements, l'absence n'est pas notable).
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

/// Dialog modal pour saisir le nom d'une session sauvegardée. Renvoie le
/// nom (chaîne non vide trimmée) ou null si annulé.
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
