import 'dart:math';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:beat_bitch/career/services/challenge_service.dart';
import 'package:beat_bitch/career/services/generation/capability_clamps.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La durée d'un défi reste proportionnée au format choisi.
///
/// L'ampleur d'un défi « durée » vaut `comfort × kChallengeOverloadFactor` et
/// `comfort` ne fait que monter avec la pratique. C'était le seul des trois
/// types de seuil sans borne — la vitesse est bornée par le BPM maximum du
/// moteur, la profondeur par le nombre de crans. Sur le profil du retour
/// utilisateur 0.6.1 (`comfort = 353`), une Bâclée annoncée 6 minutes en
/// durait déjà 15 ; à `comfort = 3000`, 73.
///
/// La garantie tient en une phrase, exprimée par le format lui-même : **tous
/// les défis qu'un palier peut demander n'ajoutent jamais plus que la part
/// [kChallengesShareOfFormat] de la durée annoncée.**
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // Paliers réels, hors `aleatoire` (méta-choix résolu en amont par
  // `resolveAleatoireIfNeeded`, ses champs sont des sentinelles).
  const formats = [
    SessionLengthChoice.bachee,
    SessionLengthChoice.courte,
    SessionLengthChoice.moyenne,
    SessionLengthChoice.longue,
  ];

  // Dérivés, pas listés : un axe durée ajouté demain est couvert d'office.
  final durationAxes = CapabilityClamps.overloadableAxes
      .where((a) => a.unit == CapabilityUnit.seconds)
      .toList();

  group(
      'les défis d\'une séance tiennent dans la part que le format leur '
      'concède', () {
    for (final format in formats) {
      for (final axis in durationAxes) {
        test('${format.name} / ${axis.storageKey}', () async {
          final challenge = await ChallengeService().buildForSession(
            profile: _trainedOn(axis),
            ceilings: const {},
            excludeAxes: _allOverloadableExcept(axis),
            rng: Random(0),
            isTutorial: false,
            maxChallengeDurationSeconds: format.maxChallengeDurationSeconds,
          );

          expect(challenge?.axis, axis,
              reason: "le tirage doit tomber sur l'axe testé");
          final worstCase =
              format.targetChallengesFor(0) * challenge!.nominalDurationSeconds;
          final concede =
              (format.durationSeconds * kChallengesShareOfFormat).round();
          expect(
            worstCase,
            lessThanOrEqualTo(concede),
            reason: 'un palier « ${format.name} » annonce '
                '${format.durationSeconds} s et peut demander '
                '${format.targetChallengesFor(0)} défi(s) de '
                '${challenge.nominalDurationSeconds} s : $worstCase s de défis '
                'pour $concede s concédées',
          );
        });
      }
    }
  });

  test('le plafond ne tronque aucun défi de découverte', () {
    // Garde anti-sur-correction : un plafond réglé trop bas viderait les
    // défis de leur sens. Le plus petit des paliers doit laisser passer
    // intacts le tutoriel et tous les défis exploratoires.
    final smallest = SessionLengthChoice.bachee.maxChallengeDurationSeconds;
    expect(kChallengeTutorialDurationSeconds, lessThanOrEqualTo(smallest));
    for (final axis in durationAxes) {
      expect(Challenge.initialEstimateSecondsForAxis(axis),
          lessThanOrEqualTo(smallest),
          reason: "le défi exploratoire de ${axis.storageKey} ne doit pas "
              'être tronqué sur le plus court des formats');
    }
  });

  test('le plafond s\'élargit avec le format', () {
    // Sur les formats longs, un gros défi est précisément ce qu'on veut :
    // le plafond ne doit jamais se resserrer quand la séance s'allonge.
    for (var i = 1; i < formats.length; i++) {
      expect(formats[i].maxChallengeDurationSeconds,
          greaterThanOrEqualTo(formats[i - 1].maxChallengeDurationSeconds));
    }
    expect(SessionLengthChoice.longue.maxChallengeDurationSeconds,
        greaterThan(SessionLengthChoice.bachee.maxChallengeDurationSeconds));
  });

  test('un défi plafonné ne fabrique ni record ni recalibrage', () async {
    // L'ampleur d'un défi sert aussi de cible mesurée au profil : tronquer
    // la cible tronque la valeur créditée. Elle passe alors **sous** le
    // comfort, où la régulation est neutre — ni `best` (ratchet monotone) ni
    // `comfort` ne bougent. La mesure n'est pas faussée, elle est absente ;
    // la voie « JE TIENS ENCORE » reste ouverte pour la reprendre.
    const axis = CapabilityAxis.holdThroatStreak;
    final challenge = await ChallengeService().buildForSession(
      profile: _trainedOn(axis),
      ceilings: const {},
      excludeAxes: _allOverloadableExcept(axis),
      rng: Random(0),
      isTutorial: false,
      maxChallengeDurationSeconds:
          SessionLengthChoice.bachee.maxChallengeDurationSeconds,
    );
    expect(challenge!.targetThreshold,
        SessionLengthChoice.bachee.maxChallengeDurationSeconds,
        reason: 'le seuil doit bien avoir été tronqué pour que le test porte');

    const before = CapabilityAxisState(
      best: _trainedComfort,
      comfort: _trainedComfort,
      successRate: 0.9,
      lastSeenSession: 1,
    );
    final after = CapabilityRegulator.regulate(
      axis: axis,
      prev: before,
      reached: challengeReachedValue(challenge, extensionsCount: 0),
      sessionIndex: 2,
    );

    expect(after.best, before.best, reason: 'record intact');
    expect(after.comfort, before.comfort, reason: 'cible intacte');
    expect(after.successRate, before.successRate, reason: 'confiance intacte');
  });
}

/// `comfort` volontairement hors de portée de tout format : c'est le régime
/// où l'absence de borne se voyait (défi de 65 minutes).
const double _trainedComfort = 3000.0;

CapabilityProfile _trainedOn(CapabilityAxis axis) => CapabilityProfile({
      axis: const CapabilityAxisState(
        best: _trainedComfort,
        comfort: _trainedComfort,
        successRate: 0.9,
        lastSeenSession: 1,
      ),
      // Profondeur prouvée : sans elle, le gating profondeur écarte les axes
      // qui visent throat/full et le tirage retombe ailleurs.
      CapabilityAxis.rhythmDepthMax: const CapabilityAxisState(
        best: 4.0,
        comfort: 4.0,
        successRate: 0.9,
        lastSeenSession: 2,
      ),
    });

/// Ne laisse qu'un seul axe candidat au tirage — le test porte sur l'ampleur
/// du défi, pas sur le choix de l'axe.
Set<CapabilityAxis> _allOverloadableExcept(CapabilityAxis axis) =>
    {...CapabilityClamps.overloadableAxes}..remove(axis);
