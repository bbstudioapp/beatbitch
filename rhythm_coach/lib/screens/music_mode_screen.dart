import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/session_step.dart' show Position;
import '../music/beat_pattern.dart';
import '../music/music_session_controller.dart';
import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import '../theme/app_theme.dart';

/// Écran du mode Music (PR1) : taper le tempo, démarrer, voir le pattern joué
/// (séquenceur) avec sa tête de lecture. Cf. `specs/music_mode.md` §9.
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
                child: c.isRunning && c.currentPattern != null
                    ? _PatternView(
                        pattern: c.currentPattern!,
                        cursor: c.currentSlot,
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

/// Affichage du pattern courant (style séquenceur, debug + lisibilité) : une
/// colonne par slot, `y` = profondeur jouée (head haut → full bas), avec la
/// **tête de lecture** sur le slot en cours. La même figure est répétée
/// plusieurs phrases (cf. `MusicSessionEngine.repeatPhrases`) → on la voit
/// boucler avant de changer.
class _PatternView extends StatelessWidget {
  final BeatPattern pattern;
  final int cursor;

  const _PatternView({required this.pattern, required this.cursor});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: _PatternPainter(pattern: pattern, cursor: cursor),
      );
}

class _PatternPainter extends CustomPainter {
  final BeatPattern pattern;
  final int cursor;

  _PatternPainter({required this.pattern, required this.cursor});

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

  /// Profondeur affichée par slot : la cible pour une frappe, la profondeur
  /// tenue pour un hold, l'ancre pour un release.
  List<Position> _displayDepths() {
    final out = <Position>[];
    var last = pattern.anchor;
    for (final s in pattern.slots) {
      switch (s.onset) {
        case SlotOnset.strike:
          last = s.to!;
          out.add(last);
        case SlotOnset.hold:
          out.add(last);
        case SlotOnset.release:
          out.add(pattern.anchor);
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final depths = _displayDepths();
    final n = depths.length;
    final trackW = size.width - _leftPad - _rightPad;
    final colW = n == 0 ? trackW : trackW / n;
    double colX(int i) => _leftPad + colW * (i + 0.5);

    // Lignes-repères + labels de profondeur.
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
    if (n == 0) return;

    // Bande de la tête de lecture.
    if (cursor >= 0 && cursor < n) {
      final cx = colX(cursor);
      canvas.drawRect(
        Rect.fromLTRB(
            cx - colW / 2, _vPad - 10, cx + colW / 2, size.height - _vPad + 10),
        Paint()..color = AppTheme.accent.withValues(alpha: 0.12),
      );
    }

    // Contour (relie les nodes) pour lire la forme du pattern.
    final line = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final o = Offset(colX(i), _y(depths[i], size.height));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, line);

    // Nodes par nature de slot.
    for (var i = 0; i < n; i++) {
      final o = Offset(colX(i), _y(depths[i], size.height));
      final isNow = i == cursor;
      final onset = pattern.slots[i].onset;
      final color =
          onset == SlotOnset.release ? AppTheme.textMuted : AppTheme.accent;
      if (isNow) {
        canvas.drawCircle(
            o, 13, Paint()..color = AppTheme.accent.withValues(alpha: 0.25));
      }
      final r = isNow ? 8.0 : 5.0;
      switch (onset) {
        case SlotOnset.strike:
          canvas.drawCircle(o, r, Paint()..color = color);
        case SlotOnset.hold:
          canvas.drawCircle(
            o,
            r,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );
        case SlotOnset.release:
          canvas.drawCircle(o, isNow ? 5 : 3, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.cursor != cursor || !identical(old.pattern, pattern);
}
