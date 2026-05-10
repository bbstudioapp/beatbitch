import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../models/coach.dart';
import '../models/specialization.dart';
import '../services/coach_service.dart';

/// Écran de sélection du coach. Renvoie le `Coach` choisi via `Navigator.pop`,
/// ou `null` si l'utilisateur revient en arrière sans choisir.
///
/// Affiche tous les coachs du catalogue : débloqués sélectionnables,
/// verrouillés grisés. Le Principal du palier courant est mis en avant
/// par un badge dédié. La sélection d'un non-Principal passe par un dialog
/// de confirmation expliquant que la session ne fera pas progresser le palier.
class CoachPickerScreen extends StatelessWidget {
  final CoachService service;
  final int playerMaxLevel;
  final bool handsEnabled;
  final SpecializationAllocation specialization;

  const CoachPickerScreen({
    super.key,
    required this.service,
    required this.playerMaxLevel,
    required this.handsEnabled,
    required this.specialization,
  });

  Future<void> _handleTap(BuildContext context, Coach coach) async {
    final status = service.evaluate(
      coach,
      playerMaxLevel: playerMaxLevel,
      handsEnabled: handsEnabled,
      branchPoints: specialization.points,
    );

    final t = AppLocalizations.of(context);
    switch (status) {
      case CoachSelectionStatus.lockedTier:
        _snack(context, t.coachErrorLockedTier(coach.tier));
        return;
      case CoachSelectionStatus.blockedRequiresHands:
        _snack(context, t.coachErrorRequiresHands(coach.name));
        return;
      case CoachSelectionStatus.blockedMinLevel:
        _snack(
            context,
            t.coachErrorMinLevel(
                coach.name, coach.requirements.minPlayerLevel));
        return;
      case CoachSelectionStatus.blockedMissingSpecialization:
        _snack(context, t.coachErrorMissingSpecialization);
        return;
      case CoachSelectionStatus.blockedInsufficientBranchPoints:
        final missing = coach.requirements.requiredBranchPoints.entries
            .where((e) => (specialization.points[e.key] ?? 0) < e.value)
            .map((e) =>
                '${SpecializationBranchMeta.forBranch(e.key).label} ≥ ${e.value}')
            .join(', ');
        _snack(
            context, t.coachErrorInsufficientBranchPoints(coach.name, missing));
        return;
      case CoachSelectionStatus.selectedAdvancing:
        await service.selectCoach(coach);
        if (context.mounted) Navigator.of(context).pop(coach);
        return;
      case CoachSelectionStatus.selectedFreeTraining:
        final confirmed = await _confirmFreeTraining(context, coach);
        if (!confirmed) return;
        await service.selectCoach(coach);
        if (context.mounted) Navigator.of(context).pop(coach);
        return;
    }
  }

  Future<bool> _confirmFreeTraining(BuildContext context, Coach coach) async {
    final principal = service.currentTierPrincipal;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final tDialog = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(tDialog.coachFreeTrainingDialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tDialog.coachFreeTrainingDialogBody(coach.name),
                style:
                    const TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
              if (principal != null) ...[
                const SizedBox(height: 12),
                Text(
                  tDialog.coachFreeTrainingDialogHint(principal.name),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tDialog.commonCancel),
            ),
            if (principal != null)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tDialog
                    .coachFreeTrainingDialogChoosePrincipal(principal.name)),
              ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(tDialog.coachFreeTrainingDialogContinueAnyway),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.coachPickerTitle),
      ),
      body: AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final coaches = [...service.coaches]
            ..sort((a, b) => a.tier.compareTo(b.tier));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: coaches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = coaches[index];
              final unlocked = service.isUnlocked(c);
              final isCurrentPrincipal =
                  c.isPrincipal && c.tier == service.currentTier;
              final isSelected = service.selectedCoachId == c.id;
              return _CoachCard(
                coach: c,
                unlocked: unlocked,
                isCurrentPrincipal: isCurrentPrincipal,
                isSelected: isSelected,
                onTap: () => _handleTap(context, c),
              );
            },
          );
        },
      ),
    );
  }
}

class _CoachCard extends StatelessWidget {
  final Coach coach;
  final bool unlocked;
  final bool isCurrentPrincipal;
  final bool isSelected;
  final VoidCallback onTap;

  const _CoachCard({
    required this.coach,
    required this.unlocked,
    required this.isCurrentPrincipal,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final borderColor = isSelected
        ? AppTheme.accent
        : (isCurrentPrincipal
            ? AppTheme.accent.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.06));

    final opacity = unlocked ? 1.0 : 0.45;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t.coachPickerTierLabel(coach.tier),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isCurrentPrincipal)
                      _Badge(
                        icon: Icons.star,
                        label: t.coachBadgePrincipal,
                        color: AppTheme.accent,
                      )
                    else if (unlocked && coach.isPrincipal)
                      _Badge(
                        icon: Icons.history_edu,
                        label: t.coachBadgePalierAcquis,
                        color: AppTheme.textMuted,
                      )
                    else if (unlocked && !coach.isPrincipal)
                      _Badge(
                        icon: Icons.tune,
                        label: t.coachBadgeFreeTraining,
                        color: const Color(0xFFE8B33A),
                      )
                    else
                      _Badge(
                        icon: Icons.lock_outline,
                        label: t.coachBadgeLocked,
                        color: AppTheme.textMuted,
                      ),
                    const Spacer(),
                    if (isSelected)
                      const Icon(Icons.check_circle,
                          color: AppTheme.accent, size: 20),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  coach.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  coach.title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  coach.publicBio,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (coach.requirements.requiresHands) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.pan_tool_alt,
                          size: 14, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        t.coachRequiresHands,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
