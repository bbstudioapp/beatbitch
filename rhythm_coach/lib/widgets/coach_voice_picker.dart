import 'package:flutter/material.dart';

import '../career/models/coach.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'voice_settings_section.dart'
    show LabeledVoiceSlider, resolveVoiceTestPhrase;

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

  /// `coachId` → débit et hauteur réglés à la main, absents si le coach garde
  /// ceux de son preset. Contrairement à la voix, ils ne dépendent pas de la
  /// langue (cf. [TtsService.coachRateAndPitch]).
  final Map<String, double> _rates;
  final Map<String, double> _pitches;

  const CoachVoiceLabels._(
      this.voices, this._chosen, this._rates, this._pitches);

  /// État avant chargement : aucune voix, aucun réglage connu.
  static const CoachVoiceLabels empty = CoachVoiceLabels._(
    <Map<String, String>>[],
    <String, String>{},
    <String, double>{},
    <String, double>{},
  );

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
    final rates = <String, double>{};
    final pitches = <String, double>{};
    for (final coach in coaches) {
      final name = await tts.coachVoiceName(coach.id);
      if (name != null) chosen[coach.id] = name;
      final tuning = await tts.coachRateAndPitch(coach.id);
      if (tuning.rate != null) rates[coach.id] = tuning.rate!;
      if (tuning.pitch != null) pitches[coach.id] = tuning.pitch!;
    }
    return CoachVoiceLabels._(voices, chosen, rates, pitches);
  }

  String? chosenFor(String coachId) => _chosen[coachId];

  /// Débit réglé à la main pour ce coach, `null` s'il garde celui de son
  /// preset.
  double? rateFor(String coachId) => _rates[coachId];
  double? pitchFor(String coachId) => _pitches[coachId];

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
      initialRate: labels.rateFor(coach.id),
      initialPitch: labels.pitchFor(coach.id),
    ),
  );
  // Couper l'aperçu encore audible : hors file, puisque c'est justement
  // l'opération en cours qu'il s'agit d'interrompre.
  await tts.stop();
  await tts.enqueueVoiceOp(tts.restoreDefaultVoicePreset);
}

/// Ligne « Voix : … » posée sur une carte de coach, cliquable.
///
/// L'utilisateur qui entend une voix qui ne colle pas au personnage n'a
/// aucune raison de soupçonner qu'un réglage existe : il conclut que l'app
/// est mal faite. Cette ligne ne dit pas qu'il y a un problème — elle dit
/// qu'il y a un réglage, au moment exact où l'on regarde le coach.
class CoachVoiceLine extends StatelessWidget {
  /// Voix effective (cf. [CoachVoiceLabels.labelFor]).
  final String label;
  final VoidCallback onTap;

  const CoachVoiceLine({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.record_voice_over_outlined,
                    size: 13, color: AppTheme.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    t.coachVoiceLine(label),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right,
                    size: 14, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Feuille de réglage vocal d'un coach : « Automatique » en tête de la liste
/// de voix (= suppression de la clé, cf. [TtsService.clearCoachVoice]), les
/// voix du moteur pour la langue active, puis la vitesse et la hauteur.
///
/// Toucher un réglage le mémorise **et** l'apercevoit dans la foulée : les
/// noms de voix sont des identifiants techniques (`en-gb-x-gbd-local`) et
/// deux nombres ne disent rien d'un timbre — sans écoute l'utilisateur ne
/// choisit pas, il tâtonne en relançant des séances.
///
/// Les deux curseurs sont **posés à même la feuille**, pas repliés derrière
/// un second geste : décision de Manu, 2026-08-18. Le prix est une feuille
/// plus haute, donc une liste de voix plus courte à l'écran — elle défile.
class _CoachVoiceSheet extends StatefulWidget {
  final TtsService tts;
  final Coach coach;
  final List<Map<String, String>> voices;
  final UserProfileService userProfile;
  final String? initialSelection;

  /// Réglages manuels en vigueur, `null` quand le coach garde ceux de son
  /// preset — c'est cette absence, et non une valeur repère, qui distingue
  /// « réglé » de « d'origine ».
  final double? initialRate;
  final double? initialPitch;

  const _CoachVoiceSheet({
    required this.tts,
    required this.coach,
    required this.voices,
    required this.userProfile,
    required this.initialSelection,
    required this.initialRate,
    required this.initialPitch,
  });

  @override
  State<_CoachVoiceSheet> createState() => _CoachVoiceSheetState();
}

class _CoachVoiceSheetState extends State<_CoachVoiceSheet> {
  String? _selected;
  double? _rate;
  double? _pitch;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
    _rate = widget.initialRate;
    _pitch = widget.initialPitch;
  }

  /// Débit affiché : celui réglé à la main, sinon celui du preset du coach,
  /// sinon le défaut de la plateforme — la cascade que [TtsService] applique.
  double get _shownRate =>
      _rate ?? widget.coach.voicePreset.rate ?? TtsService.defaultRate;
  double get _shownPitch =>
      _pitch ?? widget.coach.voicePreset.pitch ?? TtsService.defaultPitch;

  bool get _tuned => _rate != null || _pitch != null;

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

  /// Enregistre au **relâchement** seulement, et apercevoit dans la foulée :
  /// écrire à chaque frame du glissement ferait une préférence par pixel et
  /// une phrase par pixel.
  Future<void> _commitRate(double v) async {
    await widget.tts.setCoachRate(widget.coach.id, v);
    await _preview();
  }

  Future<void> _commitPitch(double v) async {
    await widget.tts.setCoachPitch(widget.coach.id, v);
    await _preview();
  }

  /// Rend au coach la vitesse et la hauteur de son preset d'origine.
  Future<void> _resetTuning() async {
    await widget.tts.clearCoachRateAndPitch(widget.coach.id);
    if (!mounted) return;
    setState(() {
      _rate = null;
      _pitch = null;
    });
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
        skipPreferredVoices: preset.skipPreferredVoices,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledVoiceSlider(
                    label: t.soundsRateLabel,
                    value: _shownRate,
                    min: 0.3,
                    max: 0.8,
                    onChanged: (v) => setState(() => _rate = v),
                    onChangeEnd: _commitRate,
                  ),
                  LabeledVoiceSlider(
                    label: t.soundsPitchLabel,
                    value: _shownPitch,
                    min: 0.5,
                    max: 2.0,
                    onChanged: (v) => setState(() => _pitch = v),
                    onChangeEnd: _commitPitch,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    // Affiché même inerte : un bouton qui apparaît ferait
                    // sauter la feuille au premier glissement, et son absence
                    // laisserait croire qu'aucun retour en arrière n'existe.
                    child: TextButton.icon(
                      onPressed: _tuned ? _resetTuning : null,
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: Text(t.coachVoiceResetRatePitch),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        disabledForegroundColor: AppTheme.textMuted,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
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
