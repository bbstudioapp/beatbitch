import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pauses scénarisées et défis intra-séance partagent la même séance
/// (issue #77) — les deux sont actifs par défaut.
///
/// Leurs horaires étaient calculés par deux fonctions indépendantes qui
/// visaient toutes deux le milieu de la séance : le trou d'effort de la pause
/// avalait le trigger du défi, que la boucle de génération réémettait à
/// `break.endTime`. La joueuse recevait alors l'ordre de changer de position
/// et l'annonce du défi au même instant — deux bandeaux, deux consignes.
///
/// Le planificateur de pauses connaît désormais les créneaux de défi et cède
/// le passage (les horaires de défi, eux, ne bougent pas).
void main() {
  List<PhraseEntry> phrases(List<String> t) =>
      t.map((s) => PhraseEntry(text: s)).toList();

  PhraseBank bank() => PhraseBank(
        byMode: {
          for (final m in SessionMode.values)
            m: {
              'soft': phrases(['s']),
              'medium': phrases(['m']),
              'hard': phrases(['h']),
              'finale': phrases(['f']),
              'attempt': phrases(['a']),
              'extension': phrases(['e']),
              'fail': phrases(['fa']),
              'stop': phrases(['st']),
              'success': phrases(['su']),
              'skip': phrases(['sk']),
            },
        },
        congrats: phrases(['bravo']),
        intros: phrases(['intro']),
      );

  const challengePool = [
    Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 10,
      mode: SessionMode.hold,
    ),
    Challenge(
      axis: CapabilityAxis.gorgeApneeStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 8,
      mode: SessionMode.hold,
    ),
    Challenge(
      axis: CapabilityAxis.biffleStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 12,
      mode: SessionMode.biffle,
    ),
    Challenge(
      axis: CapabilityAxis.rhythmMotionStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 15,
      mode: SessionMode.rhythm,
    ),
  ];

  test(
      'aucun trigger de défi ne tombe dans la fenêtre de mise en place d\'une '
      'pause, sur tout le domaine où les deux coexistent', () {
    // Countdown du breath de défi, dupliqué : la constante est privée au
    // générateur. La fenêtre à risque va du début de la pause à la fin de son
    // ordre de posture.
    const challengeBreathSeconds = 13;
    final collisions = <String>[];
    var generatedWithBoth = 0;

    for (final minutes in [28, 32, 40, 45, 50, 60, 75, 90]) {
      for (final challengeCount in [1, 2, 3, 4]) {
        for (var seed = 0; seed < 60; seed++) {
          final session = CareerSessionGenerator(seed: seed)
              .generate(
                level: 14,
                bank: bank(),
                durationSeconds: minutes * 60,
                unlockedKeys: UnlockKey.values.toSet(),
                scriptedBreaks: true,
                challenge: ChallengeInputs(
                  challenges: challengePool.take(challengeCount).toList(),
                ),
              )
              .session;
          if (session.breaks.isEmpty || session.challengeTriggerTimes.isEmpty) {
            continue;
          }
          generatedWithBoth++;
          for (final b in session.breaks) {
            // Pas d'ordre de posture, pas de mise en place à attendre.
            if (b.newPose == null) continue;
            for (final t in session.challengeTriggerTimes) {
              if (t >= b.time && t < b.endTime + challengeBreathSeconds) {
                collisions.add('${minutes}min ×$challengeCount défis seed=$seed'
                    ' : pause [${b.time},${b.endTime}) vs trigger $t');
              }
            }
          }
        }
      }
    }

    expect(generatedWithBoth, greaterThan(0),
        reason: 'sans séance portant les deux, le balayage ne teste rien');
    expect(collisions, isEmpty,
        reason: 'les deux plannings se connaissent : la pause cède le passage');
  });

  test('sans défi, les pauses gardent leurs horaires nominaux', () {
    // Le décalage ne doit s'appliquer qu'en présence d'un créneau occupé —
    // sinon il déplacerait les pauses de toutes les séances sans défi.
    for (final minutes in [28, 45, 60]) {
      final withoutChallenges = CareerSessionGenerator(seed: 7)
          .generate(
            level: 14,
            bank: bank(),
            durationSeconds: minutes * 60,
            unlockedKeys: UnlockKey.values.toSet(),
            scriptedBreaks: true,
          )
          .session;
      final expectedCount = minutes >= 45 ? 2 : 1;
      expect(withoutChallenges.breaks.length, expectedCount,
          reason: '$minutes min → $expectedCount pause(s)');
    }
  });
}
