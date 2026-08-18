import 'dart:convert';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/l10n/app_localizations.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:beat_bitch/services/locale_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:beat_bitch/services/user_profile_service.dart';
import 'package:beat_bitch/widgets/coach_voice_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Export **dédié** aux réglages de voix (Phase 4).
///
/// Il existe parce que l'export diagnostic complet est disproportionné pour
/// la question posée : il porte le temps de jeu, les scores d'humiliation et
/// d'obéissance, les capacités mesurées, les paliers, l'anatomie, les
/// surnoms, le consentement. Demander ça pour connaître une voix, c'est ne
/// jamais le recevoir. Un fichier qui ne contient que les voix est anodin —
/// **à condition qu'il le reste**.
///
/// C'est tout l'objet du premier groupe de tests, qui prend le fichier par
/// trois angles :
///
/// 1. **Sentinelles** — aucune valeur connue du profil n'en ressort.
/// 2. **Structure** — aucun champ n'apparaît, à aucun niveau.
/// 3. **Provenance** — chaque valeur du fichier est traçable à une source
///    autorisée (réglages de voix, catalogue de coachs, plateforme, langue
///    active, version de l'app).
///
/// Les deux premiers énumèrent ce qui ne doit **pas** sortir : c'est une
/// liste ouverte, en retard d'une clé à l'instant où quelqu'un en ajoute une
/// au profil. Le troisième énumère ce qui a le **droit** de sortir : liste
/// fermée, courte, et qu'on ne peut pas étendre par distraction. C'est lui
/// qui porte la garantie ; les deux autres restent parce qu'ils nomment la
/// fuite en clair quand elle se produit.
///
/// Limite résiduelle, assumée : une valeur du profil qui coïnciderait
/// exactement avec une valeur déjà autorisée (le nom d'un coach, la
/// plateforme) passerait — elle n'apprendrait alors rien que le fichier ne
/// dise déjà.
PackageInfo _info() => PackageInfo(
      appName: 'BeatBitch',
      packageName: 'app.bbstudio.beatbitch',
      version: '0.6.1',
      buildNumber: '12',
    );

/// Clés persistées du profil, chacune remplie d'une valeur **reconnaissable**.
///
/// Le préfixe `SENTINEL-` garantit qu'une correspondance dans le fichier est
/// une vraie fuite et pas une collision : aucun identifiant de voix, aucun
/// nom de coach, aucun code langue ne le contient. Les valeurs numériques
/// sont choisies hors de toute plage plausible pour la même raison.
const _profileSentinels = <String, Object>{
  // career
  'career.max_level': 424242,
  'career.completed_sessions': 424243,
  // specialization
  'specialization.respec_count': 424244,
  // stats / thermomètres
  'stats.total_seconds': 313131,
  'stats.humiliation_level': 271828.5,
  'stats.obedience_level': 161803.5,
  // capacités
  'cap.gorge.apnee_streak.best': 999888.5,
  'cap.gorge.apnee_streak.comfort': 999889.5,
  // paliers
  'career.milestones_completed': '["SENTINEL-milestone"]',
  // coach
  'coach.selected_id': 'SENTINEL-selected-coach',
  'coach.unlocked_ids': <String>['SENTINEL-unlocked-coach'],
  // anatomie
  'profile.anatomy.has_balls': false,
  // surnoms (jamais exportés par défaut, mais on vérifie quand même)
  'user_profile_prenom': 'SENTINEL-prenom',
  'user_profile_custom_nicknames': <String>['SENTINEL-nickname'],
  // configs custom
  'custom.last_config_id': 'SENTINEL-custom-config',
  // surprises / affichage
  'surprise.window_seconds': 555444,
  // consentement
  'app.adult_consent_accepted': true,
};

/// Réglages de voix d'une anglophone qui a réglé Marc (et l'avait déjà réglé
/// quand elle jouait en français), plus une voix par défaut hors carrière et
/// un débit et une hauteur écartés de leurs défauts.
const _voiceSettings = <String, Object>{
  'tts.voice.en': 'en-gb-x-gba-local',
  'tts.voice.coach.coach_07_marc.en': 'en-gb-x-gbd-local',
  'tts.voice.coach.coach_07_marc.fr': 'fr-fr-x-frd-local',
  'tts.rate': 0.42,
  'tts.pitch': 1.6,
};

Future<DiagnosticExportService> _build({
  Map<String, Object> seed = const <String, Object>{},
  String locale = 'en',
  String platform = 'android',
}) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return DiagnosticExportService(
    prefs: prefs,
    packageInfo: _info(),
    platform: platform,
    locale: locale,
    exportedAt: DateTime.utc(2026, 8, 8, 10, 0, 0),
  );
}

Map<String, Object> _seedWithProfile() => <String, Object>{
      ..._profileSentinels,
      ..._voiceSettings,
    };

/// Aplatit un payload JSON en ses feuilles : `chemin → valeur`, l'indice de
/// liste écrasé en `[]` (`voice.coaches[].voice`). C'est la **forme** du
/// champ qu'on veut contraindre, pas la position d'une entrée dans sa liste.
Iterable<MapEntry<String, Object?>> _leaves(Object? node,
    [String path = '']) sync* {
  if (node is Map) {
    for (final e in node.entries) {
      yield* _leaves(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
    }
  } else if (node is List) {
    for (final v in node) {
      yield* _leaves(v, '$path[]');
    }
  } else {
    yield MapEntry(path, node);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('non-fuite — le fichier ne contient que les voix', () {
    test('aucune valeur du profil ne se retrouve dans le fichier partagé',
        () async {
      final svc = await _build(seed: _seedWithProfile());
      final raw = svc.buildVoiceShareJson();

      for (final entry in _profileSentinels.entries) {
        final value = entry.value;
        // Les booléens et les petits entiers ne font pas des sentinelles
        // fiables (`false` et `1` apparaissent légitimement) : ceux-là sont
        // couverts par le verrou structurel du test suivant.
        if (value is bool) continue;
        final needle = value is List ? (value.first as String) : '$value';
        expect(
          raw,
          isNot(contains(needle)),
          reason: 'La valeur persistée sous `${entry.key}` s\'est invitée '
              'dans le fichier de partage des voix. Ce fichier est proposé '
              'comme anodin : il ne doit contenir QUE des réglages de voix.',
        );
      }
    });

    test('la structure du fichier est verrouillée, champ par champ', () async {
      final svc = await _build(seed: _seedWithProfile());
      final payload = svc.buildVoiceSharePayload();

      // Tout ce que le fichier a le droit de porter, nommément. Ajouter un
      // champ ici est une décision à prendre — pas un effet de bord.
      expect(
        payload.keys.toSet(),
        <String>{'kind', 'appVersion', 'platform', 'voice'},
        reason: 'Un champ est apparu (ou a disparu) au premier niveau du '
            'fichier de partage.',
      );
      expect(
        (payload['voice'] as Map<String, dynamic>).keys.toSet(),
        <String>{
          'activeLanguage',
          'selectionSupported',
          'rate',
          'pitch',
          'default',
          'coaches',
        },
        reason: 'Un champ est apparu (ou a disparu) dans la section voix.',
      );

      // Et aucune section du profil, quelle qu'elle soit — y compris celles
      // qui seraient ajoutées à l'export complet après coup.
      final full = svc.buildPayload(
        const DiagnosticExportOptions(includeNicknames: true),
      );
      for (final section in full.keys) {
        if (section == 'voice' ||
            section == 'appVersion' ||
            section == 'platform') {
          continue;
        }
        expect(
          payload.containsKey(section),
          isFalse,
          reason: 'La section `$section` de l\'export diagnostic complet '
              's\'est invitée dans le fichier de partage des voix.',
        );
      }
    });

    test('les entrées de voix ne portent rien de plus qu\'à l\'export complet',
        () async {
      final svc = await _build(seed: _seedWithProfile());
      final voice =
          svc.buildVoiceSharePayload()['voice'] as Map<String, dynamic>;

      for (final entry
          in (voice['coaches'] as List).cast<Map<String, dynamic>>()) {
        expect(
          entry.keys.toSet(),
          entry['voice'] == null
              ? <String>{'coachId', 'coachName', 'language', 'voice', 'source'}
              : <String>{
                  'coachId',
                  'coachName',
                  'language',
                  'voice',
                  'source',
                  'platform',
                },
          reason: 'Une entrée de coach porte un champ inattendu : '
              '${entry['coachId']}.',
        );
      }
      for (final entry
          in (voice['default'] as List).cast<Map<String, dynamic>>()) {
        expect(
          entry.keys.toSet(),
          entry['voice'] == null
              ? <String>{'language', 'voice', 'source'}
              : <String>{'language', 'voice', 'source', 'platform'},
          reason: 'Une entrée de voix par défaut porte un champ inattendu.',
        );
      }
    });

    test('chaque valeur du fichier vient d\'une source autorisée', () async {
      // Les deux tests précédents cherchent ce qui ne doit pas sortir.
      // Celui-ci prend le problème par l'autre bout et n'admet que ce qui a
      // le droit de sortir — c'est ce qui attrape l'**enrichissement d'un
      // champ déjà permis**, le vecteur qu'une sentinelle ne voit pas : un
      // `platform` qui deviendrait `"android:<palier de carrière>"` ne crée
      // aucune clé nouvelle et ne porte aucune valeur sentinelle.
      const platform = 'android';
      const locale = 'en';
      final svc = await _build(
        seed: _seedWithProfile(),
        locale: locale,
        platform: platform,
      );
      final prefs = await SharedPreferences.getInstance();
      final languages = kSupportedLocales.map((l) => l.languageCode).toSet();

      // Provenance des identifiants de voix : ce qui est rangé sous une clé
      // de voix, et rien d'autre. Les clés sont composées via `TtsService`,
      // comme le service lui-même — une divergence de préfixe rétrécirait
      // l'ensemble autorisé, donc ferait échouer ce test, jamais l'inverse.
      final storedVoices = <String>{
        for (final lang in languages)
          ...<String?>[
            prefs.getString(TtsService.userVoiceKey(lang)),
            for (final c in CoachCatalog.defaults)
              prefs.getString(TtsService.coachVoiceKey(c.id, lang)),
          ].whereType<String>(),
      };
      // Même règle pour les deux nombres : ce qui est rangé sous la clé de
      // débit, et rien d'autre. Le seed les écarte de leurs défauts, sinon
      // `null == null` suffirait à passer et la provenance ne serait pas
      // éprouvée.
      final storedRate = prefs.getDouble(TtsService.userRateKey);
      final storedPitch = prefs.getDouble(TtsService.userPitchKey);
      expect(storedRate, isNotNull);
      expect(storedPitch, isNotNull);

      // La liste fermée. Chaque entrée dit d'où la valeur vient ; aucune ne
      // se contente de décrire son type.
      final sources = <String, bool Function(Object?)>{
        'kind': (v) => v == DiagnosticExportService.voiceShareKind,
        'appVersion': (v) => v == '${_info().version}+${_info().buildNumber}',
        'platform': (v) => v == platform,
        'voice.activeLanguage': (v) => v == locale,
        'voice.selectionSupported': (v) => v is bool,
        'voice.rate': (v) => v == storedRate,
        'voice.pitch': (v) => v == storedPitch,
        'voice.default[].language': languages.contains,
        'voice.default[].voice': (v) => v == null || storedVoices.contains(v),
        'voice.default[].source': (v) => v == 'chosen' || v == 'automatic',
        'voice.default[].platform': (v) => v == platform,
        'voice.coaches[].coachId': (v) =>
            CoachCatalog.defaults.any((c) => c.id == v),
        'voice.coaches[].coachName': (v) =>
            CoachCatalog.defaults.any((c) => c.name == v),
        'voice.coaches[].language': languages.contains,
        'voice.coaches[].voice': (v) => v == null || storedVoices.contains(v),
        'voice.coaches[].source': (v) => v == 'chosen' || v == 'automatic',
        'voice.coaches[].platform': (v) => v == platform,
      };

      for (final leaf in _leaves(svc.buildVoiceSharePayload())) {
        final fromAnAllowedSource = sources[leaf.key];
        expect(
          fromAnAllowedSource,
          isNotNull,
          reason: 'Le champ `${leaf.key}` n\'existait pas quand la garantie '
              'de non-fuite a été écrite. L\'ajouter ici est une décision à '
              'prendre : dire de quelle source la valeur vient, pas la '
              'laisser passer parce qu\'elle a l\'air inoffensive.',
        );
        expect(
          fromAnAllowedSource!(leaf.value),
          isTrue,
          reason: '`${leaf.key}` vaut `${leaf.value}`, qui ne vient d\'aucune '
              'source autorisée (réglages de voix, catalogue de coachs, '
              'plateforme, langue active, version de l\'app). Ce fichier est '
              'proposé comme anodin : tout ce qu\'il porte doit être '
              'traçable jusqu\'à l\'une de ces cinq sources.',
        );
      }
    });
  });

  group('lisible et agrégeable seul', () {
    test('la section voix est identique à celle de l\'export complet',
        () async {
      final svc = await _build(seed: _seedWithProfile());
      final full = json.decode(svc.buildJson(const DiagnosticExportOptions()))
          as Map<String, dynamic>;
      final shared =
          json.decode(svc.buildVoiceShareJson()) as Map<String, dynamic>;

      // Même clé, même contenu : `.voice.coaches[]` agrège un lot mélangeant
      // les deux formats sans transformation.
      expect(shared['voice'], full['voice']);
    });

    test('le moteur reste lisible même quand rien n\'est réglé', () async {
      // Le cas qui perd l'information au détachement : sans aucun réglage,
      // aucune entrée ne porte de `platform` (elle n'est posée que là où il
      // y a une voix à attribuer). Le fichier complet la donnait en tête —
      // celui-ci doit la donner aussi, sinon un export « tout automatique »
      // ne dit plus de quelle plateforme il vient.
      final svc = await _build(platform: 'android');
      final payload = svc.buildVoiceSharePayload();
      final voice = payload['voice'] as Map<String, dynamic>;

      expect(payload['platform'], 'android');
      expect(
        (voice['coaches'] as List)
            .cast<Map<String, dynamic>>()
            .every((e) => !e.containsKey('platform')),
        isTrue,
        reason: 'Prémisse du test : aucune entrée ne porte le moteur ici.',
      );
    });

    test('la version de l\'app date le fichier, sans horodatage', () async {
      final svc = await _build(seed: _seedWithProfile());
      final payload = svc.buildVoiceSharePayload();

      expect(payload['appVersion'], '0.6.1+12');
      expect(payload.containsKey('exportedAt'), isFalse,
          reason: 'Un horodatage précis permettrait de recouper deux envois '
              'd\'une même personne, sans rien apporter à l\'analyse.');
      expect(payload.containsKey('integrity'), isFalse,
          reason: 'Ce fichier n\'est pas réimporté par l\'app : un checksum '
              'y serait un champ opaque au milieu d\'un fichier dont tout '
              'l\'argument est qu\'on peut le lire en entier.');
    });

    test('le catalogue entier est décrit dans la langue active', () async {
      final svc = await _build(seed: _seedWithProfile());
      final voice =
          svc.buildVoiceSharePayload()['voice'] as Map<String, dynamic>;
      final coaches = (voice['coaches'] as List).cast<Map<String, dynamic>>();

      expect(voice['activeLanguage'], 'en');
      expect(
        coaches.where((e) => e['language'] == 'en').length,
        CoachCatalog.defaults.length,
      );
      // Le réglage laissé sur une langue devenue inactive remonte aussi.
      final marcFr = coaches.firstWhere(
        (e) => e['coachId'] == 'coach_07_marc' && e['language'] == 'fr',
      );
      expect(marcFr['voice'], 'fr-fr-x-frd-local');
    });

    test('le nom de fichier ne se confond pas avec l\'export complet',
        () async {
      final svc = await _build(seed: _seedWithProfile());

      expect(svc.voiceShareFilename(), 'beatbitch-voices-en.json');
      expect(svc.defaultFilename(), 'beatbitch-export-20260808-100000.json');
      expect(
        svc.voiceShareFilename(),
        isNot(contains('20260808')),
        reason: 'Pas d\'horodatage dans le nom non plus — c\'est le même '
            'vecteur de recoupement que dans le contenu.',
      );
    });

    test('la langue du nom de fichier suit la langue active', () async {
      final svc = await _build(locale: 'de');
      expect(svc.voiceShareFilename(), 'beatbitch-voices-de.json');
    });
  });

  group('l\'export complet n\'a pas changé', () {
    test('il porte toujours toutes ses sections et un checksum valide',
        () async {
      final svc = await _build(seed: _seedWithProfile());
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      expect(DiagnosticExportService.verifyIntegrity(payload), isTrue);
      for (final section in const <String>[
        'career',
        'stats',
        'capabilities',
        'milestones',
        'coach',
        'voice',
        'consent',
        'integrity',
      ]) {
        expect(payload.containsKey(section), isTrue, reason: section);
      }
    });

    test('produire le fichier de voix ne perturbe pas l\'export complet',
        () async {
      final svc = await _build(seed: _seedWithProfile());
      final before = svc.buildJson(const DiagnosticExportOptions());
      svc.buildVoiceShareJson();
      final after = svc.buildJson(const DiagnosticExportOptions());

      expect(after, before);
    });

    test('les clés lues sont bien celles que la séance honore', () async {
      // Garde-fou de composition : le fichier partagé se compose des mêmes
      // clés que `TtsService`, jamais de littéraux recopiés.
      final svc = await _build(seed: <String, Object>{
        TtsService.userVoiceKey('en'): 'en-gb-x-gba-local',
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final voice =
          svc.buildVoiceSharePayload()['voice'] as Map<String, dynamic>;

      expect(
        (voice['default'] as List).cast<Map<String, dynamic>>().single['voice'],
        'en-gb-x-gba-local',
      );
      expect(
        (voice['coaches'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((e) => e['coachId'] == 'coach_07_marc')['voice'],
        'en-gb-x-gbd-local',
      );
    });
  });

  group('montrer avant d\'envoyer', () {
    const channel = MethodChannel('flutter_tts');
    const lina = Coach(
      id: 'coach_01_lina',
      name: 'Lina',
      title: 'La Douce',
      archetype: CoachArchetype.bienveillant,
      publicBio: 'Bio',
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

    setUp(() async {
      SharedPreferences.setMockInitialValues(_seedWithProfile());
      PackageInfo.setMockInitialValues(
        appName: 'BeatBitch',
        packageName: 'app.bbstudio.beatbitch',
        version: '0.6.1',
        buildNumber: '12',
        buildSignature: '',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getVoices') {
          return <Map<String, String>>[
            {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
            {'name': 'en-gb-x-gbd-local', 'locale': 'en-GB'},
          ];
        }
        return 1;
      });
      await LocaleService.instance.setLocale(const Locale('en'));
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('la feuille affiche le fichier entier avant de l\'envoyer',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      final profile = UserProfileService();
      addTearDown(profile.dispose);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoachVoiceSection(
            tts: tts,
            coaches: const [lina],
            userProfile: profile,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      // Le fichier est affiché tel qu'il sera envoyé, pas résumé.
      final expected = await _build(seed: _seedWithProfile())
          .then((s) => s.buildVoiceShareJson());
      expect(find.text(expected), findsOneWidget);

      // Et rien du profil n'y figure, jusque sur l'écran de confirmation.
      expect(find.textContaining('SENTINEL-'), findsNothing);

      // Le bouton d'envoi n'est actif que parce que le contenu est là.
      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.onPressed, isNotNull);
    });

    testWidgets('le bouton d\'envoi est inerte tant que rien n\'est affiché',
        (tester) async {
      final tts = TtsService(locale: const Locale('en'));
      final profile = UserProfileService();
      addTearDown(profile.dispose);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CoachVoiceSection(
            tts: tts,
            coaches: const [lina],
            userProfile: profile,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OutlinedButton));
      // Une seule frame : la feuille est montée, le contenu est encore en
      // vol. C'est exactement la fenêtre où un envoi serait aveugle.
      await tester.pump();

      final send = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(send.onPressed, isNull);

      await tester.pumpAndSettle();
    });
  });
}
