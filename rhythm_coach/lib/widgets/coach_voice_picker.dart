import 'package:flutter/material.dart';

import '../career/models/coach.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'voice_settings_section.dart' show resolveVoiceTestPhrase;

/// Voix effective de chaque coach, résolue en un seul aller-retour moteur
/// pour tout un écran.
///
/// `listVoicesForLocale` traverse le canal de plateforme à chaque appel : on
/// la lit une fois par écran, pas une fois par ligne. Les libellés en
/// découlent, donc tous les écrans qui exposent le réglage disent la même
/// chose du même état.
class CoachVoiceLabels {
  /// Voix du moteur pour la langue active — la liste que propose la feuille,
  /// et celle qui dit si un réglage mémorisé est encore installé.
  final List<Map<String, String>> voices;

  /// `coachId` → voix choisie pour la langue active, absent si « automatique ».
  final Map<String, String> _chosen;

  const CoachVoiceLabels._(this.voices, this._chosen);

  /// État avant chargement : aucune voix, aucun réglage connu.
  static const CoachVoiceLabels empty =
      CoachVoiceLabels._(<Map<String, String>>[], <String, String>{});

  static Future<CoachVoiceLabels> load(
    TtsService tts,
    Iterable<Coach> coaches,
  ) async {
    await tts.init();
    await tts.setLocale(LocaleService.instance.current);
    final voices = TtsService.supportsVoiceSelection
        ? await tts.listVoicesForLocale(tts.locale)
        : const <Map<String, String>>[];
    final chosen = <String, String>{};
    for (final coach in coaches) {
      final name = await tts.coachVoiceName(coach.id);
      if (name != null) chosen[coach.id] = name;
    }
    return CoachVoiceLabels._(voices, chosen);
  }

  String? chosenFor(String coachId) => _chosen[coachId];

  /// Voix effective : le nom choisi, l'absence constatée, ou « Automatique ».
  ///
  /// L'absence n'est dite que là où elle est actionnable — sans elle,
  /// l'utilisateur qui a réglé sa voix et qui l'entend redevenir arbitraire
  /// repart dans le problème initial sans comprendre.
  String labelFor(AppLocalizations t, String coachId) {
    if (!TtsService.supportsVoiceSelection) return t.coachVoiceAutomatic;
    final chosen = _chosen[coachId];
    if (chosen == null) return t.coachVoiceAutomatic;
    final installed = voices.any((v) => v['name'] == chosen);
    return installed ? chosen : t.coachVoiceUnavailable;
  }
}

/// Ouvre la feuille de sélection de voix de [coach] — **le seul** point
/// d'entrée, depuis le Profil comme depuis les sélecteurs de coach.
///
/// Il n'est pas là pour éviter une duplication d'affichage : il encapsule la
/// restauration de sortie et la file d'écritures qui la rend étanche (cf.
/// [TtsService.enqueueVoiceOp]). Un écran qui referait le
/// `showModalBottomSheet` à la main laisserait le timbre, le débit et la
/// hauteur du coach posés sur toute la navigation suivante.
Future<void> showCoachVoicePicker(
  BuildContext context, {
  required TtsService tts,
  required Coach coach,
  required UserProfileService userProfile,
  required CoachVoiceLabels labels,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _CoachVoiceSheet(
      tts: tts,
      coach: coach,
      voices: labels.voices,
      userProfile: userProfile,
      initialSelection: labels.chosenFor(coach.id),
    ),
  );
  // Couper l'aperçu encore audible : hors file, puisque c'est justement
  // l'opération en cours qu'il s'agit d'interrompre.
  await tts.stop();
  await tts.enqueueVoiceOp(tts.restoreDefaultVoicePreset);
}

/// Feuille de sélection de la voix d'un coach : « Automatique » en tête (=
/// suppression de la clé, cf. [TtsService.clearCoachVoice]), puis les voix du
/// moteur pour la langue active.
///
/// Sélectionner une voix la mémorise **et** l'apercevoit dans la foulée : les
/// noms sont des identifiants techniques (`en-gb-x-gbd-local`), sans écoute
/// l'utilisateur ne choisit pas, il tâtonne en relançant des séances.
class _CoachVoiceSheet extends StatefulWidget {
  final TtsService tts;
  final Coach coach;
  final List<Map<String, String>> voices;
  final UserProfileService userProfile;
  final String? initialSelection;

  const _CoachVoiceSheet({
    required this.tts,
    required this.coach,
    required this.voices,
    required this.userProfile,
    required this.initialSelection,
  });

  @override
  State<_CoachVoiceSheet> createState() => _CoachVoiceSheetState();
}

class _CoachVoiceSheetState extends State<_CoachVoiceSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
  }

  /// `null` = « Automatique ».
  Future<void> _select(String? name) async {
    if (name == null) {
      await widget.tts.clearCoachVoice(widget.coach.id);
    } else {
      await widget.tts.setCoachVoice(widget.coach.id, name);
    }
    if (!mounted) return;
    setState(() => _selected = name);
    await _preview();
  }

  /// Joue la phrase de test avec le preset complet du coach — donc en
  /// passant par le même chemin qu'une séance, réglage manuel compris.
  /// L'utilisateur entend exactement ce qui sortira, y compris le débit et
  /// la hauteur du personnage : on juge un timbre *dans* sa couleur vocale.
  Future<void> _preview() async {
    final preset = widget.coach.voicePreset;
    await widget.tts.enqueueVoiceOp(() async {
      await widget.tts.stop();
      await widget.tts.applyCoachVoicePreset(
        coachId: widget.coach.id,
        voiceName: preset.voiceName,
        voiceLocale: preset.voiceLocale,
        rate: preset.rate,
        pitch: preset.pitch,
        preferredGender: preset.preferredGender,
      );
    });
    // Feuille fermée pendant la pose du preset : la restauration est déjà
    // enfilée derrière, on ne parle pas par-dessus avec la voix du coach.
    if (!mounted) return;
    await widget.tts.speak(resolveVoiceTestPhrase(widget.userProfile));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phrase = resolveVoiceTestPhrase(widget.userProfile);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                t.coachVoicePickerTitle(widget.coach.name),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (widget.voices.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  t.soundsNoVoiceDetected,
                  style:
                      const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    _VoiceOption(
                      label: t.coachVoiceAutomatic,
                      selected: _selected == null,
                      onTap: () => _select(null),
                    ),
                    for (final voice in widget.voices)
                      _VoiceOption(
                        label: '${voice['name']}  ·  ${voice['locale']}',
                        selected: _selected == voice['name'],
                        onTap: () => _select(voice['name']),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: AppTheme.accent),
              title: Text(
                t.coachVoicePreview,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              // La phrase est affichée avant d'être jouée : l'app s'utilise
              // aussi dans des lieux partagés, aucune surprise sonore.
              subtitle: Text(
                '« $phrase »',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              onTap: _preview,
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VoiceOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: selected ? AppTheme.accent : AppTheme.textPrimary,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppTheme.accent, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
