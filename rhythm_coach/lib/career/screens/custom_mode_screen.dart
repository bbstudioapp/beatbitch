import 'dart:math';

import 'package:flutter/material.dart';

import '../../controllers/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/enum_labels.dart';
import '../../l10n/format_helpers.dart';
import '../../main.dart' show coachService;
import '../../models/session.dart';
import '../../models/session_step.dart';
import '../../screens/session_screen.dart';
import '../../services/ambience_engine.dart';
import '../../services/beep_engine.dart';
import '../../services/camera_motion_service.dart';
import '../../services/coach_phrases_loader.dart';
import '../../services/hold_verifier.dart';
import '../../services/punishment_loader.dart';
import '../../services/random_comments_loader.dart';
import '../../services/tts_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_theme.dart';
import '../models/coach.dart';
import '../models/custom_session_config.dart';
import '../models/phrase_bank.dart';
import '../services/career_session_generator.dart';
import '../services/custom_config_service.dart';
import '../services/phrase_bank_loader.dart';
import 'custom_config_editor_screen.dart';

/// Écran d'accueil du mode « Custom » : liste des configurations
/// sauvegardées (créer / modifier / dupliquer / supprimer / lancer) et
/// orchestration des séances générées. Joue le rôle que `CareerScreen` tient
/// pour la carrière : il possède le bundle de jeu, génère via
/// `CareerSessionGenerator`, pousse `SessionScreen`, et enchaîne les cycles
/// en mode non-stop (mécanisme d'encore).
class CustomModeScreen extends StatefulWidget {
  final TtsService tts;
  final BeepEngine beep;
  final AmbienceEngine ambience;
  final UserProfileService userProfile;

  const CustomModeScreen({
    super.key,
    required this.tts,
    required this.beep,
    required this.ambience,
    required this.userProfile,
  });

  @override
  State<CustomModeScreen> createState() => _CustomModeScreenState();
}

class _CustomModeScreenState extends State<CustomModeScreen> {
  /// Secondes restantes minimum pour qu'un « Termine-moi » ait un sens (la
  /// mini-session de finition a besoin de place pour son apothéose).
  static const int _finishNowMinRemainingSeconds = 75;

  final CustomConfigService _service = CustomConfigService();
  late Future<_ListBundle> _listFuture;

  /// Bundle de jeu (PhraseBank globale, punitions, commentaires) — chargé
  /// paresseusement au premier lancement de session.
  Future<_RunBundle>? _runBundleFuture;

  @override
  void initState() {
    super.initState();
    _listFuture = _loadList();
  }

  Future<_ListBundle> _loadList() async {
    final configs = await _service.loadAll();
    final lastId = await _service.getLastUsedId();
    return _ListBundle(configs: configs, lastUsedId: lastId);
  }

  void _reloadList() {
    if (!mounted) return;
    // NB: callback `setState` synchrone explicite — un `() => x = future()`
    // évalue l'assignation comme expression, sa valeur est le Future à
    // droite, et `setState` jette « setState() callback argument returned a
    // Future. » (cf. issue #63). Le bloc `{}` garantit un retour void.
    setState(() {
      _listFuture = _loadList();
    });
  }

  Future<_RunBundle> _loadRunBundle() async {
    final results = await Future.wait([
      PhraseBankLoader().load(),
      PunishmentLoader().load(),
      RandomCommentsLoader().load(),
    ]);
    return _RunBundle(
      bank: results[0] as PhraseBank,
      punishments: results[1] as PunishmentBundle,
      comments: results[2] as RandomCommentsBundle,
    );
  }

  // ─── Résolution coach / bank ───────────────────────────────────────────

  Coach? _resolveCoach(String? coachId) {
    if (coachId == null) return null;
    for (final c in coachService.coaches) {
      if (c.id == coachId) return c;
    }
    return null;
  }

  PhraseBank _resolveBank(_RunBundle b, CustomSessionConfig cfg, Coach? coach) {
    if (coach == null) return b.bank;
    return coach.toPhraseBank(
      fallback: b.bank,
      specialization: cfg.resolveSpecialization(),
    );
  }

  RandomCommentsBundle _resolveComments(_RunBundle b, Coach? coach) =>
      coach == null ? b.comments : coach.composeRandomComments(b.comments);

  void _installCoachNameResolver(Coach? coach) {
    if (coach == null ||
        (coach.phrases.nicknames.isEmpty &&
            coach.phrases.coachNicknames.isEmpty)) {
      widget.tts.setNameResolver(null);
      return;
    }
    widget.tts.setNameResolver(
      coach.buildTextResolver(
        userPrenom: widget.userProfile.prenom,
        userNicknames: widget.userProfile.activePool,
        userFallback: widget.userProfile.activePool,
      ),
    );
  }

  Future<void> _applyCoachVoicePreset(Coach? coach) async {
    final preset = coach?.voicePreset;
    if (preset == null || preset.isEmpty) {
      await widget.tts.restoreDefaultVoicePreset();
      return;
    }
    await widget.tts.applyCoachVoicePreset(
      voiceName: preset.voiceName,
      voiceLocale: preset.voiceLocale,
      rate: preset.rate,
      pitch: preset.pitch,
    );
  }

  /// Restaure la voix/résolveur par défaut — mais SEULEMENT si on est de
  /// retour sur cet écran (chaîne terminée). Si un cycle suivant est déjà
  /// actif au-dessus (cas non-stop : la cleanup de la séance précédente
  /// s'exécute après le `pushReplacement` du cycle suivant), on ne touche
  /// à rien pour ne pas écraser le preset du coach que le cycle suivant
  /// vient de poser.
  Future<void> _restoreTtsIfBackHere() async {
    if (!mounted) return;
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrent) return;
    widget.tts.setNameResolver(null);
    await widget.tts.restoreDefaultVoicePreset();
  }

  // ─── Génération ────────────────────────────────────────────────────────

  String _sessionName(CustomSessionConfig cfg) {
    final t = AppLocalizations.of(context);
    final name = cfg.name.trim();
    return t.customSessionName(name.isEmpty ? t.customUnnamed : name);
  }

  CareerGenerationResult _generate(
    PhraseBank bank,
    CustomSessionConfig cfg, {
    required int cycleIndex,
    String? openingPhrase,
  }) {
    return CareerSessionGenerator().generate(
      level: cfg.resolveVirtualLevel(cycleIndex: cycleIndex),
      bank: bank,
      durationSeconds: cfg.resolveDurationSeconds(),
      includeHand: cfg.resolveIncludeHand,
      encoreChainIndex: cfg.resolveEncoreChainIndex(cycleIndex: cycleIndex),
      openingPhrase: openingPhrase,
      specialization: cfg.resolveSpecialization(),
      // Custom = bac à sable : valeurs neutres/élevées pour ne pas être
      // bridé par les thermomètres de carrière.
      obedience: 100.0,
      humiliationCareer: 400.0,
      humiliationSession: 0.0,
      unlockedKeys: const {},
      coachModeWeights: cfg.resolveCoachModeWeights(),
      sessionName: _sessionName(cfg),
      intensityFloorOverride: cfg.resolveIntensityFloor(),
      maxDepthIndexOverride: cfg.maxDepthIndex < 4 ? cfg.maxDepthIndex : null,
      bpmRange: (cfg.bpmMin, cfg.bpmMax),
      holdDurationRange: (cfg.holdDurationMin, cfg.holdDurationMax),
      noStats: true,
    );
  }

  // ─── Lancement / cycles / Termine-moi ──────────────────────────────────

  Future<void> _launchConfig(CustomSessionConfig cfg) async {
    HoldVerifier? verifier;
    try {
      await _service.setLastUsed(cfg.id);
      _runBundleFuture ??= _loadRunBundle();
      final _RunBundle b;
      try {
        b = await _runBundleFuture!;
      } catch (e) {
        _runBundleFuture = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context).customHostLoadError('$e'))),
        );
        return;
      }
      if (!mounted) return;

      final coach = _resolveCoach(cfg.coachId);
      final bank = _resolveBank(b, cfg, coach);
      _installCoachNameResolver(coach);
      await _applyCoachVoicePreset(coach);

      final result = _generate(bank, cfg, cycleIndex: 0);
      final introText = bank.pickIntro(Random());

      final camService = CameraMotionService();
      verifier = await camService.buildVerifierIfEnabled(widget.tts);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SessionScreen(
            session: result.session,
            tts: widget.tts,
            beep: widget.beep,
            ambience: widget.ambience,
            punishmentBundle: b.punishments,
            randomComments: _resolveComments(b, coach),
            isCareer: false,
            staminaProfile: result.staminaProfile,
            introText: introText,
            // Pas d'intro disponible (ex. voix par défaut, coach sans intro)
            // → on démarre direct, sinon l'écran reste bloqué en idle sans
            // bouton play en mode prod.
            autoStart: introText == null,
            phraseBank: bank,
            holdVerifier: verifier,
            canSave: true,
            coachAdvancesTier: false,
            coachTag: coach?.slug,
            specialization: cfg.resolveSpecialization(),
            autoContinueOnFinish: cfg.nonStop,
            onRequestEncore: cfg.nonStop
                ? (ctrl) => _handleCycle(b, bank, coach, cfg, ctrl, 1)
                : null,
            onRequestFinishNow: (ctrl) => _handleFinishNow(bank, cfg, ctrl, 0),
          ),
        ),
      );

      if (verifier != null) CameraMotionService().stopSessionDetection();
      await _restoreTtsIfBackHere();
      _reloadList();
    } catch (e, stack) {
      // Toute exception inattendue dans le flow de lancement (génération,
      // TTS preset, push de la route, init du SessionScreen) — sans ce
      // garde-fou, l'erreur remontait au Future de `_openEditor` et l'écran
      // restait silencieusement sur CustomModeScreen sans feedback (cf.
      // issue #63).
      debugPrint('[custom] _launchConfig failed: $e\n$stack');
      if (verifier != null) CameraMotionService().stopSessionDetection();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).customLaunchError('$e'))),
      );
    }
  }

  Future<void> _handleCycle(
    _RunBundle b,
    PhraseBank bank,
    Coach? coach,
    CustomSessionConfig cfg,
    SessionController prevCtrl,
    int nextCycleIndex,
  ) async {
    await prevCtrl.detachAudio();
    _installCoachNameResolver(coach);
    await _applyCoachVoicePreset(coach);

    final opening = bank.pickEncore(Random()) ??
        CoachPhrasesService.instance.current.encoreFallback;
    final result = _generate(bank, cfg,
        cycleIndex: nextCycleIndex, openingPhrase: opening);

    final camService = CameraMotionService();
    final verifier = await camService.buildVerifierIfEnabled(widget.tts);

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionScreen(
          session: result.session,
          tts: widget.tts,
          beep: widget.beep,
          ambience: widget.ambience,
          punishmentBundle: b.punishments,
          randomComments: _resolveComments(b, coach),
          isCareer: false,
          staminaProfile: result.staminaProfile,
          // Pas d'introText : on enchaîne directement (l'opening est dans
          // le step #0).
          phraseBank: bank,
          autoStart: true,
          holdVerifier: verifier,
          canSave: true,
          coachAdvancesTier: false,
          coachTag: coach?.slug,
          specialization: cfg.resolveSpecialization(),
          autoContinueOnFinish: true,
          onRequestEncore: (ctrl) =>
              _handleCycle(b, bank, coach, cfg, ctrl, nextCycleIndex + 1),
          onRequestFinishNow: (ctrl) =>
              _handleFinishNow(bank, cfg, ctrl, nextCycleIndex),
        ),
      ),
    );

    if (verifier != null) camService.stopSessionDetection();
    await _restoreTtsIfBackHere();
  }

  Future<void> _handleFinishNow(
    PhraseBank bank,
    CustomSessionConfig cfg,
    SessionController ctrl,
    int cycleIndex,
  ) async {
    final remaining = ctrl.session.durationSeconds - ctrl.elapsedSeconds;
    if (remaining < _finishNowMinRemainingSeconds) return;
    const begDuration = 5;
    // ~60 s : avec `intense` (pas de soft-intro) + `intensityFloorOverride`
    // élevé, ça donne une amorce courte, un sprint dur, puis la phase finish
    // (boosts + final + chime). Volontairement plus court que le gate de 75 s
    // pour que « Termine-moi » raccourcisse toujours la séance restante.
    final mini = CareerSessionGenerator()
        .generate(
          durationSeconds: 60,
          level: cfg.resolveVirtualLevel(cycleIndex: cycleIndex) + 2,
          bank: bank,
          includeHand: cfg.includeHand,
          specialization: cfg.resolveSpecialization(),
          intense: true,
          obedience: 100.0,
          humiliationCareer: 400.0,
          humiliationSession: 0.0,
          unlockedKeys: const {},
          coachModeWeights: cfg.resolveCoachModeWeights(),
          intensityFloorOverride: 0.8,
          maxDepthIndexOverride:
              cfg.maxDepthIndex < 4 ? cfg.maxDepthIndex : null,
          bpmRange: (cfg.bpmMin, cfg.bpmMax),
          holdDurationRange: (cfg.holdDurationMin, cfg.holdDurationMax),
          noStats: true,
          sessionName: ctrl.session.name,
        )
        .session;
    final beg = SessionStep(
      time: 0,
      text: bank.pickFor(SessionMode.beg, 'insistent', Random()),
      mode: SessionMode.beg,
      duration: begDuration,
    );
    await ctrl.requestUpgrade(insistentBeg: beg, upcomingSession: mini);
  }

  // ─── Édition de configs ────────────────────────────────────────────────

  Future<void> _openEditor({CustomSessionConfig? config}) async {
    final isNew = config == null;
    final initial = config ?? CustomSessionConfig.defaults();
    final result = await Navigator.of(context).push<CustomEditorResult>(
      MaterialPageRoute(
        builder: (_) =>
            CustomConfigEditorScreen(initial: initial, isNew: isNew),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _service.save(result.config);
    } catch (e, stack) {
      debugPrint('[custom] save failed: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).customSaveError('$e'))),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context).customConfigSavedSnack)),
    );
    _reloadList();
    if (result.launch) {
      await _launchConfig(result.config);
    }
  }

  Future<void> _duplicate(CustomSessionConfig config) async {
    final t = AppLocalizations.of(context);
    final copy = config.copyWith(
      id: _service.newId(),
      name:
          '${config.name.trim().isEmpty ? t.customUnnamed : config.name.trim()}${t.customDuplicateSuffix}',
    );
    await _service.save(copy);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.customConfigSavedSnack)),
    );
    _reloadList();
  }

  Future<void> _confirmDelete(CustomSessionConfig config) async {
    final t = AppLocalizations.of(context);
    final name =
        config.name.trim().isEmpty ? t.customUnnamed : config.name.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.customDeleteConfirmTitle),
        content: Text(t.customDeleteConfirmBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.customActionDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.delete(config.id);
    _reloadList();
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.customAppBarTitle),
        actions: [
          IconButton(
            tooltip: t.customNewConfig,
            icon: const Icon(Icons.add),
            onPressed: _openEditor,
          ),
        ],
      ),
      body: FutureBuilder<_ListBundle>(
        future: _listFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final bundle = snapshot.data!;
          if (bundle.configs.isEmpty) {
            return _EmptyState(onCreate: _openEditor);
          }
          final lastUsed = _findById(bundle.configs, bundle.lastUsedId);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (lastUsed != null) ...[
                _LastUsedCard(
                  config: lastUsed,
                  onLaunch: () => _launchConfig(lastUsed),
                ),
                const SizedBox(height: 20),
              ],
              for (final cfg in bundle.configs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ConfigCard(
                    config: cfg,
                    highlighted: cfg.id == bundle.lastUsedId,
                    onLaunch: () => _launchConfig(cfg),
                    onEdit: () => _openEditor(config: cfg),
                    onDuplicate: () => _duplicate(cfg),
                    onDelete: () => _confirmDelete(cfg),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ListBundle {
  final List<CustomSessionConfig> configs;
  final String? lastUsedId;
  const _ListBundle({required this.configs, required this.lastUsedId});
}

CustomSessionConfig? _findById(List<CustomSessionConfig> list, String? id) {
  if (id == null) return null;
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
}

class _RunBundle {
  final PhraseBank bank;
  final PunishmentBundle punishments;
  final RandomCommentsBundle comments;
  const _RunBundle({
    required this.bank,
    required this.punishments,
    required this.comments,
  });
}

String _configSubtitle(BuildContext context, CustomSessionConfig cfg) {
  final t = AppLocalizations.of(context);
  final durLabel = cfg.nonStop
      ? t.customNonStopBadge
      : formatDurationCompact(context, cfg.resolveDurationSeconds());
  return '$durLabel · ${cfg.difficulty.localizedLabel(context)}';
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 48, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              t.customListEmptyTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.customListEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(t.customNewConfig),
            ),
          ],
        ),
      ),
    );
  }
}

class _LastUsedCard extends StatelessWidget {
  final CustomSessionConfig config;
  final VoidCallback onLaunch;
  const _LastUsedCard({required this.config, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name =
        config.name.trim().isEmpty ? t.customUnnamed : config.name.trim();
    return Material(
      color: AppTheme.accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onLaunch,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.replay, color: AppTheme.accent, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.customLaunchLastTitle,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _configSubtitle(context, config),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow, color: AppTheme.accent, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ConfigAction { edit, duplicate, delete }

class _ConfigCard extends StatelessWidget {
  final CustomSessionConfig config;
  final bool highlighted;
  final VoidCallback onLaunch;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _ConfigCard({
    required this.config,
    required this.highlighted,
    required this.onLaunch,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final name =
        config.name.trim().isEmpty ? t.customUnnamed : config.name.trim();
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onLaunch,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted
                  ? AppTheme.accent.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.accent.withValues(alpha: 0.14),
                child: Icon(
                  config.nonStop ? Icons.all_inclusive : Icons.tune,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _configSubtitle(context, config),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_ConfigAction>(
                icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                onSelected: (a) {
                  switch (a) {
                    case _ConfigAction.edit:
                      onEdit();
                    case _ConfigAction.duplicate:
                      onDuplicate();
                    case _ConfigAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ConfigAction.edit,
                    child: Text(t.customActionEdit),
                  ),
                  PopupMenuItem(
                    value: _ConfigAction.duplicate,
                    child: Text(t.customActionDuplicate),
                  ),
                  PopupMenuItem(
                    value: _ConfigAction.delete,
                    child: Text(t.customActionDelete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
