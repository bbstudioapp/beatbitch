import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/locale_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:beat_bitch/widgets/coach_voice_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vitesse et hauteur réglables **par coach**, depuis sa fiche.
///
/// La 0.6.1 a rendu la *voix* de chaque coach choisissable ; sa couleur
/// vocale, elle, restait celle de son JSON. Or c'est souvent elle qui cloche :
/// une voix correcte prononcée trop vite ou trop haut ne colle pas davantage
/// au personnage, et aucune oreille autre que celle de la joueuse ne peut en
/// juger — même raison qui avait rendu le choix de voix manuel.
///
/// Le retour à la couleur d'origine est la moitié du réglage : sans lui,
/// tâtonner est un aller sans retour, et personne n'ose déplacer un curseur.
///
/// Les tests pilotent la fiche réelle (feuille ouverte depuis
/// `CoachVoiceSection`) et observent ce que le moteur **reçoit** au démarrage
/// d'une séance — pas ce qu'une API de service sait écrire.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  const enVoices = <Map<String, String>>[
    {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
    {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
  ];

  /// Marc et Lina tels que déclarés dans `assets/career/coaches/` : chacun
  /// avec une couleur vocale distincte, c'est elle qu'on remplace.
  const marc = Coach(
    id: 'coach_07_marc',
    name: 'Marc',
    title: '',
    archetype: CoachArchetype.brutal,
    publicBio: '',
    specialties: [],
    tier: 3,
    isPrincipal: true,
    voicePreset: CoachVoicePreset(
      skipPreferredVoices: true,
      rate: 0.55,
      pitch: 0.85,
    ),
  );

  const lina = Coach(
    id: 'coach_01_lina',
    name: 'Lina',
    title: '',
    archetype: CoachArchetype.bienveillant,
    publicBio: '',
    specialties: [],
    tier: 1,
    isPrincipal: true,
    voicePreset: CoachVoicePreset(
      voiceName: 'fr-fr-x-fra-local',
      voiceLocale: 'fr-FR',
      rate: 0.56,
      pitch: 1.13,
    ),
  );

  /// Ce que le moteur reçoit **réellement**.
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

  Future<void> pumpSection(
    WidgetTester tester,
    TtsService tts, {
    List<Coach> coaches = const [marc],
  }) async {
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    // Démontage préalable : sans ça un second `pumpWidget` du même arbre
    // réutilise l'état déjà chargé, et un « redémarrage » n'en serait pas un.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        locale: LocaleService.instance.current,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoachVoiceSection(
            tts: tts,
            coaches: coaches,
            userProfile: profile,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester, String coachName) async {
    await tester.tap(find.text(coachName));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(Scaffold))).pop();
    await tester.pumpAndSettle();
  }

  const rateSlider = 0;
  const pitchSlider = 1;

  /// Glisse un curseur de la fiche jusqu'à sa butée : le déplacement demandé
  /// dépasse largement la largeur du curseur, la valeur obtenue est donc la
  /// borne et ne dépend pas de la géométrie du rendu.
  Future<void> dragToBound(WidgetTester tester, int index, double dx) async {
    await tester.drag(find.byType(Slider).at(index), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  /// Amène l'option de voix [label] dans le viewport de la feuille, puis la
  /// rend : les curseurs occupent le bas de la feuille, la liste défile.
  Future<Finder> voiceOption(WidgetTester tester, String label) async {
    final option = find.text(label);
    await tester.scrollUntilVisible(
      option,
      60,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    return option;
  }

  /// Ce que fait `career_screen._applyCoachVoicePreset` au démarrage d'une
  /// séance : prendre la main sur l'état vocal, puis pousser le preset.
  Future<void> startSessionWith(TtsService tts, Coach coach) {
    final preset = coach.voicePreset;
    return tts.takeVoiceLead(
      () => tts.applyCoachVoicePreset(
        coachId: coach.id,
        voiceName: preset.voiceName,
        voiceLocale: preset.voiceLocale,
        rate: preset.rate,
        pitch: preset.pitch,
        skipPreferredVoices: preset.skipPreferredVoices,
      ),
    );
  }

  group('Le réglage arrive-t-il jusqu\'au moteur en séance ?', () {
    testWidgets('la vitesse réglée pour Marc remplace celle de son preset',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      await closeSheet(tester);

      ratesPushed.clear();
      await startSessionWith(tts, marc);

      expect(tts.currentRate, lessThan(0.55),
          reason: 'le preset de Marc déclare 0.55, la joueuse a réglé plus '
              'lent');
      expect(ratesPushed.last, tts.currentRate,
          reason: 'la vitesse réellement poussée au moteur');
    });

    testWidgets('la hauteur non touchée reste celle du preset', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      await closeSheet(tester);

      await startSessionWith(tts, marc);

      expect(tts.currentPitch, 0.85,
          reason: 'régler la vitesse d\'un coach ne lui prend pas sa hauteur');
    });

    testWidgets('le réglage survit à la fermeture de l\'app', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, pitchSlider, 600);
      final chosenPitch = tts.currentPitch;
      await closeSheet(tester);

      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();
      await startSessionWith(restarted, marc);

      expect(restarted.currentPitch, chosenPitch);
    });

    testWidgets('la fiche rouvre sur les valeurs réglées', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      final shown =
          tester.widget<Slider>(find.byType(Slider).at(rateSlider)).value;
      await closeSheet(tester);

      await pumpSection(tester, TtsService(locale: const Locale('en')));
      await openSheet(tester, 'Marc');

      expect(tester.widget<Slider>(find.byType(Slider).at(rateSlider)).value,
          shown);
    });

    testWidgets('une fiche jamais touchée montre la couleur du coach',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');

      expect(tester.widget<Slider>(find.byType(Slider).at(rateSlider)).value,
          0.55);
      expect(tester.widget<Slider>(find.byType(Slider).at(pitchSlider)).value,
          0.85);
    });

    testWidgets(
        'une voix choisie pour le coach n\'annule pas sa vitesse '
        'réglée', (tester) async {
      // Ce cas-là emprunte une **autre sortie** d'`applyCoachVoicePreset` :
      // une voix mémorisée trouvée sur l'appareil rend la main tout de suite,
      // avant la cascade. Une résolution du réglage faite au fil des sorties
      // plutôt qu'en tête l'oublierait précisément ici.
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await tester
          .tap(await voiceOption(tester, 'en-gb-x-gbd-local  ·  en-GB'));
      await tester.pumpAndSettle();
      await dragToBound(tester, rateSlider, -600);
      final chosenRate = tts.currentRate;
      await closeSheet(tester);

      await startSessionWith(tts, marc);

      expect(tts.currentRate, chosenRate);
      expect(tts.currentRate, isNot(0.55));
    });
  });

  group('Retour à la couleur d\'origine', () {
    testWidgets('le bouton est inerte tant que rien n\'a été réglé',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');

      final t =
          AppLocalizations.of(tester.element(find.byType(CoachVoiceSection)));
      final button = tester.widget<TextButton>(find.ancestor(
        of: find.text(t.coachVoiceResetRatePitch),
        matching: find.byType(TextButton),
      ));
      expect(button.onPressed, isNull,
          reason: 'affiché quand même : son absence laisserait croire '
              'qu\'aucun retour en arrière n\'existe');
    });

    testWidgets('il rend au coach la couleur de son preset', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      await dragToBound(tester, pitchSlider, 600);
      expect(tts.currentRate, isNot(0.55));

      final t =
          AppLocalizations.of(tester.element(find.byType(CoachVoiceSection)));
      await tester.tap(find.text(t.coachVoiceResetRatePitch));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      await startSessionWith(tts, marc);

      expect(tts.currentRate, 0.55);
      expect(tts.currentPitch, 0.85);
    });

    testWidgets('la remise à l\'origine survit au redémarrage', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      final t =
          AppLocalizations.of(tester.element(find.byType(CoachVoiceSection)));
      await tester.tap(find.text(t.coachVoiceResetRatePitch));
      await tester.pumpAndSettle();
      await closeSheet(tester);

      // Effacement, pas écriture d'une valeur repère : au redémarrage il ne
      // doit rien rester à distinguer d'un réglage réel.
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();
      await startSessionWith(restarted, marc);

      expect(restarted.currentRate, 0.55);
    });
  });

  group('Étanchéité entre coachs et avec la voix par défaut', () {
    testWidgets('régler Marc ne touche pas Lina', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts, coaches: const [marc, lina]);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      await closeSheet(tester);

      await startSessionWith(tts, lina);

      expect(tts.currentRate, 0.56, reason: 'Lina garde son propre preset');
    });

    testWidgets('régler un coach ne touche pas la voix par défaut',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await tts.setUserRate(0.7);
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');
      await dragToBound(tester, rateSlider, -600);
      await closeSheet(tester);

      // Sortie de séance : c'est le réglage hors-carrière qui revient.
      await tts.restoreDefaultVoicePreset();

      expect(tts.currentRate, 0.7);
    });
  });

  group('La fiche tient à l\'écran', () {
    testWidgets(
        'les deux curseurs et le retour à l\'origine sur un petit '
        'écran', (tester) async {
      // iPhone SE : le plus petit écran que la PWA ait à servir. C'est là que
      // « curseurs visibles, pas repliés » se paie — la liste de voix se
      // raccourcit d'autant, et elle défile.
      tester.view.physicalSize = const Size(320 * 3, 568 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final tts = TtsService(locale: const Locale('en'));
      await pumpSection(tester, tts);
      await openSheet(tester, 'Marc');

      // Un débordement de mise en page lèverait ici, avant les attentes.
      expect(find.byType(Slider), findsExactly(2));
      final t =
          AppLocalizations.of(tester.element(find.byType(CoachVoiceSection)));
      expect(find.text(t.coachVoiceResetRatePitch), findsOne);
      expect(find.text(t.coachVoicePreview), findsOne,
          reason: 'l\'aperçu reste atteignable : sans lui, régler deux '
              'nombres à l\'aveugle n\'a pas de sens');
    });
  });
}
