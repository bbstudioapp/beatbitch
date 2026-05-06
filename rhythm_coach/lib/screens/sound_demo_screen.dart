import 'package:flutter/material.dart';

import '../career/screens/career_scenario_debug_screen.dart';
import '../career/services/debug_settings_service.dart';
import '../l10n/app_localizations.dart';
import '../models/ambience_pack.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import '../services/ambience_engine.dart';
import '../services/beep_engine.dart';
import '../services/coach_phrases_loader.dart';
import '../services/locale_service.dart';
import '../services/tts_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_theme.dart';

/// Écran d'apprentissage des sons + réglages voix/ambiance partagés
/// avec l'écran de jeu (vitesse TTS, choix de voix, sélection du pack
/// d'ambiance).
class SoundDemoScreen extends StatefulWidget {
  final BeepEngine beep;
  final TtsService tts;
  final AmbienceEngine ambience;
  final List<AmbiencePack> ambiencePacks;
  final UserProfileService userProfile;

  const SoundDemoScreen({
    super.key,
    required this.beep,
    required this.tts,
    required this.ambience,
    required this.ambiencePacks,
    required this.userProfile,
  });

  @override
  State<SoundDemoScreen> createState() => _SoundDemoScreenState();
}

class _SoundDemoScreenState extends State<SoundDemoScreen> {
  bool _ready = false;
  String? _looping;
  int _bpm = 70;

  // Réglages voix — on initialise avec la valeur par défaut du TtsService.
  double _rate = 0.5;
  List<Map<String, String>> _voices = const [];
  String? _selectedVoiceName;

  // Ambiance : asset en cours d'écoute (test page SONS uniquement).
  String? _ambienceTestingAsset;

  // Debug.
  final DebugSettingsService _debug = DebugSettingsService();
  bool _showStaminaBar = false;
  bool _showTimer = false;
  bool _showExcitationBar = false;
  bool _showHumiliationBar = false;
  bool _showObedienceBar = false;
  bool _showSalivaBar = false;
  bool _showSessionControls = false;
  bool _showModeBadge = false;
  bool _cameraHoldCheck = false;
  bool _skipSessionButton = false;

  // Identité.
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _newNicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.userProfile.addListener(_onProfileChanged);
    Future.wait([
      widget.beep.ensureReady(),
      widget.tts.init(),
      widget.userProfile.load(),
    ]).then((_) async {
      final voices = await widget.tts.listVoicesForLocale(widget.tts.locale);
      final showBar = await _debug.getShowStaminaBar();
      final showTimer = await _debug.getShowTimer();
      final showExcit = await _debug.getShowExcitationBar();
      final showHumil = await _debug.getShowHumiliationBar();
      final showObed = await _debug.getShowObedienceBar();
      final showSaliva = await _debug.getShowSalivaBar();
      final showControls = await _debug.getShowSessionControls();
      final showBadge = await _debug.getShowModeBadge();
      final camCheck = await _debug.getCameraHoldCheck();
      final skipSession = await _debug.getSkipSessionButton();
      if (!mounted) return;
      setState(() {
        _ready = true;
        _voices = voices;
        _selectedVoiceName = widget.tts.currentVoiceName ??
            (voices.isNotEmpty ? voices.first['name'] : null);
        _showStaminaBar = showBar;
        _showTimer = showTimer;
        _showExcitationBar = showExcit;
        _showHumiliationBar = showHumil;
        _showObedienceBar = showObed;
        _showSalivaBar = showSaliva;
        _showSessionControls = showControls;
        _showModeBadge = showBadge;
        _cameraHoldCheck = camCheck;
        _skipSessionButton = skipSession;
        _prenomController.text = widget.userProfile.prenom ?? '';
      });
    });
  }

  void _onProfileChanged() {
    if (!mounted) return;
    final prenom = widget.userProfile.prenom ?? '';
    if (_prenomController.text != prenom) {
      _prenomController.text = prenom;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.userProfile.removeListener(_onProfileChanged);
    _prenomController.dispose();
    _newNicknameController.dispose();
    widget.beep.stop();
    // L'ambiance est laissée pilotée par l'engine global ; on coupe juste
    // le test d'écoute si on quitte la page.
    if (_ambienceTestingAsset != null) widget.ambience.stop();
    super.dispose();
  }

  void _stopLoop() {
    widget.beep.stop();
    setState(() => _looping = null);
  }

  void _startLoop(String label, VoidCallback start) {
    if (_looping != null) widget.beep.stop();
    start();
    setState(() => _looping = label);
  }

  Future<void> _testVoice() async {
    await widget.tts.stop();
    await widget.tts.speak(CoachPhrasesService.instance.current.testVoicePhrase);
  }

  Future<void> _testIdentity() async {
    await widget.tts.stop();
    await widget.tts.speak(
      CoachPhrasesService.instance.current.testIdentityPhrase,
    );
  }

  Future<void> _addCustomNickname() async {
    final value = _newNicknameController.text.trim();
    if (value.isEmpty) return;
    await widget.userProfile.addCustomNickname(value);
    _newNicknameController.clear();
  }

  Future<void> _previewAmbience(SessionMode mode) async {
    // Test d'écoute : on joue l'ambiance correspondant au mode dans le
    // pack courant. Si déjà en cours sur ce mode → stop.
    final asset = widget.ambience.currentPack.assetFor(mode);
    if (asset == null) return;
    if (_ambienceTestingAsset == asset) {
      await widget.ambience.stop();
      setState(() => _ambienceTestingAsset = null);
      return;
    }
    await widget.ambience.play(asset);
    setState(() => _ambienceTestingAsset = asset);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.soundsAppBarTitle),
        actions: [
          if (_looping != null)
            IconButton(
              tooltip: t.soundsStopLoopTooltip,
              icon: const Icon(Icons.stop_circle, color: AppTheme.accent),
              onPressed: _stopLoop,
            ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(
                  title: t.soundsIdentitySection,
                  subtitle: t.soundsIdentitySubtitle('name'),
                  children: [
                    TextField(
                      controller: _prenomController,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: t.soundsFirstNameLabel,
                        helperText: t.soundsFirstNameHelper,
                      ),
                      onSubmitted: (v) => widget.userProfile.setPrenom(v),
                      onEditingComplete: () =>
                          widget.userProfile.setPrenom(_prenomController.text),
                    ),
                    const SizedBox(height: 8),
                    _SoundButton(
                      label: t.soundsTestSubstitution,
                      subtitle:
                          '« ${CoachPhrasesService.instance.current.testIdentityPhrase} »',
                      onTap: _testIdentity,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t.soundsDefaultNicknames,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final n in widget.userProfile.defaultNicknames)
                      _NicknameToggleTile(
                        label: n,
                        enabled:
                            !widget.userProfile.disabledDefaults.contains(n),
                        onChanged: (v) =>
                            widget.userProfile.setDefaultEnabled(n, v),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      t.soundsCustomNicknames,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (widget.userProfile.customNicknames.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          t.soundsNoCustomNicknames,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    for (final n in widget.userProfile.customNicknames)
                      _NicknameRemovableTile(
                        label: n,
                        onRemove: () =>
                            widget.userProfile.removeCustomNickname(n),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newNicknameController,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: t.soundsAddNicknameLabel,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _addCustomNickname(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: t.commonAdd,
                          icon: const Icon(Icons.add_circle,
                              color: AppTheme.accent),
                          onPressed: _addCustomNickname,
                        ),
                      ],
                    ),
                  ],
                ),
                _buildSection(
                  title: t.soundsVoiceSection,
                  subtitle: t.soundsVoiceSubtitle,
                  children: [
                    _VoicePicker(
                      voices: _voices,
                      selectedName: _selectedVoiceName,
                      onChanged: (name) async {
                        if (name == null) return;
                        final voice =
                            _voices.firstWhere((v) => v['name'] == name);
                        await widget.tts
                            .setVoiceByName(name, voice['locale'] ?? 'fr-FR');
                        setState(() => _selectedVoiceName = name);
                      },
                    ),
                    _LabeledSlider(
                      label: t.soundsRateLabel,
                      value: _rate,
                      min: 0.3,
                      max: 0.8,
                      onChanged: (v) {
                        setState(() => _rate = v);
                        widget.tts.setRate(v);
                      },
                    ),
                    _SoundButton(
                      label: t.soundsTestVoice,
                      subtitle:
                          '« ${CoachPhrasesService.instance.current.testVoicePhrase} »',
                      onTap: _testVoice,
                    ),
                  ],
                ),
                _buildSection(
                  title: t.soundsAmbienceSection,
                  subtitle: t.soundsAmbienceSubtitle,
                  children: [
                    _AmbiencePackPicker(
                      packs: widget.ambiencePacks,
                      selectedId: widget.ambience.currentPack.id,
                      onChanged: (id) async {
                        if (id == null) return;
                        final pack = widget.ambiencePacks
                            .firstWhere((p) => p.id == id);
                        widget.ambience.setPack(pack);
                        // Si on était en train de tester un asset du pack
                        // précédent, on coupe.
                        if (_ambienceTestingAsset != null) {
                          await widget.ambience.stop();
                        }
                        setState(() => _ambienceTestingAsset = null);
                      },
                    ),
                    if (widget.ambience.currentPack.id !=
                        AmbiencePack.none.id) ...[
                      for (final mode in SessionMode.values)
                        _AmbiencePreviewButton(
                          mode: mode,
                          asset: widget.ambience.currentPack.assetFor(mode),
                          isPlaying: widget.ambience.currentPack
                                  .assetFor(mode) ==
                              _ambienceTestingAsset,
                          onTap: () => _previewAmbience(mode),
                        ),
                    ],
                  ],
                ),
                _buildSection(
                  title: t.soundsRhythmPositionsSection,
                  subtitle: t.soundsRhythmPositionsSubtitle,
                  children: [
                    for (final p in Position.values)
                      _SoundButton(
                        label: _positionLabel(p),
                        subtitle: _positionDescription(t, p),
                        onTap: () => widget.beep.playPositionOnce(p),
                      ),
                  ],
                ),
                _buildSection(
                  title: t.soundsLickPositionsSection,
                  subtitle: t.soundsLickPositionsSubtitle,
                  children: [
                    for (final p in Position.values)
                      _SoundButton(
                        label: t.soundsLickPositionLabel(_positionLabel(p)),
                        subtitle: t.soundsLickPositionSubtitle(p.name),
                        onTap: () => widget.beep.playLickPositionOnce(p),
                      ),
                  ],
                ),
                _buildSection(
                  title: t.soundsHoldSection,
                  subtitle: t.soundsHoldSubtitle,
                  children: [
                    for (final p in Position.values)
                      _SoundButton(
                        label: t.soundsHoldButton(_positionLabel(p)),
                        subtitle: t.soundsHoldPositionSubtitle(p.name),
                        onTap: () => widget.beep.playHoldOnce(p),
                      ),
                  ],
                ),
                _buildSection(
                  title: t.soundsSpecificSounds,
                  children: [
                    _SoundButton(
                      label: t.soundsBiffleOneShot,
                      subtitle: t.soundsBiffleOneShotSubtitle,
                      onTap: () => widget.beep.playBiffleOnce(),
                    ),
                    _SoundButton(
                      label: t.soundsBreath,
                      subtitle: t.soundsBreathSubtitle,
                      onTap: () => widget.beep.playBreathOnce(),
                    ),
                  ],
                ),
                _buildSection(
                  title: t.soundsLoopsDemoSection,
                  subtitle: t.soundsLoopsDemoSubtitle,
                  children: [
                    _BpmControl(
                      bpm: _bpm,
                      onChanged: (v) => setState(() => _bpm = v),
                    ),
                    _LoopButton(
                      label: t.soundsLoopRhythmHeadMid,
                      active: _looping == 'rhythm',
                      onStart: () => _startLoop(
                        'rhythm',
                        () => widget.beep.startRhythmDemo(
                          from: Position.head,
                          to: Position.mid,
                          bpm: _bpm,
                        ),
                      ),
                      onStop: _stopLoop,
                    ),
                    _LoopButton(
                      label: t.soundsLoopRhythmThroatFull,
                      active: _looping == 'rhythm-deep',
                      onStart: () => _startLoop(
                        'rhythm-deep',
                        () => widget.beep.startRhythmDemo(
                          from: Position.throat,
                          to: Position.full,
                          bpm: _bpm,
                        ),
                      ),
                      onStop: _stopLoop,
                    ),
                    _LoopButton(
                      label: t.soundsLoopLickTipHead,
                      active: _looping == 'lick',
                      onStart: () => _startLoop(
                        'lick',
                        () => widget.beep.startLickDemo(
                          from: Position.tip,
                          to: Position.head,
                          bpm: _bpm,
                        ),
                      ),
                      onStop: _stopLoop,
                    ),
                    _LoopButton(
                      label: t.soundsLoopBiffle,
                      active: _looping == 'biffle',
                      onStart: () => _startLoop(
                        'biffle',
                        () => widget.beep.startBiffleDemo(bpm: _bpm),
                      ),
                      onStop: _stopLoop,
                    ),
                  ],
                ),
                _buildSection(
                  title: t.settingsLanguageSection,
                  subtitle: t.settingsLanguageSubtitle,
                  children: [
                    _LanguagePicker(
                      current: LocaleService.instance.current,
                      onChanged: (locale) async {
                        await LocaleService.instance.setLocale(locale);
                        if (!mounted) return;
                        setState(() {});
                      },
                    ),
                  ],
                ),
                _buildSection(
                  title: t.soundsDebugSection,
                  subtitle: t.soundsDebugSubtitle,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowTimer,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowTimerSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showTimer,
                      onChanged: (v) async {
                        await _debug.setShowTimer(v);
                        if (!mounted) return;
                        setState(() => _showTimer = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowStaminaBar,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowStaminaBarSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showStaminaBar,
                      onChanged: (v) async {
                        await _debug.setShowStaminaBar(v);
                        if (!mounted) return;
                        setState(() => _showStaminaBar = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowExcitationBar,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowExcitationBarSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showExcitationBar,
                      onChanged: (v) async {
                        await _debug.setShowExcitationBar(v);
                        if (!mounted) return;
                        setState(() => _showExcitationBar = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowHumiliationBar,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowHumiliationBarSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showHumiliationBar,
                      onChanged: (v) async {
                        await _debug.setShowHumiliationBar(v);
                        if (!mounted) return;
                        setState(() => _showHumiliationBar = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowObedienceBar,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowObedienceBarSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showObedienceBar,
                      onChanged: (v) async {
                        await _debug.setShowObedienceBar(v);
                        if (!mounted) return;
                        setState(() => _showObedienceBar = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowSalivaBar,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowSalivaBarSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showSalivaBar,
                      onChanged: (v) async {
                        await _debug.setShowSalivaBar(v);
                        if (!mounted) return;
                        setState(() => _showSalivaBar = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowSessionControls,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowSessionControlsSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showSessionControls,
                      onChanged: (v) async {
                        await _debug.setShowSessionControls(v);
                        if (!mounted) return;
                        setState(() => _showSessionControls = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugShowModeBadge,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugShowModeBadgeSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _showModeBadge,
                      onChanged: (v) async {
                        await _debug.setShowModeBadge(v);
                        if (!mounted) return;
                        setState(() => _showModeBadge = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugCameraHoldCheck,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugCameraHoldCheckSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _cameraHoldCheck,
                      onChanged: (v) async {
                        await _debug.setCameraHoldCheck(v);
                        if (!mounted) return;
                        setState(() => _cameraHoldCheck = v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t.soundsDebugSkipSession,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugSkipSessionSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      value: _skipSessionButton,
                      onChanged: (v) async {
                        await _debug.setSkipSessionButton(v);
                        if (!mounted) return;
                        setState(() => _skipSessionButton = v);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.auto_awesome,
                        color: AppTheme.accent,
                      ),
                      title: Text(
                        t.soundsDebugScenarioButton,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        t.soundsDebugScenarioSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppTheme.textMuted,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const CareerScenarioDebugScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppTheme.accent,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...children.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: c,
            ),
          ),
        ],
      ),
    );
  }

  /// Étiquette technique (codes internes des bips) — non localisée volontairement,
  /// les noms anglais sont des constantes du moteur audio.
  String _positionLabel(Position p) => switch (p) {
        Position.tip => 'Tip',
        Position.head => 'Head',
        Position.mid => 'Mid',
        Position.throat => 'Throat',
        Position.full => 'Full',
      };

  String _positionDescription(AppLocalizations t, Position p) => switch (p) {
        Position.tip => t.soundsPosDescTip,
        Position.head => t.soundsPosDescHead,
        Position.mid => t.soundsPosDescMid,
        Position.throat => t.soundsPosDescThroat,
        Position.full => t.soundsPosDescFull,
      };
}

class _SoundButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _SoundButton({
    required this.label,
    this.subtitle,
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
              const Icon(Icons.play_arrow,
                  color: AppTheme.accent, size: 22),
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
                    if (subtitle != null)
                      Text(
                        subtitle!,
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

class _LoopButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _LoopButton({
    required this.label,
    required this.active,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accent : AppTheme.surface;
    final fg = active ? Colors.black : AppTheme.textPrimary;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: active ? onStop : onStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(active ? Icons.stop : Icons.loop, color: fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              if (active)
                Text(
                  AppLocalizations.of(context).soundsLoopActive,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BpmControl extends StatelessWidget {
  final int bpm;
  final ValueChanged<int> onChanged;

  const _BpmControl({required this.bpm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              AppLocalizations.of(context).soundsBpmLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: bpm.toDouble(),
              min: 30,
              max: 180,
              divisions: 30,
              label: '$bpm',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$bpm',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
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
          ),
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

class _AmbiencePackPicker extends StatelessWidget {
  final List<AmbiencePack> packs;
  final String selectedId;
  final ValueChanged<String?> onChanged;

  const _AmbiencePackPicker({
    required this.packs,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value =
        packs.any((p) => p.id == selectedId) ? selectedId : AmbiencePack.none.id;
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            AppLocalizations.of(context).soundsPackLabel,
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
            items: packs
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.name,
                        style: const TextStyle(fontSize: 13),
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

class _AmbiencePreviewButton extends StatelessWidget {
  final SessionMode mode;
  final String? asset;
  final bool isPlaying;
  final VoidCallback onTap;

  const _AmbiencePreviewButton({
    required this.mode,
    required this.asset,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final disabled = asset == null;
    final color = isPlaying ? AppTheme.accent : AppTheme.surface;
    final fg = isPlaying ? Colors.black : AppTheme.textPrimary;
    return Material(
      color: disabled ? AppTheme.surface.withValues(alpha: 0.4) : color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isPlaying ? Icons.stop : Icons.play_arrow,
                color: disabled ? AppTheme.textMuted : fg,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.soundsModeLabel(mode.name),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: disabled ? AppTheme.textMuted : fg,
                      ),
                    ),
                    Text(
                      asset ?? t.soundsNoTrack,
                      style: TextStyle(
                        fontSize: 11,
                        color: disabled
                            ? AppTheme.textMuted
                            : (isPlaying
                                ? Colors.black54
                                : AppTheme.textMuted),
                      ),
                      overflow: TextOverflow.ellipsis,
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

class _NicknameToggleTile extends StatelessWidget {
  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _NicknameToggleTile({
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.check_box : Icons.check_box_outline_blank,
              color: enabled ? AppTheme.accent : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  final Locale current;
  final ValueChanged<Locale> onChanged;

  const _LanguagePicker({required this.current, required this.onChanged});

  String _labelFor(BuildContext context, Locale locale) {
    final t = AppLocalizations.of(context);
    return switch (locale.languageCode) {
      'fr' => t.settingsLanguageFrench,
      'en' => t.settingsLanguageEnglish,
      _ => locale.languageCode.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final value =
        kSupportedLocales.any((l) => l.languageCode == current.languageCode)
            ? current.languageCode
            : kSupportedLocales.first.languageCode;
    final disabled = kSupportedLocales.length <= 1;
    return Row(
      children: [
        const SizedBox(
          width: 64,
          child: Icon(Icons.language, color: AppTheme.accent, size: 20),
        ),
        Expanded(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            onChanged: disabled
                ? null
                : (code) {
                    if (code == null) return;
                    onChanged(Locale(code));
                  },
            items: [
              for (final l in kSupportedLocales)
                DropdownMenuItem(
                  value: l.languageCode,
                  child: Text(
                    _labelFor(context, l),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NicknameRemovableTile extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _NicknameRemovableTile({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.label_important_outline,
              color: AppTheme.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).soundsRemoveNicknameTooltip,
            icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
