import 'package:beat_bitch/career/models/posture_unlock.dart';
import 'package:beat_bitch/career/models/unlock_key.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostureUnlock — Posture ↔ UnlockKey', () {
    test('free n\'a pas de clé enum, les autres oui', () {
      expect(Posture.free.unlockKeyEnum, isNull);
      for (final p in Posture.values.where((p) => p != Posture.free)) {
        expect(p.unlockKeyEnum, isNotNull,
            reason: '$p doit mapper une UnlockKey');
      }
    });

    test('unlockKeyEnum.serialized cohérent avec Posture.unlockKey (String)',
        () {
      for (final p in Posture.values) {
        expect(p.unlockKeyEnum?.serialized, p.unlockKey,
            reason: 'le pont enum doit produire la même clé que le modèle');
      }
    });
  });

  group('availablePostures', () {
    test('free seule quand aucun unlock', () {
      expect(availablePostures({}), [Posture.free]);
    });

    test('inclut une posture débloquée, free toujours en tête', () {
      final result = availablePostures({UnlockKey.postureKneeling});
      expect(result, contains(Posture.kneeling));
      expect(result.first, Posture.free);
      expect(result, isNot(contains(Posture.allFours)));
    });

    test('toutes débloquées = toutes les postures', () {
      final all = {
        for (final p in Posture.values)
          if (p.unlockKeyEnum != null) p.unlockKeyEnum!,
      };
      expect(availablePostures(all).toSet(), Posture.values.toSet());
    });

    test('ignore les unlocks non-posture', () {
      expect(availablePostures({UnlockKey.lickBalls, UnlockKey.throatHold}),
          [Posture.free]);
    });

    test('ordre déterministe = ordre de Posture.values', () {
      final result = availablePostures({
        UnlockKey.postureOnBack,
        UnlockKey.postureSitting,
      });
      expect(result, [Posture.free, Posture.sitting, Posture.onBack]);
    });
  });
}
