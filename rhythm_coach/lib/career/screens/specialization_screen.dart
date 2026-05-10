import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/enum_labels.dart';
import '../../theme/app_theme.dart';
import '../models/specialization.dart';
import '../services/career_progress_service.dart';
import '../services/specialization_service.dart';

/// Écran de répartition des points de spécialisation.
///
/// Affiche le niveau global atteint, le nombre de points acquis et
/// dépensés, six branches avec un bouton + chacune, et un bouton de
/// respec en bas avec cooldown. Pas d'effet sur le générateur en
/// Phase A — l'allocation est lue plus tard par le générateur en
/// Phase B.
class SpecializationScreen extends StatefulWidget {
  const SpecializationScreen({super.key});

  @override
  State<SpecializationScreen> createState() => _SpecializationScreenState();
}

class _SpecializationScreenState extends State<SpecializationScreen> {
  final SpecializationService _spec = SpecializationService();
  final CareerProgressService _progress = CareerProgressService();

  late Future<_SpecBundle> _bundleFuture;

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  Future<_SpecBundle> _loadBundle() async {
    final results = await Future.wait([
      _spec.load(),
      _progress.getMaxLevel(),
      _spec.canRespec(),
      _spec.respecCooldownRemainingHours(),
    ]);
    return _SpecBundle(
      allocation: results[0] as SpecializationAllocation,
      maxLevel: results[1] as int,
      canRespec: results[2] as bool,
      respecCooldownHours: results[3] as int,
    );
  }

  void _reload() {
    setState(() {
      _bundleFuture = _loadBundle();
    });
  }

  Future<void> _invest(SpecializationBranch branch, int maxLevel) async {
    final ok = await _spec.invest(branch, maxLevel);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).specNotEnoughPoints),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _reload();
  }

  Future<void> _confirmRespec(_SpecBundle bundle) async {
    if (!bundle.canRespec) return;
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.specRespecConfirmTitle),
        content: Text(t.specRespecConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.specRespecConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _spec.respec();
    await _progress.decrementMaxLevel();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.specAppBarTitle)),
      body: FutureBuilder<_SpecBundle>(
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
                  t.specLoadError(snapshot.error.toString()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          final bundle = snapshot.data!;
          final cap =
              SpecializationService.totalPointsForLevel(bundle.maxLevel);
          final available = cap - bundle.allocation.totalSpent;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _Header(
                available: available,
                cap: cap,
                spent: bundle.allocation.totalSpent,
                maxLevel: bundle.maxLevel,
              ),
              const SizedBox(height: 16),
              Text(
                t.specIntro,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              for (final meta in SpecializationBranchMeta.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BranchCard(
                    meta: meta,
                    points: bundle.allocation.pointsIn(meta.branch),
                    canInvest: available > 0,
                    onInvest: () => _invest(meta.branch, bundle.maxLevel),
                  ),
                ),
              const SizedBox(height: 12),
              _RespecButton(
                canRespec: bundle.canRespec,
                cooldownHours: bundle.respecCooldownHours,
                onPressed: () => _confirmRespec(bundle),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int available;
  final int cap;
  final int spent;
  final int maxLevel;

  const _Header({
    required this.available,
    required this.cap,
    required this.spent,
    required this.maxLevel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$available',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                t.specPointsAvailableLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.specLevelLabel(maxLevel),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.specSpentLabel(spent, cap),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final SpecializationBranchMeta meta;
  final int points;
  final bool canInvest;
  final VoidCallback onInvest;

  const _BranchCard({
    required this.meta,
    required this.points,
    required this.canInvest,
    required this.onInvest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(meta.icon, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.branch.localizedLabel(context),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta.branch.localizedDescription(context),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                '$points',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.accent,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(context).specPointsUnit,
                style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: canInvest
                  ? AppTheme.accent
                  : AppTheme.surface.withValues(alpha: 0.6),
              foregroundColor: canInvest ? Colors.black : AppTheme.textMuted,
            ),
            onPressed: canInvest ? onInvest : null,
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
    );
  }
}

class _RespecButton extends StatelessWidget {
  final bool canRespec;
  final int cooldownHours;
  final VoidCallback onPressed;

  const _RespecButton({
    required this.canRespec,
    required this.cooldownHours,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: canRespec
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.textMuted.withValues(alpha: 0.3),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: canRespec ? onPressed : null,
        icon: Icon(
          Icons.replay,
          color: canRespec ? AppTheme.accent : AppTheme.textMuted,
          size: 18,
        ),
        label: Text(
          canRespec
              ? AppLocalizations.of(context).specRespecActiveLabel
              : AppLocalizations.of(context)
                  .specRespecCooldownLabel(cooldownHours),
          style: TextStyle(
            fontSize: 13,
            color: canRespec ? AppTheme.textPrimary : AppTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _SpecBundle {
  final SpecializationAllocation allocation;
  final int maxLevel;
  final bool canRespec;
  final int respecCooldownHours;

  const _SpecBundle({
    required this.allocation,
    required this.maxLevel,
    required this.canRespec,
    required this.respecCooldownHours,
  });
}
