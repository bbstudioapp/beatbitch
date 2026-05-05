import 'package:flutter_test/flutter_test.dart';
import 'package:rhythm_coach/career/models/level_milestone.dart';
import 'package:rhythm_coach/career/models/phrase_bank.dart';
import 'package:rhythm_coach/career/models/unlock_key.dart';
import 'package:rhythm_coach/career/services/career_session_generator.dart';
import 'package:rhythm_coach/models/session.dart';
import 'package:rhythm_coach/models/session_step.dart';
import 'package:rhythm_coach/services/humiliation_engine.dart';

PhraseBank _bank() {
  return PhraseBank(
    byMode: {
      for (final m in SessionMode.values)
        m: {
          'soft': ['s'],
          'medium': ['m'],
          'hard': ['h'],
          'finale': ['f'],
        },
    },
    congrats: ['bravo'],
    intros: ['intro'],
  );
}

/// Set d'unlocks « tout autorisé » : reproduit l'ancien comportement
/// hérité (set vide → fallback `_isUnlocked = true`) sans la branche
/// dangereuse qui ouvrait des actions non encore acquises en prod.
final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

void main() {
  test('generate(humiliation=0) — corps de session reste tempéré', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 1,
      bank: _bank(),
      unlockedKeys: _allUnlocks,
    );
    expect(result.session.steps, isNotEmpty);
    // À humiliation=0 sur niveau 1, la **médiane** des steps de config
    // doit rester ≤ 4 d'humiliation requise (corps modéré). Les boosts
    // et finisher peuvent dépasser, mais ils restent minoritaires.
    final required = result.session.steps
        .where((s) => !s.isTextOnly)
        .map((s) => HumiliationScale.requiredFor(
              mode: s.mode ?? SessionMode.rhythm,
              from: s.from,
              to: s.to,
              bpm: s.bpm,
              duration: s.duration,
            ))
        .toList()
      ..sort();
    final median = required[required.length ~/ 2];
    expect(median, lessThanOrEqualTo(4.0),
        reason: 'médiane $median trop élevée pour humiliation=0');
  });

  test('generate(humiliation=30) débloque des actions humiliantes', () {
    final gen = CareerSessionGenerator(seed: 42);
    final result = gen.generate(
      level: 10,
      bank: _bank(),
      humiliationScore: 30.0,
      unlockedKeys: _allUnlocks,
    );
    expect(result.session.steps, isNotEmpty);
    // À ce score on doit avoir au moins un step à humiliation requise ≥ 8
    // (= hold throat / rhythm head→full léger).
    final maxRequired = result.session.steps
        .where((s) => !s.isTextOnly)
        .map((s) => HumiliationScale.requiredFor(
              mode: s.mode ?? SessionMode.rhythm,
              from: s.from,
              to: s.to,
              bpm: s.bpm,
              duration: s.duration,
            ))
        .fold<double>(0.0, (a, b) => a > b ? a : b);
    expect(maxRequired, greaterThanOrEqualTo(8.0));
  });

  test('profil excitation reste dans [0, 100]', () {
    final gen = CareerSessionGenerator(seed: 7);
    final result = gen.generate(
      level: 5,
      bank: _bank(),
      unlockedKeys: _allUnlocks,
    );
    for (final v in result.excitationProfile) {
      expect(v, lessThanOrEqualTo(100.5));
      expect(v, greaterThanOrEqualTo(-0.5));
    }
  });

  test('finalMilestone (placement=final) remplace la phase finish', () {
    // Une milestone-final remplace pré-finisher + boosts + step finisher.
    // Sa séquence est posée juste avant le congrats text-only et fournit
    // l'apotheose entière. `session.finalMilestoneId` est renseigné.
    const milestone = LevelMilestone(
      id: 'intro_final_hold_tip',
      level: 2,
      displayLabel: 'test',
      placement: MilestonePlacement.finalApotheose,
      sequence: [
        SessionStep(
          time: 0,
          text: 'apotheose-1',
          mode: SessionMode.hold,
          to: Position.tip,
          duration: 8,
        ),
        SessionStep(
          time: 8,
          text: 'apotheose-2',
          mode: SessionMode.breath,
          duration: 4,
        ),
        SessionStep(
          time: 12,
          text: 'apotheose-3',
          mode: SessionMode.hold,
          to: Position.tip,
          duration: 10,
        ),
      ],
      durationSeconds: 22,
      unlocks: [UnlockKey.finalHoldTip],
    );
    final result = CareerSessionGenerator(seed: 1234).generate(
      level: 2,
      bank: _bank(),
      finalMilestone: milestone,
      unlockedKeys: _allUnlocks,
    );

    // 1) La session porte bien l'id de la milestone-final.
    expect(result.session.finalMilestoneId, 'intro_final_hold_tip');
    expect(result.session.finalMilestoneStartTime, isNotNull);
    expect(result.session.finalMilestoneDurationSeconds, 22);

    // 2) Les steps de la séquence sont bien dans la session, en fin.
    const apotheoseTexts = {'apotheose-1', 'apotheose-2', 'apotheose-3'};
    final apoSteps = result.session.steps
        .where((s) => apotheoseTexts.contains(s.text))
        .toList();
    expect(apoSteps.length, 3,
        reason: 'les 3 steps de la milestone-final doivent être insérés');

    // 3) Le dernier step de config est bien le dernier step de config de
    //    la séquence milestone (= hold tip 'apotheose-3'), preuve que
    //    `_pickFinal` n'a PAS été appelé.
    final configSteps =
        result.session.steps.where((s) => !s.isTextOnly).toList();
    final finisher = configSteps.last;
    expect(finisher.text, 'apotheose-3',
        reason:
            'le finisher doit être le dernier step de config de la '
            'séquence milestone-final, reçu text=${finisher.text}');
    expect(finisher.mode, SessionMode.hold);
    expect(finisher.to, Position.tip);
  });

  test('body milestone + final milestone coexistent dans la même séance',
      () {
    // Le générateur accepte les deux canaux indépendamment. La body est
    // insérée dans la fenêtre [insertAtMin, insertAtMax], la final
    // remplace la phase finish.
    const body = LevelMilestone(
      id: 'body_test',
      level: 2,
      displayLabel: 'body',
      sequence: [
        SessionStep(
          time: 0,
          text: 'body-step',
          mode: SessionMode.rhythm,
          from: Position.tip,
          to: Position.head,
          bpm: 80,
          duration: 10,
        ),
      ],
      durationSeconds: 10,
      unlocks: [UnlockKey.holdHeadShort],
    );
    const finalM = LevelMilestone(
      id: 'final_test',
      level: 2,
      displayLabel: 'final',
      placement: MilestonePlacement.finalApotheose,
      sequence: [
        SessionStep(
          time: 0,
          text: 'final-step',
          mode: SessionMode.hold,
          to: Position.tip,
          duration: 8,
        ),
      ],
      durationSeconds: 8,
      unlocks: [UnlockKey.finalHoldTip],
    );
    final result = CareerSessionGenerator(seed: 1234).generate(
      level: 2,
      bank: _bank(),
      milestone: body,
      finalMilestone: finalM,
      unlockedKeys: _allUnlocks,
    );

    expect(result.session.milestoneId, 'body_test');
    expect(result.session.finalMilestoneId, 'final_test');
    expect(result.session.steps.any((s) => s.text == 'body-step'), isTrue);
    expect(result.session.steps.any((s) => s.text == 'final-step'), isTrue);

    // La body apparaît AVANT la final dans la timeline.
    final bodyTime = result.session.steps
        .firstWhere((s) => s.text == 'body-step')
        .time;
    final finalTime = result.session.steps
        .firstWhere((s) => s.text == 'final-step')
        .time;
    expect(bodyTime, lessThan(finalTime),
        reason:
            'body-step (t=$bodyTime) doit précéder final-step (t=$finalTime)');
  });

  test('sans finalMilestone, _pickFinal classique est appelé', () {
    // Contre-épreuve : sans finalMilestone, le finisher est calculé par
    // `_pickFinal` (= comportement historique). À humil 0 + niveau 2,
    // sans finalXxx dans `unlockedKeys`, le candidat valide unique est
    // hand head→mid → c'est lui qui doit clore la séance.
    final acquired = <UnlockKey>{
      UnlockKey.handBasic,
      UnlockKey.lickTipBasic,
      UnlockKey.rhythmTipHead,
      UnlockKey.holdTip,
      UnlockKey.holdHead,
      UnlockKey.rhythmMidBasic,
      UnlockKey.lickFull,
    };
    final result = CareerSessionGenerator(seed: 1234).generate(
      level: 2,
      bank: _bank(),
      unlockedKeys: acquired,
      humiliationScore: 0.0,
    );
    expect(result.session.finalMilestoneId, isNull,
        reason: 'pas de milestone-final → finalMilestoneId doit être null');
    final configSteps =
        result.session.steps.where((s) => !s.isTextOnly).toList();
    final finisher = configSteps.last;
    expect(finisher.mode, SessionMode.hand,
        reason:
            '_pickFinal classique avec humil=0 doit retomber sur hand '
            'baseline, reçu ${finisher.mode}');
  });

  test('aucun step de config ne retourne from == to', () {
    // Règle transverse de design : `from` et `to` désignent toujours deux
    // zones différentes. Pas de stimulation sur place dans les modes
    // rythmés (rhythm/lick/biffle/hand) — sémantiquement, alterner entre
    // deux positions implique qu'elles sont distinctes. Modes hold/beg/
    // breath/freestyle utilisent `to=null` ou `from=null` donc hors check.
    //
    // On balaye plusieurs niveaux + 2 humil pour couvrir un large spectre
    // de cascades possibles dans `_enforceHumiliationRequired` et de
    // tirages dans `_diversifyLongSegment`.
    for (final level in [1, 3, 7, 12, 18]) {
      for (final humil in [0.0, 50.0]) {
        final gen = CareerSessionGenerator(seed: level * 100 + humil.toInt());
        final result = gen.generate(
          level: level,
          bank: _bank(),
          humiliationScore: humil,
          unlockedKeys: _allUnlocks,
        );
        for (final s in result.session.steps) {
          final from = s.from;
          final to = s.to;
          if (from != null && to != null) {
            expect(from, isNot(equals(to)),
                reason:
                    'level=$level humil=$humil mode=${s.mode} '
                    'from=${from.name} to=${to.name} bpm=${s.bpm} '
                    'time=${s.time}');
          }
        }
      }
    }
  });
}
