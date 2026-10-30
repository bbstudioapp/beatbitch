import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/posture.dart';
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

  test(
      'après une régénération post-défi, aucun défi gardé ne tombe dans une '
      'pause reportée', () {
    // Même calcul que `_handlePostChallengeRegen` : durée restante sans les
    // pauses à venir, pauses et changements rebasés sur la fin du souffle.
    // Les horaires des défis restants gardent ceux de la séance d'origine.
    const postChallengeBreath = 10;
    var regens = 0;
    var closeCalls = 0;
    final collisions = <String>[];
    for (final minutes in [30, 45, 60, 75, 90]) {
      for (final count in [2, 3, 4]) {
        for (var seed = 0; seed < 100; seed++) {
          final pool = challengePool.take(count).toList();
          final s = CareerSessionGenerator(seed: seed)
              .generate(
                level: 14,
                bank: bank(),
                durationSeconds: minutes * 60,
                unlockedKeys: UnlockKey.values.toSet(),
                scriptedBreaks: true,
                challenge: ChallengeInputs(challenges: pool),
              )
              .session;
          final triggers = s.challengeTriggerTimes;
          if (triggers.length < 2) continue;
          final window = kChallengeBreathDurationSeconds +
              pool.first.nominalDurationSeconds;
          final breathEnd = triggers.first + postChallengeBreath;
          final unplayed =
              s.breaks.where((b) => b.time >= triggers.first + window);
          final carry = [
            for (final b in unplayed)
              ScriptedBreak(
                time: b.time - window - breathEnd,
                durationSeconds: b.durationSeconds,
                newPose: b.newPose,
                orders: b.orders,
              ),
          ];
          if (carry.isEmpty || carry.any((b) => b.time < 0)) continue;
          final pauseSeconds =
              unplayed.fold<int>(0, (a, b) => a + b.durationSeconds);
          final remaining =
              s.durationSeconds - window - breathEnd - pauseSeconds;
          final regen = CareerSessionGenerator(seed: seed + 1000)
              .generate(
                level: 14,
                bank: bank(),
                durationSeconds: remaining,
                carry: PostureScript(breaks: carry, changes: const []),
                unlockedKeys: UnlockKey.values.toSet(),
                scriptedBreaks: true,
              )
              .session;
          regens++;
          for (final b in regen.breaks) {
            final start = breathEnd + b.time;
            for (final t in triggers.skip(1)) {
              final trigger = t - window;
              if (trigger < start) continue;
              if (trigger - (start + b.durationSeconds) < 60) closeCalls++;
              if (trigger < start + b.durationSeconds) {
                collisions.add('${minutes}min ×$count défis seed=$seed : '
                    'pause [$start,${start + b.durationSeconds}) vs défi à $trigger');
              }
            }
          }
        }
      }
    }
    expect(regens, greaterThan(500),
        reason: 'le balayage doit régénérer des suites avec pauses reportées');
    expect(closeCalls, greaterThan(0),
        reason: 'aucune pause proche d\'un défi : le balayage ne mesure rien');
    expect(collisions, isEmpty);
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
      final breaks = withoutChallenges.breaks;
      expect(breaks, isNotEmpty);
      var pausesBefore = 0;
      for (var k = 0; k < breaks.length; k++) {
        // Sans spécialisation : une pause toutes les 7 min d'effort, posée à
        // la première frontière de bloc qui suit.
        expect(breaks[k].time - pausesBefore,
            inInclusiveRange((k + 1) * 420, (k + 1) * 420 + 150),
            reason: '$minutes min → pause n°${k + 1}');
        pausesBefore += breaks[k].durationSeconds;
      }
    }
  });
}
