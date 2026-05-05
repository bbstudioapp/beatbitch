import 'package:flutter/material.dart';

import '../l10n/enum_labels.dart';
import '../models/session.dart';
import '../models/session_step.dart';
import '../theme/app_theme.dart';

class ModeBadgeRow extends StatelessWidget {
  final SessionMode mode;
  final Position from;
  final Position? to;
  final int bpm;

  const ModeBadgeRow({
    super.key,
    required this.mode,
    required this.from,
    required this.to,
    required this.bpm,
  });

  @override
  Widget build(BuildContext context) {
    final showPosition = mode == SessionMode.rhythm ||
        mode == SessionMode.lick ||
        mode == SessionMode.hand ||
        mode == SessionMode.hold ||
        mode == SessionMode.beg;
    final showBpm = mode == SessionMode.rhythm ||
        mode == SessionMode.lick ||
        mode == SessionMode.hand ||
        mode == SessionMode.biffle;

    final color = _modeColor(mode);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _Badge(
          label: mode.shortLabel(context),
          color: color,
          filled: true,
          icon: _modeIcon(mode),
        ),
        if (showBpm)
          _Badge(
            label: '$bpm BPM',
            color: color,
          ),
        if (showPosition)
          _Badge(
            label: _positionLabel(from, to, mode),
            color: color,
          ),
      ],
    );
  }

  static IconData _modeIcon(SessionMode m) => switch (m) {
        SessionMode.rhythm => Icons.graphic_eq,
        SessionMode.hold => Icons.pause_circle_filled,
        SessionMode.lick => Icons.water_drop,
        SessionMode.biffle => Icons.flash_on,
        SessionMode.breath => Icons.air,
        SessionMode.beg => Icons.record_voice_over,
        SessionMode.freestyle => Icons.shuffle,
        SessionMode.hand => Icons.back_hand,
      };

  static Color _modeColor(SessionMode m) => switch (m) {
        SessionMode.rhythm => AppTheme.accent,
        SessionMode.lick => const Color(0xFF4FC3F7),
        SessionMode.hold => const Color(0xFFFFD54F),
        SessionMode.biffle => const Color(0xFFEF5350),
        SessionMode.breath => const Color(0xFF81C784),
        SessionMode.beg => const Color(0xFFCE93D8),
        SessionMode.freestyle => const Color(0xFFB0BEC5),
        SessionMode.hand => const Color(0xFFFFAB91),
      };

  static String _positionLabel(Position from, Position? to, SessionMode mode) {
    final f = _positionName(from);
    if (to == null ||
        to == from ||
        mode == SessionMode.hold ||
        mode == SessionMode.beg) {
      return f;
    }
    return '$f → ${_positionName(to)}';
  }

  static String _positionName(Position p) => switch (p) {
        Position.tip => 'tip',
        Position.head => 'head',
        Position.mid => 'mid',
        Position.throat => 'throat',
        Position.full => 'full',
      };
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;

  const _Badge({
    required this.label,
    required this.color,
    this.filled = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.black : color;
    final bg = filled ? color : color.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: filled ? color : color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
