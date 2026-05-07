import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';

Coach _coachWith(CoachNicknamePool pool) {
  return CoachCatalog.defaults.first.withPhrases(
    CoachPhrasePack(nicknames: pool),
  );
}

void main() {
  final rng = Random(42);

  group('CoachNicknamePool.fromJson', () {
    test('parse pool + flags', () {
      final p = CoachNicknamePool.fromJson({
        'pool': ['ma jolie', 'ma puce'],
        'use_user_prenom': true,
        'use_user_nicknames': false,
      });
      expect(p.pool, ['ma jolie', 'ma puce']);
      expect(p.useUserPrenom, isTrue);
      expect(p.useUserNicknames, isFalse);
    });

    test('JSON vide → empty pool', () {
      final p = CoachNicknamePool.fromJson({});
      expect(p.isEmpty, isTrue);
    });

    test('liste de pool ignore les vides et trims', () {
      final p = CoachNicknamePool.fromJson({
        'pool': ['  ', 'ok', '', 'valid'],
      });
      expect(p.pool, ['ok', 'valid']);
    });
  });

  group('Coach.pickName', () {
    test('pool seul → tirage uniquement dans le pool coach', () {
      final coach = _coachWith(const CoachNicknamePool(pool: ['x', 'y', 'z']));
      for (var i = 0; i < 30; i++) {
        final name = coach.pickName(
          userPrenom: 'Marie',
          userNicknames: const ['user1', 'user2'],
          userFallback: const ['fallback'],
          rng: rng,
        );
        expect(['x', 'y', 'z'].contains(name), isTrue);
      }
    });

    test('useUserPrenom → prénom user inclus', () {
      final coach = _coachWith(const CoachNicknamePool(
        pool: ['x'],
        useUserPrenom: true,
      ));
      final picks = <String>{};
      for (var i = 0; i < 50; i++) {
        picks.add(coach.pickName(
          userPrenom: 'Marie',
          userNicknames: const ['ignored'],
          userFallback: const ['ignored'],
          rng: rng,
        ));
      }
      expect(picks.contains('Marie'), isTrue);
      expect(picks.contains('x'), isTrue);
      expect(picks.contains('ignored'), isFalse,
          reason: 'useUserNicknames est false');
    });

    test('useUserPrenom mais prenom null → ignoré sans crasher', () {
      final coach = _coachWith(const CoachNicknamePool(
        pool: ['x'],
        useUserPrenom: true,
      ));
      final name = coach.pickName(
        userPrenom: null,
        userNicknames: const [],
        userFallback: const [],
        rng: rng,
      );
      expect(name, 'x');
    });

    test('useUserNicknames → fusion avec pool user', () {
      final coach = _coachWith(const CoachNicknamePool(
        pool: ['x'],
        useUserNicknames: true,
      ));
      final picks = <String>{};
      for (var i = 0; i < 50; i++) {
        picks.add(coach.pickName(
          userPrenom: 'Marie',
          userNicknames: const ['user1', 'user2'],
          userFallback: const ['ignored'],
          rng: rng,
        ));
      }
      expect(picks.contains('x'), isTrue);
      expect(picks.contains('user1'), isTrue);
      expect(picks.contains('user2'), isTrue);
      expect(picks.contains('Marie'), isFalse,
          reason: 'useUserPrenom est false');
    });

    test('pool effectif vide → fallback sur userFallback', () {
      final coach = _coachWith(CoachNicknamePool.empty);
      final name = coach.pickName(
        userPrenom: 'Marie',
        userNicknames: const ['n1'],
        userFallback: const ['fallback_only'],
        rng: rng,
      );
      expect(name, 'fallback_only');
    });

    test('pool effectif vide ET fallback vide → emergency salope', () {
      final coach = _coachWith(CoachNicknamePool.empty);
      final name = coach.pickName(
        userPrenom: null,
        userNicknames: const [],
        userFallback: const [],
        rng: rng,
      );
      expect(name, 'salope');
    });
  });

  group('Coach.buildTextResolver', () {
    test('substitue {name} en respectant le pool coach', () {
      final coach = _coachWith(const CoachNicknamePool(pool: ['ALPHA']));
      // Le resolver écrase 1 occurrence sur 2 (drop 50/50). On vérifie
      // qu'à terme il y a au moins une substitution dans une phrase
      // multi-occurrences sur 50 essais — assez large pour ne pas
      // dépendre du hasard de la seed.
      var sawSubstitution = false;
      var sawDrop = false;
      for (var seed = 0; seed < 50; seed++) {
        final resolve = coach.buildTextResolver(
          userPrenom: 'Marie',
          userNicknames: const ['ignored'],
          userFallback: const ['ignored'],
          rng: Random(seed),
        );
        final out = resolve('vas-y {name}, encore {name} !');
        if (out.contains('ALPHA')) sawSubstitution = true;
        if (out == 'vas-y, encore !') sawDrop = true;
        // Aucun caractère résiduel d'un nom non-coach.
        expect(out.contains('Marie'), isFalse);
        expect(out.contains('ignored'), isFalse);
      }
      expect(sawSubstitution, isTrue);
      expect(sawDrop, isTrue);
    });

    test('insensible à la casse, tolère espaces internes', () {
      final coach = _coachWith(const CoachNicknamePool(pool: ['X']));
      // Sur plusieurs seeds, on doit voir au moins un cas où chaque
      // variante du placeholder est substituée par 'X'. La couverture
      // 1/2 garantit qu'avec 30 tirages, chaque slot tombe au moins
      // une fois sur la branche substitution.
      var allSubstituted = false;
      for (var seed = 0; seed < 30 && !allSubstituted; seed++) {
        final resolve = coach.buildTextResolver(
          userPrenom: null,
          userNicknames: const [],
          userFallback: const [],
          rng: Random(seed),
        );
        final out = resolve('hé {NAME}, hé { name }, hé {Name}');
        if (out == 'hé X, hé X, hé X') allSubstituted = true;
      }
      expect(allSubstituted, isTrue);
    });

    test('texte sans accolades → pass-through', () {
      final coach = _coachWith(const CoachNicknamePool(pool: ['X']));
      final resolve = coach.buildTextResolver(
        userPrenom: null,
        userNicknames: const [],
        userFallback: const [],
        rng: Random(0),
      );
      expect(resolve('aucun placeholder'), 'aucun placeholder');
    });
  });
}
