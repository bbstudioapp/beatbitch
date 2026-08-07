/// Rattrapage des profils déjà dérivés par la boucle des défis BPM.
///
/// Deux garanties symétriques :
///   - un profil **corrompu** chargé doit ressortir jouable ;
///   - un profil **sain** doit ressortir **inchangé**, à l'octet près — c'est
///     le test qui protège les gens qui n'ont rien.
///
/// Cf. `docs/analysis/2026-08-07-challenge-bpm-target-runaway.md` et
/// `challenge_bpm_target_runaway_test.dart` (les trois bornes du calcul).
library;

import 'dart:async';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/career/services/generation/bpm_pacing.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:beat_bitch/services/profile_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Le profil de la capture utilisateur : `rhythm.bpm_ceil.shallow` emballé
/// (cible affichée 956 ⇒ `comfort ≈ 735`), plancher d'humiliation carrière
/// écrasé par le même calcul quadratique.
Map<String, Object> _corruptedProfile() => <String, Object>{
      'cap.rhythm.bpm_ceil.shallow.best': 735.0,
      'cap.rhythm.bpm_ceil.shallow.comfort': 735.0,
      'cap.rhythm.bpm_ceil.shallow.sr': 0.99,
      'cap.rhythm.bpm_ceil.shallow.seen': 42,
      'stats.humiliation_level': 4166.4,
    };

/// Un profil avancé mais sain : rien au-dessus de la borne moteur.
Map<String, Object> _healthyProfile() => <String, Object>{
      'cap.rhythm.bpm_ceil.shallow.best': 168.0,
      'cap.rhythm.bpm_ceil.shallow.comfort': 152.0,
      'cap.rhythm.bpm_ceil.shallow.sr': 0.87,
      'cap.rhythm.bpm_ceil.shallow.seen': 31,
      'cap.rhythm.bpm_floor.shallow.best': 18.0,
      'cap.rhythm.bpm_floor.shallow.comfort': 18.0,
      'cap.rhythm.bpm_floor.shallow.sr': 0.7,
      'cap.hold.throat.streak.best': 26.0,
      'cap.hold.throat.streak.comfort': 22.0,
      // Score très élevé mais légitime : aucun axe ne prouve la dérive,
      // donc on n'y touche pas.
      'stats.humiliation_level': 512.0,
    };

Map<String, Object?> _dump(SharedPreferences prefs) => <String, Object?>{
      for (final k in prefs.getKeys()) k: prefs.get(k),
    };

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

/// Store persisté dont le canal se **fige** : les [stallAfter] premières
/// écritures aboutissent, la suivante retourne un `Future` qui ne se résout
/// jamais — exactement ce que fait un canal de plateforme bloqué, et ce
/// qu'aucun `try`/`catch` n'attrape.
class _StallingStore extends InMemorySharedPreferencesStore {
  _StallingStore.withData(super.data, {required this.stallAfter})
      : super.withData();

  final int stallAfter;
  int writes = 0;

  /// Rétablit le canal — pour rejouer la passe comme au lancement suivant.
  bool healed = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (!healed && writes++ >= stallAfter) return Completer<bool>().future;
    return super.setValue(valueType, key, value);
  }
}

/// Installe [store] comme persistance et vide le cache statique de
/// `SharedPreferences` pour que la prochaine résolution le relise.
Future<SharedPreferences> _prefsOn(SharedPreferencesStorePlatform store) async {
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

Map<String, Object> _persisted(Map<String, Object> values) => <String, Object>{
      for (final e in values.entries) 'flutter.${e.key}': e.value,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Profil corrompu — ressort jouable', () {
    test('`best` et `comfort` reviennent à la borne moteur', () async {
      final prefs = await _prefsWith(_corruptedProfile());
      final report = await ProfileReconciliation.applyTo(prefs);

      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.best'),
          BeepEngine.kMaxBpm.toDouble());
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort'),
          BeepEngine.kMaxBpm.toDouble());
      expect(report!.axes.keys, contains('rhythm.bpm_ceil.shallow'));
    });

    test('la bannière du défi suivant redevient jouable', () async {
      final prefs = await _prefsWith(_corruptedProfile());
      await ProfileReconciliation.applyTo(prefs);

      final target = ChallengeService.thresholdFor(
        ChallengeAxisKind.bpm,
        prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort')!,
        CapabilityAxis.rhythmBpmCeilShallow,
      );
      expect(target, lessThanOrEqualTo(BeepEngine.kMaxBpm));
    });

    test('le `successRate` gonflé par la boucle revient au neutre', () async {
      final prefs = await _prefsWith(_corruptedProfile());
      await ProfileReconciliation.applyTo(prefs);

      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.sr'),
          CapabilityService.defaultSuccessRate);
      // `lastSeenSession` n'est pas une valeur dérivée — l'horloge de decay
      // reste celle du vrai parcours.
      expect(prefs.getInt('cap.rhythm.bpm_ceil.shallow.seen'), 42);
    });

    test('le score d\'humiliation carrière est ramené sous le plafond',
        () async {
      final prefs = await _prefsWith(_corruptedProfile());
      final report = await ProfileReconciliation.applyTo(prefs);

      final after = prefs.getDouble('stats.humiliation_level')!;
      expect(after, ProfileReconciliation.careerHumiliationCeiling);
      expect(after, lessThan(300));
      expect(report!.humiliationBefore, 4166.4);
      expect(report.humiliationAfter, after);
    });

    test('le plafond domine les exigences du contenu', () {
      // Argument de non-régression fonctionnelle : ramener un profil dérivé
      // à ce plafond ne reverrouille rien. Le contenu le plus coûteux est le
      // `hold full` au cap de 80 s de `_pickFinal` — calculé ici plutôt que
      // recopié, pour que le test suive une éventuelle recalibration.
      final costliestFinal = HumiliationScale.requiredFor(
        mode: SessionMode.hold,
        to: Position.full,
        duration: 80,
      );
      expect(ProfileReconciliation.careerHumiliationCeiling,
          greaterThan(costliestFinal));
    });

    test('les six axes BPM `maximize` sont traités, pas seulement le rapporté',
        () async {
      // `throat`, `full`, les deux `crossings_pm` et `biffle.bpm_max`
      // partagent exactement le même chemin de code que l'axe rapporté.
      const derived = <CapabilityAxis>[
        CapabilityAxis.rhythmBpmCeilShallow,
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.rhythmBpmCeilFull,
        CapabilityAxis.gorgeCrossingsBpmThroat,
        CapabilityAxis.gorgeCrossingsBpmFull,
        CapabilityAxis.biffleBpmMax,
      ];
      final prefs = await _prefsWith(<String, Object>{
        for (final a in derived) ...<String, Object>{
          'cap.${a.storageKey}.best': 3182.0,
          'cap.${a.storageKey}.comfort': 3298.7,
          'cap.${a.storageKey}.sr': 0.99,
        },
      });
      final report = await ProfileReconciliation.applyTo(prefs);

      expect(
          report!.axes.keys.toSet(), derived.map((a) => a.storageKey).toSet());
      for (final a in derived) {
        expect(prefs.getDouble('cap.${a.storageKey}.comfort'),
            BeepEngine.kMaxBpm.toDouble(),
            reason: a.storageKey);
      }
    });

    test('un axe non-BPM emballé n\'est pas touché', () async {
      // La borne est une borne *de BPM* : elle n'a pas de sens sur une durée
      // (un hold de 400 s serait un exploit, pas une dérive).
      final prefs = await _prefsWith(<String, Object>{
        ...(_corruptedProfile()),
        'cap.hold.throat.streak.best': 400.0,
        'cap.hold.throat.streak.comfort': 400.0,
      });
      await ProfileReconciliation.applyTo(prefs);

      expect(prefs.getDouble('cap.hold.throat.streak.best'), 400.0);
      expect(prefs.getDouble('cap.hold.throat.streak.comfort'), 400.0);
    });
  });

  group('Profil sain — ressort inchangé', () {
    test('aucune clé du profil n\'est modifiée', () async {
      final prefs = await _prefsWith(_healthyProfile());
      final before = _dump(prefs);

      final report = await ProfileReconciliation.applyTo(prefs);

      expect(report!.isEmpty, isTrue);
      final after = _dump(prefs)
        ..remove(ProfileReconciliation.flagKey)
        ..remove(ProfileReconciliation.ranAtKey);
      expect(after, before);
      // Aucune trace de modification : il n'y a rien à raconter.
      expect(prefs.getString(ProfileReconciliation.reportKey), isNull);
    });

    test('un score d\'humiliation très haut mais non dérivé est préservé',
        () async {
      final prefs = await _prefsWith(_healthyProfile());
      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('stats.humiliation_level'), 512.0);
    });

    test('le plancher BPM à 18 n\'est pas remonté à kMinBpm', () async {
      // Pas de clamp par le bas : `kBpmFloorPractical` (18) est sous
      // `BeepEngine.kMinBpm` (20) et c'est légitime.
      final prefs = await _prefsWith(_healthyProfile());
      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('cap.rhythm.bpm_floor.shallow.best'), 18.0);
      expect(prefs.getDouble('cap.rhythm.bpm_floor.shallow.comfort'), 18.0);
    });

    test('un profil neuf ne crée aucune clé de capacité', () async {
      final prefs = await _prefsWith(const <String, Object>{});
      final report = await ProfileReconciliation.applyTo(prefs);

      expect(report!.isEmpty, isTrue);
      expect(prefs.getKeys().where((k) => k.startsWith('cap.')), isEmpty);
      expect(prefs.getDouble('stats.humiliation_level'), isNull);
    });
  });

  group('Idempotence et trace', () {
    test('la passe ne se rejoue pas au lancement suivant', () async {
      final prefs = await _prefsWith(_corruptedProfile());
      expect(await ProfileReconciliation.applyTo(prefs), isNotNull);

      // Une dérive volontaire réinjectée après coup ne doit PAS être
      // rattrapée : la passe v1 a déjà tourné, elle ne boucle pas.
      await prefs.setDouble('cap.rhythm.bpm_ceil.shallow.comfort', 900.0);
      expect(await ProfileReconciliation.applyTo(prefs), isNull);
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort'), 900.0);
    });

    test('la trace persistée dit ce qui a été modifié', () async {
      final prefs = await _prefsWith(_corruptedProfile());
      await ProfileReconciliation.applyTo(prefs);

      final stored = ProfileReconciliation.storedReport(prefs);
      final axis = stored!.axes['rhythm.bpm_ceil.shallow']!;
      expect(axis.comfortBefore, 735.0);
      expect(axis.comfortAfter, BeepEngine.kMaxBpm.toDouble());
      expect(axis.successRateBefore, 0.99);
      expect(axis.successRateAfter, CapabilityService.defaultSuccessRate);
      expect(stored.humiliationBefore, 4166.4);
      expect(prefs.getString(ProfileReconciliation.ranAtKey), isNotNull);
    });

    test('une trace illisible ne fait pas planter la lecture', () async {
      final prefs = await _prefsWith(<String, Object>{
        ProfileReconciliation.reportKey: 'pas du json',
      });
      expect(ProfileReconciliation.storedReport(prefs), isNull);
    });
  });

  group('Démarrage — rien ne doit empêcher l\'app de se lancer', () {
    // La passe est le deuxième appel de `main()`, avant le premier
    // `runApp`. Une exception ou une attente sans fin y coûterait le
    // lancement complet — strictement pire que le défaut qu'elle corrige.

    test('une clé d\'un type inattendu ne fait pas remonter d\'exception',
        () async {
      // `getDouble`/`getBool` castent directement la valeur en cache : sur
      // un type inattendu, ils jettent un `TypeError`.
      for (final corrupted in <Map<String, Object>>[
        <String, Object>{'cap.rhythm.bpm_ceil.shallow.best': 'pas un double'},
        <String, Object>{'stats.humiliation_level': 'pas un double'},
        <String, Object>{ProfileReconciliation.flagKey: 'pas un booléen'},
      ]) {
        final prefs = await _prefsWith(<String, Object>{
          ..._corruptedProfile(),
          ...corrupted,
        });
        await expectLater(ProfileReconciliation.applyTo(prefs), completes,
            reason: corrupted.keys.first);
      }
    });

    test('un axe illisible n\'empêche pas les autres d\'être réconciliés',
        () async {
      // Le filet de `runIfNeeded` avalerait l'exception, mais la passe
      // n'aurait rien fait : la tolérance doit être dans la lecture.
      final prefs = await _prefsWith(<String, Object>{
        'cap.rhythm.bpm_ceil.shallow.best': 'pas un double',
        'cap.rhythm.bpm_ceil.full.best': 3182.0,
        'cap.rhythm.bpm_ceil.full.comfort': 3298.7,
        'stats.humiliation_level': 4166.4,
      });
      final report = await ProfileReconciliation.applyTo(prefs);

      expect(report!.axes.keys, contains('rhythm.bpm_ceil.full'));
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.full.comfort'),
          BeepEngine.kMaxBpm.toDouble());
      expect(prefs.getDouble('stats.humiliation_level'),
          ProfileReconciliation.careerHumiliationCeiling);
    });

    test('un `comfort` stocké en entier est lu et corrigé', () async {
      // Un entier reste un nombre : le refuser laisserait la dérive en
      // place alors qu'on sait la lire.
      final prefs = await _prefsWith(<String, Object>{
        'cap.rhythm.bpm_ceil.shallow.comfort': 735,
      });
      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort'),
          BeepEngine.kMaxBpm.toDouble());
    });

    test('un drapeau de version illisible vaut « pas encore tourné »',
        () async {
      final prefs = await _prefsWith(<String, Object>{
        ..._corruptedProfile(),
        ProfileReconciliation.flagKey: 'pas un booléen',
      });
      expect(await ProfileReconciliation.applyTo(prefs), isNotNull);
      expect(prefs.getBool(ProfileReconciliation.flagKey), isTrue);
    });

    test('un canal figé rend la main, sans marquer la passe comme faite',
        () async {
      // On fige à la 4ᵉ écriture, en plein milieu de la correction d'axe.
      final store = _StallingStore.withData(
        _persisted(_corruptedProfile()),
        stallAfter: 3,
      );
      await _prefsOn(store);

      final elapsed = Stopwatch()..start();
      expect(await ProfileReconciliation.runIfNeeded(), isNull);
      expect(
          elapsed.elapsed, lessThan(ProfileReconciliation.startupBudget * 2));

      // Le drapeau n'a pas été posé : la passe se rejouera. Et la reprise
      // doit finir le travail — d'où l'ordre d'écriture, le thermomètre
      // avant les axes : ce sont les axes hors du jouable qui prouvent la
      // dérive, ils doivent être les derniers à disparaître.
      store.healed = true;
      final prefs = await _prefsOn(store);
      expect(prefs.getBool(ProfileReconciliation.flagKey), isNot(isTrue));

      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort'),
          BeepEngine.kMaxBpm.toDouble());
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.best'),
          BeepEngine.kMaxBpm.toDouble());
      expect(prefs.getDouble('stats.humiliation_level'),
          ProfileReconciliation.careerHumiliationCeiling);
      expect(prefs.getBool(ProfileReconciliation.flagKey), isTrue);
    });
  });

  group('Valeurs numériques dégénérées', () {
    test('un `best` NaN est corrigé, pas ignoré', () async {
      // `NaN > ceiling` vaut `false` en IEEE754 : la seule comparaison
      // laisserait la valeur en place *et* conclurait « aucune dérive ».
      final prefs = await _prefsWith(<String, Object>{
        'cap.rhythm.bpm_ceil.shallow.best': double.nan,
        'stats.humiliation_level': 4166.4,
      });
      final report = await ProfileReconciliation.applyTo(prefs);

      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.best'),
          BeepEngine.kMaxBpm.toDouble());
      expect(report!.axes.keys, contains('rhythm.bpm_ceil.shallow'));
      // La dérive est prouvée, donc le thermomètre est rattrapé aussi.
      expect(prefs.getDouble('stats.humiliation_level'),
          ProfileReconciliation.careerHumiliationCeiling);
    });

    test('un `comfort` infini est ramené à la borne moteur', () async {
      final prefs = await _prefsWith(<String, Object>{
        'cap.rhythm.bpm_ceil.shallow.comfort': double.infinity,
      });
      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('cap.rhythm.bpm_ceil.shallow.comfort'),
          BeepEngine.kMaxBpm.toDouble());
    });

    test('un score d\'humiliation NaN est ramené sous le plafond', () async {
      final prefs = await _prefsWith(<String, Object>{
        ..._corruptedProfile(),
        'stats.humiliation_level': double.nan,
      });
      await ProfileReconciliation.applyTo(prefs);
      expect(prefs.getDouble('stats.humiliation_level'),
          ProfileReconciliation.careerHumiliationCeiling);
    });

    test('la trace se sérialise et se relit malgré des valeurs non finies',
        () async {
      // `jsonEncode` jette sur NaN/Infinity — au démarrage, ça vaut un
      // crash. La trace doit rester écrivable, quitte à être incomplète.
      final prefs = await _prefsWith(<String, Object>{
        'cap.rhythm.bpm_ceil.shallow.best': double.nan,
        'cap.rhythm.bpm_ceil.shallow.comfort': double.infinity,
        'cap.rhythm.bpm_ceil.shallow.sr': double.negativeInfinity,
        'stats.humiliation_level': double.nan,
      });
      await ProfileReconciliation.applyTo(prefs);

      final stored = ProfileReconciliation.storedReport(prefs);
      final axis = stored!.axes['rhythm.bpm_ceil.shallow']!;
      // Le « avant » n'est pas représentable en JSON, le « après » l'est —
      // et c'est lui qui dit ce que vaut le profil maintenant.
      expect(axis.bestBefore, isNull);
      expect(axis.bestAfter, BeepEngine.kMaxBpm.toDouble());
      expect(axis.comfortAfter, BeepEngine.kMaxBpm.toDouble());
      expect(axis.successRateAfter, CapabilityService.defaultSuccessRate);
      expect(stored.humiliationAfter,
          ProfileReconciliation.careerHumiliationCeiling);
    });
  });

  group('Le plafond domine tout le contenu atteignable', () {
    // L'argument de non-régression du rattrapage est que ramener un profil
    // dérivé au plafond ne **reverrouille** rien. Ça ne tient que si le
    // plafond domine toute exigence que le contenu peut produire — ce que
    // rien ne garantit dans le code : `rhythm tip→balls` au BPM maximum
    // passe à 0,5 point près, par coïncidence de constantes. Une
    // recalibration d'un seul chiffre ou un 7ᵉ cran de profondeur ferait
    // basculer l'invariant en silence, et la passe se remettrait à
    // reverrouiller du contenu légitime.
    //
    // D'où un balayage exhaustif, calculé — jamais recopié.

    // Bornes dures du contenu. Le BPM vient des constantes de prod ; la
    // durée est le cap des holds finaux (`maxDur: 80` dans
    // `FinalPicker.trimHoldFinalDuration`, repris tel quel par le final du
    // mode « Utilise-moi »), le plus long que le générateur puisse émettre.
    const maxContentSeconds = 80;
    const reachableBpm = <int?>[
      null,
      BeepEngine.kMaxBpm,
      BpmPacing.kUseMeBpmPeak,
    ];

    Iterable<({String label, double required})> reachable() sync* {
      const positions = <Position?>[null, ...Position.values];
      const durations = <int?>[null, 1, maxContentSeconds];
      const tiers = <PhraseTier?>[null, ...PhraseTier.values];
      for (final mode in SessionMode.values) {
        for (final from in positions) {
          for (final to in positions) {
            for (final bpm in reachableBpm) {
              for (final duration in durations) {
                for (final tier in tiers) {
                  yield (
                    label: '$mode from=$from to=$to bpm=$bpm '
                        'dur=$duration tier=$tier',
                    required: HumiliationScale.requiredFor(
                      mode: mode,
                      from: from,
                      to: to,
                      bpm: bpm,
                      duration: duration,
                      phraseTier: tier,
                    ),
                  );
                }
              }
            }
          }
        }
      }
    }

    test('aucune action jouable n\'exige plus que le plafond', () {
      final ceiling = ProfileReconciliation.careerHumiliationCeiling;
      final worst =
          reachable().reduce((a, b) => b.required > a.required ? b : a);
      expect(worst.required, lessThanOrEqualTo(ceiling),
          reason: 'Le plafond de réconciliation ne domine plus le contenu : '
              '${worst.label} exige ${worst.required} pour un plafond de '
              '$ceiling. Un profil rattrapé perdrait l\'accès à du contenu '
              'légitimement débloqué — relever `careerHumiliationCeiling` '
              'ou revoir la recalibration qui a fait basculer ça.');
    });

    test('les amplitudes de rythme, `balls` comprise, tiennent sous le plafond',
        () {
      final ceiling = ProfileReconciliation.careerHumiliationCeiling;
      for (final from in Position.values) {
        for (final to in Position.values) {
          final req = HumiliationScale.requiredFor(
            mode: SessionMode.rhythm,
            from: from,
            to: to,
            bpm: BeepEngine.kMaxBpm,
          );
          expect(req, lessThanOrEqualTo(ceiling), reason: '$from→$to');
        }
      }
      // `tip→balls` est le cas serré : il passe uniquement parce que le
      // score de profondeur de `balls` est sous celui de `full`, ce qui
      // compense le cran d'amplitude en plus. Rien ne le garantit.
      final tipToBalls = HumiliationScale.requiredFor(
        mode: SessionMode.rhythm,
        from: Position.tip,
        to: Position.balls,
        bpm: BeepEngine.kMaxBpm,
      );
      expect(ceiling - tipToBalls, lessThan(1.0),
          reason: 'La marge de `tip→balls` s\'est élargie : le tuning des '
              'scores de profondeur a bougé, ce test mérite d\'être relu.');
    });

    test('le biffle au BPM maximum tient sous le plafond', () {
      expect(
        HumiliationScale.requiredFor(
          mode: SessionMode.biffle,
          bpm: BeepEngine.kMaxBpm,
        ),
        lessThanOrEqualTo(ProfileReconciliation.careerHumiliationCeiling),
      );
    });

    test('les bornes dures du mode « Utilise-moi » tiennent sous le plafond',
        () {
      // Le mode le plus agressif du jeu : il court-circuite volontairement
      // l'enveloppe de capacité (profondeur et BPM assumés). Ce qui le
      // borne, ce sont ces trois constantes.
      final ceiling = ProfileReconciliation.careerHumiliationCeiling;
      expect(BpmPacing.kUseMeBpmPeak, lessThanOrEqualTo(BeepEngine.kMaxBpm),
          reason: 'Le pic « Utilise-moi » est sorti de la plage moteur.');
      expect(
        HumiliationScale.requiredFor(
          mode: SessionMode.rhythm,
          from: Position.throat,
          to: Position.full,
          bpm: BpmPacing.kUseMeBpmPeak,
        ),
        lessThanOrEqualTo(ceiling),
      );
      expect(
        HumiliationScale.requiredFor(
          mode: SessionMode.hold,
          to: Position.full,
          duration: maxContentSeconds,
        ),
        lessThanOrEqualTo(ceiling),
      );
    });
  });
}
