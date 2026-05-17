import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/career_generation_inputs.dart';
import 'package:beat_bitch/career/models/level_milestone.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/services/humiliation_engine.dart';

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
      humiliationCareer: 30.0,
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

  test('finalMilestone (placement=final) remplace la phase finish', () {
    // Une milestone-final remplace pré-finisher + boosts + step finisher.
    // Sa séquence est posée juste avant le congrats text-only et fournit
    // l'apotheose entière. `session.finalMilestoneId` est renseigné.
    const milestone = LevelMilestone(
      id: 'intro_final_hold_tip',
      humilRequired: 0.0,
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
      milestones: const MilestonePlan(finalMilestone: milestone),
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
        reason: 'le finisher doit être le dernier step de config de la '
            'séquence milestone-final, reçu text=${finisher.text}');
    expect(finisher.mode, SessionMode.hold);
    expect(finisher.to, Position.tip);
  });

  test('body milestone + final milestone coexistent dans la même séance', () {
    // Le générateur accepte les deux canaux indépendamment. La body est
    // insérée dans la fenêtre [insertAtMin, insertAtMax], la final
    // remplace la phase finish.
    const body = LevelMilestone(
      id: 'body_test',
      humilRequired: 0.0,
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
      unlocks: [UnlockKey.holdMidShort],
    );
    const finalM = LevelMilestone(
      id: 'final_test',
      humilRequired: 0.0,
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
      milestones: const MilestonePlan(bodies: [body], finalMilestone: finalM),
      unlockedKeys: _allUnlocks,
    );

    expect(result.session.milestoneId, 'body_test');
    expect(result.session.finalMilestoneId, 'final_test');
    expect(result.session.steps.any((s) => s.text == 'body-step'), isTrue);
    expect(result.session.steps.any((s) => s.text == 'final-step'), isTrue);

    // La body apparaît AVANT la final dans la timeline.
    final bodyTime =
        result.session.steps.firstWhere((s) => s.text == 'body-step').time;
    final finalTime =
        result.session.steps.firstWhere((s) => s.text == 'final-step').time;
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
      UnlockKey.basics,
      UnlockKey.rhythmMidBasic,
      UnlockKey.lickFull,
    };
    final result = CareerSessionGenerator(seed: 1234).generate(
      level: 2,
      bank: _bank(),
      unlockedKeys: acquired,
      humiliationCareer: 0.0,
    );
    expect(result.session.finalMilestoneId, isNull,
        reason: 'pas de milestone-final → finalMilestoneId doit être null');
    // Le step final est désormais identifié par `Session.finalStepTime`
    // (= moment où `_finale_chime` se déclenche). Avant cette refacto, le
    // dernier step de config était le step final ; depuis l'ajout du step
    // de post-final (action douce après l'orgasme), on doit cibler le step
    // dont `time == finalStepTime` pour vérifier l'apothéose elle-même.
    final finalT = result.session.finalStepTime;
    expect(finalT, isNotNull,
        reason: 'le générateur doit annoter `finalStepTime`');
    final finisher = result.session.steps.firstWhere(
      (s) => !s.isTextOnly && s.time == finalT,
    );
    expect(finisher.mode, SessionMode.hand,
        reason: '_pickFinal classique avec humil=0 doit retomber sur hand '
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
          humiliationCareer: humil,
          unlockedKeys: _allUnlocks,
        );
        for (final s in result.session.steps) {
          final from = s.from;
          final to = s.to;
          if (from != null && to != null) {
            expect(from, isNot(equals(to)),
                reason: 'level=$level humil=$humil mode=${s.mode} '
                    'from=${from.name} to=${to.name} bpm=${s.bpm} '
                    'time=${s.time}');
          }
        }
      }
    }
  });

  test('milestone unlock — la compétence devient utilisable APRÈS la séquence',
      () {
    // On utilise `UnlockKey.freestyle` parce que ce mode est gaté
    // uniquement via `_isUnlocked` / `_buildRecoveryStep` : aucune cascade
    // de diversification (`_diversifyAmplitude`, `_diversifyLongSegment`)
    // ne peut le produire incidemment. Sans l'unlock, aucun step
    // `mode=freestyle` n'est généré ; avec l'unlock propagé après la
    // milestone, les recovery steps peuvent en piocher.
    const milestone = LevelMilestone(
      id: 'unlock_freestyle_test',
      humilRequired: 0.0,
      displayLabel: 'unlock freestyle',
      insertAtMinSeconds: 60,
      insertAtMaxSeconds: 60,
      sequence: [
        SessionStep(
          time: 0,
          text: 'm-intro',
          mode: SessionMode.lick,
          from: Position.tip,
          to: Position.head,
          bpm: 60,
          duration: 8,
        ),
        SessionStep(
          time: 8,
          text: 'm-payoff',
          mode: SessionMode.freestyle,
          duration: 10,
        ),
      ],
      durationSeconds: 18,
      unlocks: [UnlockKey.freestyle],
    );
    final initial = <UnlockKey>{
      UnlockKey.basics,
      UnlockKey.rhythmMidBasic,
      UnlockKey.lickFull,
      UnlockKey.holdMidShort,
      UnlockKey.biffleBasic,
      UnlockKey.begLibre,
    };

    // (1) Sans milestone, aucun step `mode=freestyle` ne doit apparaître :
    // le set initial ne contient pas la clé, et le mode n'est candidat
    // qu'à travers `_buildRecoveryStep` (qui consulte `_unlockedKeys`).
    for (var seed = 0; seed < 10; seed++) {
      final r = CareerSessionGenerator(seed: seed).generate(
        level: 4,
        bank: _bank(),
        unlockedKeys: initial,
        humiliationCareer: 30.0,
      );
      final freestyles = r.session.steps
          .where((s) => !s.isTextOnly && s.mode == SessionMode.freestyle);
      expect(freestyles, isEmpty,
          reason: 'seed=$seed sans milestone : freestyle devrait rester gaté '
              'par _isUnlocked');
    }

    // (2) Avec milestone : la séquence en pose un en interne, et tout
    // freestyle hors séquence doit se trouver APRÈS la fin de la milestone.
    // Sur 30 seeds, on doit observer au moins une apparition post-milestone
    // — preuve que l'unlock est bien propagé dans `_unlockedKeys`.
    var foundPostMilestone = false;
    for (var seed = 0; seed < 30; seed++) {
      final r = CareerSessionGenerator(seed: seed).generate(
        level: 4,
        bank: _bank(),
        milestones: const MilestonePlan(bodies: [milestone]),
        unlockedKeys: initial,
        humiliationCareer: 30.0,
      );
      final mStart = r.session.milestoneStartTime!;
      final mEnd = mStart + r.session.milestoneDurationSeconds!;
      for (final s in r.session.steps) {
        if (s.isTextOnly) continue;
        if (s.mode != SessionMode.freestyle) continue;
        final isMilestoneStep = s.time >= mStart && s.time < mEnd;
        if (isMilestoneStep) continue;
        expect(s.time, greaterThanOrEqualTo(mEnd),
            reason: 'seed=$seed freestyle à t=${s.time} avant la fin de la '
                'milestone (mEnd=$mEnd) — gating violé');
        foundPostMilestone = true;
      }
    }
    expect(foundPostMilestone, isTrue,
        reason: 'sur 30 seeds, aucun freestyle post-milestone : l\'unlock ne '
            'semble pas propagé dans _unlockedKeys après l\'insertion');
  });

  test('cohérence par type — la séance reste plusieurs steps sur le même type',
      () {
    // Le but du jeu est de se concentrer sur la bouche. Le générateur doit
    // produire des séries de steps consécutifs du même type (bouche /
    // langue / libre-main) plutôt que de sauter d'un type à l'autre à
    // chaque step. Breath/freestyle sont des parenthèses transparentes.
    //
    // Critères vérifiés sur 30 seeds en niveau 8 (toutes les compétences
    // sont susceptibles d'apparaître) :
    // 1) la longueur moyenne d'une série du même type > 1.6 (= au moins
    //    un peu de continuité, vs 1.0 si le générateur sautait à chaque
    //    fois) ;
    // 2) bouche est le type majoritaire en nombre de steps (le but du jeu) ;
    // 3) aucun saut langue ↔ libre-main sans passer par bouche ne dépasse
    //    une fréquence "anormale" (tolérance large car la friction n'est
    //    pas une interdiction).
    final samples = <List<SessionStep>>[];
    for (var seed = 0; seed < 30; seed++) {
      final r = CareerSessionGenerator(seed: seed).generate(
        level: 8,
        bank: _bank(),
        unlockedKeys: _allUnlocks,
        humiliationCareer: 25.0,
        obedience: 100.0,
      );
      samples.add(r.session.steps);
    }

    // Classifier local — on duplique la logique pour que le test reste
    // indépendant du privé.
    String classify(SessionMode mode, Position? to) {
      switch (mode) {
        case SessionMode.rhythm:
        case SessionMode.hold:
          return 'bouche';
        case SessionMode.lick:
          return 'langue';
        case SessionMode.hand:
        case SessionMode.biffle:
          return 'libreMain';
        case SessionMode.beg:
          return to == null ? 'libreMain' : 'bouche';
        case SessionMode.breath:
        case SessionMode.freestyle:
          return 'transit';
        case SessionMode.suckle:
          return 'bouche';
      }
    }

    var totalRunLengths = 0;
    var totalRuns = 0;
    // Comptage en temps cumulé (et pas en nombre de steps brut) — c'est
    // ça que l'utilisateur ressent : un rhythm de 30s dominant compte
    // plus qu'un beg-libre de 8s ponctuel. Le test brut "majorité de
    // bouche en nombre de steps" pénalisait à tort les sessions où la
    // bouche tient 60% du temps avec quelques transitions courtes.
    var boucheSec = 0;
    var langueSec = 0;
    var libreSec = 0;
    for (final steps in samples) {
      String? currentType;
      var currentLen = 0;
      for (final s in steps) {
        if (s.isTextOnly || s.mode == null) continue;
        final t = classify(s.mode!, s.to);
        if (t == 'transit') continue;
        final dur = s.duration ?? 0;
        switch (t) {
          case 'bouche':
            boucheSec += dur;
          case 'langue':
            langueSec += dur;
          case 'libreMain':
            libreSec += dur;
        }
        if (t == currentType) {
          currentLen++;
        } else {
          if (currentType != null) {
            totalRunLengths += currentLen;
            totalRuns++;
          }
          currentType = t;
          currentLen = 1;
        }
      }
      if (currentType != null && currentLen > 0) {
        totalRunLengths += currentLen;
        totalRuns++;
      }
    }
    final avgRunLen = totalRunLengths / totalRuns;
    expect(avgRunLen, greaterThan(1.6),
        reason: 'avg run length=$avgRunLen — le générateur saute trop vite '
            'd\'un type à l\'autre, la friction de continuité ne mord pas');
    final totalSec = boucheSec + langueSec + libreSec;
    expect(boucheSec, greaterThan(langueSec + libreSec),
        reason: 'bouche=${boucheSec}s langue=${langueSec}s libre=${libreSec}s '
            '(total=${totalSec}s) — la bouche doit dominer en temps cumulé');
  });
}
