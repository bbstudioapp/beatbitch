import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chantier aimant, étape 4 : la séquence de swings du final `hold` ancré.
/// `_holdSwingSequence` (exposée via `holdSwingSequenceForTest`) est pure —
/// aucun Timer réel n'est nécessaire pour la piloter.
void main() {
  group('BeepEngine.holdSwingSequenceForTest', () {
    test('4 allers-retours à ratio 9, 60 bpm : 1,8 s ancre / 0,2 s haut', () {
      final engine = BeepEngine();
      final seq = engine.holdSwingSequenceForTest(
        anchorPos: Position.full,
        bpm: 60,
        ratio: 9,
        swings: 4,
      );
      // 4 allers-retours = 8 beats : (throat, 1800) puis (full, 200), ×4.
      expect(seq.length, 8);
      for (var i = 0; i < seq.length; i += 2) {
        expect(seq[i].$1, Position.throat, reason: 'beat $i (aller)');
        expect(seq[i].$2, 1800, reason: 'beat $i (aller)');
        expect(seq[i + 1].$1, Position.full, reason: 'beat ${i + 1} (retour)');
        expect(seq[i + 1].$2, 200, reason: 'beat ${i + 1} (retour)');
      }
    });

    test(
        'valeur de production (aucun [swings] explicite) : 4 allers-'
        'retours — c\'est bien ce que joue `_startHoldSwingLoop`', () {
      final engine = BeepEngine();
      final seq = engine.holdSwingSequenceForTest(
        anchorPos: Position.full,
        bpm: 60,
        ratio: 9,
      );
      expect(seq.length, 8);
    });

    test('la position haute est toujours un cran au-dessus de l\'ancre', () {
      final engine = BeepEngine();
      final seq = engine.holdSwingSequenceForTest(
        anchorPos: Position.throat,
        bpm: 60,
        ratio: 9,
        swings: 1,
      );
      expect(seq.first.$1, Position.mid);
      expect(seq.last.$1, Position.throat);
    });

    test(
        'invariant 2T : chaque paire aller+retour vaut exactement le '
        'cycle nominal, quel que soit le ratio', () {
      final engine = BeepEngine();
      for (final ratio in [2, 3, 9, 20]) {
        final seq = engine.holdSwingSequenceForTest(
          anchorPos: Position.full,
          bpm: 72,
          ratio: ratio,
          swings: 3,
        );
        final expectedFullCycle = (2 * 60000 / 72).round();
        for (var i = 0; i + 1 < seq.length; i += 2) {
          expect(seq[i].$2 + seq[i + 1].$2, expectedFullCycle,
              reason: 'ratio=$ratio i=$i');
        }
      }
    });

    test(
        'le compte de swings pilote exactement la longueur de la séquence '
        '— pas de code mort qui ignorerait [swings]', () {
      final engine = BeepEngine();
      expect(
          engine
              .holdSwingSequenceForTest(
                  anchorPos: Position.full, bpm: 60, ratio: 9, swings: 3)
              .length,
          6);
      expect(
          engine
              .holdSwingSequenceForTest(
                  anchorPos: Position.full, bpm: 60, ratio: 9, swings: 0)
              .length,
          0);
    });

    test(
        'ratio 1 : aucune bascule — aller et retour durent chacun 1 T '
        '(pas d\'aimant)', () {
      final engine = BeepEngine();
      final seq = engine.holdSwingSequenceForTest(
        anchorPos: Position.full,
        bpm: 60,
        ratio: 1,
        swings: 1,
      );
      expect(seq[0].$2, 1000);
      expect(seq[1].$2, 1000);
    });
  });
}
