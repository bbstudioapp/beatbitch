import 'dart:io';

import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:flutter_test/flutter_test.dart';

// Aucun banc ne monte `CareerScreen` : le câblage vers le contrôleur se garde
// sur la source de l'écran, et le calcul sur `session_pauses_ahead_test.dart`.
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), '');

String _method(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature introuvable');
  return _flat(src.substring(start, src.indexOf('\n  }\n', start)));
}

void main() {
  final src = File('lib/career/screens/career_screen.dart').readAsStringSync();

  group('Régénération — l\'écran passe par le contrôleur', () {
    test('Utilise-moi : l\'effort restant retranche les pauses à venir', () {
      expect(_method(src, 'Future<void> _handleUpgrade('),
          contains('ctrl.effortSecondsLeftFrom(ctrl.elapsedSeconds)'));
    });

    test('retry de milestone : effort restant et pauses reportées', () {
      final body = _method(src, 'Future<bool> _handleMilestoneRetry(');
      expect(body, contains('ctrl.effortSecondsLeftFrom(ctrl.elapsedSeconds)'));
      expect(
          body,
          contains(
              'carry:ctrl.postureCarryFrom(ctrl.elapsedSeconds+begDuration)'));
    });

    test('régénération post-défi : effort restant et pauses reportées', () {
      final body = _method(src, 'Future<void> _handlePostChallengeRegen(');
      expect(body, contains('ctrl.effortSecondsLeftFrom(breathEnd)'));
      expect(body, contains('carry:ctrl.postureCarryFrom(breathEnd)'));
    });

    test('le libellé de durée annonce les pauses d\'après le palier', () {
      final flat = _flat(src);
      expect(
          flat,
          contains(
              'lengthChoice.hasPauses(scriptedBreaks:bundle.scriptedBreaks)'));
      expect(flat, contains('hasPauses?'));
    });
  });

  group('SessionLengthChoice.hasPauses', () {
    test('la séance bâclée n\'a jamais de pause', () {
      expect(
          SessionLengthChoice.bachee.hasPauses(scriptedBreaks: true), isFalse);
    });

    test('les autres paliers en ont quand la préférence est active', () {
      for (final c in SessionLengthChoice.values) {
        if (c == SessionLengthChoice.bachee) continue;
        expect(c.hasPauses(scriptedBreaks: true), isTrue, reason: '$c');
        expect(c.hasPauses(scriptedBreaks: false), isFalse, reason: '$c');
      }
    });
  });
}
