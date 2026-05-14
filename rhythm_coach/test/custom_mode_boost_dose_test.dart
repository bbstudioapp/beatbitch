import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/career_session_generator.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';

/// Garde-fou issue #68 : en Custom Extrême avec hand=rare et rhythm=frequent,
/// le sprint final (boosts pre-final) ne devait pas systématiquement utiliser
/// la main. La proba carrière baseline (25 % de hand) ignorait les doses
/// utilisateur, qui ne servaient qu'à exclure les modes (poids 0). Désormais
/// le `preferHand` est composé avec le ratio handWeight/(handWeight+rhythmWeight)
/// → avec hand=0.4 (rare) et rhythm=2.2 (frequent), la proba effective tombe
/// à ~7.7 %.

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
          'boost': _p(['b']),
          'finale': _p(['f']),
          'fake_breath': _p(['ssh']),
        },
    },
    congrats: _p(['bravo']),
    intros: _p(['intro']),
  );
}

/// Doses telles que `CustomSessionConfig.resolveCoachModeWeights` les pose
/// (`none=0.0, rare=0.4, normal=1.0, frequent=2.2`). Modes non listés = normal.
Map<SessionMode, double> _doses(Map<SessionMode, double> overrides) => {
      for (final m in SessionMode.values) m: overrides[m] ?? 1.0,
    };

/// Récupère les steps de boost = ceux dont le `time` tombe **après**
/// `silentFinishStartTime` (= début de la phase finish, posée par le
/// générateur), à l'exclusion du step final lui-même.
List<SessionStep> _boostSteps(Session s) {
  final finishStart = s.silentFinishStartTime;
  final finalTime = s.finalStepTime;
  expect(finishStart, isNotNull,
      reason: 'le générateur doit annoter `silentFinishStartTime`');
  return s.steps
      .where((step) =>
          !step.isTextOnly &&
          step.time >= finishStart! &&
          step.time != finalTime)
      .toList();
}

void main() {
  group('Custom Extrême — boosts respectent la dose hand', () {
    // Reproduit le scénario de l'issue #68 : maxDepth=full, hold/rhythm
    // frequent, hand rare. Sur un échantillon de seeds, la part de boosts
    // en mode `hand` doit rester nettement minoritaire (< 20 %, vs. 25 %
    // sans le fix — qui tombait souvent sur hand pur).
    test('hand=rare + rhythm=frequent : <20 % des boosts utilisent hand', () {
      var handBoosts = 0;
      var totalBoosts = 0;
      for (final seed in [1, 2, 3, 7, 11, 13, 17, 23, 42, 99, 314, 1234]) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 18, // CustomDifficulty.extreme
          bank: _bank(),
          durationSeconds: 12 * 60,
          unlockedKeys: const {}, // mode hérité Custom
          humiliationCareer: 400.0,
          obedience: 100.0,
          intensityFloorOverride: 0.45,
          coachModeWeights: _doses({
            SessionMode.hand: 0.4, // rare
            SessionMode.rhythm: 2.2, // frequent
            SessionMode.hold: 2.2, // frequent (≈ scénario issue)
          }),
        );
        final boosts = _boostSteps(result.session);
        totalBoosts += boosts.length;
        handBoosts += boosts.where((b) => b.mode == SessionMode.hand).length;
      }
      expect(totalBoosts, greaterThan(0),
          reason: 'aucun boost détecté sur l\'échantillon — '
              'silentFinishStartTime mal calé ?');
      final handRatio = handBoosts / totalBoosts;
      expect(handRatio, lessThan(0.20),
          reason: 'hand=rare ignoré : $handBoosts/$totalBoosts boosts en hand '
              '(${(handRatio * 100).toStringAsFixed(1)} %). '
              'Avant fix #68, la proba effective était 25 % constante.');
    });

    test('hand=frequent + rhythm=rare : >50 % des boosts utilisent hand', () {
      // Réciproque : si l'utilisatrice veut un finish *main-dominé*, les
      // boosts doivent y être nettement majoritaires (ratio inversé par
      // rapport au défaut carrière 25/75).
      var handBoosts = 0;
      var totalBoosts = 0;
      for (final seed in [1, 2, 3, 7, 11, 13, 17, 23, 42, 99, 314, 1234]) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 18,
          bank: _bank(),
          durationSeconds: 12 * 60,
          unlockedKeys: const {},
          humiliationCareer: 400.0,
          obedience: 100.0,
          coachModeWeights: _doses({
            SessionMode.hand: 2.2, // frequent
            SessionMode.rhythm: 0.4, // rare
          }),
        );
        final boosts = _boostSteps(result.session);
        totalBoosts += boosts.length;
        handBoosts += boosts.where((b) => b.mode == SessionMode.hand).length;
      }
      final handRatio = handBoosts / totalBoosts;
      expect(handRatio, greaterThan(0.50),
          reason: 'hand=frequent mais boosts toujours rhythm-dominés : '
              '$handBoosts/$totalBoosts en hand '
              '(${(handRatio * 100).toStringAsFixed(1)} %)');
    });

    test('doses neutres (toutes égales) : comportement carrière inchangé', () {
      // Quand handWeight == rhythmWeight, le doseFactor vaut 1.0 → la proba
      // tombe sur `preferHandBase` historique (~0.25 à humilCareer haut).
      // On vérifie que sur un gros échantillon de seeds, la part de hand
      // reste dans la fenêtre 10–40 % (centré sur 25 %, marge généreuse pour
      // absorber la randomisation).
      var handBoosts = 0;
      var totalBoosts = 0;
      for (final seed in List.generate(20, (i) => i + 1)) {
        final gen = CareerSessionGenerator(seed: seed);
        final result = gen.generate(
          level: 18,
          bank: _bank(),
          durationSeconds: 12 * 60,
          unlockedKeys: const {},
          humiliationCareer: 400.0,
          obedience: 100.0,
          coachModeWeights: const {}, // pas de dose ⇒ tous neutres
        );
        final boosts = _boostSteps(result.session);
        totalBoosts += boosts.length;
        handBoosts += boosts.where((b) => b.mode == SessionMode.hand).length;
      }
      final handRatio = handBoosts / totalBoosts;
      expect(handRatio, inInclusiveRange(0.10, 0.45),
          reason: 'doses neutres : la part de hand a dérivé hors de la '
              'fenêtre attendue (~25 %) — reçu '
              '${(handRatio * 100).toStringAsFixed(1)} %');
    });
  });
}
