/// Régression : attribution des points de spécialisation basée sur le
/// temps cumulé (totalSeconds) au lieu du nombre de sessions complétées.
///
/// Cadence : 1ᵉʳ point à 5 min, delta entre 2 points augmente de 5 min à
/// chaque fois (5, +10, +15, +20, +25 …). Seuil du n-ième point :
/// `2.5 × n × (n+1)` minutes = `n × (n+1) × 150` secondes.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/services/specialization_service.dart';

void main() {
  group('SpecializationService.totalPointsForSeconds', () {
    test('0 s → 0 point', () {
      expect(SpecializationService.totalPointsForSeconds(0), 0);
    });

    test('299 s (juste sous 5 min) → 0 point', () {
      expect(SpecializationService.totalPointsForSeconds(299), 0);
    });

    test('300 s (5 min pile) → 1 point', () {
      expect(SpecializationService.totalPointsForSeconds(300), 1);
    });

    test('899 s (juste sous 15 min) → 1 point', () {
      expect(SpecializationService.totalPointsForSeconds(899), 1);
    });

    test('900 s (15 min pile) → 2 points', () {
      expect(SpecializationService.totalPointsForSeconds(900), 2);
    });

    test('1800 s (30 min) → 3 points', () {
      expect(SpecializationService.totalPointsForSeconds(1800), 3);
    });

    test('3000 s (50 min) → 4 points', () {
      expect(SpecializationService.totalPointsForSeconds(3000), 4);
    });

    test('4500 s (1 h 15) → 5 points', () {
      expect(SpecializationService.totalPointsForSeconds(4500), 5);
    });

    test('6300 s (1 h 45) → 6 points', () {
      expect(SpecializationService.totalPointsForSeconds(6300), 6);
    });

    test('8400 s (2 h 20) → 7 points', () {
      expect(SpecializationService.totalPointsForSeconds(8400), 7);
    });

    test('10800 s (3 h) → 8 points', () {
      expect(SpecializationService.totalPointsForSeconds(10800), 8);
    });

    test('monotonie : f(t+1) >= f(t) sur une grande plage', () {
      // Garde-fou contre une régression de la formule (ex : passage à une
      // expression qui décroirait au-delà d'un certain seuil).
      var previous = 0;
      for (var t = 0; t <= 20000; t += 50) {
        final current = SpecializationService.totalPointsForSeconds(t);
        expect(current >= previous, isTrue,
            reason: 't=$t : $current < $previous');
        previous = current;
      }
    });
  });
}
