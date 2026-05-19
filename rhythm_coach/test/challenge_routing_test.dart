import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() {
  return PhraseBank(
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
}

const Challenge _challengeHoldThroat = Challenge(
  axis: CapabilityAxis.holdThroatStreak,
  kind: ChallengeAxisKind.duration,
  targetThreshold: 15,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  comfortAtCalibration: 10.0,
);

void main() {
  test('challenge=none → session.challenge null, pas de step défi inséré', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 3,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
    );
    expect(result.challenge, isNull);
    expect(result.session.challenge, isNull);
    expect(result.session.challengeBreathStartTime, isNull);
    expect(result.session.challengeStepTime, isNull);
  });

  test('challenge inséré : Session porte les méta + 2 steps consécutifs', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 3,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      challenge: const ChallengeInputs(challenge: _challengeHoldThroat),
    );
    expect(result.challenge, _challengeHoldThroat);
    expect(result.session.challenge, _challengeHoldThroat);
    final breathStart = result.session.challengeBreathStartTime;
    final stepStart = result.session.challengeStepTime;
    expect(breathStart, isNotNull);
    expect(stepStart, isNotNull);
    // Le step défi commence pile après le breath countdown (13 s).
    expect(stepStart, breathStart! + kChallengeBreathDurationSeconds);
    // Les 2 steps existent dans la timeline.
    final breathStep =
        result.session.steps.where((s) => s.time == breathStart).toList();
    final challengeStep =
        result.session.steps.where((s) => s.time == stepStart).toList();
    expect(breathStep, hasLength(1));
    expect(breathStep.first.mode, SessionMode.breath);
    expect(breathStep.first.duration, kChallengeBreathDurationSeconds);
    expect(challengeStep, hasLength(1));
    expect(challengeStep.first.mode, SessionMode.hold);
    expect(challengeStep.first.from, Position.throat);
    expect(challengeStep.first.duration, 15);
  });

  test('insertion vers 60 % du temps planifié (± marge)', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 3,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      challenge: const ChallengeInputs(challenge: _challengeHoldThroat),
    );
    final breathStart = result.session.challengeBreathStartTime!;
    final total = result.session.durationSeconds;
    final ratio = breathStart / total;
    // Le scheduler insère au premier tick où `ctx.time >= 60% × genUntil`.
    // Sur le ratio absolu `breathStart / total`, le numérateur est ~60 %
    // de `genUntil` (= durée moins finish budget) ; le dénominateur est
    // `ctx.time + 2` qui inclut tout le post-insertion + finish phase.
    // La fenêtre observée est donc 0.40-0.85.
    expect(ratio, greaterThan(0.40));
    expect(ratio, lessThan(0.90));
  });

  test(
      'quickie : le caller n\'envoie pas de challenge (passe none) — '
      'la session reste sans défi', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 9,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      quickie: true,
      // Convention CareerScreen : quickie ⇒ ChallengeInputs.none.
    );
    expect(result.session.challenge, isNull);
  });
}
