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
  CapabilityProfile? _profile;
  bool _debug = false;
  bool _useMic = false;
  bool _started = false; // micro : capture lancée (écoute/lecture)

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
      _profile = profile;
      _controller = _make();
    });
  }

  MusicSessionController _make() => MusicSessionController(
        beep: widget.beep,
        profile: _profile,
        ignoreGating: _debug,
        useMic: _useMic,
      );

  void _rebuild() {
    _controller?.dispose();
    _controller = _make();
    _started = false;
  }

  /// Bascule le mode debug (ignore le gating) — recrée le contrôleur.
  void _toggleDebug() => setState(() {
        _debug = !_debug;
        _rebuild();
      });

  /// Bascule source tap ↔ micro — recrée le contrôleur.
  void _setMic(bool mic) {
    if (mic == _useMic) return;
    setState(() {
      _useMic = mic;
      _rebuild();
    });
  }

  /// Démarre (tap : nécessite un tempo ; micro : lance l'écoute + permission).
  Future<void> _onStart(MusicSessionController c) async {
    final ok = await c.start();
    if (!mounted) return;
    if (_useMic && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).musicMicDenied)),
      );
      return;
    }
    setState(() => _started = true);
  }

  void _onStop(MusicSessionController c) {
    c.stop();
    setState(() => _started = false);
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
      appBar: AppBar(
        title: Text(t.modeSelectionMusicTitle),
        actions: [
          IconButton(
            tooltip: t.musicDebugTooltip,
            icon: Icon(
              Icons.bug_report_outlined,
              color: _debug ? AppTheme.accent : AppTheme.textMuted,
            ),
            onPressed: _toggleDebug,
          ),
        ],
      ),
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
    final locked = _started || c.isRunning;
    final running = _useMic ? _started : c.isRunning;
    final canStart = _useMic || c.hasTempo;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(t.musicSourceTap),
                icon: const Icon(Icons.touch_app_outlined),
              ),
              ButtonSegment(
                value: true,
                label: Text(t.musicSourceMic),
                icon: const Icon(Icons.mic_none_outlined),
              ),
            ],
            selected: {_useMic},
            onSelectionChanged: locked ? null : (s) => _setMic(s.first),
          ),
          const SizedBox(height: 12),
          Text(
            _useMic ? t.musicMicHint : t.musicTapPrompt,
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
          Expanded(child: _box(t, c)),
          const SizedBox(height: 16),
          if (!_useMic && !c.isStable && !c.isRunning)
            Text(
              t.musicWaitingTempo,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: !canStart
                  ? null
                  : (running ? () => _onStop(c) : () => _onStart(c)),
              child: Text(running ? t.musicStop : t.musicStart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(AppLocalizations t, MusicSessionController c) {
    final Widget content;
    if (c.isRunning && c.currentPattern != null) {
      content = _PatternView(
        pattern: c.currentPattern!,
        cursor: c.currentSlot,
        slotInterval: c.slotInterval ?? const Duration(milliseconds: 400),
      );
    } else if (_useMic && _started) {
      // Intro micro : on écoute jusqu'au verrou du tempo.
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.graphic_eq, color: AppTheme.accent, size: 40),
          const SizedBox(height: 12),
          Text(t.musicListening,
              style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    } else if (_useMic) {
      content = const Icon(Icons.mic_none_outlined,
          color: AppTheme.textMuted, size: 48);
    } else {
      content = Text(
        t.musicTapAction,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 22,
          letterSpacing: 2,
        ),
      );
    }

    final box = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: content),
    );

    // Mode tap, pas encore lancé : taper dans le cadre pose le tempo.
    if (!_useMic && !c.isRunning) {
      return GestureDetector(onTap: c.tap, child: box);
    }
    return box;
  }
}

/// Affichage du pattern courant (style séquenceur, debug + lisibilité) : une
/// colonne par slot, `y` = profondeur jouée (head haut → full bas), avec la
/// **tête de lecture** sur le slot en cours. La même figure est répétée
/// plusieurs boucles (cf. `MusicSessionEngine.repeatLoops`) → on la voit
/// boucler avant de changer.
class _PatternView extends StatefulWidget {
  final BeatPattern pattern;
  final int cursor;
  final Duration slotInterval;

  const _PatternView({
    required this.pattern,
    required this.cursor,
    required this.slotInterval,
  });

  @override
  State<_PatternView> createState() => _PatternViewState();
}

class _PatternViewState extends State<_PatternView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.slotInterval)
      ..forward();
  }

  @override
  void didUpdateWidget(_PatternView old) {
    super.didUpdateWidget(old);
    _ctrl.duration = widget.slotInterval;
    // Nouveau slot → la tête de lecture glisse de ce slot vers le suivant.
    if (old.cursor != widget.cursor) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _PatternPainter(
            pattern: widget.pattern,
            cursor: widget.cursor,
            frac: _ctrl.value,
          ),
        ),
      );
}

class _PatternPainter extends CustomPainter {
  final BeatPattern pattern;
  final int cursor;

  /// Progression dans le slot courant (0→1) — pour la tête de lecture fluide.
  final double frac;

  _PatternPainter({
    required this.pattern,
    required this.cursor,
    required this.frac,
  });

  // Échelle complète : `tip` en haut (ancre la plus haute) → `full` en bas.
  static const _rows = [
    Position.tip,
    Position.head,
    Position.mid,
    Position.throat,
    Position.full,
  ];
  static const _leftPad = 52.0;
  static const _rightPad = 14.0;
  static const _vPad = 26.0;

  double _y(Position p, double h) {
    final frac = p.index / Position.full.index; // tip(0)..full(4)
    return _vPad + frac.clamp(0.0, 1.0) * (h - 2 * _vPad);
  }

  /// Profondeur affichée par slot (la **courbe du mouvement**) :
  /// - frappe → sa profondeur (creux sur le temps) ;
  /// - hold → la profondeur tenue (palier) ;
  /// - release → l'**ancre** : un cran au-dessus de la plus haute des deux
  ///   frappes voisines (donc `tip` entre des frappes head/mid).
  List<Position> _displayDepths() {
    final slots = pattern.slots;
    final n = slots.length;
    // Prochaine frappe (lookahead **cyclique** : la dernière ancre tient compte
    // de la 1ʳᵉ frappe, donc reste au-dessus du premier temps).
    Position? firstStrike;
    for (final s in slots) {
      if (s.onset == SlotOnset.strike) {
        firstStrike = s.to;
        break;
      }
    }
    final nextStrike = List<Position?>.filled(n, null);
    Position? nxt;
    for (var i = n - 1; i >= 0; i--) {
      if (slots[i].onset == SlotOnset.strike) nxt = slots[i].to;
      nextStrike[i] = nxt;
    }
    final out = <Position>[];
    var running = pattern.anchor; // dernière frappe (défaut = ancre)
    for (var i = 0; i < n; i++) {
      switch (slots[i].onset) {
        case SlotOnset.strike:
          running = slots[i].to!;
          out.add(running);
        case SlotOnset.hold:
          out.add(running);
        case SlotOnset.release:
          final next = nextStrike[i] ?? firstStrike ?? running;
          final shallower = running.index <= next.index ? running : next;
          final idx = (shallower.index - 1).clamp(0, Position.full.index);
          out.add(Position.values[idx]);
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

    // Tête de lecture fluide : glisse du slot courant vers le suivant.
    final headX = colX(cursor) + frac.clamp(0.0, 1.0) * colW;
    canvas.drawLine(
      Offset(headX, _vPad - 10),
      Offset(headX, size.height - _vPad + 10),
      Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.55)
        ..strokeWidth = 2,
    );

    Offset pt(int i) => Offset(colX(i), _y(depths[i], size.height));

    // Courbe du mouvement **arrondie qui passe par les nœuds** (Catmull-Rom →
    // cubiques de Bézier) : reliant frappes (creux) et ancres (sommets) sans
    // couper les angles sur les changements brusques.
    final line = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.5)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    Offset clampPt(int i) => pt(i.clamp(0, n - 1));
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final p0 = clampPt(i - 1);
      final p1 = pt(i);
      final p2 = pt(i + 1);
      final p3 = clampPt(i + 2);
      final c1 =
          Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 =
          Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    canvas.drawPath(path, line);

    // Paliers de hold : segment épais à la profondeur tenue.
    final holdPaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < n; i++) {
      if (pattern.slots[i].onset == SlotOnset.hold) {
        canvas.drawLine(pt(i - 1), pt(i), holdPaint);
      }
    }

    // Nodes : frappe = creux plein, ancre (release) = sommet plein plus petit.
    for (var i = 0; i < n; i++) {
      final onset = pattern.slots[i].onset;
      if (onset == SlotOnset.hold) continue; // matérialisé par le palier
      final o = pt(i);
      final isNow = i == cursor;
      if (isNow) {
        canvas.drawCircle(
            o, 13, Paint()..color = AppTheme.accent.withValues(alpha: 0.25));
      }
      final isStrike = onset == SlotOnset.strike;
      final r = isStrike ? (isNow ? 8.0 : 5.0) : (isNow ? 5.0 : 3.0);
      canvas.drawCircle(
        o,
        r,
        Paint()
          ..color = AppTheme.accent.withValues(alpha: isStrike ? 1.0 : 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.frac != frac ||
      old.cursor != cursor ||
      !identical(old.pattern, pattern);
}
