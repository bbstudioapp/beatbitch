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
    expect(result.session.challengeTriggerTime, isNull);
  });

  test(
      'challenge inséré (Phase B streaming) : Session porte les méta + 1 step '
      'trigger ; le step défi n\'est plus pré-positionné', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 3,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      challenge: const ChallengeInputs(challenges: [_challengeHoldThroat]),
    );
    expect(result.challenge, _challengeHoldThroat);
    expect(result.session.challenge, _challengeHoldThroat);
    final triggerStart = result.session.challengeTriggerTime;
    expect(triggerStart, isNotNull);
    // Le step trigger (breath de countdown) est seul dans la timeline ; le
    // step défi sera émis en runtime par le ChallengeSegmentBuilder (Phase B).
    final triggerStep =
        result.session.steps.where((s) => s.time == triggerStart).toList();
    expect(triggerStep, hasLength(1));
    expect(triggerStep.first.mode, SessionMode.breath);
    expect(triggerStep.first.duration, kChallengeBreathDurationSeconds);
    // Aucun step matérialisé immédiatement après le trigger dans la fenêtre
    // réservée au défi (le builder l'émettra à chaud).
    final afterTrigger = triggerStart! + kChallengeBreathDurationSeconds;
    final reservedEnd =
        afterTrigger + _challengeHoldThroat.nominalDurationSeconds;
    final stepsInWindow = result.session.steps
        .where((s) => s.time >= afterTrigger && s.time < reservedEnd)
        .toList();
    expect(stepsInWindow, isEmpty);
  });

  test('insertion vers 60 % du temps planifié (± marge)', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 3,
      bank: _bank(),
      unlockedKeys: UnlockKey.values.toSet(),
      challenge: const ChallengeInputs(challenges: [_challengeHoldThroat]),
    );
    final breathStart = result.session.challengeTriggerTime!;
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
