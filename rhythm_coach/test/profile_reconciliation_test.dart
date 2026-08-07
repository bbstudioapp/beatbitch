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

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';
import 'package:beat_bitch/services/profile_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
