import 'package:flutter/material.dart';

import '../career/models/coach.dart';
import '../career/widgets/coach_portrait.dart';
import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';
import 'voice_settings_section.dart' show resolveVoiceTestPhrase;

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
  List<Map<String, String>> _voices = const [];

  /// `coachId` → voix choisie pour la langue active, absent si « automatique ».
  Map<String, String> _overrides = const {};

  /// Chaîne des écritures de l'état vocal partagé du service : pose du
  /// preset par l'aperçu, restauration à la fermeture de la feuille.
  ///
  /// La feuille se ferme par n'importe quel geste — bouton retour, tap hors
  /// zone, glissement vers le bas — et rend la main **sans attendre**
  /// l'aperçu qu'un `onTap` a lancé. Les deux chaînes écrivent alors sur le
  /// même service : si la restauration finit la première, l'aperçu repose
  /// le timbre, le débit et la hauteur du coach derrière elle, et la
  /// section VOIX juste au-dessus les présente comme le réglage par défaut
  /// de l'utilisateur — la confusion même que ce bloc existe pour dissiper.
  /// La restauration étant toujours la dernière enfilée, c'est elle qui a
  /// le dernier mot, quel que soit le moment de la fermeture.
  Future<void> _voiceOps = Future<void>.value();

  Future<void> _enqueueVoiceOp(Future<void> Function() op) {
    final next = _voiceOps.then((_) => op());
    // Une opération en échec ne doit pas condamner celles d'après : c'est
    // la restauration qui compte, et elle passe en dernier.
    _voiceOps = next.catchError((Object _) {});
    return next;
  }

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
    await widget.tts.init();
    await widget.tts.setLocale(LocaleService.instance.current);
    final voices = TtsService.supportsVoiceSelection
        ? await widget.tts.listVoicesForLocale(widget.tts.locale)
        : const <Map<String, String>>[];
    final overrides = <String, String>{};
    for (final coach in widget.coaches) {
      final name = await widget.tts.coachVoiceName(coach.id);
      if (name != null) overrides[coach.id] = name;
    }
    if (!mounted) return;
    setState(() {
      if (markReady) _ready = true;
      _voices = voices;
      _overrides = overrides;
    });
  }

  /// Ouvre la feuille de sélection. À la fermeture, on restaure le réglage
  /// hors-carrière : l'aperçu a posé la voix et le rate/pitch du coach sur le
  /// service partagé, ils ne doivent pas rester sur la navigation suivante.
  Future<void> _openPicker(Coach coach) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CoachVoiceSheet(
        tts: widget.tts,
        coach: coach,
        voices: _voices,
        userProfile: widget.userProfile,
        initialSelection: _overrides[coach.id],
        enqueueVoiceOp: _enqueueVoiceOp,
      ),
    );
    // Couper l'aperçu encore audible : hors file, puisque c'est justement
    // l'opération en cours qu'il s'agit d'interrompre.
    await widget.tts.stop();
    await _enqueueVoiceOp(widget.tts.restoreDefaultVoicePreset);
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
            subtitle: _subtitleFor(t, coach),
            onTap: selectable ? () => _openPicker(coach) : null,
          ),
      ],
    );
  }

  /// Voix effective de la ligne : le nom choisi, l'absence constatée, ou
  /// « Automatique ». Sur Linux, la ligne est inerte et le sous-titre a déjà
  /// été porté par l'explication en tête de bloc.
  String _subtitleFor(AppLocalizations t, Coach coach) {
    if (!TtsService.supportsVoiceSelection) return t.coachVoiceAutomatic;
    final chosen = _overrides[coach.id];
    if (chosen == null) return t.coachVoiceAutomatic;
    final installed = _voices.any((v) => v['name'] == chosen);
    return installed ? chosen : t.coachVoiceUnavailable;
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

  /// Enchaîne une écriture de l'état vocal partagé derrière celles déjà en
  /// vol (cf. [_CoachVoiceSectionState._enqueueVoiceOp]).
  final Future<void> Function(Future<void> Function()) enqueueVoiceOp;

  const _CoachVoiceSheet({
    required this.tts,
    required this.coach,
    required this.voices,
    required this.userProfile,
    required this.initialSelection,
    required this.enqueueVoiceOp,
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
    await widget.enqueueVoiceOp(() async {
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
