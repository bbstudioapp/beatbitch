import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/format_helpers.dart';
import '../../services/tts_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coach_voice_picker.dart';
import '../models/coach.dart';
import '../services/coach_service.dart';
import '../widgets/coach_portrait.dart';

/// Écran de sélection du coach. Renvoie le `Coach` choisi via `Navigator.pop`,
/// ou `null` si l'utilisateur revient en arrière sans choisir.
///
/// Affiche tous les coachs du catalogue : débloqués sélectionnables,
/// verrouillés grisés. Le Principal du palier courant est mis en avant
/// par un badge dédié. La sélection d'un non-Principal passe par un dialog
/// de confirmation expliquant que la session ne fera pas progresser le palier.
///
/// Porte aussi la ligne « Voix : … » de chaque coach débloqué : c'est ici
/// qu'on regarde un coach, donc ici que la question de sa voix se pose.
class CoachPickerScreen extends StatefulWidget {
  final CoachService service;
  final int playerTotalSeconds;
  final bool handsEnabled;

  /// Sert au réglage de voix par coach (lecture, aperçu, restauration).
  final TtsService tts;

  /// Résout `{name}` dans la phrase d'aperçu, comme au Profil.
  final UserProfileService userProfile;

  const CoachPickerScreen({
    super.key,
    required this.service,
    required this.playerTotalSeconds,
    required this.handsEnabled,
    required this.tts,
    required this.userProfile,
  });

  @override
  State<CoachPickerScreen> createState() => _CoachPickerScreenState();
}

class _CoachPickerScreenState extends State<CoachPickerScreen> {
  /// `null` tant que les voix du moteur n'ont pas répondu : la ligne
  /// n'apparaît qu'une fois qu'elle a quelque chose de vrai à dire.
  CoachVoiceLabels? _voiceLabels;

  @override
  void initState() {
    super.initState();
    if (TtsService.supportsVoiceSelection) _loadVoiceLabels();
  }

  Future<void> _loadVoiceLabels() async {
    final labels =
        await CoachVoiceLabels.load(widget.tts, widget.service.coaches);
    if (!mounted) return;
    setState(() => _voiceLabels = labels);
  }

  /// Ouvre **la** feuille de réglage de voix — celle du Profil, avec sa
  /// restauration de sortie et sa file d'écritures.
  Future<void> _openVoicePicker(Coach coach) async {
    final labels = _voiceLabels;
    if (labels == null) return;
    await showCoachVoicePicker(
      context,
      tts: widget.tts,
      coach: coach,
      userProfile: widget.userProfile,
      labels: labels,
    );
    await _loadVoiceLabels();
  }

  Future<void> _handleTap(BuildContext context, Coach coach) async {
    final status = widget.service.evaluate(
      coach,
      playerTotalSeconds: widget.playerTotalSeconds,
      handsEnabled: widget.handsEnabled,
    );

    final t = AppLocalizations.of(context);
    switch (status) {
      case CoachSelectionStatus.lockedTier:
        _snack(context, t.coachErrorLockedTier(coach.tier));
        return;
      case CoachSelectionStatus.blockedMinPlayerSeconds:
        _snack(
          context,
          t.coachErrorMinPlayerSeconds(
            coach.name,
            formatDurationCompact(
              context,
              coach.requirements.minPlayerSeconds,
            ),
          ),
        );
        return;
      case CoachSelectionStatus.selectedAdvancing:
        await widget.service.selectCoach(coach);
        if (context.mounted) Navigator.of(context).pop(coach);
        return;
      case CoachSelectionStatus.selectedFreeTraining:
        final confirmed = await _confirmFreeTraining(context, coach);
        if (!confirmed) return;
        await widget.service.selectCoach(coach);
        if (context.mounted) Navigator.of(context).pop(coach);
        return;
    }
  }

  Future<bool> _confirmFreeTraining(BuildContext context, Coach coach) async {
    final principal = widget.service.currentTierPrincipal;
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
        animation: widget.service,
        builder: (context, _) {
          // Révélation progressive : on ne dévoile que le palier en cours
          // + le palier juste suivant (= prochain coach à débloquer). Les
          // tiers supérieurs restent cachés — leur existence et identité
          // se révèlent à mesure que la joueuse progresse, pas en flash dès
          // la 1ʳᵉ ouverture du picker.
          final coaches = [...widget.service.coaches]
            ..sort((a, b) => a.tier.compareTo(b.tier))
            ..removeWhere((c) => c.tier > widget.service.currentTier + 1);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: coaches.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = coaches[index];
              final unlocked = widget.service.isUnlocked(c);
              final isCurrentPrincipal =
                  c.isPrincipal && c.tier == widget.service.currentTier;
              final isSelected = widget.service.selectedCoachId == c.id;
              final labels = _voiceLabels;
              return _CoachCard(
                coach: c,
                unlocked: unlocked,
                isCurrentPrincipal: isCurrentPrincipal,
                isSelected: isSelected,
                onTap: () => _handleTap(context, c),
                // Réservé aux coachs débloqués : régler la voix d'un coach
                // qu'on ne joue pas encore n'a pas d'objet ici, et le picker
                // Custom — qui les propose tous — porte déjà leur accroche.
                voiceLabel: unlocked && labels != null
                    ? labels.labelFor(t, c.id)
                    : null,
                onTapVoice: () => _openVoicePicker(c),
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

  /// Voix effective du coach. `null` = pas de ligne (coach verrouillé,
  /// plateforme sans sélection, ou voix pas encore lues).
  final String? voiceLabel;
  final VoidCallback onTapVoice;

  const _CoachCard({
    required this.coach,
    required this.unlocked,
    required this.isCurrentPrincipal,
    required this.isSelected,
    required this.onTap,
    required this.voiceLabel,
    required this.onTapVoice,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoachPortrait(
                  coach: coach,
                  height: 112,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 14),
                Expanded(
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
                      if (voiceLabel != null) ...[
                        const SizedBox(height: 10),
                        CoachVoiceLine(
                          label: voiceLabel!,
                          onTap: onTapVoice,
                        ),
                      ],
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
