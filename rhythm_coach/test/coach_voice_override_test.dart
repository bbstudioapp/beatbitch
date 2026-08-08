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

/// Réglage de voix **par coach** — la seule réponse possible au défaut
/// « Marc parle avec une voix de femme ».
///
/// Aucune plateforme cible n'expose le genre d'une voix : ni le plugin, ni
/// `android.speech.tts.Voice`, et les noms Google (`en-gb-x-gbd-local`) ne
/// portent aucun indice exploitable. Le filtre par genre de `_fallbackPick`
/// ne peut donc jamais réussir — seule une oreille humaine peut choisir. Ces
/// tests vérifient que ce choix humain, une fois fait, est bien celui que le
/// moteur reçoit en séance.
///
/// Le problème dépasse Marc : six coachs sur sept déclarent une voix `fr-FR`
/// en dur, donc tout utilisateur non-francophone entend une rotation
/// arbitraire pour *tous* ses coachs. C'est ce que ce réglage rend réglable.
///
/// Les tests pilotent le bloc réel du Profil (`CoachVoiceSection`) plutôt que
/// le service : c'est le seul moyen de prouver que *le choix de
/// l'utilisateur* est respecté, et pas seulement qu'une API sait écrire une
/// préférence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');

  /// Voix telles que les retourne le moteur Google Android en anglais.
  /// `en-gb-x-gba-local` est la 1ʳᵉ préférée (donc ce que l'auto-sélection
  /// impose), `en-gb-x-gbd-local` est celle que l'utilisateur choisit — c'est
  /// littéralement celle qu'il avait sélectionnée dans son rapport de bug.
  ///
  /// **Aucune entrée ne porte de `gender`**, et c'est le point : le composant
  /// Android ne remonte que nom, langue, qualité, latence, réseau et
  /// fonctionnalités. Un mock qui inventerait un genre ferait passer des
  /// tests sur un chemin qui n'existe sur aucun appareil.
  const enVoices = <Map<String, String>>[
    {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
    {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
    {'name': 'en-us-x-tpd-local', 'locale': 'en-US'},
  ];

  const deVoices = <Map<String, String>>[
    {'name': 'de-de-x-deg-local', 'locale': 'de-DE'},
    {'name': 'de-de-x-deb-local', 'locale': 'de-DE'},
  ];

  /// Marc, tel qu'il est déclaré dans `coach_07_marc.json` : aucune voix
  /// nommée, juste un genre que rien ne sait honorer, et un rate/pitch
  /// masculins qui portent aujourd'hui seuls son identité.
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
      preferredGender: 'male',
      rate: 0.55,
      pitch: 0.85,
    ),
  );

  /// Lina : voix nommée en `fr-FR`, donc hors locale dès qu'on n'est pas en
  /// français — le cas des six autres coachs.
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

  /// Faux moteur TTS qui enregistre ce qui lui est **réellement poussé** —
  /// distinct de ce que le service expose et de ce que l'UI affiche.
  final voicesPushed = <String>[];
  var engineVoices = <Map<String, String>>[...enVoices];

  /// Temps que met le moteur à répondre aux appels de voix. Zéro partout
  /// sauf là où on veut observer ce qui se passe *pendant* un aperçu : un
  /// moteur qui répond dans la foulée referme la fenêtre de course, et un
  /// test de concurrence passerait alors avant comme après un correctif.
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

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
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

  /// Monte le bloc « VOIX DES COACHS » du Profil.
  Future<void> pumpSection(
    WidgetTester tester,
    TtsService tts, {
    List<Coach> coaches = const [marc],
  }) async {
    final profile = UserProfileService();
    addTearDown(profile.dispose);
    // Démontage préalable : sans ça, un second `pumpWidget` du même arbre
    // réutilise l'élément existant et l'état (voix chargées, réglages lus)
    // survit — ce qu'on veut justement rejouer à neuf après un redémarrage.
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

  /// Ouvre la feuille du coach et y choisit [voiceLabel], exactement comme
  /// l'utilisateur le fait dans le Profil.
  Future<void> pickVoiceForCoach(
    WidgetTester tester,
    TtsService tts,
    String coachName,
    String voiceLabel, {
    List<Coach> coaches = const [marc],
  }) async {
    await pumpSection(tester, tts, coaches: coaches);
    await tester.tap(find.text(coachName));
    await tester.pumpAndSettle();
    await tester.tap(find.text(voiceLabel));
    await tester.pumpAndSettle();
    // Fermer la feuille : c'est là que le service rend la main au réglage
    // hors-carrière (l'aperçu a posé le preset du coach).
    Navigator.of(tester.element(find.byType(Scaffold))).pop();
    await tester.pumpAndSettle();
  }

  /// Ce que fait `career_screen._applyCoachVoicePreset` au démarrage d'une
  /// séance : prendre la main sur l'état vocal, puis pousser le preset du
  /// coach au moteur.
  Future<void> startSessionWith(TtsService tts, Coach coach) {
    final preset = coach.voicePreset;
    return tts.takeVoiceLead(
      () => tts.applyCoachVoicePreset(
        coachId: coach.id,
        voiceName: preset.voiceName,
        voiceLocale: preset.voiceLocale,
        rate: preset.rate,
        pitch: preset.pitch,
        preferredGender: preset.preferredGender,
      ),
    );
  }

  group('Le choix de l\'utilisateur arrive-t-il jusqu\'au moteur ?', () {
    testWidgets(
        'la voix choisie pour Marc est celle poussée à la séance '
        'suivante', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      voicesPushed.clear();
      await startSessionWith(tts, marc);

      expect(voicesPushed.last, 'en-gb-x-gbd-local',
          reason: 'la voix réellement poussée au moteur, pas seulement '
              'celle affichée');
      expect(tts.currentVoiceName, 'en-gb-x-gbd-local');
    });

    testWidgets('le choix survit à un redémarrage de l\'app', (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      // Redémarrage : nouveau service, mêmes SharedPreferences.
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();
      voicesPushed.clear();
      await startSessionWith(restarted, marc);

      expect(voicesPushed.last, 'en-gb-x-gbd-local');
    });

    testWidgets(
        'le réglage vaut aussi pour un coach à voix nommée hors '
        'locale', (tester) async {
      // Lina déclare `fr-fr-x-fra-local` : en anglais, la cascade lui donne
      // une voix tirée au hash de ce nom. C'est ce que le réglage remplace.
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
        tester,
        tts,
        'Lina',
        'en-us-x-tpd-local  ·  en-US',
        coaches: const [lina],
      );

      voicesPushed.clear();
      await startSessionWith(tts, lina);

      expect(voicesPushed.last, 'en-us-x-tpd-local');
    });

    testWidgets('un coach non réglé garde sa cascade d\'origine',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
        tester,
        tts,
        'Marc',
        'en-gb-x-gbd-local  ·  en-GB',
        coaches: const [marc, lina],
      );

      voicesPushed.clear();
      await startSessionWith(tts, lina);

      expect(voicesPushed.last, isNot('en-gb-x-gbd-local'),
          reason: 'le réglage de Marc ne doit pas fuiter sur Lina');
    });
  });

  group('Débit et hauteur restent ceux du coach', () {
    testWidgets('l\'utilisateur choisit un timbre, pas un rythme',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      await startSessionWith(tts, marc);

      expect(tts.currentVoiceName, 'en-gb-x-gbd-local');
      expect(tts.currentRate, closeTo(0.55, 0.001));
      expect(tts.currentPitch, closeTo(0.85, 0.001));
    });
  });

  group('Repli quand la voix disparaît', () {
    testWidgets('repli silencieux en séance, sans effacer la préférence',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      // Pack de langue désinstallé / moteur TTS changé.
      engineVoices = enVoices
          .where((v) => v['name'] != 'en-gb-x-gbd-local')
          .map(Map<String, String>.from)
          .toList();
      final restarted = TtsService(locale: const Locale('en'));
      await restarted.init();
      voicesPushed.clear();
      await startSessionWith(restarted, marc);

      expect(voicesPushed, isNotEmpty,
          reason: 'la cascade coach reprend la main, le coach n\'est pas muet');
      expect(voicesPushed.last, isNot('en-gb-x-gbd-local'));

      // La clé n'a pas été effacée : une absence peut être temporaire.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts.voice.coach.coach_07_marc.en'),
          'en-gb-x-gbd-local');

      // La voix réapparaît : le choix reprend de lui-même.
      engineVoices = <Map<String, String>>[...enVoices];
      final later = TtsService(locale: const Locale('en'));
      await later.init();
      voicesPushed.clear();
      await startSessionWith(later, marc);
      expect(voicesPushed.last, 'en-gb-x-gbd-local');
    });

    testWidgets('le Profil signale la voix absente au lieu de son nom',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      engineVoices = enVoices
          .where((v) => v['name'] != 'en-gb-x-gbd-local')
          .map(Map<String, String>.from)
          .toList();
      final restarted = TtsService(locale: const Locale('en'));
      await pumpSection(tester, restarted);

      expect(find.text('Saved voice not available on this device'), findsOne);
      expect(find.text('en-gb-x-gbd-local'), findsNothing);
    });
  });

  group('« Automatique » rétablit la cascade', () {
    testWidgets('la clé est supprimée, pas remplacée par une valeur magique',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tts.voice.coach.coach_07_marc.en'), isNotNull);

      await pickVoiceForCoach(tester, tts, 'Marc', 'Automatic');

      expect(prefs.getString('tts.voice.coach.coach_07_marc.en'), isNull,
          reason: 'absence de clé = comportement d\'origine, un seul état '
              'à raisonner');

      voicesPushed.clear();
      await startSessionWith(tts, marc);
      expect(voicesPushed.last, isNot('en-gb-x-gbd-local'));
    });
  });

  group('Un réglage vaut pour une langue', () {
    testWidgets('l\'override anglais est invisible depuis l\'allemand',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      // Passage en allemand : la voix anglaise choisie n'y existe pas, et la
      // réappliquer produirait de l'allemand à phonétique anglaise.
      engineVoices = <Map<String, String>>[...deVoices];
      await LocaleService.instance.setLocale(const Locale('de'));
      addTearDown(() => LocaleService.instance.setLocale(const Locale('en')));
      await pumpSection(tester, tts);

      expect(find.text('Automatisch'), findsOne,
          reason: 'aucun réglage pour cette langue → cascade d\'origine');

      voicesPushed.clear();
      await startSessionWith(tts, marc);
      expect(voicesPushed.last, isNot('en-gb-x-gbd-local'));

      // Retour en anglais : le réglage y est retrouvé intact.
      engineVoices = <Map<String, String>>[...enVoices];
      await LocaleService.instance.setLocale(const Locale('en'));
      await tts.setLocale(const Locale('en'));
      voicesPushed.clear();
      await startSessionWith(tts, marc);
      expect(voicesPushed.last, 'en-gb-x-gbd-local');
    });
  });

  group('Le réglage coach n\'empiète pas sur la voix par défaut', () {
    testWidgets('la sortie de séance rend sa voix à l\'utilisateur',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      await tts.init();
      await tts.setUserVoice('en-us-x-tpd-local', 'en-US');
      await pickVoiceForCoach(
          tester, tts, 'Marc', 'en-gb-x-gbd-local  ·  en-GB');

      await startSessionWith(tts, marc);
      expect(tts.currentVoiceName, 'en-gb-x-gbd-local');

      await tts.restoreDefaultVoicePreset();
      expect(tts.currentVoiceName, 'en-us-x-tpd-local',
          reason: 'le coach n\'a pas le droit de détruire le réglage '
              'hors-carrière en repartant');
    });

    testWidgets('fermer la feuille en plein aperçu ne laisse rien du coach',
        (tester) async {
      // Une feuille modale se ferme par le bouton retour, un tap hors zone
      // ou un glissement vers le bas, et rend la main **sans attendre**
      // l'aperçu qu'un `onTap` a lancé. Les deux chaînes écrivent alors sur
      // le même service : si la restauration finit la première, l'aperçu
      // repose le preset du coach derrière elle et la section VOIX du
      // dessus présente la voix de Marc comme celle de l'utilisateur.
      final tts = TtsService(locale: const Locale('en'));
      await tts.init();
      await tts.setUserVoice('en-us-x-tpd-local', 'en-US');
      await pumpSection(tester, tts);

      // Le moteur devient lent : sur appareil, chaque appel de voix
      // traverse le canal de plateforme puis le moteur TTS. Sans cette
      // latence, la fenêtre de course s'effondre à zéro.
      voiceCallLatency = const Duration(milliseconds: 200);

      await tester.tap(find.text('Marc'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('en-gb-x-gbd-local  ·  en-GB'));
      // Surtout pas de `pumpAndSettle` ici : l'aperçu doit être encore en
      // vol au moment où la feuille se ferme.
      await tester.pump();

      Navigator.of(tester.element(find.byType(Scaffold))).pop();
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
