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

/// Le débit et la hauteur de la voix par défaut se réglaient depuis le Profil
/// mais n'étaient enregistrés nulle part : perdus à la fermeture de l'app, et
/// remplacés par les défauts plateforme dès qu'une séance carrière rendait la
/// main. Exactement le défaut corrigé en 0.6.1 sur le *choix* de voix (cf.
/// `voice_preference_persistence_test.dart`), sur les deux réglages voisins.
///
/// Les mêmes deux chemins y sont couverts, et pour la même raison :
///  - **fermeture de l'app** → `init()` ;
///  - **sortie de séance carrière** → `restoreDefaultVoicePreset()`.
///
/// Les tests glissent les vrais curseurs de `VoiceSettingsSection` : prouver
/// qu'une API de service sait écrire un double ne dirait rien de ce que
/// l'utilisateur obtient en réglant depuis le Profil.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  const enVoices = <Map<String, String>>[
    {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
    {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
  ];

  /// Ce que le moteur reçoit **réellement**, distinct de ce que le service
  /// expose et de ce que le curseur affiche.
  final ratesPushed = <double>[];
  final pitchesPushed = <double>[];

  void installFakeEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getVoices':
          return enVoices.map(Map<String, String>.from).toList(growable: false);
        case 'setSpeechRate':
          ratesPushed.add(call.arguments as double);
          return 1;
        case 'setPitch':
          pitchesPushed.add(call.arguments as double);
          return 1;
        default:
          return 1;
      }
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ratesPushed.clear();
    pitchesPushed.clear();
    installFakeEngine();
    await LocaleService.instance.setLocale(const Locale('en'));
    await CoachPhrasesService.instance.ensureLoaded(locale: const Locale('en'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpSettings(WidgetTester tester, TtsService tts) async {
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    // Vider l'arbre d'abord : sans ça, un second montage réutilise le `State`
    // du premier — les curseurs garderaient leur valeur en mémoire et le test
    // passerait sans qu'aucune préférence ait été relue.
    await tester.pumpWidget(const SizedBox.shrink());
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
  }

  /// Glisse un curseur jusqu'à sa butée. Le déplacement demandé dépasse
  /// largement la largeur du curseur : la valeur obtenue est donc la borne,
  /// sans dépendre de la géométrie exacte du rendu.
  ///
  /// Le glissement passe par `onChangeEnd`, seul moment où le réglage est
  /// enregistré — un `onChanged` seul ne prouverait rien de la persistance.
  Future<void> dragToBound(WidgetTester tester, int index, double dx) async {
    await tester.drag(find.byType(Slider).at(index), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  const rateSlider = 0;
  const pitchSlider = 1;

  group('Question 1 — le réglage survit-il à la fermeture de l\'app ?', () {
    testWidgets('le débit et la hauteur réglés dans le Profil sont restitués',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, tts);

      // Butée basse pour le débit, haute pour la hauteur : deux bornes
      // opposées, toutes deux distinctes des défauts plateforme — un test
      // qui atterrirait sur le défaut ne discriminerait rien.
      await dragToBound(tester, rateSlider, -600);
      await dragToBound(tester, pitchSlider, 600);
      expect(tts.currentRate, lessThan(TtsService.defaultRate));
      expect(tts.currentPitch, greaterThan(TtsService.defaultPitch));
      final chosenRate = tts.currentRate;
      final chosenPitch = tts.currentPitch;

      // Redémarrage de l'app : nouveau service, mêmes SharedPreferences.
      ratesPushed.clear();
      pitchesPushed.clear();
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();

      expect(restarted.currentRate, chosenRate);
      expect(restarted.currentPitch, chosenPitch);
      expect(ratesPushed, contains(chosenRate),
          reason: 'le débit réellement poussé au moteur, pas seulement '
              'celui affiché');
      expect(pitchesPushed, contains(chosenPitch));
    });

    testWidgets('les curseurs rouvrent sur les valeurs enregistrées',
        (tester) async {
      final first = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, first);
      await dragToBound(tester, rateSlider, -600);
      final chosenRate = first.currentRate;

      await pumpSettings(tester, TtsService(locale: const Locale('en')));

      expect(tester.widget<Slider>(find.byType(Slider).at(rateSlider)).value,
          chosenRate);
    });

    testWidgets('un réglage laissé de côté garde son défaut plateforme',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, tts);
      await dragToBound(tester, rateSlider, -600);

      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();

      expect(restarted.currentPitch, TtsService.defaultPitch,
          reason: 'régler le débit n\'impose pas une hauteur');
    });
  });

  group('Question 2 — la séance carrière rend-elle SON réglage ?', () {
    testWidgets('le coach impose sa couleur vocale, puis la rend en sortant',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, tts);
      await dragToBound(tester, rateSlider, -600);
      await dragToBound(tester, pitchSlider, 600);
      final chosenRate = tts.currentRate;
      final chosenPitch = tts.currentPitch;

      // Début de séance carrière : le coach impose son débit. Voulu.
      await tts.applyCoachVoicePreset(rate: 0.62, pitch: 1.30);
      expect(tts.currentRate, 0.62);
      expect(tts.currentPitch, 1.30);

      // Sortie de séance : c'est le réglage de l'utilisateur qui revient,
      // pas le défaut de l'app.
      ratesPushed.clear();
      pitchesPushed.clear();
      await tts.restoreDefaultVoicePreset();

      expect(tts.currentRate, chosenRate);
      expect(tts.currentPitch, chosenPitch);
      expect(ratesPushed, contains(chosenRate));
      expect(pitchesPushed, contains(chosenPitch));
    });

    testWidgets('le preset coach ne détruit pas le réglage enregistré',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, tts);
      await dragToBound(tester, rateSlider, -600);
      final chosenRate = tts.currentRate;

      await tts.applyCoachVoicePreset(rate: 0.62, pitch: 1.30);

      // Redémarrage sans passer par `restoreDefaultVoicePreset` : si le
      // preset coach avait écrit dans la clé de préférence, on retrouverait
      // son débit ici.
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();

      expect(restarted.currentRate, chosenRate);
    });
  });

  group('Arbitrages', () {
    testWidgets(
        'le réglage est global, il ne se perd pas en changeant '
        'de langue', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSettings(tester, tts);
      await dragToBound(tester, rateSlider, -600);
      final chosenRate = tts.currentRate;

      // Contrairement à la voix, dont chaque langue garde la sienne : un
      // débit est un confort d'écoute, le même nombre a le même sens partout.
      await tts.setLocale(const Locale('de'));

      expect(tts.currentRate, chosenRate);
    });
  });
}
