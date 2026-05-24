/// Régression : les paliers de durée de séance carrière doivent être
/// gatés selon l'investissement de la joueuse.
///
/// Source : premier playtest 0.6 — une débutante à 0 min se voyait
/// proposer bâclée (intense dès le départ) et moyenne/longue (25-45 min
/// sans repère). Le gating remet une marche pédagogique :
/// - Bâclée : 30 min de jeu cumulé (intense + court = pas pour la 1ʳᵉ fois)
/// - Moyenne : 1 séance complétée OU 10 min de jeu
/// - Longue : 1 h de jeu cumulé (pas de bypass session — un format 45 min
///   demande d'avoir tenu au moins une moyenne ou plusieurs courtes)
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/session_length_choice.dart';
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

  group('isSessionLengthMoyenneUnlocked', () {
    test('0 s + 0 session → verrouillée', () {
      expect(
        isSessionLengthMoyenneUnlocked(
          totalSeconds: 0,
          completedSessions: 0,
        ),
        isFalse,
      );
    });

    test('599 s + 0 session (sous 10 min, pas de séance) → verrouillée', () {
      expect(
        isSessionLengthMoyenneUnlocked(
          totalSeconds: 599,
          completedSessions: 0,
        ),
        isFalse,
      );
    });

    test('600 s + 0 session (10 min pile) → déverrouillée', () {
      expect(
        isSessionLengthMoyenneUnlocked(
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
        isSessionLengthMoyenneUnlocked(
          totalSeconds: 0,
          completedSessions: 1,
        ),
        isTrue,
      );
    });

    test('0 s + 3 sessions → déverrouillée', () {
      expect(
        isSessionLengthMoyenneUnlocked(
          totalSeconds: 0,
          completedSessions: 3,
        ),
        isTrue,
      );
    });
  });

  group('isSessionLengthLongueUnlocked', () {
    test('0 s → verrouillée', () {
      expect(isSessionLengthLongueUnlocked(0), isFalse);
    });

    test('3599 s (juste sous 1 h) → verrouillée', () {
      expect(isSessionLengthLongueUnlocked(3599), isFalse);
    });

    test('3600 s (1 h pile) → déverrouillée', () {
      expect(isSessionLengthLongueUnlocked(3600), isTrue);
    });

    test('7200 s (2 h) → déverrouillée', () {
      expect(isSessionLengthLongueUnlocked(7200), isTrue);
    });

    test(
      'pas de bypass session : 1 séance bâclée ne suffit pas (= '
      '360 s < 1 h)',
      () {
        // Sanity check : la signature n'accepte pas `completedSessions`,
        // donc la séance bâclée ne peut pas servir de bypass. Le test
        // matérialise la décision de design (vs `isSessionLengthMoyenneUnlocked`).
        expect(isSessionLengthLongueUnlocked(360), isFalse);
      },
    );
  });

  // Helper partagé entre `build` (rendu du picker) et `_start` (génération +
  // persistance). Bug détecté en review PR #249 : `_start` lisait
  // `bundle.lastLengthChoice` brut, court-circuitant le fallback du picker.
  group('resolveSessionLengthChoice', () {
    test('persisted déverrouillé → pas de fallback', () {
      expect(
        resolveSessionLengthChoice(
          persisted: SessionLengthChoice.longue,
          bacheeUnlocked: true,
          moyenneUnlocked: true,
          longueUnlocked: true,
        ),
        SessionLengthChoice.longue,
      );
    });

    test('longue persisté + gate Longue lock → fallback courte', () {
      expect(
        resolveSessionLengthChoice(
          persisted: SessionLengthChoice.longue,
          bacheeUnlocked: true,
          moyenneUnlocked: true,
          longueUnlocked: false,
        ),
        SessionLengthChoice.courte,
      );
    });

    test('moyenne persisté + gate Moyenne lock → fallback courte', () {
      expect(
        resolveSessionLengthChoice(
          persisted: SessionLengthChoice.moyenne,
          bacheeUnlocked: true,
          moyenneUnlocked: false,
          longueUnlocked: false,
        ),
        SessionLengthChoice.courte,
      );
    });

    test('bachee persisté + gate Bâclée lock → fallback courte', () {
      expect(
        resolveSessionLengthChoice(
          persisted: SessionLengthChoice.bachee,
          bacheeUnlocked: false,
          moyenneUnlocked: true,
          longueUnlocked: true,
        ),
        SessionLengthChoice.courte,
      );
    });

    test('courte persisté → toujours retourne courte (jamais lockée)', () {
      expect(
        resolveSessionLengthChoice(
          persisted: SessionLengthChoice.courte,
          bacheeUnlocked: false,
          moyenneUnlocked: false,
          longueUnlocked: false,
        ),
        SessionLengthChoice.courte,
      );
    });
  });
}
