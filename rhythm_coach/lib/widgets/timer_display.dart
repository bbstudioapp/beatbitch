import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TimerDisplay extends StatelessWidget {
  final Duration elapsed;
  final Duration total;

  const TimerDisplay({
    super.key,
    required this.elapsed,
    required this.total,
  });

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _format(elapsed),
          style: const TextStyle(
            fontSize: 96,
            fontWeight: FontWeight.w200,
            letterSpacing: 4,
            color: AppTheme.textPrimary,
            height: 1.0,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '/ ${_format(total)}',
          style: const TextStyle(
            fontSize: 18,
            color: AppTheme.textMuted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
