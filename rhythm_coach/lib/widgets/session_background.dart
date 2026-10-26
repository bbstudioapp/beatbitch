import 'package:flutter/material.dart';

import '../services/backgrounds_loader.dart';
import '../services/backgrounds_service.dart';
import '../theme/app_theme.dart';
import 'play_once_image.dart';

class SessionBackground extends StatelessWidget {
  final bool mediaEnabled;

  final bool bottomVeilOnly;

  const SessionBackground({
    super.key,
    this.mediaEnabled = true,
    this.bottomVeilOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: !mediaEnabled
          ? const _AmbientGradient()
          : ValueListenableBuilder<BackgroundEntry?>(
              valueListenable: BackgroundsService.instance.current,
              builder: (context, entry, _) {
                // Clé de repli partagée : pas de re-fade quand le service repasse à null entre deux médias.
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: entry == null
                      ? const _AmbientGradient(key: ValueKey('__placeholder__'))
                      : _MediaBackground(
                          entry: entry,
                          bottomVeilOnly: bottomVeilOnly,
                          key: ValueKey(entry.id)),
                );
              },
            ),
    );
  }
}

class _MediaBackground extends StatelessWidget {
  final BackgroundEntry entry;
  final bool bottomVeilOnly;

  const _MediaBackground(
      {required this.entry, required this.bottomVeilOnly, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        switch (entry.type) {
          _ when entry.isTierTransition || entry.isPov || entry.isMilestone =>
            PlayOnceImage(
              path: entry.path,
              onDone: () =>
                  BackgroundsService.instance.transitionFinished(entry),
            ),
          BackgroundMediaType.image || BackgroundMediaType.gif => Image.asset(
              entry.path,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const _AmbientGradient(),
            ),
        },
        // Voile plutôt que `opacity` d'Image : l'opacité rend transparents les pixels clairs autant que les sombres.
        DecoratedBox(
          decoration: bottomVeilOnly
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.5, 0.78, 1.0],
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x99000000),
                      Color(0xD9000000),
                    ],
                  ),
                )
              : const BoxDecoration(color: Color(0x73000000)),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }
}

class _AmbientGradient extends StatefulWidget {
  const _AmbientGradient({super.key});

  @override
  State<_AmbientGradient> createState() => _AmbientGradientState();
}

class _AmbientGradientState extends State<_AmbientGradient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        final centerX = -0.12 + 0.24 * t;
        final centerY = -0.18 + 0.36 * t;
        final warm = Color.lerp(
          AppTheme.accent.withValues(alpha: 0.18),
          const Color(0xFF7E57C2).withValues(alpha: 0.16),
          t,
        )!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(centerX, centerY),
              radius: 1.2,
              colors: [
                warm,
                AppTheme.background,
              ],
              stops: const [0.0, 0.85],
            ),
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
