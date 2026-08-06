import 'dart:math';
import 'dart:ui' show Locale;

import 'package:beat_bitch/career/models/coach.dart';
import 'package:beat_bitch/career/models/coach_catalog.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/phrase_bank_loader.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phrases de break scénarisé (issue #77) : pools `break_entry` / `break_orders`
/// / `break_resume` / `break_posture` dans PhraseBank + délégation composed +
/// parsing du loader sur les assets réels (4 langues).
void main() {
  final rng = Random(7);

  group('PhraseBank — pick break', () {
    const bank = PhraseBank(
      byMode: {},
      congrats: [],
      intros: [],
      breakEntry: [PhraseEntry(text: 'entry')],
      breakOrders: [PhraseEntry(text: 'order')],
      breakResume: [PhraseEntry(text: 'resume')],
      breakPostureChange: {
        Posture.kneeling: [PhraseEntry(text: 'à genoux')],
      },
    );

    test('entry / order / resume tirés du pool', () {
      expect(bank.pickBreakEntry(rng), 'entry');
      expect(bank.pickBreakOrder(rng), 'order');
      expect(bank.pickBreakResume(rng), 'resume');
    });

    test('pickPostureChange : pool présent → phrase ; absent → null', () {
      expect(bank.pickPostureChange(Posture.kneeling, rng), 'à genoux');
      expect(bank.pickPostureChange(Posture.allFours, rng), isNull);
    });

    test('pickPostureChange(free) → null (jamais d\'imposition)', () {
      expect(bank.pickPostureChange(Posture.free, rng), isNull);
    });

    test('banque vide → null partout', () {
      const empty = PhraseBank(byMode: {}, congrats: [], intros: []);
      expect(empty.pickBreakEntry(rng), isNull);
      expect(empty.pickBreakOrder(rng), isNull);
      expect(empty.pickBreakResume(rng), isNull);
      expect(empty.pickPostureChange(Posture.kneeling, rng), isNull);
    });
  });

  group('Coach.toPhraseBank — délégation break au global', () {
    const globalBank = PhraseBank(
      byMode: {},
      congrats: [],
      intros: [],
      breakEntry: [PhraseEntry(text: 'G_entry')],
      breakOrders: [PhraseEntry(text: 'G_order')],
      breakResume: [PhraseEntry(text: 'G_resume')],
      breakPostureChange: {
        Posture.allFours: [PhraseEntry(text: 'G_quatre_pattes')],
      },
    );

    test('coach sans break → délégation au pool global', () {
      final coach =
          CoachCatalog.defaults.first.withPhrases(const CoachPhrasePack());
      final bank = coach.toPhraseBank(fallback: globalBank);
      expect(bank.pickBreakEntry(rng), 'G_entry');
      expect(bank.pickBreakOrder(rng), 'G_order');
      expect(bank.pickBreakResume(rng), 'G_resume');
      expect(bank.pickPostureChange(Posture.allFours, rng), 'G_quatre_pattes');
      expect(bank.pickPostureChange(Posture.onBack, rng), isNull);
    });
  });

  group('PhraseBankLoader — parsing break (assets réels)', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    for (final lang in const ['fr', 'en', 'de', 'es']) {
      test('$lang : break_entry / orders / resume / posture peuplés', () async {
        final bank = await PhraseBankLoader().load(locale: Locale(lang));
        expect(bank.pickBreakEntry(rng), isNotNull,
            reason: '$lang break_entry vide');
        expect(bank.pickBreakOrder(rng), isNotNull,
            reason: '$lang break_orders vide');
        expect(bank.pickBreakResume(rng), isNotNull,
            reason: '$lang break_resume vide');
        // Les 5 postures non-free ont un pool de changement de pose.
        for (final pose in Posture.values) {
          if (pose == Posture.free) {
            expect(bank.pickPostureChange(pose, rng), isNull,
                reason: '$lang : free ne doit jamais avoir de pool');
          } else {
            expect(bank.pickPostureChange(pose, rng), isNotNull,
                reason: '$lang : posture ${pose.serialized} sans pool');
          }
        }
      });

      test('$lang : aucun ordre de break ne contient « tiens/hold/halten »',
          () async {
        final bank = await PhraseBankLoader().load(locale: Locale(lang));
        // 50 tirages : couvre largement le pool d'ordres.
        for (var i = 0; i < 50; i++) {
          final order = bank.pickBreakOrder(rng)!.toLowerCase();
          expect(order.contains('tiens'), isFalse, reason: order);
          expect(order.contains('hold'), isFalse, reason: order);
          expect(order.contains('halten'), isFalse, reason: order);
        }
      });
    }
  });
}
