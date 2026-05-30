import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session_step.dart' show Position;
import '../music/music_session_controller.dart';
import '../music/slot_action.dart';
import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import '../theme/app_theme.dart';

/// Écran du mode Music (PR1) : taper le tempo, démarrer, voir la jauge de
/// profondeur animée en live. Cf. `specs/music_mode.md` §9.
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
                    ? _MusicDepthGauge(action: c.lastAction)
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

/// Jauge de profondeur live (façon `MovementAnimation` de la session) : une
/// échelle verticale head→full, un orbe qui **glisse** vers la profondeur de
/// la dernière [SlotAction] sur ~un battement. `strike` = orbe plein qui
/// « pope », `hold` = anneau tenu, `release` = orbe atténué (remontée).
class _MusicDepthGauge extends StatelessWidget {
  final SlotAction? action;

  const _MusicDepthGauge({required this.action});

  // Échelle music mode : head(1) en haut → full(4) en bas.
  static const _rows = [
    Position.head,
    Position.mid,
    Position.throat,
    Position.full,
  ];

  /// Alignement vertical (-0.8 = haut/head, 0.8 = bas/full).
  static double _alignY(Position p) {
    final frac = (p.index - Position.head.index) /
        (Position.full.index - Position.head.index);
    return -0.8 + frac.clamp(0.0, 1.0) * 1.6;
  }

  @override
  Widget build(BuildContext context) {
    final a = action;
    final target = a?.depth ?? Position.head;
    final beatMs = (a == null || a.bpm <= 0) ? 400 : (60000 / a.bpm).round();
    final kind = a?.kind ?? SlotActionKind.release;

    return Stack(
      children: [
        // Lignes-repères + labels de profondeur.
        for (final p in _rows)
          Align(
            alignment: Alignment(0, _alignY(p)),
            child: Row(
              children: [
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppTheme.textMuted.withValues(alpha: 0.18),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        // Curseur de profondeur.
        AnimatedAlign(
          alignment: Alignment(0, _alignY(target)),
          duration: Duration(milliseconds: beatMs),
          curve: Curves.easeInOut,
          child: _Cursor(kind: kind, beatKey: a?.beatIndex ?? 0),
        ),
      ],
    );
  }
}

class _Cursor extends StatelessWidget {
  final SlotActionKind kind;
  final int beatKey;

  const _Cursor({required this.kind, required this.beatKey});

  @override
  Widget build(BuildContext context) {
    final isStrike = kind == SlotActionKind.strike;
    final isHold = kind == SlotActionKind.hold;
    final color =
        kind == SlotActionKind.release ? AppTheme.textMuted : AppTheme.accent;
    final orb = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isHold ? Colors.transparent : color,
        border: isHold ? Border.all(color: color, width: 3) : null,
        boxShadow: isStrike
            ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 16)]
            : null,
      ),
    );
    // « Pop » à chaque frappe : redémarre l'échelle à chaque nouveau battement.
    if (!isStrike) return Opacity(opacity: 0.85, child: orb);
    return TweenAnimationBuilder<double>(
      key: ValueKey(beatKey),
      tween: Tween(begin: 1.35, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: orb,
    );
  }
}
