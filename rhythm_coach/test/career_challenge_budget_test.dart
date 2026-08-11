import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Non-régression du retour utilisateur 0.6.1 : « j'ai pris une séance de
/// 25 min avec 3 défis, elle a duré 30-35 min et l'écran de fin affiche
/// 15 min 59 ».
///
/// Le générateur réserve après chaque trigger de défi une enveloppe
/// `kChallengeBreathDurationSeconds + nominalDurationSeconds` : le défi est
/// joué là, donc aucun contenu n'y est posé. Cette enveloppe était prise sur
/// la durée demandée, et le runtime la retirait *encore* de la durée de séance
/// (`SessionController._excisChallengeFromSession`) — la joueuse la payait
/// deux fois. Avec les 3 défis du retour (dont un d'endurance à 530 s), une
/// séance « Moyenne » (1500 s) ne rendait plus que ~980 s de contenu.
void main() {
  // Le trio du retour utilisateur : un défi d'endurance long (le « 530 second
  // continuous play challenge ») et deux défis courts.
  const challenges = [
    Challenge(
      axis: CapabilityAxis.rhythmMotionStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 530,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 60,
      comfortAtCalibration: 353,
    ),
    Challenge(
      axis: CapabilityAxis.holdThroatStreak,
      kind: ChallengeAxisKind.duration,
      targetThreshold: 25,
      mode: SessionMode.hold,
      from: Position.throat,
      to: Position.throat,
      comfortAtCalibration: 17,
    ),
    Challenge(
      axis: CapabilityAxis.rhythmBpmCeilThroat,
      kind: ChallengeAxisKind.bpm,
      targetThreshold: 120,
      mode: SessionMode.rhythm,
      from: Position.head,
      to: Position.throat,
      bpm: 80,
      bpmEnd: 120,
      comfortAtCalibration: 80,
    ),
  ];

  /// Fenêtre que le runtime excise pour un défi joué — même formule des deux
  /// côtés : réservation dans `generate`, retrait dans
  /// `_excisChallengeFromSession`.
  int excisedFor(Challenge ch) =>
      kChallengeBreathDurationSeconds + ch.nominalDurationSeconds;

  for (final seed in [1, 7, 42]) {
    test('seed $seed : une séance « Moyenne » à 3 défis garde son contenu', () {
      const demanded = 1500; // SessionLengthChoice.moyenne
      final withChallenges = CareerSessionGenerator(seed: seed).generate(
        level: 8,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        lengthChoice: SessionLengthChoice.moyenne,
        sessionsCompleted: 40,
        challenge: const ChallengeInputs(challenges: challenges),
      );
      final without = CareerSessionGenerator(seed: seed).generate(
        level: 8,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        lengthChoice: SessionLengthChoice.moyenne,
        sessionsCompleted: 40,
      );

      expect(withChallenges.session.challenges, hasLength(3),
          reason: 'les 3 défis doivent tenir dans la séance');
      // Ce que la joueuse joue vraiment : la durée générée moins les fenêtres
      // que le runtime excisera au fil des défis.
      final playable = withChallenges.session.durationSeconds -
          withChallenges.session.challenges
              .map(excisedFor)
              .fold<int>(0, (a, b) => a + b);

      expect(playable, greaterThanOrEqualTo((demanded * 0.9).round()),
          reason: 'séance de $demanded s demandée, $playable s de contenu '
              'rendu : les fenêtres de défi ont été prises sur le contenu');
      // Et ce contenu vaut celui d'une séance sans défi : le défi ne prend
      // rien à la séance, il s'y ajoute.
      expect(
          playable, closeTo(without.session.durationSeconds, demanded * 0.15),
          reason: 'contenu à défis $playable s vs sans défi '
              '${without.session.durationSeconds} s');
    });
  }
}

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();
