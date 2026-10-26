import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/screens/coach_picker_screen.dart';
import 'package:beat_bitch/career/screens/custom_coach_picker_screen.dart';
import 'package:beat_bitch/career/services/coach_service.dart';
import 'package:beat_bitch/career/widgets/limited_time_coach_banner.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';

final _before = DateTime(2026, 10, 26, 23, 59, 59);
final _firstDay = DateTime(2026, 10, 27);
final _after = DateTime(2026, 11, 9);

List<Coach> get _permanent =>
    CoachCatalog.defaults.where((c) => c.availability == null).toList();

Widget _host(Widget screen) => MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    );

/// Noms affichés, de haut en bas.
List<String> _namesTopDown(WidgetTester tester) {
  final names = CoachCatalog.defaults.map((c) => c.name).toSet();
  final found = <(double, String)>[
    for (final e in find.byType(Text).evaluate())
      if (names.contains((e.widget as Text).data))
        (
          tester.getTopLeft(find.byWidget(e.widget)).dy,
          (e.widget as Text).data!
        )
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return found.map((f) => f.$2).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'coach.current_tier': 7,
      'coach.unlocked_ids': _permanent.map((c) => c.id).toList(),
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  Future<CoachService> pumpPicker(WidgetTester tester, DateTime now) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = CoachService(clock: () => now);
    await service.load();
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    await tester.pumpWidget(_host(CoachPickerScreen(
      service: service,
      playerTotalSeconds: 100000,
      handsEnabled: true,
      tts: TtsService(),
      userProfile: profile,
    )));
    await tester.pumpAndSettle();
    return service;
  }

  final permanentOrder = [
    'Lina',
    'Hélène',
    'Marc',
    'Jade',
    'Morgan',
    'Victoria',
    'Nyx',
  ];

  for (final now in [_before, _after]) {
    testWidgets('hors fenêtre ($now) : les 7 coachs, rien de plus',
        (tester) async {
      await pumpPicker(tester, now);
      expect(_namesTopDown(tester), permanentOrder);
      expect(find.text('ÉPHÉMÈRE'), findsNothing);
      expect(find.text('PRINCIPAL'), findsOneWidget);
      expect(find.text('PALIER ACQUIS'), findsNWidgets(6));
    });
  }

  testWidgets('dans la fenêtre : Lilith en tête, les 7 autres inchangés',
      (tester) async {
    await pumpPicker(tester, _firstDay);
    expect(_namesTopDown(tester), ['Lilith', ...permanentOrder]);
    expect(find.text('ÉPHÉMÈRE'), findsOneWidget);
    expect(find.text("Jusqu'au 8 novembre"), findsOneWidget);
    expect(find.text('PRINCIPAL'), findsOneWidget);
    expect(find.text('PALIER ACQUIS'), findsNWidgets(6));
    expect(find.text('ENTRAÎNEMENT LIBRE'), findsNothing);
  });

  testWidgets('choisir Lilith : sans dialogue d\'entraînement libre',
      (tester) async {
    final service = await pumpPicker(tester, _firstDay);
    await tester.tap(find.text('Lilith'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.selectedCoachId, CoachCatalog.lilithId);
  });

  testWidgets('sélecteur Custom : Lilith datée pendant la fenêtre seulement',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (now, shown) in [(_firstDay, true), (_after, false)]) {
      final service = CoachService(clock: () => now);
      await service.load();
      final profile = UserProfileService();
      addTearDown(profile.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(CustomCoachPickerScreen(
        service: service,
        selectedCoachId: null,
        tts: TtsService(),
        userProfile: profile,
      )));
      await tester.pumpAndSettle();
      expect(find.text("Coach d’Halloween · jusqu'au 8 novembre"),
          shown ? findsOneWidget : findsNothing,
          reason: '$now');
      expect(find.text('Coach exigeante · PALIER 2'), findsOneWidget,
          reason: '$now');
    }
  });

  testWidgets('bandeau : date du jour de fin, ESSAYER déclenche le choix',
      (tester) async {
    var tried = 0;
    await tester.pumpWidget(_host(Scaffold(
      body: LimitedTimeCoachBanner(
        coachName: 'Lilith',
        until: DateTime(2026, 11, 8),
        onTry: () => tried++,
      ),
    )));
    expect(find.text("Lilith est là jusqu'au 8 novembre."), findsOneWidget);
    await tester.tap(find.text('ESSAYER'));
    expect(tried, 1);
  });
}
