import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:flutter_test/flutter_test.dart';

List<PhraseEntry> _p(List<String> t) =>
    t.map((s) => PhraseEntry(text: s)).toList();

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

/// Réplique de la milestone `intro_posture_kneeling` (assets/career/
/// milestones.json) : 1er step `awaitReady`, reste en rythme + breath.
LevelMilestone _kneelingMilestone() => const LevelMilestone(
      id: 'intro_posture_kneeling',
      humilRequired: 0,
      displayLabel: 'À genoux',
      durationSeconds: 72,
      unlocks: [UnlockKey.postureKneeling],
      sequence: [
        SessionStep(
          time: 0,
          text: 'Mets-toi à genoux.',
          mode: SessionMode.breath,
          duration: 8,
          awaitReady: true,
        ),
        SessionStep(
          time: 8,
          text: 'À genoux devant moi.',
          mode: SessionMode.rhythm,
          from: Position.tip,
          to: Position.mid,
          bpm: 90,
          duration: 16,
        ),
      ],
    );

void main() {
  test(
      'milestone posture → session.milestoneId + fenêtre couvrent le step awaitReady',
      () {
    final gen = CareerSessionGenerator(seed: 7);
    final result = gen.generate(
      level: 6,
      bank: _bank(),
      durationSeconds: 12 * 60,
      unlockedKeys: {
        UnlockKey.postureSitting,
        UnlockKey.postureKneeling,
      },
      scriptedBreaks: true,
      milestones: MilestonePlan(bodies: [_kneelingMilestone()]),
    );
    final s = result.session;

    // La milestone posture doit être exposée comme milestone body de la
    // séance — sinon `currentMilestoneIdInWindow` ne la voit jamais.
    expect(s.milestoneId, 'intro_posture_kneeling');
    expect(s.milestoneStartTime, isNotNull);
    expect(s.milestoneDurationSeconds, isNotNull);

    // Le step `awaitReady` (gate « je suis en place ») doit tomber DANS la
    // fenêtre milestone — c'est ce que lit `_updateMilestonePose`.
    final start = s.milestoneStartTime!;
    final end = start + s.milestoneDurationSeconds!;
    final awaitStep =
        s.steps.firstWhere((st) => st.awaitReady, orElse: () => s.steps.first);
    expect(awaitStep.awaitReady, isTrue,
        reason: 'aucun step awaitReady dans la session générée');
    expect(awaitStep.time, greaterThanOrEqualTo(start));
    expect(awaitStep.time, lessThan(end));
  });

  test('id de milestone posture → Posture (mapping du contrôleur)', () {
    // Réplique de `_postureForMilestoneId` : prefix + fromString.
    Posture? poseFor(String id) {
      const prefix = 'intro_posture_';
      if (!id.startsWith(prefix)) return null;
      final p = Posture.fromString(id.substring(prefix.length));
      return p == Posture.free ? null : p;
    }

    expect(poseFor('intro_posture_kneeling'), Posture.kneeling);
    expect(poseFor('intro_posture_all_fours'), Posture.allFours);
    expect(poseFor('intro_posture_on_back'), Posture.onBack);
    expect(poseFor('intro_basics'), isNull);
  });
}
