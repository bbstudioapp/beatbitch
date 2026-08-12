import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/debug_settings_service.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Les postures imposées + pauses scénarisées (issue #77) sont annoncées dans
/// les notes de version 0.6.0 comme un comportement du jeu. Elles ont pourtant
/// vécu deux versions derrière un toggle de la section debug de l'écran SONS,
/// off par défaut — donc invisibles pour tout le monde. Ces tests verrouillent
/// l'état « allumé sans toucher à un réglage » : préférence `pref.`, on par
/// défaut, et une génération carrière qui produit réellement une posture et
/// des breaks quand on lui passe ce défaut.

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

void main() {
  group('Préférence « postures imposées et pauses »', () {
    test('profil vierge → activée par défaut', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DebugSettingsService().getScriptedBreaks(), isTrue);
    });

    test('portée par une clé `pref.`, pas par l\'ancienne clé debug', () async {
      // Une valeur restée sous l'ancienne clé debug (off par défaut à
      // l'époque) ne doit plus rien éteindre : la préférence a changé de
      // famille, l'ancien off n'est pas collant.
      SharedPreferences.setMockInitialValues({'debug.scripted_breaks': false});
      expect(await DebugSettingsService().getScriptedBreaks(), isTrue);

      SharedPreferences.setMockInitialValues({'pref.scripted_breaks': false});
      expect(await DebugSettingsService().getScriptedBreaks(), isFalse);
    });

    test('setter écrit bien sous la clé `pref.`', () async {
      SharedPreferences.setMockInitialValues({});
      await DebugSettingsService().setScriptedBreaks(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pref.scripted_breaks'), isFalse);
    });
  });

  group('Chaîne complète — le défaut de la préférence allume la génération',
      () {
    test('posture imposée à l\'intro + breaks sur une séance longue', () async {
      SharedPreferences.setMockInitialValues({});
      final enabled = await DebugSettingsService().getScriptedBreaks();

      // Le pool de tirage inclut toujours `free` : sur un seed donné le
      // résultat peut être `free` sans que ce soit un défaut. On balaie donc
      // plusieurs seeds et on exige qu'une posture sorte, et que les breaks
      // (eux, déterministes sur une séance de 50 min) soient là à chaque fois.
      final poses = <Posture>{};
      for (var seed = 0; seed < 12; seed++) {
        final result = CareerSessionGenerator(seed: seed).generate(
          level: 14,
          bank: _bank(),
          durationSeconds: 50 * 60,
          unlockedKeys: UnlockKey.values.toSet(),
          scriptedBreaks: enabled,
        );
        poses.add(result.session.initialPose);
        expect(result.session.breaks, isNotEmpty,
            reason: 'séance de 50 min, seed $seed : aucun break inséré');
      }
      expect(poses.any((p) => p != Posture.free), isTrue,
          reason: 'aucune posture imposée sur 12 seeds');
    });

    test('la préférence coupée éteint tout', () async {
      SharedPreferences.setMockInitialValues({'pref.scripted_breaks': false});
      final enabled = await DebugSettingsService().getScriptedBreaks();
      final result = CareerSessionGenerator(seed: 3).generate(
        level: 14,
        bank: _bank(),
        durationSeconds: 50 * 60,
        unlockedKeys: UnlockKey.values.toSet(),
        scriptedBreaks: enabled,
      );
      expect(result.session.initialPose, Posture.free);
      expect(result.session.breaks, isEmpty);
    });
  });
}
