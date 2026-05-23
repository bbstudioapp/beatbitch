/// Régression : les paliers de durée de séance carrière doivent être
/// gatés selon l'investissement de la joueuse.
///
/// Source : premier playtest 0.6 — une débutante à 0 min se voyait
/// proposer bâclée (intense dès le départ) et moyenne/longue (25-45 min
/// sans repère). Le gating remet une marche pédagogique :
/// - Bâclée : 30 min de jeu cumulé (intense + court = pas pour la 1ʳᵉ fois)
/// - Moyenne/Longue : 1 séance complétée OU 10 min de jeu (peu importe lequel)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/screens/career_screen.dart';

void main() {
  group('isSessionLengthBacheeUnlocked', () {
    test('0 s → verrouillée', () {
      expect(isSessionLengthBacheeUnlocked(0), isFalse);
    });

    test('1799 s (juste sous 30 min) → verrouillée', () {
      expect(isSessionLengthBacheeUnlocked(1799), isFalse);
    });

    test('1800 s (30 min pile) → déverrouillée', () {
      expect(isSessionLengthBacheeUnlocked(1800), isTrue);
    });

    test('5000 s → déverrouillée', () {
      expect(isSessionLengthBacheeUnlocked(5000), isTrue);
    });
  });

  group('isSessionLengthLongerUnlocked', () {
    test('0 s + 0 session → verrouillée', () {
      expect(
        isSessionLengthLongerUnlocked(
          totalSeconds: 0,
          completedSessions: 0,
        ),
        isFalse,
      );
    });

    test('599 s + 0 session (sous 10 min, pas de séance) → verrouillée', () {
      expect(
        isSessionLengthLongerUnlocked(
          totalSeconds: 599,
          completedSessions: 0,
        ),
        isFalse,
      );
    });

    test('600 s + 0 session (10 min pile) → déverrouillée', () {
      expect(
        isSessionLengthLongerUnlocked(
          totalSeconds: 600,
          completedSessions: 0,
        ),
        isTrue,
      );
    });

    test('0 s + 1 session (OU temps : la séance suffit) → déverrouillée', () {
      // Cas typique : joueuse interrompt sa 1ʳᵉ séance avant 10 min mais
      // la termine via debug ou Termine-moi. La séance complétée prime.
      expect(
        isSessionLengthLongerUnlocked(
          totalSeconds: 0,
          completedSessions: 1,
        ),
        isTrue,
      );
    });

    test('0 s + 3 sessions → déverrouillée', () {
      expect(
        isSessionLengthLongerUnlocked(
          totalSeconds: 0,
          completedSessions: 3,
        ),
        isTrue,
      );
    });
  });
}
