import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/tts_service.dart';
import '../../services/user_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coach_voice_picker.dart';
import '../models/coach.dart';
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
///
/// Comme il propose **tout** le catalogue, c'est aussi le seul endroit d'où
/// se règle la voix d'un coach pas encore débloqué en carrière — que le
/// Profil ne liste volontairement pas.
class CustomCoachPickerScreen extends StatefulWidget {
  final CoachService service;

  /// Sélection courante (`null` = voix par défaut). Sert juste à mettre en
  /// avant la ligne active à l'ouverture.
  final String? selectedCoachId;

  /// Sert au réglage de voix par coach (lecture, aperçu, restauration).
  final TtsService tts;

  /// Résout `{name}` dans la phrase d'aperçu, comme au Profil.
  final UserProfileService userProfile;

  const CustomCoachPickerScreen({
    super.key,
    required this.service,
    required this.selectedCoachId,
    required this.tts,
    required this.userProfile,
  });

  @override
  State<CustomCoachPickerScreen> createState() =>
      _CustomCoachPickerScreenState();

  /// Helper : pousse l'écran et renvoie la sélection. `null` = l'utilisateur
  /// est revenu en arrière sans choisir → pas de changement.
  static Future<({bool changed, String? coachId})?> pick(
    BuildContext context, {
    required CoachService service,
    required String? selectedCoachId,
    required TtsService tts,
    required UserProfileService userProfile,
  }) async {
    final result = await Navigator.of(context).push<_CoachPickerResult>(
      MaterialPageRoute(
        builder: (_) => CustomCoachPickerScreen(
          service: service,
          selectedCoachId: selectedCoachId,
          tts: tts,
          userProfile: userProfile,
        ),
      ),
    );
    if (result == null) return null;
    return (changed: true, coachId: result.coachId);
  }
}

class _CustomCoachPickerScreenState extends State<CustomCoachPickerScreen> {
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final coaches = widget.service.coaches;
    final labels = _voiceLabels;
    return Scaffold(
      appBar: AppBar(title: Text(t.customCoachPickerTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _PickerCard(
            title: t.customCoachDefaultVoice,
            subtitle: t.customCoachPickerDefaultSubtitle,
            icon: Icons.record_voice_over_outlined,
            selected: widget.selectedCoachId == null,
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
                accent: widget.selectedCoachId == c.id
                    ? AppTheme.accent
                    : AppTheme.textMuted,
              ),
              selected: widget.selectedCoachId == c.id,
              onTap: () => Navigator.of(context).pop(_CoachPickerResult(c.id)),
              voiceLabel: labels?.labelFor(t, c.id),
              onTapVoice: () => _openVoicePicker(c),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
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

  /// Voix effective du coach. `null` = pas de ligne (ligne « voix par
  /// défaut », plateforme sans sélection, ou voix pas encore lues).
  final String? voiceLabel;
  final VoidCallback? onTapVoice;

  const _PickerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.leading,
    required this.selected,
    required this.onTap,
    this.voiceLabel,
    this.onTapVoice,
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
                    if (voiceLabel != null && onTapVoice != null) ...[
                      const SizedBox(height: 6),
                      CoachVoiceLine(
                        label: voiceLabel!,
                        onTap: onTapVoice!,
                      ),
                    ],
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
