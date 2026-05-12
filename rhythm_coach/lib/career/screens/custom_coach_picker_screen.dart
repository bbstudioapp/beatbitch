import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../services/coach_service.dart';
import '../widgets/coach_portrait.dart';

/// Sélecteur de coach pour le mode Custom : ligne « Voix par défaut » en
/// tête (= pas de coach : PhraseBank globale + voix TTS système), puis tous
/// les coachs du catalogue, sélectionnables sans condition de progression.
///
/// Retourne via `Navigator.pop` la valeur sélectionnée : `null` pour la
/// voix par défaut, sinon l'id du coach. Pop sans sélection (back système)
/// = pas de changement (le `Navigator.pop()` n'est jamais appelé tout seul,
/// donc l'écran appelant interprète `null` du `await push` comme « annulé »
/// en passant par un wrapper, cf. `CustomConfigEditorScreen`).
///
/// Ne touche pas à `CoachService.selectCoach` : le coach de carrière reste
/// celui choisi côté CARRIÈRE.
class CustomCoachPickerScreen extends StatelessWidget {
  final CoachService service;

  /// Sélection courante (`null` = voix par défaut). Sert juste à mettre en
  /// avant la ligne active à l'ouverture.
  final String? selectedCoachId;

  const CustomCoachPickerScreen({
    super.key,
    required this.service,
    required this.selectedCoachId,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final coaches = service.coaches;
    return Scaffold(
      appBar: AppBar(title: Text(t.customCoachPickerTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _PickerCard(
            title: t.customCoachDefaultVoice,
            subtitle: t.customCoachPickerDefaultSubtitle,
            icon: Icons.record_voice_over_outlined,
            selected: selectedCoachId == null,
            onTap: () =>
                Navigator.of(context).pop(const _CoachPickerResult(null)),
          ),
          const SizedBox(height: 12),
          for (final c in coaches) ...[
            _PickerCard(
              title: c.name,
              subtitle: '${c.title} · ${t.coachPickerTierLabel(c.tier)}',
              icon: Icons.school_outlined,
              leading: CoachPortrait(
                coach: c,
                height: 56,
                width: 40,
                borderRadius: BorderRadius.circular(9),
                accent: selectedCoachId == c.id
                    ? AppTheme.accent
                    : AppTheme.textMuted,
              ),
              selected: selectedCoachId == c.id,
              onTap: () => Navigator.of(context).pop(_CoachPickerResult(c.id)),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// Helper : pousse l'écran et renvoie la sélection. `null` = l'utilisateur
  /// est revenu en arrière sans choisir → pas de changement.
  static Future<({bool changed, String? coachId})?> pick(
    BuildContext context, {
    required CoachService service,
    required String? selectedCoachId,
  }) async {
    final result = await Navigator.of(context).push<_CoachPickerResult>(
      MaterialPageRoute(
        builder: (_) => CustomCoachPickerScreen(
          service: service,
          selectedCoachId: selectedCoachId,
        ),
      ),
    );
    if (result == null) return null;
    return (changed: true, coachId: result.coachId);
  }
}

class _CoachPickerResult {
  final String? coachId;
  const _CoachPickerResult(this.coachId);
}

class _PickerCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Vignette à gauche. `null` = pastille ronde avec [icon] (cas « voix par
  /// défaut »). Pour un coach, on passe ici son [CoachPortrait].
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  const _PickerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.leading,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppTheme.accent : AppTheme.textMuted;
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
            border: Border.all(
              color: selected
                  ? AppTheme.accent.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              leading ??
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: accent.withValues(alpha: 0.16),
                    child: Icon(icon, color: accent, size: 20),
                  ),
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: AppTheme.accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
