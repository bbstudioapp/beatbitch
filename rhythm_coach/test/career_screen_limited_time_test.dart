import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/widgets/limited_time_coach_banner.dart';
import 'package:beat_bitch/career/screens/career_screen.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show coachService;
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// Le `coachService` global lit l'horloge du système : l'attendu suit la date
/// du jour, fenêtre ouverte ou fermée.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const silentChannels = [
    MethodChannel('flutter_tts'),
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
    MethodChannel('xyz.luan/audioplayers/events/ambience_loop'),
    MethodChannel('xyz.luan/audioplayers.global/events'),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    for (final c in silentChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
    await coachService.load();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CareerScreen(
        tts: TtsService(),
        beep: _SilentBeepEngine(),
        ambience: _SilentAmbienceEngine(),
        userProfile: UserProfileService(),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('le bandeau ESSAYER suit la fenêtre du jour', (tester) async {
    await mount(tester);
    final open = CoachCatalog.lilith.availability!.includes(DateTime.now());
    expect(find.text(coachService.currentTierPrincipal!.name), findsWidgets);
    expect(find.byType(LimitedTimeCoachBanner),
        open ? findsOneWidget : findsNothing);
  });
}
