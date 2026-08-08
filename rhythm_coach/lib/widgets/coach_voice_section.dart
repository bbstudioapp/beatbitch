import 'package:flutter/material.dart';

import '../career/models/coach.dart';
import '../career/widgets/coach_portrait.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'coach_voice_picker.dart';

/// Bloc « VOIX DES COACHS » du Profil : une ligne par coach débloqué, avec
/// la voix qu'il utilisera en séance, et une feuille de sélection pour en
/// choisir une autre.
///
/// **Pourquoi ce réglage est manuel.** Aucune plateforme cible n'expose le
/// genre d'une voix — ni le plugin, ni Android lui-même. Un coach masculin ne
/// peut donc pas obtenir une voix masculine automatiquement, et un coach dont
/// la voix est déclarée en `fr-FR` retombe sur une rotation arbitraire dès
/// que la langue active n'est pas le français. Seule une oreille humaine peut
/// trancher : c'est tout l'objet de ce bloc, et la raison de l'aperçu sonore.
///
/// Le réglage est mémorisé **par coach et par langue** (cf.
/// [TtsService.setCoachVoice]) et n'est jamais effacé parce qu'une voix a
/// disparu de l'appareil : la ligne affiche l'absence, et le choix reprend de
/// lui-même si la voix réapparaît.
///
/// Ce n'est pas le seul endroit d'où il se règle : les sélecteurs de coach
/// (carrière et Custom) ouvrent la même feuille via [showCoachVoicePicker].
class CoachVoiceSection extends StatefulWidget {
  final TtsService tts;

  /// Coachs à lister — les **débloqués** uniquement côté Profil : le picker
  /// de carrière pratique une révélation progressive délibérée, et lister
  /// tout le catalogue ici éventerait le nom des coachs à venir.
  final List<Coach> coaches;

  /// Sert à résoudre `{name}` dans la phrase d'aperçu, comme le bouton de
  /// test de la section VOIX.
  final UserProfileService userProfile;

  const CoachVoiceSection({
    super.key,
    required this.tts,
    required this.coaches,
    required this.userProfile,
  });

  @override
  State<CoachVoiceSection> createState() => _CoachVoiceSectionState();
}

class _CoachVoiceSectionState extends State<CoachVoiceSection> {
  bool _ready = false;
  CoachVoiceLabels _labels = CoachVoiceLabels.empty;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChanged);
    _load(markReady: true);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  /// Les réglages sont par langue : changer de langue depuis la section
  /// juste au-dessus doit reverser la liste sur les réglages de la nouvelle
  /// langue, pas laisser afficher ceux de l'ancienne.
  void _onLocaleChanged() {
    if (!mounted) return;
    _load(markReady: false);
  }

  Future<void> _load({required bool markReady}) async {
    final labels = await CoachVoiceLabels.load(widget.tts, widget.coaches);
    if (!mounted) return;
    setState(() {
      if (markReady) _ready = true;
      _labels = labels;
    });
  }

  Future<void> _openPicker(Coach coach) async {
    await showCoachVoicePicker(
      context,
      tts: widget.tts,
      coach: coach,
      userProfile: widget.userProfile,
      labels: _labels,
    );
    await _load(markReady: false);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final selectable = TtsService.supportsVoiceSelection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selectable
              ? t.profileCoachVoiceSubtitle
              : t.coachVoicePlatformNoSelection,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 8),
        for (final coach in widget.coaches)
          _CoachVoiceRow(
            coach: coach,
            // Sur Linux, la ligne est inerte et le sous-titre a déjà été
            // porté par l'explication en tête de bloc.
            subtitle: _labels.labelFor(t, coach.id),
            onTap: selectable ? () => _openPicker(coach) : null,
          ),
      ],
    );
  }
}

class _CoachVoiceRow extends StatelessWidget {
  final Coach coach;
  final String subtitle;

  /// `null` sur les plateformes sans sélection de voix : la ligne reste
  /// affichée et expliquée, mais elle ne mène nulle part.
  final VoidCallback? onTap;

  const _CoachVoiceRow({
    required this.coach,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inert = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CoachPortrait(
                  coach: coach,
                  height: 44,
                  width: 44,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        coach.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              inert ? AppTheme.textMuted : AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!inert)
                  const Icon(Icons.chevron_right,
                      color: AppTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
