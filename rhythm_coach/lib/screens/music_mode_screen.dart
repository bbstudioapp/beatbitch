import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session.dart' show SessionMode;
import '../models/session_step.dart' show Position;
import '../music/music_session_controller.dart';
import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import '../theme/app_theme.dart';
import '../widgets/movement_animation.dart';

/// Écran du mode Music (PR1) : taper le tempo, démarrer, voir la timeline de
/// profondeur défiler (passé · NOW · à venir). Cf. `specs/music_mode.md` §9.
class MusicModeScreen extends StatefulWidget {
  final BeepEngine beep;

  const MusicModeScreen({super.key, required this.beep});

  @override
  State<MusicModeScreen> createState() => _MusicModeScreenState();
}

class _MusicModeScreenState extends State<MusicModeScreen> {
  MusicSessionController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await widget.beep.ensureReady();
    // Mélange avec l'audio en cours (Spotify…) au lieu d'en prendre le focus.
    await widget.beep.setMixWithOthers(true);
    final profile = await CapabilityService().snapshotProfile();
    if (!mounted) return;
    setState(() {
      _controller = MusicSessionController(beep: widget.beep, profile: profile);
    });
  }

  @override
  void dispose() {
    // On ne dispose que le contrôleur : le BeepEngine est partagé (propriété
    // de ModeSelectionScreen). On rend le focus audio exclusif en sortant.
    widget.beep.setMixWithOthers(false);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(t.modeSelectionMusicTitle)),
      body: SafeArea(
        child: c == null
            ? const Center(child: CircularProgressIndicator())
            : ListenableBuilder(
                listenable: c,
                builder: (context, _) => _body(t, c),
              ),
      ),
    );
  }

  Widget _body(AppLocalizations t, MusicSessionController c) {
    final bpm = c.bpm;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            t.musicTapPrompt,
            style: const TextStyle(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            bpm == null ? '—' : '${bpm.round()} BPM',
            style: const TextStyle(
              color: AppTheme.accent,
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GestureDetector(
              onTap: c.isRunning ? null : c.tap,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
                ),
                clipBehavior: Clip.antiAlias,
                child: c.isRunning
                    ? LayoutBuilder(
                        builder: (_, cons) => Center(
                          child: MovementAnimation(
                            mode: SessionMode.rhythm,
                            from: Position.head,
                            to: c.currentTargetDepth,
                            bpm: c.bpm?.round() ?? 90,
                            height: cons.maxHeight,
                            // Pas de beepEngine : l'animation s'auto-anime au
                            // tempo (le son est joué par le contrôleur).
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          t.musicTapAction,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 22,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!c.isStable && !c.isRunning)
            Text(
              t.musicWaitingTempo,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: !c.hasTempo ? null : (c.isRunning ? c.stop : c.start),
              child: Text(c.isRunning ? t.musicStop : t.musicStart),
            ),
          ),
        ],
      ),
    );
  }
}
