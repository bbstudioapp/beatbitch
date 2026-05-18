// B.PR1 — rôles sémantiques sur `ModeRules`. Cette suite valide
// l'invariant consommé par `_resolveModeForRole` côté générateur :
// pour chaque rôle, **exactement un** mode du registre par défaut le
// déclare. Si plusieurs modes déclaraient le même rôle, la résolution
// retournerait le premier au lieu d'échouer — masquerait silencieusement
// une régression du mapping. Si aucun ne le déclarait, le helper
// lèverait `StateError` au runtime sur le premier appel.

import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModeSemanticRole / defaultModeRulesRegistry', () {
    test('chaque rôle est porté par exactement un mode', () {
      for (final role in ModeSemanticRole.values) {
        final declarers = <SessionMode>[
          for (final e in defaultModeRulesRegistry.entries)
            if (e.value.roles.contains(role)) e.key,
        ];
        expect(
          declarers,
          hasLength(1),
          reason: 'role=$role declarers=$declarers',
        );
      }
    });

    test(
        'mapping attendu — chaque rôle pointe vers le mode prévu '
        '(figé par le plan de refacto, phase B)', () {
      final mapping = {
        for (final role in ModeSemanticRole.values)
          role: defaultModeRulesRegistry.entries
              .firstWhere((e) => e.value.roles.contains(role))
              .key,
      };
      expect(mapping, {
        ModeSemanticRole.breath: SessionMode.breath,
        ModeSemanticRole.swallowOrder: SessionMode.beg,
        ModeSemanticRole.burstHumiliating: SessionMode.rhythm,
        ModeSemanticRole.burstNeutral: SessionMode.hand,
        ModeSemanticRole.burstFallback: SessionMode.lick,
        ModeSemanticRole.miniWaveCore: SessionMode.rhythm,
        ModeSemanticRole.preFinisherCore: SessionMode.rhythm,
        ModeSemanticRole.postWaveBreath: SessionMode.breath,
        ModeSemanticRole.recoveryFallback: SessionMode.breath,
        ModeSemanticRole.staticHeld: SessionMode.hold,
      });
    });

    test('les modes sans rôle dramaturgique gardent le default vide', () {
      // biffle / freestyle / suckle : pas de rôle au mapping initial
      // (cf. plan de refacto). Si on en ajoute un, ce test sautera et
      // forcera à mettre à jour la liste — c'est volontaire.
      for (final mode in [
        SessionMode.biffle,
        SessionMode.freestyle,
        SessionMode.suckle,
      ]) {
        expect(
          defaultModeRulesRegistry[mode]!.roles,
          isEmpty,
          reason: 'mode=$mode',
        );
      }
    });
  });
}
