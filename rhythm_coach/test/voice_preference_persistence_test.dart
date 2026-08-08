import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/locale_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:beat_bitch/widgets/voice_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-régression du retour utilisateur « No matter what I have the voice
/// selected to in the settings, it always female. […] the setting will always
/// change back to en-gb-x-gba-local after I close the app or start a session ».
///
/// `en-gb-x-gba-local` n'est pas une voix arbitraire : c'est la **première
/// entrée** de `_preferredVoiceNamesByLanguage['en']` dans `TtsService`,
/// c'est-à-dire exactement ce que l'auto-sélection impose quand personne ne
/// lui dit le contraire. Le défaut n'était donc pas « pas de voix masculine
/// disponible » mais « le choix explicite de l'utilisateur n'existe nulle
/// part » : il n'était ni persisté, ni relu, ni protégé des presets coach.
///
/// Deux chemins distincts du service sont couverts :
///  - **fermeture de l'app** → `init()` → `_selectVoice()` ;
///  - **sortie de séance carrière** → `restoreDefaultVoicePreset()` →
///    `_selectVoice()`.
///
/// Ce qui n'est **pas** couvert, parce que ce n'est pas un défaut : qu'un
/// coach impose sa voix *pendant* sa séance. Les voix de coach sont figées,
/// c'est le fonctionnement voulu. La ligne rouge est ailleurs — le coach n'a
/// pas le droit de **détruire** le réglage de l'utilisateur en repartant. Le
/// second test vérifie donc que le preset s'applique bien, puis que la
/// restauration rend son choix à l'utilisateur.
///
/// Les tests pilotent l'écran de réglages réel (`VoiceSettingsSection`)
/// plutôt que le service directement : c'est le seul moyen de prouver que
/// *le choix de l'utilisateur* est respecté, et pas seulement qu'une API de
/// service sait écrire une préférence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  /// Voix telles que les retourne le moteur Google Android en anglais.
  /// `en-gb-x-gba-local` est la voix de l'auto-sélection (1ʳᵉ préférée),
  /// `en-gb-x-gbd-local` est celle que l'utilisateur choisit dans les tests.
  ///
  /// **Aucune entrée ne porte de `gender`** : le composant Android ne remonte
  /// que nom, langue, qualité, latence, réseau et fonctionnalités. Ce champ y
  /// figurait, inventé — il faisait passer ces tests par un chemin qui
  /// n'existe sur aucun appareil Android.
  const enVoices = <Map<String, String>>[
    {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
    {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
    {'name': 'en-us-x-tpd-local', 'locale': 'en-US'},
  ];

  const deVoices = <Map<String, String>>[
    {'name': 'de-de-x-deg-local', 'locale': 'de-DE'},
    {'name': 'de-de-x-deb-local', 'locale': 'de-DE'},
  ];

  /// Faux moteur TTS qui enregistre ce qui lui est **réellement poussé** —
  /// distinct de ce que le service expose et de ce que l'UI affiche.
  final voicesPushed = <String>[];
  var engineVoices = <Map<String, String>>[...enVoices];

  void installFakeEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getVoices':
          return engineVoices
              .map(Map<String, String>.from)
              .toList(growable: false);
        case 'setVoice':
          final args = (call.arguments as Map).cast<String, Object?>();
          voicesPushed.add(args['name']! as String);
          return 1;
        default:
          return 1;
      }
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    voicesPushed.clear();
    engineVoices = <Map<String, String>>[...enVoices];
    installFakeEngine();
    await LocaleService.instance.setLocale(const Locale('en'));
    await CoachPhrasesService.instance.ensureLoaded(locale: const Locale('en'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Monte l'écran de réglages voix et choisit `voiceName` dans le dropdown,
  /// exactement comme l'utilisateur le fait dans le Profil.
  Future<void> pickVoiceInSettings(
    WidgetTester tester,
    TtsService tts,
    String voiceName,
  ) async {
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VoiceSettingsSection(tts: tts, userProfile: profile),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    final label = enVoices.firstWhere((v) => v['name'] == voiceName);
    await tester.tap(find.text('${label['name']}  ·  ${label['locale']}').last);
    await tester.pumpAndSettle();
  }

  group('Question 1 — la préférence survit-elle à la fermeture de l\'app ?',
      () {
    testWidgets('la voix choisie dans le Profil survit à un redémarrage',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceInSettings(tester, tts, 'en-gb-x-gbd-local');
      expect(tts.currentVoiceName, 'en-gb-x-gbd-local',
          reason: 'le choix doit au moins être appliqué dans la foulée');

      // Redémarrage de l'app : nouveau service, mêmes SharedPreferences.
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();

      expect(restarted.currentVoiceName, 'en-gb-x-gbd-local');
      expect(voicesPushed.last, 'en-gb-x-gbd-local',
          reason: 'la voix réellement poussée au moteur, pas seulement '
              'celle affichée');
    });
  });

  group('Question 2 — la restauration rend-elle SON choix à l\'utilisateur ?',
      () {
    testWidgets(
        'le coach impose sa voix pendant la séance, puis la rend en sortant',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceInSettings(tester, tts, 'en-gb-x-gbd-local');

      // Début de séance carrière : le coach impose sa voix. Voulu.
      await tts.applyCoachVoicePreset(
        voiceName: 'fr-fr-x-fra-local',
        voiceLocale: 'fr-FR',
        rate: 0.62,
        pitch: 1.30,
      );
      expect(tts.currentVoiceName, isNot('en-gb-x-gbd-local'),
          reason: 'le coach a bien pris la main pendant la séance');

      // Sortie de séance : la restauration doit rendre à l'utilisateur SON
      // choix, pas le défaut de l'app.
      await tts.restoreDefaultVoicePreset();

      expect(tts.currentVoiceName, 'en-gb-x-gbd-local');
      expect(voicesPushed.last, 'en-gb-x-gbd-local');
    });

    testWidgets('le preset coach ne détruit pas la préférence enregistrée',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceInSettings(tester, tts, 'en-gb-x-gbd-local');
      await tts.applyCoachVoicePreset(
        voiceName: 'fr-fr-x-fra-local',
        voiceLocale: 'fr-FR',
        skipPreferredVoices: true,
      );

      // Redémarrage sans passer par `restoreDefaultVoicePreset` : si le
      // preset coach avait écrit dans la clé de préférence, on retrouverait
      // sa voix ici.
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();

      expect(restarted.currentVoiceName, 'en-gb-x-gbd-local');
    });
  });

  group('Arbitrages', () {
    test('la préférence est par langue, et chaque langue garde la sienne',
        () async {
      final tts = TtsService(locale: const Locale('en'));
      await tts.init();
      await tts.setUserVoice('en-gb-x-gbd-local', 'en-GB');

      // Passage en allemand : aucun choix pour cette langue → auto-sélection
      // allemande. Imposer la voix anglaise choisie n'aurait aucun sens.
      engineVoices = <Map<String, String>>[...deVoices];
      await tts.setLocale(const Locale('de'));
      expect(tts.currentVoiceName, 'de-de-x-deg-local');

      // Retour en anglais : le choix de l'utilisateur y est retrouvé.
      engineVoices = <Map<String, String>>[...enVoices];
      await tts.setLocale(const Locale('en'));
      expect(tts.currentVoiceName, 'en-gb-x-gbd-local');
    });

    test(
        'une voix désinstallée replie sur l\'auto-sélection sans effacer '
        'la préférence', () async {
      final first = TtsService(locale: const Locale('en'));
      await first.init();
      await first.setUserVoice('en-gb-x-gbd-local', 'en-GB');

      // La voix disparaît de l'appareil (pack de langue retiré, moteur TTS
      // changé) : repli silencieux, pas de plantage.
      engineVoices = enVoices
          .where((v) => v['name'] != 'en-gb-x-gbd-local')
          .map(Map<String, String>.from)
          .toList();
      final withoutVoice = TtsService(locale: const Locale('en'));
      await withoutVoice.init();
      expect(withoutVoice.currentVoiceName, 'en-gb-x-gba-local');

      // La voix réapparaît : la préférence n'avait pas été effacée, elle
      // reprend d'elle-même.
      engineVoices = <Map<String, String>>[...enVoices];
      final restored = TtsService(locale: const Locale('en'));
      await restored.init();
      expect(restored.currentVoiceName, 'en-gb-x-gbd-local');
    });
  });
}
