import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session_step.dart' show Position;
import '../music/music_session_controller.dart';
import '../music/slot_action.dart';
import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import '../theme/app_theme.dart';

/// Écran du mode Music (PR1) : taper le tempo, démarrer, voir la courbe de
/// profondeur défiler en live. Cf. `specs/music_mode.md` §9.
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
    final profile = await CapabilityService().snapshotProfile();
    if (!mounted) return;
    setState(() {
      _controller = MusicSessionController(beep: widget.beep, profile: profile);
    });
  }

  @override
  void dispose() {
    // On ne dispose que le contrôleur : le BeepEngine est partagé (propriété
    // de ModeSelectionScreen).
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
                child: Center(
                  child: c.recent.isEmpty
                      ? Text(
                          c.isRunning ? '' : t.musicTapAction,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 22,
                            letterSpacing: 2,
                          ),
                        )
                      : CustomPaint(
                          size: Size.infinite,
                          painter: _DepthCurvePainter(c.recent),
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

/// Trace la courbe des profondeurs récentes : chaque action est un point,
/// `y` = profondeur (plus bas = plus profond), reliés par une ligne. Les
/// frappes sont pleines, les holds en anneau, les releases en petit tiret.
class _DepthCurvePainter extends CustomPainter {
  final List<SlotAction> actions;

  _DepthCurvePainter(this.actions);

  // Profondeurs jouables en music mode : head(1)..full(4).
  static const _minIdx = 1; // head
  static const _maxIdx = 4; // full

  double _y(Position p, double h) {
    final norm = (p.index - _minIdx) / (_maxIdx - _minIdx);
    return 16 + norm.clamp(0.0, 1.0) * (h - 32);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (actions.isEmpty) return;
    final n = actions.length;
    final dx = n == 1 ? 0.0 : (size.width - 32) / (n - 1);

    final line = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = 16 + i * dx;
      final y = _y(actions[i].depth, size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);

    for (var i = 0; i < n; i++) {
      final x = 16 + i * dx;
      final y = _y(actions[i].depth, size.height);
      final a = actions[i];
      switch (a.kind) {
        case SlotActionKind.strike:
          canvas.drawCircle(
            Offset(x, y),
            5,
            Paint()..color = AppTheme.accent,
          );
        case SlotActionKind.hold:
          canvas.drawCircle(
            Offset(x, y),
            5,
            Paint()
              ..color = AppTheme.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        case SlotActionKind.release:
          canvas.drawCircle(
            Offset(x, y),
            2,
            Paint()..color = AppTheme.textMuted,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_DepthCurvePainter oldDelegate) =>
      oldDelegate.actions.length != actions.length ||
      !identical(oldDelegate.actions, actions);
}
