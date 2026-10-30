import 'dart:io';

import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/badge.dart';
import 'package:beat_bitch/screens/profile_screen.dart';
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/badge_service.dart';
import 'package:beat_bitch/theme/app_theme.dart';
import 'package:beat_bitch/widgets/badge_emblem.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _ringKey = ValueKey('badge-emblem-ring');

Widget _host(Widget child, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

Color _ringColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byKey(_ringKey));
  return ((box.decoration as BoxDecoration).border as Border).top.color;
}

BadgeState _state(BadgeFamily family, BadgeTier tier) => BadgeState(
      definition: BadgeDefinition.forFamily(family),
      tier: tier,
      value: 7,
    );

void main() {
  group('table famille → image', () {
    test('chaque famille a un fichier distinct sur disque', () {
      final paths = {for (final f in BadgeFamily.values) badgeAssetPath(f)};
      expect(paths.length, BadgeFamily.values.length);
      for (final p in paths) {
        expect(File(p).existsSync(), isTrue, reason: p);
        expect(File(p).lengthSync(), lessThan(60 * 1024), reason: p);
      }
    });

    test('chaque image est déclarée dans le bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final f in BadgeFamily.values) {
        final data = await rootBundle.load(badgeAssetPath(f));
        expect(data.lengthInBytes, greaterThan(0), reason: f.name);
      }
    });
  });

  group('BadgeEmblem', () {
    for (final family in BadgeFamily.values) {
      testWidgets('${family.name} rend son image', (tester) async {
        await tester.pumpWidget(
            _host(BadgeEmblem(family: family, tier: BadgeTier.gold, size: 44)));
        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as AssetImage).assetName, badgeAssetPath(family));
      });
    }

    testWidgets('le palier se lit à la couleur de l\'anneau', (tester) async {
      final expected = {
        BadgeTier.bronze: const Color(0xFFB87333),
        BadgeTier.silver: const Color(0xFFC0C0C0),
        BadgeTier.gold: const Color(0xFFFFD700),
        BadgeTier.platinium: const Color(0xFFE5E4E2),
      };
      for (final e in expected.entries) {
        await tester.pumpWidget(_host(BadgeEmblem(
            family: BadgeFamily.throatQueen, tier: e.key, size: 44)));
        expect(_ringColor(tester), e.value, reason: e.key.name);
      }
    });

    testWidgets('débloqué : médaillon en couleurs, pleinement opaque',
        (tester) async {
      await tester.pumpWidget(_host(const BadgeEmblem(
          family: BadgeFamily.gobeuse, tier: BadgeTier.bronze, size: 44)));
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('non débloqué : médaillon grisé, atténué, anneau neutre',
        (tester) async {
      await tester.pumpWidget(_host(const BadgeEmblem(
          family: BadgeFamily.gobeuse, tier: BadgeTier.none, size: 44)));
      expect(find.byType(ColorFiltered), findsOneWidget);
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1));
      expect(_ringColor(tester), AppTheme.textMuted);
    });
  });

  group('où s\'affichent les badges', () {
    testWidgets('carte du Profil : emblème de la famille, plus de trophée',
        (tester) async {
      await tester.pumpWidget(_host(
          BadgeCard(state: _state(BadgeFamily.suppliante, BadgeTier.silver))));
      final emblem = tester.widget<BadgeEmblem>(find.byType(BadgeEmblem));
      expect(emblem.family, BadgeFamily.suppliante);
      expect(emblem.tier, BadgeTier.silver);
      expect(emblem.size, inInclusiveRange(40, 48));
      expect(find.byIcon(Icons.emoji_events), findsNothing);
      expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
    });

    for (final locale in const ['fr', 'en', 'de', 'es']) {
      for (final width in const [320.0, 350.0]) {
        testWidgets(
            'grille du Profil : aucune famille ne déborde '
            '($locale, ${width.toInt()} dp)', (tester) async {
          await tester.pumpWidget(_host(
            SizedBox(
              width: width,
              child: BadgesGrid(states: [
                for (final def in BadgeDefinition.catalog)
                  _state(def.family, BadgeTier.platinium),
              ]),
            ),
            locale: Locale(locale),
          ));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('fin de séance : tuile de déblocage avec l\'emblème',
        (tester) async {
      await tester.pumpWidget(_host(BadgeUnlockTile(
        unlock: BadgeUnlock(
          definition: BadgeDefinition.forFamily(BadgeFamily.repeinte),
          tier: BadgeTier.gold,
        ),
      )));
      final emblem = tester.widget<BadgeEmblem>(find.byType(BadgeEmblem));
      expect(emblem.family, BadgeFamily.repeinte);
      expect(emblem.tier, BadgeTier.gold);
      expect(find.byIcon(Icons.emoji_events), findsNothing);
    });
  });
}
