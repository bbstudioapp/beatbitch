import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/widgets/posture_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test de l'indicateur de posture (issue #77) : chaque pose construit
/// son silhouette + label localisé sans crash. Couvre aussi le painter
/// (`CustomPaint` peint dans le pump).
Widget _host(Posture pose, {Locale locale = const Locale('fr')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: PostureIndicator(pose: pose))),
    );

void main() {
  testWidgets('chaque posture rend son label localisé (FR)', (tester) async {
    final expected = {
      Posture.sitting: 'ASSISE',
      Posture.standing: 'DEBOUT',
      Posture.kneeling: 'À GENOUX',
      Posture.allFours: 'À QUATRE PATTES',
      Posture.onBack: 'SUR LE DOS',
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(_host(entry.key));
      expect(find.text(entry.value), findsOneWidget,
          reason: 'label manquant pour ${entry.key}');
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });

  testWidgets('les 4 langues construisent sans crash (allFours)',
      (tester) async {
    for (final lang in const ['fr', 'en', 'de', 'es']) {
      await tester.pumpWidget(_host(Posture.allFours, locale: Locale(lang)));
      expect(tester.takeException(), isNull, reason: 'crash en $lang');
    }
  });
}
