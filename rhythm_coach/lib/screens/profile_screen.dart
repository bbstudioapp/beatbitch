import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../career/services/career_progress_service.dart';
import '../career/services/custom_config_service.dart';
import '../career/services/specialization_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/enum_labels.dart';
import '../l10n/format_helpers.dart';
import '../main.dart' show coachService, milestoneService;
import '../models/badge.dart';
import '../services/badge_service.dart';
import '../services/reputation_service.dart';
import '../services/stats_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/identity_section.dart';

/// Écran Profil : affiche le score de réputation, les stats cumulées,
/// et la grille des badges débloqués / en cours. Hôte aussi le bloc
/// Identité (prénom + surnoms) — déplacé depuis l'écran SONS pour
/// regrouper tout ce qui touche « qui je suis pour la coach ».
class ProfileScreen extends StatefulWidget {
  /// Service de profil utilisateur, partagé avec `ModeSelectionScreen`
  /// (pour que les surnoms restent synchro entre les écrans).
  final UserProfileService userProfile;

  /// TTS partagé, utilisé par la section Identité pour le bouton
  /// « Tester » (lit la phrase d'identité localisée avec substitution
  /// `{name}`). Optionnel : si null, le bouton n'apparaît pas.
  final TtsService? tts;

  const ProfileScreen({
    super.key,
    required this.userProfile,
    this.tts,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ReputationService _rep = ReputationService();
  final BadgeService _badges = BadgeService();
  final StatsService _stats = StatsService();
  final CareerProgressService _career = CareerProgressService();
  final SpecializationService _spec = SpecializationService();
  final CustomConfigService _customConfigs = CustomConfigService();
  late Future<_ProfileBundle> _bundleFuture;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    // Chargement asynchrone — `load()` est idempotent côté service. La
    // section Identité s'abonne ensuite via `addListener` pour rebuild
    // quand prénom / surnoms changent.
    widget.userProfile.load();
    _bundleFuture = _loadBundle();
  }

  Future<_ProfileBundle> _loadBundle() async {
    final repSnap = await _rep.snapshot();
    final badges = await _badges.currentStates(repSnap.stats);
    final packageInfo = await PackageInfo.fromPlatform();
    return _ProfileBundle(
      reputation: repSnap,
      badges: badges,
      packageInfo: packageInfo,
    );
  }

  Future<void> _confirmAndResetAll() async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.profileResetDialogTitle),
        content: Text(t.profileResetDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.profileResetCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.profileResetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _resetting = true);
    await Future.wait([
      _stats.resetAll(),
      _badges.resetAll(),
      _career.resetAll(),
      _spec.resetAll(),
      coachService.resetAll(),
      milestoneService.resetAll(),
      _customConfigs.resetAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _resetting = false;
      _bundleFuture = _loadBundle();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.profileResetDoneSnackbar)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.profileAppBarTitle)),
      body: FutureBuilder<_ProfileBundle>(
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
                  t.profileLoadError(snapshot.error.toString()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          final bundle = snapshot.data!;
          final level = bundle.reputation.maxLevel;
          final title = localizedCareerLevelTitle(context, level);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _ReputationCard(
                title: title,
                level: level,
                score: bundle.reputation.score,
              ),
              const SizedBox(height: 24),
              _SectionLabel(t.soundsIdentitySection),
              const SizedBox(height: 8),
              IdentitySection(
                userProfile: widget.userProfile,
                tts: widget.tts,
              ),
              const SizedBox(height: 24),
              _SectionLabel(t.profileStatsSection),
              const SizedBox(height: 8),
              _StatsBlock(stats: bundle.reputation.stats),
              const SizedBox(height: 24),
              _SectionLabel(t.profileBadgesSection),
              const SizedBox(height: 8),
              _BadgesGrid(states: bundle.badges),
              const SizedBox(height: 32),
              _ResetSection(
                resetting: _resetting,
                onReset: _confirmAndResetAll,
              ),
              const SizedBox(height: 24),
              _AboutSection(info: bundle.packageInfo),
            ],
          );
        },
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  final PackageInfo info;
  const _AboutSection({required this.info});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(t.profileAboutSection),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.profileAboutVersion(
                  info.appName,
                  info.version,
                  info.buildNumber,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.profileAboutOffline,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResetSection extends StatelessWidget {
  final bool resetting;
  final VoidCallback onReset;

  const _ResetSection({required this.resetting, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(t.profileResetSection),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: resetting ? null : onReset,
          icon: resetting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever),
          label: Text(t.profileResetButton),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: const BorderSide(color: Colors.redAccent),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _ReputationCard extends StatelessWidget {
  final String title;
  final int level;
  final int score;

  const _ReputationCard({
    required this.title,
    required this.level,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.18),
            AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium,
                  color: AppTheme.accent, size: 24),
              const SizedBox(width: 8),
              Text(
                t.profileLevel(level),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatLocalizedNumber(context, score),
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t.profileReputationUnit,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: AppTheme.accent,
      ),
    );
  }
}

class _StatsBlock extends StatelessWidget {
  final StatsSnapshot stats;

  const _StatsBlock({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // On masque les stats qui n'ont jamais été incrémentées : on ne veut
    // pas dévoiler les axes possibles (throatfucks, biffles, holds…) à une
    // utilisatrice qui n'y a pas encore touché. Le bloc `gateBy` porte
    // l'entier de référence ; dès qu'il dépasse 0, l'entrée est révélée.
    final entries = <_StatEntry>[
      _StatEntry(t.profileStatSessionsCompleted, '${stats.sessionsCompleted}',
          gateBy: stats.sessionsCompleted),
      _StatEntry(t.profileStatNoFailStreak, '${stats.sessionsNoFailStreak}',
          gateBy: stats.sessionsNoFailStreak),
      _StatEntry(t.profileStatDailyStreak, t.formatDaysShort(stats.dailyStreak),
          gateBy: stats.dailyStreak),
      _StatEntry(t.profileStatTotalTime,
          formatDurationDetailed(context, stats.totalSeconds),
          gateBy: stats.totalSeconds),
      _StatEntry(t.profileStatThroatfucks, '${stats.throatfucks}',
          gateBy: stats.throatfucks),
      _StatEntry(t.profileStatBiffles, '${stats.biffles}',
          gateBy: stats.biffles),
      _StatEntry(t.profileStatHoldFullMax, '${stats.maxHoldFullAtomic} s',
          gateBy: stats.maxHoldFullAtomic),
      _StatEntry(t.profileStatHoldThroatTotal,
          formatDurationDetailed(context, stats.holdThroatSeconds),
          gateBy: stats.holdThroatSeconds),
      _StatEntry(t.profileStatHoldFullTotal,
          formatDurationDetailed(context, stats.holdFullSeconds),
          gateBy: stats.holdFullSeconds),
      _StatEntry(t.profileStatEncores, '${stats.encoresAsked}',
          gateBy: stats.encoresAsked),
      _StatEntry(t.profileStatQuickies, '${stats.quickiesCompleted}',
          gateBy: stats.quickiesCompleted),
      _StatEntry(t.profileStatModesUsed, '${stats.distinctModesUsed} / 8',
          gateBy: stats.distinctModesUsed),
    ].where((e) => e.gateBy > 0).toList(growable: false);

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          t.profileStatsEmpty,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: i == entries.length - 1 ? 6 : 6,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entries[i].label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    entries[i].value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
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

class _StatEntry {
  final String label;
  final String value;

  /// Valeur de référence utilisée pour décider si l'entrée est affichée.
  /// 0 = stat jamais touchée → entrée masquée (on ne révèle pas l'axe).
  final int gateBy;
  const _StatEntry(this.label, this.value, {required this.gateBy});
}

class _BadgesGrid extends StatelessWidget {
  final List<BadgeState> states;

  const _BadgesGrid({required this.states});

  @override
  Widget build(BuildContext context) {
    // On ne dévoile que les badges déjà décrochés au moins en bronze.
    // Les familles à tier=none restent invisibles → pas de spoil sur les
    // axes possibles tant que l'utilisatrice n'a pas commencé à les
    // travailler.
    final unlocked = states.where((s) => s.tier != BadgeTier.none).toList();
    if (unlocked.isEmpty) {
      final t = AppLocalizations.of(context);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          t.profileBadgesEmpty,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        for (final s in unlocked) _BadgeCard(state: s),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final BadgeState state;

  const _BadgeCard({required this.state});

  Color _tierColor() {
    switch (state.tier) {
      case BadgeTier.none:
        return AppTheme.textMuted;
      case BadgeTier.bronze:
        return const Color(0xFFB87333);
      case BadgeTier.silver:
        return const Color(0xFFC0C0C0);
      case BadgeTier.gold:
        return const Color(0xFFFFD700);
      case BadgeTier.platinium:
        return const Color(0xFFE5E4E2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _tierColor();
    final unlocked = state.tier != BadgeTier.none;
    final next = state.nextThreshold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? color.withValues(alpha: 0.6)
              : AppTheme.textMuted.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.emoji_events : Icons.emoji_events_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.tier.localizedLabel(context),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.definition.family.localizedDisplayName(context),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          Text(
            next != null ? '${state.value} / $next' : '${state.value} pts',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBundle {
  final ReputationSnapshot reputation;
  final List<BadgeState> badges;
  final PackageInfo packageInfo;

  const _ProfileBundle({
    required this.reputation,
    required this.badges,
    required this.packageInfo,
  });
}
