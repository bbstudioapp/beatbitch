import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';
import 'package:beat_bitch/services/backgrounds_service.dart';

BackgroundEntry _e(String basename) {
  // Reconstruit une entry comme le loader le ferait (parse les tags
  // depuis le basename). On passe par parseEntry pour garder la même
  // sémantique de séparation id/tags.
  final entry = BackgroundsLoader.parseEntry(
    'assets/backgrounds/$basename',
  );
  if (entry == null) {
    throw ArgumentError('Invalid basename for test: $basename');
  }
  return entry;
}

void main() {
  setUp(BackgroundsService.instance.debugResetForTest);

  group('BackgroundsService.pickForContext', () {
    test('empty bundle → no-op', () {
      BackgroundsService.instance.setBundle(BackgroundsBundle.empty);
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm'),
      );
      expect(BackgroundsService.instance.current.value, isNull);
    });

    test('prefers exact mode+position match over untagged', () {
      final tagged = _e('clip_rhythm_throat.png');
      final untagged = _e('plain.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [tagged, untagged]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      expect(BackgroundsService.instance.current.value, tagged);
    });

    test('higher-score entry wins over lower-score', () {
      final twoMatch = _e('a_rhythm_throat.png'); // score 2
      final oneMatch = _e('b_rhythm.png'); // score 1
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [twoMatch, oneMatch]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      expect(BackgroundsService.instance.current.value, twoMatch);
    });

    test('disqualifies entries whose tag category mismatches context', () {
      // Contexte rhythm + throat. Entry tagué `lick` → mismatch sur la
      // catégorie mode → disqualifiée. L'entrée plain est piochée.
      final wrongMode = _e('a_lick_throat.png');
      final plain = _e('b.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [wrongMode, plain]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      expect(BackgroundsService.instance.current.value, plain);
    });

    test('disqualifies entries tagged in a category absent from context', () {
      // Tag `final` sur l'entrée, mais le contexte n'a pas de phase →
      // disqualifiée. C'est ce qui empêche un fond « final » d'apparaître
      // en plein milieu de séance.
      final finalTagged = _e('a_final.png');
      final plain = _e('b.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [finalTagged, plain]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      expect(BackgroundsService.instance.current.value, plain);
    });

    test('coach tag matches when context provides coach', () {
      final linaThroat = _e('clip_lina_throat.png');
      final plain = _e('other.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [linaThroat, plain]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(
          mode: 'rhythm',
          position: 'throat',
          coach: 'lina',
        ),
      );
      expect(BackgroundsService.instance.current.value, linaThroat);
    });

    test('coach mismatch disqualifies the entry', () {
      // Entry taguée Victoria mais contexte coach=lina → disqualifiée.
      final victoria = _e('clip_victoria_throat.png');
      final plain = _e('other.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [victoria, plain]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(
          mode: 'rhythm',
          position: 'throat',
          coach: 'lina',
        ),
      );
      expect(BackgroundsService.instance.current.value, plain);
    });

    test('phase tag matches when context provides phase', () {
      final finalTag = _e('a_final.png');
      final plain = _e('b.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [finalTag, plain]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(phase: 'final'),
      );
      expect(BackgroundsService.instance.current.value, finalTag);
    });

    test('all-tagged catalog with no match → falls back to random', () {
      // Aucun fond non-tagué et aucun ne match → fallback `pickRandom`
      // global (non-null garanti tant que le bundle n'est pas vide).
      final wrong = _e('a_lick_full.png');
      final wrong2 = _e('b_biffle_head.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [wrong, wrong2]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      expect(BackgroundsService.instance.current.value, isNotNull);
    });

    test('empty context behaves like pickRandom', () {
      final a = _e('a.png');
      final b = _e('b.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [a, b]),
      );
      BackgroundsService.instance.pickForContext(const BackgroundContext());
      expect(BackgroundsService.instance.current.value, isNotNull);
    });

    test('untagged fallback when no tagged entry qualifies', () {
      // Context = rhythm + throat. Tagged candidates : lick (mismatch) →
      // none qualifies. Pool sans tag = [plain1, plain2] → un des deux.
      final wrongMode = _e('w_lick_throat.png');
      final plain1 = _e('p1.png');
      final plain2 = _e('p2.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [wrongMode, plain1, plain2]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm', position: 'throat'),
      );
      final picked = BackgroundsService.instance.current.value;
      expect(picked, isNotNull);
      expect(picked == plain1 || picked == plain2, isTrue);
    });

    test('anti-doublon : same call twice changes the entry when possible', () {
      // Deux entrées matchent score 1 (rhythm) ; au 2e appel, on doit
      // basculer sur l'autre.
      final a = _e('a_rhythm.png');
      final b = _e('b_rhythm.png');
      BackgroundsService.instance.setBundle(
        BackgroundsBundle(entries: [a, b]),
      );
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm'),
      );
      final first = BackgroundsService.instance.current.value;
      BackgroundsService.instance.pickForContext(
        const BackgroundContext(mode: 'rhythm'),
      );
      final second = BackgroundsService.instance.current.value;
      expect(second, isNotNull);
      expect(second, isNot(first));
    });
  });
}
