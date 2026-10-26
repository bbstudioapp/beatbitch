import 'package:flutter/material.dart';

import '../models/badge.dart';
import '../theme/app_theme.dart';

String badgeAssetPath(BadgeFamily family) => switch (family) {
      BadgeFamily.marathonien => 'assets/badges/marathonien.png',
      BadgeFamily.throatQueen => 'assets/badges/throat_queen.png',
      BadgeFamily.ironLungs => 'assets/badges/iron_lungs.png',
      BadgeFamily.toutTerrain => 'assets/badges/tout_terrain.png',
      BadgeFamily.sansBroncher => 'assets/badges/sans_broncher.png',
      BadgeFamily.reguliere => 'assets/badges/reguliere.png',
      BadgeFamily.jamaisRassasiee => 'assets/badges/jamais_rassasiee.png',
      BadgeFamily.videCouilles => 'assets/badges/vide_couilles.png',
      BadgeFamily.bouchePleine => 'assets/badges/bouche_pleine.png',
      BadgeFamily.repeinte => 'assets/badges/repeinte.png',
      BadgeFamily.gobeuse => 'assets/badges/gobeuse.png',
      BadgeFamily.nettoyeuse => 'assets/badges/nettoyeuse.png',
      BadgeFamily.suppliante => 'assets/badges/suppliante.png',
      BadgeFamily.sabbat => 'assets/badges/sabbat.png',
    };

Color badgeTierColor(BadgeTier tier) => switch (tier) {
      BadgeTier.none => AppTheme.textMuted,
      BadgeTier.bronze => const Color(0xFFB87333),
      BadgeTier.silver => const Color(0xFFC0C0C0),
      BadgeTier.gold => const Color(0xFFFFD700),
      BadgeTier.platinium => const Color(0xFFE5E4E2),
    };

const ColorFilter _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

class BadgeEmblem extends StatelessWidget {
  final BadgeFamily family;
  final BadgeTier tier;
  final double size;

  const BadgeEmblem({
    super.key,
    required this.family,
    required this.tier,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final ringWidth = size * 0.07;
    Widget medal = Image.asset(
      badgeAssetPath(family),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    if (tier == BadgeTier.none) {
      medal = Opacity(
        opacity: 0.45,
        child: ColorFiltered(colorFilter: _grayscale, child: medal),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        key: const ValueKey('badge-emblem-ring'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: badgeTierColor(tier), width: ringWidth),
        ),
        child: Padding(padding: EdgeInsets.all(ringWidth), child: medal),
      ),
    );
  }
}
