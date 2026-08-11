import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La durée annoncée au moment du choix ne doit pas promettre un chiffre
/// faux : un défi ne prend rien à la séance, son temps s'y ajoute. Une
/// « Moyenne » à 3 défis annonçait « 25 min » pour ~35 min vécues.
///
/// Ce test couvre les deux risques du changement : la substitution du
/// placeholder dans les 4 langues, et la tenue de la mise en page une fois
/// le vrai texte écrit (un libellé provisoire court peut masquer un
/// débordement). Il reconstruit les contraintes de `_LevelTitleCard`
/// (Container padding 16, icône 20 + gap 12, texte dans un Expanded,
/// fontSize 12) sur l'écran le plus étroit visé ; la carte elle-même est
/// privée à `career_screen.dart`. La police de test (Ahem) rend chaque
/// glyphe carré, soit environ deux fois plus large que Roboto : ce qui
/// tient ici tient a fortiori en vrai.
void main() {
  const narrowest = 320.0;

  Widget host(Locale locale, String Function(AppLocalizations) label) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Builder(builder: (context) {
                final t = AppLocalizations.of(context);
                return Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.workspace_premium_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('NIVEAU',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(label(t),
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      );

  for (final lang in const ['fr', 'en', 'de', 'es']) {
    testWidgets('$lang : la mention défis compose la durée sans déborder',
        (tester) async {
      tester.view.physicalSize = const Size(narrowest, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Référence une ligne : le chiffre nu, tel qu'affiché aujourd'hui.
      await tester.pumpWidget(host(Locale(lang), (_) => '25 min'));
      final oneLine = tester.getSize(find.text('25 min')).height;

      await tester.pumpWidget(host(
        Locale(lang),
        (t) => t.careerDurationPlusChallenges('25 min'),
      ));
      expect(tester.takeException(), isNull);

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .firstWhere((s) => s.contains('25 min'));
      expect(rendered, isNot('25 min'),
          reason: 'la mention doit compléter la durée, pas la remplacer');
      // La carte reste dans l'écran : le texte enveloppe au lieu de pousser.
      expect(tester.getSize(find.byType(Row).first).width,
          lessThanOrEqualTo(narrowest - 40 - 32));
      // Budget : 2 lignes en Ahem, soit environ une seule en Roboto. Au-delà,
      // la mention n'est plus « courte » et pousse le reste de l'écran.
      expect(tester.getSize(find.text(rendered)).height,
          lessThanOrEqualTo(2 * oneLine),
          reason: 'mention trop longue en $lang : « $rendered »');
    });
  }

  testWidgets('sans défis, la durée reste le chiffre nu', (tester) async {
    await tester.pumpWidget(host(const Locale('fr'), (_) => '25 min'));
    expect(find.text('25 min'), findsOneWidget);
  });
}
