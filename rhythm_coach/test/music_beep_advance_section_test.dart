import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/widgets/music_beep_advance_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const prefKey = 'debug.music_beep_advance_ms';
  const valueKey = Key('profileMusicBeepAdvanceValue');

  Future<void> pumpSection(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: MusicBeepAdvanceSection(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sans valeur mémorisée le réglage affiche 150 ms',
      (tester) async {
    await pumpSection(tester, const Locale('fr'));
    expect(tester.widget<Text>(find.byKey(valueKey)).data, '150 ms');
  });

  testWidgets('− / + écrivent la valeur, la séance suivante la relit',
      (tester) async {
    await pumpSection(tester, const Locale('fr'));
    final t = AppLocalizations.of(
        tester.element(find.byType(MusicBeepAdvanceSection)));

    await tester.tap(find.byTooltip(t.sessionDebugMusicBeepAdvanceIncrease));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(valueKey)).data, '160 ms');
    expect((await SharedPreferences.getInstance()).getInt(prefKey), 160);
    expect(await DebugSettingsService().getMusicBeepAdvanceMs(), 160,
        reason: 'c\'est cette lecture que fait SessionController.start');

    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byTooltip(t.sessionDebugMusicBeepAdvanceIncrease));
    }
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(valueKey)).data, '400 ms');
    expect((await SharedPreferences.getInstance()).getInt(prefKey), 400);

    for (var i = 0; i < 50; i++) {
      await tester.tap(find.byTooltip(t.sessionDebugMusicBeepAdvanceDecrease));
    }
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(valueKey)).data, '0 ms');
    expect((await SharedPreferences.getInstance()).getInt(prefKey), 0);
  });

  testWidgets('une valeur mémorisée est reprise', (tester) async {
    SharedPreferences.setMockInitialValues({prefKey: 90});
    await pumpSection(tester, const Locale('fr'));
    expect(tester.widget<Text>(find.byKey(valueKey)).data, '90 ms');
  });

  for (final code in ['fr', 'en', 'de', 'es']) {
    testWidgets('le texte définitif tient sur 320 px, police ×2 ($code)',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpSection(tester, Locale(code));

      final t = AppLocalizations.of(
          tester.element(find.byType(MusicBeepAdvanceSection)));
      expect(tester.takeException(), isNull);
      expect(find.text(t.profileMusicBeepAdvanceTitle), findsOne);
      expect(find.text(t.profileMusicBeepAdvanceSubtitle), findsOne);
      expect(find.byTooltip(t.sessionDebugMusicBeepAdvanceIncrease), findsOne);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final box = tester.getRect(find.byType(MusicBeepAdvanceSection));
      expect(box.right, lessThanOrEqualTo(screen.width));
    });
  }
}
