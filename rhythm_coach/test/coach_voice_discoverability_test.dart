import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/screens/coach_picker_screen.dart';
import 'package:beat_bitch/career/screens/custom_coach_picker_screen.dart';
import 'package:beat_bitch/career/services/coach_service.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/services/coach_phrases_loader.dart';
import 'package:beat_bitch/services/locale_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:beat_bitch/widgets/coach_voice_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Découvrabilité du réglage de voix par coach.
///
/// La Phase 1 a livré le réglage, dans le Profil. Mais quelqu'un qui entend
/// une voix qui ne colle pas au personnage n'a aucune raison de soupçonner
/// qu'un réglage existe : il conclut que l'app est mal faite — c'est
/// exactement ce qui s'est passé. Ces tests vérifient que le réglage se
/// montre là où l'on regarde le coach, et qu'il y est **le même** qu'au
/// Profil : même feuille, même écriture, même étanchéité de l'aperçu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  /// Voix telles que les retourne le moteur Google Android en anglais.
  /// Aucune n'expose de `gender` : le composant Android ne le remonte pas,
  /// et un mock qui l'inventerait testerait un chemin mort.
  const enVoices = <Map<String, String>>[
    {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
    {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
    {'name': 'en-us-x-tpd-local', 'locale': 'en-US'},
  ];

  /// Marc : le coach masculin, aucune voix nommée, juste un genre que rien
  /// ne sait honorer.
  const marc = Coach(
    id: 'coach_07_marc',
    name: 'Marc',
    title: 'Le Boss',
    archetype: CoachArchetype.brutal,
    publicBio: 'Bio',
    specialties: [],
    tier: 3,
    isPrincipal: true,
    voicePreset: CoachVoicePreset(
      preferredGender: 'male',
      rate: 0.55,
      pitch: 0.85,
    ),
  );

  /// Victoria : palier au-dessus, donc **verrouillée** en carrière — mais
  /// jouable en Custom, qui ne gate rien.
  const victoria = Coach(
    id: 'coach_05_victoria',
    name: 'Victoria',
    title: 'La Reine',
    archetype: CoachArchetype.hautain,
    publicBio: 'Bio',
    specialties: [],
    tier: 4,
    isPrincipal: true,
    voicePreset: CoachVoicePreset(
      voiceName: 'fr-fr-x-frc-local',
      voiceLocale: 'fr-FR',
      rate: 0.56,
      pitch: 1.13,
    ),
  );

  /// Faux moteur TTS qui enregistre ce qui lui est **réellement poussé**.
  final voicesPushed = <String>[];
  var engineVoices = <Map<String, String>>[...enVoices];

  /// Temps que met le moteur à répondre aux appels de voix. Zéro partout
  /// sauf là où on veut observer ce qui se passe *pendant* un aperçu : un
  /// moteur qui répond dans la foulée referme la fenêtre de course.
  var voiceCallLatency = Duration.zero;

  void installFakeEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getVoices':
          if (voiceCallLatency > Duration.zero) {
            await Future<void>.delayed(voiceCallLatency);
          }
          return engineVoices
              .map(Map<String, String>.from)
              .toList(growable: false);
        case 'setVoice':
          if (voiceCallLatency > Duration.zero) {
            await Future<void>.delayed(voiceCallLatency);
          }
          final args = (call.arguments as Map).cast<String, Object?>();
          voicesPushed.add(args['name']! as String);
          return 1;
        default:
          return 1;
      }
    });
  }

  /// Catalogue réduit, Marc débloqué au palier 3, Victoria (palier 4) non.
  Future<CoachService> loadService() async {
    final service = CoachService(coaches: const [marc, victoria]);
    await service.load();
    return service;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'coach.current_tier': 3,
      'coach.unlocked_ids': <String>['coach_07_marc'],
    });
    voicesPushed.clear();
    engineVoices = <Map<String, String>>[...enVoices];
    voiceCallLatency = Duration.zero;
    installFakeEngine();
    await LocaleService.instance.setLocale(const Locale('en'));
    await CoachPhrasesService.instance.ensureLoaded(locale: const Locale('en'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget screen) {
    return MaterialApp(
      locale: LocaleService.instance.current,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: screen,
    );
  }

  /// Monte le sélecteur de coach de la carrière, tel que `career_screen`
  /// le pousse.
  Future<void> pumpCareerPicker(WidgetTester tester, TtsService tts) async {
    final service = await loadService();
    addTearDown(service.dispose);
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(CoachPickerScreen(
      service: service,
      playerTotalSeconds: 100000,
      handsEnabled: true,
      tts: tts,
      userProfile: profile,
    )));
    await tester.pumpAndSettle();
  }

  /// Monte le sélecteur de coach du mode Custom, tel que l'éditeur de
  /// config le pousse.
  Future<void> pumpCustomPicker(WidgetTester tester, TtsService tts) async {
    final service = await loadService();
    addTearDown(service.dispose);
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(CustomCoachPickerScreen(
      service: service,
      selectedCoachId: null,
      tts: tts,
      userProfile: profile,
    )));
    await tester.pumpAndSettle();
  }

  /// Zone tapable de la ligne « Voix : … ». La ligne occupe toute la
  /// largeur de la carte mais n'y peint qu'une pastille alignée à gauche :
  /// viser le centre de sa boîte taperait à côté, comme l'utilisateur.
  Finder voiceLineButton([int index = 0]) => find
      .descendant(
        of: find.byType(CoachVoiceLine),
        matching: find.byType(InkWell),
      )
      .at(index);

  /// Ce que fait `career_screen._applyCoachVoicePreset` au démarrage d'une
  /// séance : pousser le preset du coach au moteur.
  Future<void> startSessionWith(TtsService tts, Coach coach) {
    final preset = coach.voicePreset;
    return tts.applyCoachVoicePreset(
      coachId: coach.id,
      voiceName: preset.voiceName,
      voiceLocale: preset.voiceLocale,
      rate: preset.rate,
      pitch: preset.pitch,
      preferredGender: preset.preferredGender,
    );
  }

  group('La ligne « Voix » sur le sélecteur de carrière', () {
    testWidgets('annonce la voix effective du coach', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCareerPicker(tester, tts);

      expect(find.text('Voice: Automatic'), findsOne,
          reason: 'la ligne dit qu\'il y a un réglage, pas qu\'il y a un '
              'problème');

      // Une fois une voix choisie, c'est elle que la ligne nomme.
      await tts.setCoachVoice('coach_07_marc', 'en-gb-x-gbd-local');
      await pumpCareerPicker(tester, tts);

      expect(find.text('Voice: en-gb-x-gbd-local'), findsOne);
      expect(find.text('Voice: Automatic'), findsNothing);
    });

    testWidgets('un coach verrouillé n\'en porte pas', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCareerPicker(tester, tts);

      // Victoria est visible (révélation du palier suivant) mais pas
      // jouable : régler sa voix ici n'a pas d'objet. C'est le sélecteur
      // Custom qui porte son accroche.
      expect(find.text('Victoria'), findsOne);
      expect(find.byType(CoachVoiceLine), findsOne);
    });

    testWidgets('la toucher ouvre la feuille sans choisir le coach',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCareerPicker(tester, tts);

      await tester.tap(voiceLineButton());
      await tester.pumpAndSettle();

      expect(find.text('Marc\'s voice'), findsOne,
          reason: 'la même feuille qu\'au Profil');
      expect(find.text('Automatic'), findsOne);
      // Le sélecteur est un écran de geste : taper une carte choisit le
      // coach et referme l'écran. La ligne ne doit pas déclencher ça.
      expect(find.byType(CoachPickerScreen), findsOne);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('coach.selected_id'), isNull);
    });

    testWidgets('un choix fait ici est celui poussé à la séance suivante',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCareerPicker(tester, tts);

      await tester.tap(voiceLineButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('en-gb-x-gbd-local  ·  en-GB'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(CoachPickerScreen))).pop();
      await tester.pumpAndSettle();

      // La ligne rend compte du choix sans quitter l'écran.
      expect(find.text('Voice: en-gb-x-gbd-local'), findsOne);

      voicesPushed.clear();
      await startSessionWith(tts, marc);
      expect(voicesPushed.last, 'en-gb-x-gbd-local',
          reason: 'la voix réellement poussée au moteur, pas seulement '
              'celle affichée');
      expect(tts.currentRate, closeTo(0.55, 0.001),
          reason: 'l\'utilisateur a choisi un timbre, pas un rythme');
      expect(tts.currentPitch, closeTo(0.85, 0.001));
    });
  });

  group('Le sélecteur du mode Custom', () {
    testWidgets('porte la ligne, y compris pour un coach non débloqué',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCustomPicker(tester, tts);

      // Le mode Custom propose tout le catalogue : c'est là que la voix
      // d'un coach que la carrière n'a pas encore ouvert devient réglable.
      expect(find.byType(CoachVoiceLine), findsExactly(2));
      expect(find.text('Voice: Automatic'), findsExactly(2));
    });

    testWidgets('un choix fait sur un coach verrouillé vaut pour sa séance',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pumpCustomPicker(tester, tts);

      // La ligne de Victoria : la seconde carte de coach.
      await tester.tap(voiceLineButton(1));
      await tester.pumpAndSettle();
      expect(find.text('Victoria\'s voice'), findsOne);

      await tester.tap(find.text('en-us-x-tpd-local  ·  en-US'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(CustomCoachPickerScreen))).pop();
      await tester.pumpAndSettle();

      voicesPushed.clear();
      await startSessionWith(tts, victoria);
      expect(voicesPushed.last, 'en-us-x-tpd-local');
    });
  });

  group('L\'étanchéité de l\'aperçu suit la feuille', () {
    testWidgets(
        'fermer la feuille en plein aperçu, depuis le sélecteur de coach, '
        'ne laisse rien du coach', (tester) async {
      // Même défaut que celui corrigé au Profil : la feuille se ferme par
      // n'importe quel geste et rend la main **sans attendre** l'aperçu
      // qu'un `onTap` a lancé. Si la restauration finit la première,
      // l'aperçu repose le preset du coach derrière elle, et le Profil
      // présente ensuite la voix de Marc comme celle de l'utilisateur.
      final tts = TtsService(locale: const Locale('en'));
      await tts.init();
      await tts.setUserVoice('en-us-x-tpd-local', 'en-US');
      await pumpCareerPicker(tester, tts);

      // Le moteur devient lent : sur appareil, chaque appel de voix
      // traverse le canal de plateforme puis le moteur TTS. Sans cette
      // latence, la fenêtre de course s'effondre à zéro.
      voiceCallLatency = const Duration(milliseconds: 200);

      await tester.tap(voiceLineButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('en-gb-x-gbd-local  ·  en-GB'));
      // Surtout pas de `pumpAndSettle` ici : l'aperçu doit être encore en
      // vol au moment où la feuille se ferme.
      await tester.pump();

      Navigator.of(tester.element(find.byType(CoachPickerScreen))).pop();
      await tester.pumpAndSettle();
      // Les réponses du moteur lent sont des timers, pas des animations :
      // `pumpAndSettle` rend la main avant qu'elles soient toutes tombées.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(tts.currentPitch, closeTo(TtsService.defaultPitch, 0.001),
          reason: 'la hauteur de Marc (0.85) survit à la fermeture et '
              'devient celle que le Profil affiche comme réglage par '
              'défaut');
      expect(tts.currentRate, closeTo(TtsService.defaultRate, 0.001),
          reason: 'même chose pour le débit du coach');
      expect(tts.currentVoiceName, 'en-us-x-tpd-local',
          reason: 'et la voix rendue reste celle que l\'utilisateur a '
              'choisie');
    });
  });
}
