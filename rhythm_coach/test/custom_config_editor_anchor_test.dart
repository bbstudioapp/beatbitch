import 'package:beat_bitch/career/models/custom_session_config.dart';
import 'package:beat_bitch/career/screens/custom_config_editor_screen.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/models/session_step.dart' show BeatAnchor;
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monte l'éditeur pour de vrai et rend la config qu'il renvoie quand on
/// tape « Enregistrer » : c'est le seul moyen de prouver que les trois
/// réglages traversent l'écran plutôt que d'être seulement dans le modèle.
Future<CustomSessionConfig> _editAndSave(
  WidgetTester tester,
  CustomSessionConfig initial, {
  required Future<void> Function(WidgetTester tester) interact,
}) async {
  CustomEditorResult? result;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          child: const Text('ouvrir'),
          onPressed: () async {
            result = await Navigator.of(context).push<CustomEditorResult>(
              MaterialPageRoute(
                builder: (_) => CustomConfigEditorScreen(
                  initial: initial,
                  isNew: true,
                  hasBalls: false,
                  tts: TtsService(),
                  userProfile: UserProfileService(),
                ),
              ),
            );
          },
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();

  await interact(tester);

  final t = await AppLocalizations.delegate.load(const Locale('fr'));
  // Les boutons d'action vivent dans la `bottomNavigationBar`, hors du
  // ListView : toujours montés, pas besoin de faire défiler.
  await tester.tap(find.text(t.customSaveOnly));
  await tester.pumpAndSettle();
  return result!.config;
}

/// L'éditeur est une `ListView` : ses sections basses ne sont pas
/// construites tant qu'on n'a pas fait défiler jusqu'à elles — `find.text`
/// ne les verrait pas.
Future<Finder> _reveal(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return finder;
}

Future<void> _tapText(WidgetTester tester, String label) async {
  await tester.tap(await _reveal(tester, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('une config neuve sort de l\'éditeur avec l\'aimant éteint',
      (tester) async {
    final saved = await _editAndSave(
      tester,
      CustomSessionConfig.defaults(id: 'c'),
      interact: (_) async {},
    );
    expect(saved.anchorEnabled, isFalse);
    expect(saved.resolveAnchor(), isNull);
  });

  testWidgets('les crans de force ne s\'affichent qu\'aimant allumé',
      (tester) async {
    final t = await AppLocalizations.delegate.load(const Locale('fr'));
    await _editAndSave(
      tester,
      CustomSessionConfig.defaults(id: 'c'),
      interact: (tester) async {
        await _reveal(tester, t.customAnchorLabel);
        expect(find.text(t.customAnchorStrengthLabel), findsNothing,
            reason: 'l\'interrupteur est visible et éteint : ses réglages '
                'n\'ont pas à être là');
        await _tapText(tester, t.customAnchorLabel);
        expect(find.text(t.customAnchorStrengthLabel), findsOneWidget);
        expect(find.text(t.customAnchorPointLabel), findsOneWidget);
      },
    );
  });

  testWidgets(
      'allumer l\'aimant et choisir dur + arrivée ressort dans '
      'la config', (tester) async {
    final t = await AppLocalizations.delegate.load(const Locale('fr'));
    final saved = await _editAndSave(
      tester,
      CustomSessionConfig.defaults(id: 'c'),
      interact: (tester) async {
        await _tapText(tester, t.customAnchorLabel);
        await _tapText(tester, t.customAnchorStrengthHard);
        await _tapText(tester, t.customAnchorPointTo);
      },
    );
    expect(saved.anchorEnabled, isTrue);
    expect(saved.anchorStrength, AnchorStrength.hard);
    expect(saved.anchorPoint, BeatAnchor.to);
    expect(saved.resolveAnchor(), isNotNull);
  });

  testWidgets('une config enregistrée avec l\'aimant rouvre sur ses réglages',
      (tester) async {
    final t = await AppLocalizations.delegate.load(const Locale('fr'));
    final saved = await _editAndSave(
      tester,
      CustomSessionConfig.defaults(id: 'c').copyWith(
        anchorEnabled: true,
        anchorStrength: AnchorStrength.light,
        anchorPoint: BeatAnchor.to,
      ),
      interact: (tester) async {
        await _reveal(tester, t.customAnchorStrengthLabel);
        expect(find.text(t.customAnchorStrengthLabel), findsOneWidget);
      },
    );
    expect(saved.anchorEnabled, isTrue);
    expect(saved.anchorStrength, AnchorStrength.light);
    expect(saved.anchorPoint, BeatAnchor.to);
  });
}
