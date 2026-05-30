import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session_step.dart' show Position;
import '../music/music_session_controller.dart';
import '../music/slot_action.dart';
import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import '../theme/app_theme.dart';

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
                    ? _DepthTimeline(
                        recent: c.recent,
                        upcoming: c.upcoming(12),
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

/// Timeline de profondeur : passé court (gauche) · **NOW** · slots à venir
/// (droite, pour anticiper). `y` = profondeur (head haut → full bas), nodes
/// par nature (frappe pleine, hold anneau, release petit point). La courbe
/// défile vers la gauche à chaque battement. Cf. `specs/music_mode.md` §9.
class _DepthTimeline extends StatelessWidget {
  /// Historique récent (du plus ancien au plus récent ; le dernier = NOW).
  final List<SlotAction> recent;

  /// Slots à venir (du prochain au plus lointain).
  final List<({SlotActionKind kind, Position depth})> upcoming;

  const _DepthTimeline({required this.recent, required this.upcoming});

  @override
  Widget build(BuildContext context) {
    final r = recent.length <= 5 ? recent : recent.sublist(recent.length - 5);
    final past = [for (final a in r) (kind: a.kind, depth: a.depth)];
    return CustomPaint(
      size: Size.infinite,
      painter: _TimelinePainter(past: past, upcoming: upcoming),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<({SlotActionKind kind, Position depth})> past;
  final List<({SlotActionKind kind, Position depth})> upcoming;

  _TimelinePainter({required this.past, required this.upcoming});

  static const _rows = [
    Position.head,
    Position.mid,
    Position.throat,
    Position.full,
  ];
  static const _leftPad = 52.0;
  static const _rightPad = 14.0;
  static const _vPad = 26.0;

  double _y(Position p, double h) {
    final frac = (p.index - Position.head.index) /
        (Position.full.index - Position.head.index);
    return _vPad + frac.clamp(0.0, 1.0) * (h - 2 * _vPad);
  }

  double _x(int i, int n, double w) {
    if (n <= 1) return _leftPad;
    return _leftPad + i / (n - 1) * (w - _leftPad - _rightPad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Lignes-repères + labels.
    final guide = Paint()
      ..color = AppTheme.textMuted.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (final p in _rows) {
      final y = _y(p, size.height);
      canvas.drawLine(
          Offset(_leftPad, y), Offset(size.width - _rightPad, y), guide);
      final tp = TextPainter(
        text: TextSpan(
          text: p.name,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, y - tp.height / 2));
    }

    final points = [...past, ...upcoming];
    if (points.isEmpty) return;
    final n = points.length;
    final nowIdx = past.isEmpty ? 0 : past.length - 1;

    // Courbe : passé plein, futur atténué.
    for (var seg = 0; seg < 2; seg++) {
      final isPast = seg == 0;
      final paint = Paint()
        ..color = AppTheme.accent.withValues(alpha: isPast ? 0.85 : 0.30)
        ..strokeWidth = isPast ? 2.5 : 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      final lo = isPast ? 0 : nowIdx;
      final hi = isPast ? nowIdx : n - 1;
      var started = false;
      for (var i = lo; i <= hi; i++) {
        final o =
            Offset(_x(i, n, size.width), _y(points[i].depth, size.height));
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    // Ligne NOW.
    final nowX = _x(nowIdx, n, size.width);
    canvas.drawLine(
      Offset(nowX, _vPad - 8),
      Offset(nowX, size.height - _vPad + 8),
      Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );

    // Nodes.
    for (var i = 0; i < n; i++) {
      final isNow = i == nowIdx;
      final isFuture = i > nowIdx;
      final o = Offset(_x(i, n, size.width), _y(points[i].depth, size.height));
      final a = isFuture ? 0.45 : 1.0;
      final color = points[i].kind == SlotActionKind.release
          ? AppTheme.textMuted.withValues(alpha: a)
          : AppTheme.accent.withValues(alpha: a);
      switch (points[i].kind) {
        case SlotActionKind.strike:
          if (isNow) {
            canvas.drawCircle(
              o,
              11,
              Paint()..color = AppTheme.accent.withValues(alpha: 0.25),
            );
          }
          canvas.drawCircle(o, isNow ? 7 : 4.5, Paint()..color = color);
        case SlotActionKind.hold:
          canvas.drawCircle(
            o,
            isNow ? 7 : 4.5,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        case SlotActionKind.release:
          canvas.drawCircle(o, isNow ? 4 : 2.5, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) => true;
}
