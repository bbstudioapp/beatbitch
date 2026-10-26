import 'dart:io';

import 'package:beat_bitch/career/models/session_length_choice.dart';
import 'package:flutter_test/flutter_test.dart';

// Aucun banc ne monte `CareerScreen` : le câblage vers les arguments du
// contrôleur se garde sur la source de l'écran, commentaires retirés, et leur
// calcul sur `session_pauses_ahead_test.dart`.
String _flat(String s) =>
    s.replaceAll(RegExp(r'//[^\n]*'), '').replaceAll(RegExp(r'\s+'), '');

String _method(String src, String signature) {
  final start = src.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature introuvable');
  return _flat(src.substring(start, src.indexOf('\n  }\n', start)));
}

void main() {
  final src = File('lib/career/screens/career_screen.dart').readAsStringSync();

  group('Régénération — l\'écran passe par le contrôleur', () {
    test('Utilise-moi : la durée générée vient du contrôleur', () {
      final body = _method(src, 'Future<void> _handleUpgrade(');
      expect(body,
          contains('genDuration=ctrl.upgradeRegenDuration(begDuration);'));
      expect(body, contains('generate(durationSeconds:genDuration,'));
    });

    test('retry de milestone : durée et pauses reportées du contrôleur', () {
      final body = _method(src, 'Future<bool> _handleMilestoneRetry(');
      expect(body, contains('regen=ctrl.milestoneRetryRegenArgs('));
      expect(
          body,
          contains('generate(durationSeconds:regen.durationSeconds,'
              'carry:regen.carry,'));
    });

    test('régénération post-défi : durée et pauses reportées du contrôleur',
        () {
      final body = _method(src, 'Future<void> _handlePostChallengeRegen(');
      expect(body, contains('regen=ctrl.postChallengeRegenArgs();'));
      expect(
          body,
          contains('generate(durationSeconds:regen.durationSeconds,'
              'carry:regen.carry,'));
    });

    test('le libellé de durée annonce les pauses d\'après le palier', () {
      final flat = _flat(src);
      expect(
          flat,
          contains(
              'hasPauses=lengthChoice.hasPauses(scriptedBreaks:bundle.scriptedBreaks);'));
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
