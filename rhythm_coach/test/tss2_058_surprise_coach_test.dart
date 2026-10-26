import 'dart:math';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/services/coach_loader.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/main.dart' show coachService;
import 'package:beat_bitch/screens/session_screen.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/surprise_router.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _VoiceTts extends TtsService {
  final coachIds = <String?>[];

  @override
  Future<void> applyCoachVoicePreset({
    String? coachId,
    String? voiceName,
    String? voiceLocale,
    double? rate,
    double? pitch,
    bool skipPreferredVoices = false,
  }) async =>
      coachIds.add(coachId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  final audioEventChannels = [
    const EventChannel('xyz.luan/audioplayers.global/events'),
    const EventChannel('xyz.luan/audioplayers/events/ambience_loop'),
    for (final pos in ['head', 'mid', 'tip'])
      for (var i = 0; i < 4; i++)
        EventChannel('xyz.luan/audioplayers/events/beep_${pos}_beep_$i'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final unlocked = [
    for (final c in CoachCatalog.defaults)
      if (c.isPrincipal && c.tier <= 3) c.id
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'coach.unlocked_ids': unlocked,
      'coach.selected_id': unlocked.first,
    });
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(
          channel, MockStreamHandler.inline(onListen: (_, __) {}));
    }
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      messenger.setMockMethodCallHandler(c, null);
    }
    for (final name in wakelockChannels) {
      messenger.setMockMessageHandler(name, null);
    }
    for (final channel in audioEventChannels) {
      messenger.setMockStreamHandler(channel, null);
    }
  });

  testWidgets(
      'surprise : une coach débloquée tirée au hasard donne voix et fonds',
      (tester) async {
    await tester.runAsync(() async {
      await CoachPhrasesService.instance.ensureLoaded();
      await coachService.load();
      coachService.attachPhrases(await CoachLoader().load());
    });
    expect(coachService.selectedCoach?.id, unlocked.first);

    final drawn = <Coach>[];
    for (var seed = 0; seed < 6; seed++) {
      SurpriseRouter.debugRandom = Random(seed);
      final tts = _VoiceTts();
      late BuildContext launcher;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          launcher = context;
          return const SizedBox();
        }),
      ));
      SurpriseRouter.launchSession(
        context: launcher,
        tts: tts,
        beep: BeepEngine(),
        ambience: AmbienceEngine(),
      );
      await _until(
          tester, () => find.byType(SessionScreen).evaluate().isNotEmpty);

      final tag =
          tester.widget<SessionScreen>(find.byType(SessionScreen)).coachTag;
      expect(tag, isNotNull);
      final coach = coachService.coaches.where((c) => c.slug == tag).single;
      expect(coachService.isUnlocked(coach), isTrue);
      expect(tts.coachIds, [coach.id]);
      drawn.add(coach);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }
    expect(drawn.map((c) => c.id).toSet().length, greaterThan(1));
  });
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('condition non atteinte');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
