import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/services/diagnostic_export_integrity.dart';
import 'package:beat_bitch/services/diagnostic_export_service.dart';
import 'package:beat_bitch/services/diagnostic_import_service.dart';
import 'package:beat_bitch/services/locale_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Section `voice` de l'export diagnostic (Phase 3 du réglage de voix par
/// coach) : elle porte la voix par défaut par langue (`tts.voice.<lang>`), les
/// réglages par coach (`tts.voice.coach.<coachId>.<lang>`) et le débit et la
/// hauteur de la voix par défaut (`tts.rate`, `tts.pitch`).
///
/// Son premier lecteur est **humain** : les exports renvoyés par les
/// utilisateurs sont le seul moyen de savoir quelle voix mettre par défaut
/// dans les langues que la mainteneuse ne parle pas. Les tests de forme
/// ci-dessous verrouillent donc ce qui rend une entrée interprétable hors
/// contexte (langue, nom du coach, marqueur « automatique » explicite),
/// pas seulement ce qui la rend réimportable.
PackageInfo _info() => PackageInfo(
      appName: 'BeatBitch',
      packageName: 'app.bbstudio.beatbitch',
      version: '0.6.1',
      buildNumber: '12',
    );

Future<DiagnosticExportService> _build({
  required Map<String, Object> seed,
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

Map<String, dynamic> _voiceOf(DiagnosticExportService svc) =>
    svc.buildPayload(const DiagnosticExportOptions())['voice']
        as Map<String, dynamic>;

List<Map<String, dynamic>> _entries(Map<String, dynamic> voice, String key) =>
    (voice[key] as List).cast<Map<String, dynamic>>();

Map<String, dynamic>? _coachEntry(
  Map<String, dynamic> voice,
  String coachId,
  String language,
) {
  for (final e in _entries(voice, 'coaches')) {
    if (e['coachId'] == coachId && e['language'] == language) return e;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('export — forme de la section voice', () {
    test('la langue active est décrite en entier, coachs compris', () async {
      final svc = await _build(seed: const <String, Object>{});
      final voice = _voiceOf(svc);

      expect(voice['activeLanguage'], 'en');

      // Voix par défaut : la langue active y est toujours, même sans choix.
      final defaults = _entries(voice, 'default');
      expect(defaults.length, 1);
      expect(defaults.single['language'], 'en');
      expect(defaults.single['voice'], isNull);
      expect(defaults.single['source'], 'automatic');

      // Coachs : tout le catalogue pour la langue active — un coach laissé
      // en automatique est une donnée, pas une absence de donnée.
      final coaches = _entries(voice, 'coaches');
      expect(coaches.length, CoachCatalog.defaults.length);
      for (final c in CoachCatalog.defaults) {
        final entry = _coachEntry(voice, c.id, 'en');
        expect(entry, isNotNull, reason: '${c.id} absent de la section');
        expect(entry!['coachName'], c.name);
        expect(entry['voice'], isNull);
        expect(entry['source'], 'automatic');
      }
    });

    test('un réglage explicite est marqué `chosen` avec son identifiant',
        () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.userVoiceKey('en'): 'en-gb-x-gba-local',
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final voice = _voiceOf(svc);

      final def = _entries(voice, 'default').single;
      expect(def['voice'], 'en-gb-x-gba-local');
      expect(def['source'], 'chosen');

      final marc = _coachEntry(voice, 'coach_07_marc', 'en')!;
      expect(marc['coachName'], 'Marc');
      expect(marc['voice'], 'en-gb-x-gbd-local');
      expect(marc['source'], 'chosen');

      // Les autres coachs de la langue active restent listés en automatique.
      final lina = _coachEntry(voice, 'coach_01_lina', 'en')!;
      expect(lina['source'], 'automatic');
    });

    test('une autre langue n\'apparaît que là où un choix a été fait',
        () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.userVoiceKey('fr'): 'fr-fr-x-fra-local',
        TtsService.coachVoiceKey('coach_07_marc', 'fr'): 'fr-fr-x-frd-local',
      });
      final voice = _voiceOf(svc);

      // Langue active (en) : décrite en entier malgré l'absence de réglage.
      expect(_coachEntry(voice, 'coach_01_lina', 'en'), isNotNull);
      // Langue inactive : seul le coach réglé remonte.
      final marcFr = _coachEntry(voice, 'coach_07_marc', 'fr')!;
      expect(marcFr['voice'], 'fr-fr-x-frd-local');
      expect(marcFr['source'], 'chosen');
      expect(_coachEntry(voice, 'coach_01_lina', 'fr'), isNull,
          reason: 'Une langue inutilisée ne doit pas encombrer l\'export.');

      final defaults = _entries(voice, 'default');
      expect(defaults.map((e) => e['language']), containsAll(['en', 'fr']));
      expect(defaults.where((e) => e['language'] == 'de'), isEmpty);
      expect(
        defaults.firstWhere((e) => e['language'] == 'fr')['voice'],
        'fr-fr-x-fra-local',
      );
    });

    test('signale que la plateforme n\'a pas prise sur la voix', () async {
      final android = await _build(seed: const <String, Object>{});
      expect(_voiceOf(android)['selectionSupported'], isTrue);

      final linux =
          await _build(seed: const <String, Object>{}, platform: 'linux');
      expect(_voiceOf(linux)['selectionSupported'], isFalse,
          reason: 'Sans ça, un export Linux plein d\'« automatique » se lit '
              'comme un désintérêt alors que le réglage n\'a aucune prise.');
    });

    test('le débit et la hauteur sont portés, `null` quand rien n\'est réglé',
        () async {
      final vierge = _voiceOf(await _build(seed: const <String, Object>{}));
      expect(vierge['rate'], isNull);
      expect(vierge['pitch'], isNull);

      // Hors de la liste `default`, qui a une entrée par langue : ces deux
      // réglages-là sont globaux.
      final regle = _voiceOf(await _build(seed: <String, Object>{
        TtsService.userRateKey: 0.42,
        TtsService.userPitchKey: 1.6,
      }));
      expect(regle['rate'], 0.42);
      expect(regle['pitch'], 1.6);
    });

    test('ordre déterministe : catalogue, langue active en tête', () async {
      final seed = <String, Object>{};
      for (final l in kSupportedLocales) {
        for (final c in CoachCatalog.defaults) {
          seed[TtsService.coachVoiceKey(c.id, l.languageCode)] = 'v';
        }
      }
      final svc = await _build(seed: seed);
      final coaches = _entries(_voiceOf(svc), 'coaches');

      // Le checksum ne trie pas les listes : l'ordre doit être stable. Et
      // la langue active passe devant — c'est celle qu'on vient lire.
      final languages = <String>[
        'en',
        for (final l in kSupportedLocales)
          if (l.languageCode != 'en') l.languageCode,
      ];
      final expected = <String>[
        for (final c in CoachCatalog.defaults)
          for (final lang in languages) '${c.id}#$lang',
      ];
      expect(
        coaches.map((e) => '${e['coachId']}#${e['language']}').toList(),
        expected,
      );
    });
  });

  group('export — attribution d\'une voix à son moteur', () {
    test(
        'un lot mélangeant les plateformes reste attribuable entrée par entrée',
        () async {
      // Même coach, même langue, deux moteurs : les identifiants viennent
      // d'espaces de noms disjoints (voix Android vs voix SAPI Windows), et
      // ne sont pas interchangeables.
      final android = await _build(seed: <String, Object>{
        TtsService.userVoiceKey('en'): 'en-gb-x-gba-local',
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final windows = await _build(
        seed: <String, Object>{
          TtsService.userVoiceKey('en'): 'Microsoft Zira Desktop',
          TtsService.coachVoiceKey('coach_07_marc', 'en'):
              'Microsoft David Desktop',
        },
        platform: 'windows',
      );

      // Agrégation type : on concatène les entrées des deux fichiers. Le
      // contexte parent disparaît — c'est l'entrée seule qui doit rester
      // interprétable.
      Iterable<Map<String, dynamic>> lot(String key) => <Map<String, dynamic>>[
            ..._entries(_voiceOf(android), key),
            ..._entries(_voiceOf(windows), key),
          ].where((e) => e['voice'] != null);

      expect(
        lot('coaches')
            .where((e) => e['coachId'] == 'coach_07_marc')
            .map((e) => '${e['platform']}:${e['voice']}')
            .toSet(),
        {'android:en-gb-x-gbd-local', 'windows:Microsoft David Desktop'},
        reason: 'Sans le moteur sur l\'entrée, le lot agrégé est une liste '
            'plate de chaînes hétérogènes : impossible de savoir laquelle '
            'est réutilisable sur quelle plateforme.',
      );
      expect(
        lot('default').map((e) => '${e['platform']}:${e['voice']}').toSet(),
        {'android:en-gb-x-gba-local', 'windows:Microsoft Zira Desktop'},
      );
    });

    test('le moteur n\'est porté que par les entrées qui ont une voix',
        () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final voice = _voiceOf(svc);

      expect(_coachEntry(voice, 'coach_07_marc', 'en')!['platform'], 'android');
      // Une entrée automatique n'a aucune valeur à interpréter : lui coller
      // le moteur ajouterait une colonne constante sur tout le catalogue.
      expect(
        _coachEntry(voice, 'coach_01_lina', 'en')!.containsKey('platform'),
        isFalse,
      );
      expect(
        _entries(voice, 'default').single.containsKey('platform'),
        isFalse,
      );
    });
  });

  group('export — intégrité', () {
    test('un export sans aucun réglage reste vérifiable', () async {
      final svc = await _build(seed: const <String, Object>{});
      final payload = svc.buildPayload(const DiagnosticExportOptions());
      expect(DiagnosticExportService.verifyIntegrity(payload), isTrue);
      expect(payload['voice'], isNotNull);
    });

    test('un export avec réglages reste vérifiable et son hash en dépend',
        () async {
      final withVoice = await _build(seed: <String, Object>{
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final p1 = withVoice.buildPayload(const DiagnosticExportOptions());
      expect(DiagnosticExportService.verifyIntegrity(p1), isTrue);

      final without = await _build(seed: const <String, Object>{});
      final p2 = without.buildPayload(const DiagnosticExportOptions());
      expect(
        (p1['integrity'] as Map)['value'],
        isNot((p2['integrity'] as Map)['value']),
        reason: 'Le checksum couvre toutes les sections, voice comprise.',
      );
    });

    test('une voix éditée après coup casse le checksum', () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());
      final coaches =
          (payload['voice'] as Map<String, dynamic>)['coaches'] as List;
      (coaches.first as Map<String, dynamic>)['voice'] = 'autre-voix';
      expect(DiagnosticExportService.verifyIntegrity(payload), isFalse);
    });

    test('un export produit avant la section voice reste vérifiable', () async {
      // Payload figé au format d'avant la Phase 3 : son `integrity` a été
      // calculé sans section voice, la vérification doit continuer de
      // passer (elle rehashe le fichier, pas ce que l'app produirait).
      final legacy = <String, dynamic>{
        'schemaVersion': 1,
        'exportedAt': '2026-05-17T14:32:05.000Z',
        'appVersion': '0.6.0+11',
        'platform': 'android',
        'locale': 'en',
        'career': {'maxLevel': 3},
      };
      legacy['integrity'] = <String, dynamic>{
        'algorithm': 'sha256',
        'value': DiagnosticExportIntegrity.compute(legacy),
        'scope': 'legacy',
      };
      expect(DiagnosticExportService.verifyIntegrity(legacy), isTrue);
    });
  });

  group('import — aller-retour', () {
    test('les réglages de voix survivent à un export → import', () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.userVoiceKey('en'): 'en-gb-x-gba-local',
        TtsService.coachVoiceKey('coach_07_marc', 'en'): 'en-gb-x-gbd-local',
        TtsService.coachVoiceKey('coach_01_lina', 'en'): 'en-us-x-tpf-local',
        // Langue que l'utilisateur n'utilise plus : le choix reste réel.
        TtsService.coachVoiceKey('coach_07_marc', 'fr'): 'fr-fr-x-frd-local',
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      // Nouvel appareil : prefs vierges.
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(payload);

      expect(
          prefs.getString(TtsService.userVoiceKey('en')), 'en-gb-x-gba-local');
      expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'en')),
          'en-gb-x-gbd-local');
      expect(prefs.getString(TtsService.coachVoiceKey('coach_01_lina', 'en')),
          'en-us-x-tpf-local');
      expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'fr')),
          'fr-fr-x-frd-local');
      // Un coach laissé en automatique n'écrit aucune clé.
      expect(prefs.getString(TtsService.coachVoiceKey('coach_06_nyx', 'en')),
          isNull);
    });

    test('le débit et la hauteur survivent à un export → import', () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.userRateKey: 0.42,
        TtsService.userPitchKey: 1.6,
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(payload);

      expect(prefs.getDouble(TtsService.userRateKey), 0.42);
      expect(prefs.getDouble(TtsService.userPitchKey), 1.6);
    });

    test('le débit d\'un coach survit à un export → import', () async {
      final svc = await _build(seed: <String, Object>{
        TtsService.coachRateKey('coach_07_marc'): 0.48,
        TtsService.coachPitchKey('coach_07_marc'): 0.78,
      });
      final payload = svc.buildPayload(const DiagnosticExportOptions());

      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(payload);

      expect(prefs.getDouble(TtsService.coachRateKey('coach_07_marc')), 0.48);
      expect(prefs.getDouble(TtsService.coachPitchKey('coach_07_marc')), 0.78);
      // Un coach laissé à sa couleur d'origine n'écrit aucune clé.
      expect(prefs.getDouble(TtsService.coachRateKey('coach_06_nyx')), isNull);
    });

    test('un payload porteur de voix efface un débit résiduel', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        TtsService.userRateKey: 0.42,
      });
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(<String, dynamic>{
        'voice': {
          'activeLanguage': 'en',
          'default': <Map<String, dynamic>>[],
          'coaches': <Map<String, dynamic>>[],
        },
      });
      expect(prefs.getDouble(TtsService.userRateKey), isNull,
          reason: 'même règle que les voix : un export qui parle de la voix '
              'repose l\'état vocal en entier, sinon on diagnostiquerait '
              'un débit en entendant le sien.');
    });

    test('une voix absente de cet appareil est posée telle quelle', () async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(<String, dynamic>{
        'voice': {
          'activeLanguage': 'de',
          'coaches': [
            {
              'coachId': 'coach_07_marc',
              'coachName': 'Marc',
              'language': 'de',
              'voice': 'voix-qui-nexiste-pas-ici',
              'source': 'chosen',
            },
          ],
        },
      });
      expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'de')),
          'voix-qui-nexiste-pas-ici',
          reason: 'L\'import ne valide pas : le repli silencieux de la '
              'séance s\'en charge, et la préférence n\'est jamais effacée.');
    });

    test('un payload porteur de voix efface les réglages résiduels', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        TtsService.coachVoiceKey('coach_01_lina', 'en'): 'residu-local',
        TtsService.userVoiceKey('en'): 'residu-defaut',
      });
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(<String, dynamic>{
        'voice': {
          'activeLanguage': 'en',
          'default': [
            {'language': 'en', 'voice': null, 'source': 'automatic'},
          ],
          'coaches': [
            {
              'coachId': 'coach_07_marc',
              'coachName': 'Marc',
              'language': 'en',
              'voice': 'en-gb-x-gbd-local',
              'source': 'chosen',
            },
          ],
        },
      });

      expect(prefs.getString(TtsService.coachVoiceKey('coach_01_lina', 'en')),
          isNull,
          reason: 'Diagnostiquer la voix d\'un utilisateur exige de ne pas '
              'entendre ses propres réglages par-dessus.');
      expect(prefs.getString(TtsService.userVoiceKey('en')), isNull);
      expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'en')),
          'en-gb-x-gbd-local');
    });

    test('une section voice inexploitable n\'efface pas les réglages',
        () async {
      // L'effacement préalable n'a de sens que si le payload a de quoi
      // reposer derrière. Une valeur tronquée / d'une autre forme ne doit
      // pas vider les réglages sans rien réécrire.
      for (final malformed in <dynamic>[
        <String, dynamic>{},
        'en-gb-x-gbd-local',
        42,
        <dynamic>[],
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          TtsService.coachVoiceKey('coach_07_marc', 'en'): 'reglage-machine',
          TtsService.userVoiceKey('en'): 'defaut-machine',
        });
        final prefs = await SharedPreferences.getInstance();
        await DiagnosticImportService(prefs)
            .apply(<String, dynamic>{'voice': malformed});

        expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'en')),
            'reglage-machine',
            reason: 'voice=$malformed : rien à reposer, donc rien à effacer.');
        expect(
            prefs.getString(TtsService.userVoiceKey('en')), 'defaut-machine');
      }
    });

    test('un ancien export sans section voice n\'y touche pas', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        TtsService.coachVoiceKey('coach_07_marc', 'en'):
            'reglage-de-la-machine',
        TtsService.userVoiceKey('en'): 'defaut-de-la-machine',
      });
      final prefs = await SharedPreferences.getInstance();
      await DiagnosticImportService(prefs).apply(<String, dynamic>{
        'schemaVersion': 1,
        'career': {'maxLevel': 3, 'completedSessions': 7},
      });

      expect(prefs.getInt('career.max_level'), 3, reason: 'import fonctionnel');
      expect(prefs.getString(TtsService.coachVoiceKey('coach_07_marc', 'en')),
          'reglage-de-la-machine',
          reason: 'Un payload qui ne parle pas de voix ne gère pas les voix.');
      expect(prefs.getString(TtsService.userVoiceKey('en')),
          'defaut-de-la-machine');
    });
  });
}
