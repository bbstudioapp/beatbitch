import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/coach_phrases_loader.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';

/// Réglages de la voix par défaut de la coach : sélection de la voix TTS,
/// vitesse, hauteur, et un bouton « Tester la voix » qui lit la phrase de
/// test de la coach. Le placeholder `{name}` y est substitué de façon
/// **déterministe** par le prénom saisi (ou retiré proprement s'il est
/// vide), sans passer par le tirage aléatoire du pool de surnoms — on teste
/// le rendu sonore, pas la mécanique de substitution.
///
/// Hébergé par l'écran Profil — les coachs de carrière ont leur propre voix
/// figée, seule cette voix par défaut (utilisée hors-carrière) est
/// paramétrable.
///
/// Charge la liste des voix à l'init (après `tts.init()`, idempotent) et
/// reflète l'état courant du [TtsService] partagé : changer la voix /
/// vitesse / hauteur ici s'applique immédiatement.
///
/// Les trois réglages sont mémorisés et restitués à l'identique — à la
/// fermeture de l'app comme en sortie de session carrière (cf.
/// `TtsService.setUserVoice`, `setUserRate`, `setUserPitch`). La voix l'est
/// par langue, la vitesse et la hauteur globalement : un nom de voix
/// appartient à sa langue, un débit est un confort d'écoute.
///
/// Les curseurs poussent au moteur à chaque frame et n'enregistrent qu'au
/// relâchement : on entend l'effet en glissant sans écrire une préférence
/// par pixel parcouru.
final RegExp _namePlaceholder =
    RegExp(r'\s?\{\s*name\s*\}', caseSensitive: false);

/// Construit la phrase de test de voix telle qu'elle sera **exactement**
/// prononcée : `{name}` substitué par le prénom (l'espace capturé devant est
/// préservé), ou retiré proprement s'il est vide. Pas de tirage aléatoire
/// dans le pool de surnoms — l'audio rendu correspond mot pour mot au
/// sous-titre affiché.
///
/// Partagée avec le réglage de voix par coach (`CoachVoiceSection`), qui
/// réutilise cette même phrase pour son aperçu sonore plutôt que d'en
/// introduire une seconde.
String resolveVoiceTestPhrase(UserProfileService userProfile) {
  final raw = CoachPhrasesService.instance.current.testVoicePhrase;
  final prenom = userProfile.prenom?.trim();
  return raw.replaceAllMapped(_namePlaceholder, (m) {
    if (prenom == null || prenom.isEmpty) return '';
    final hadSpace = m.group(0)?.startsWith(' ') ?? false;
    return hadSpace ? ' $prenom' : prenom;
  });
}

class VoiceSettingsSection extends StatefulWidget {
  final TtsService tts;
  final UserProfileService userProfile;

  const VoiceSettingsSection({
    super.key,
    required this.tts,
    required this.userProfile,
  });

  @override
  State<VoiceSettingsSection> createState() => _VoiceSettingsSectionState();
}

class _VoiceSettingsSectionState extends State<VoiceSettingsSection> {
  bool _ready = false;
  List<Map<String, String>> _voices = const [];
  String? _selectedVoiceName;
  double _rate = TtsService.defaultRate;
  double _pitch = TtsService.defaultPitch;

  @override
  void initState() {
    super.initState();
    widget.userProfile.addListener(_onProfileChanged);
    LocaleService.instance.addListener(_onLocaleChanged);
    widget.tts.init().then((_) async {
      await _loadVoicesForCurrentLocale(markReady: true);
    });
  }

  @override
  void dispose() {
    widget.userProfile.removeListener(_onProfileChanged);
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    _loadVoicesForCurrentLocale(markReady: false);
  }

  /// Recharge la liste des voix pour la locale active et resync les sliders
  /// sur l'état du service. On appelle `tts.setLocale` ici (idempotent si la
  /// locale n'a pas changé) pour garantir que la voix par défaut de la
  /// nouvelle langue est sélectionnée *avant* qu'on lise `currentVoiceName`.
  ///
  /// Si la voix courante du service n'est pas dans la liste filtrée de la
  /// nouvelle locale (cas observé sur Web Speech API où `_selectVoice` ne
  /// propage pas toujours le changement), on bascule explicitement sur la
  /// 1re voix dispo de la langue active et on le pousse au service — sinon
  /// le dropdown reste figé sur l'ancien nom alors que le test sonne dans
  /// la bonne langue (via `setLanguage`).
  Future<void> _loadVoicesForCurrentLocale({required bool markReady}) async {
    await widget.tts.setLocale(LocaleService.instance.current);
    final voices = await widget.tts.listVoicesForLocale(widget.tts.locale);
    String? resolved = widget.tts.currentVoiceName;
    final hasCurrent =
        resolved != null && voices.any((v) => v['name'] == resolved);
    if (!hasCurrent && voices.isNotEmpty) {
      final first = voices.first;
      final name = first['name'];
      final localeTag = first['locale'];
      if (name != null && localeTag != null) {
        await widget.tts.setVoiceByName(name, localeTag);
        resolved = name;
      }
    }
    if (!mounted) return;
    setState(() {
      if (markReady) _ready = true;
      _voices = voices;
      _selectedVoiceName =
          resolved ?? (voices.isNotEmpty ? voices.first['name'] : null);
      _rate = widget.tts.currentRate;
      _pitch = widget.tts.currentPitch;
    });
  }

  String _resolveTestPhrase() => resolveVoiceTestPhrase(widget.userProfile);

  Future<void> _testVoice() async {
    await widget.tts.stop();
    await widget.tts.speak(_resolveTestPhrase());
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VoicePicker(
          voices: _voices,
          selectedName: _selectedVoiceName,
          onChanged: (name) async {
            if (name == null) return;
            final voice = _voices.firstWhere((v) => v['name'] == name);
            // `setUserVoice` et non `setVoiceByName` : c'est LE choix
            // explicite de l'utilisateur, le seul qui soit mémorisé et qui
            // prime ensuite sur l'auto-sélection.
            await widget.tts.setUserVoice(name, voice['locale'] ?? 'fr-FR');
            if (!mounted) return;
            setState(() => _selectedVoiceName = name);
          },
        ),
        const SizedBox(height: 8),
        LabeledVoiceSlider(
          label: t.soundsRateLabel,
          value: _rate,
          min: 0.3,
          max: 0.8,
          onChanged: (v) {
            setState(() => _rate = v);
            widget.tts.setRate(v);
          },
          onChangeEnd: widget.tts.setUserRate,
        ),
        const SizedBox(height: 8),
        LabeledVoiceSlider(
          label: t.soundsPitchLabel,
          value: _pitch,
          min: 0.5,
          max: 2.0,
          onChanged: (v) {
            setState(() => _pitch = v);
            widget.tts.setPitch(v);
          },
          onChangeEnd: widget.tts.setUserPitch,
        ),
        const SizedBox(height: 8),
        _TestVoiceButton(
          label: t.soundsTestVoice,
          subtitle: '« ${_resolveTestPhrase()} »',
          onTap: _testVoice,
        ),
      ],
    );
  }
}

class _VoicePicker extends StatelessWidget {
  final List<Map<String, String>> voices;
  final String? selectedName;
  final ValueChanged<String?> onChanged;

  const _VoicePicker({
    required this.voices,
    required this.selectedName,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (voices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          t.soundsNoVoiceDetected,
          style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
        ),
      );
    }
    final value = voices.any((v) => v['name'] == selectedName)
        ? selectedName
        : voices.first['name'];
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            t.soundsVoiceSection,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: voices
                .map((v) => DropdownMenuItem(
                      value: v['name'],
                      child: Text(
                        '${v['name']}  ·  ${v['locale']}',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Curseur de débit ou de hauteur : libellé à gauche, valeur chiffrée à
/// droite, alignés en colonnes fixes pour que deux curseurs empilés se lisent
/// comme un tableau.
///
/// Partagé avec le réglage par coach (`coach_voice_picker.dart`) — les deux
/// écrans règlent la même chose et doivent se lire pareil.
class LabeledVoiceSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Appelé au relâchement seulement — c'est là que la valeur est
  /// enregistrée, pas à chaque frame du glissement.
  final ValueChanged<double> onChangeEnd;

  const LabeledVoiceSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _TestVoiceButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _TestVoiceButton({
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.play_arrow, color: AppTheme.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}
