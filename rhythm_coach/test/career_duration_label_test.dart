import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/l10n/enum_labels.dart';
import 'package:beat_bitch/l10n/format_helpers.dart';
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
///
/// Les libellés testés sont les **vrais** libellés de paliers, pas un
/// exemple : « Surprise » n'est pas un nombre, et « Überraschung » fait le
/// double de « ~6 Min. ».
void main() {
  // La carte est élastique : c'est la plus étroite qui contraint le plus,
  // mais un texte allemand recomposé se relit sur toute la gamme de
  // téléphones visée.
  const widths = [320.0, 360.0, 400.0, 480.0];

  /// Le libellé de base tel que le calcule `career_screen.dart`.
  String baseLabel(BuildContext context, SessionLengthChoice choice) =>
      choice == SessionLengthChoice.aleatoire
          ? choice.localizedDuration(context)
          : formatDurationCompact(context, choice.durationSeconds);

  Widget host(Locale locale, String Function(BuildContext) f) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Builder(builder: (context) {
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
                            Text(f(context),
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
    for (final choice in SessionLengthChoice.values) {
      for (final width in widths) {
        testWidgets(
            '$lang / ${choice.name} / ${width.toInt()} dp : la mention défis '
            'compose la durée sans déborder', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          // Référence une ligne : le libellé nu du palier, tel qu'affiché
          // quand les défis sont désactivés.
          await tester
              .pumpWidget(host(Locale(lang), (ctx) => baseLabel(ctx, choice)));
          final base = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .last;
          final oneLine = tester.getSize(find.text(base)).height;

          await tester.pumpWidget(host(
            Locale(lang),
            (ctx) => AppLocalizations.of(ctx)
                .careerDurationPlusChallenges(baseLabel(ctx, choice)),
          ));
          expect(tester.takeException(), isNull);

          final rendered = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .firstWhere((s) => s.contains(base));
          expect(rendered, isNot(base),
              reason: 'la mention doit compléter la durée, pas la remplacer');
          // La carte reste dans l'écran : le texte enveloppe au lieu de pousser.
          expect(tester.getSize(find.byType(Row).first).width,
              lessThanOrEqualTo(width - 40 - 32));
          // Budget : 2 lignes en Ahem, soit environ une seule en Roboto.
          // Au-delà, la mention n'est plus « courte » et pousse le reste de
          // l'écran.
          expect(tester.getSize(find.text(rendered)).height,
              lessThanOrEqualTo(2 * oneLine),
              reason: 'mention trop longue en $lang sur ${choice.name} à '
                  '${width.toInt()} dp : « $rendered »');
        });
      }
    }
  }

  testWidgets('sans défis, la durée reste le libellé nu du palier',
      (tester) async {
    await tester.pumpWidget(host(const Locale('fr'),
        (ctx) => baseLabel(ctx, SessionLengthChoice.moyenne)));
    expect(find.text('25 min'), findsOneWidget);
  });
}
