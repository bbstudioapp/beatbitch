import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/services/backgrounds_loader.dart';

void main() {
  group('BackgroundsLoader.parseEntry — tags parsing', () {
    test('basename without underscore → no tags', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/porngif-d242ee.png',
      );
      expect(e, isNotNull);
      expect(e!.id, 'porngif-d242ee');
      expect(e.tags, isEmpty);
      expect(e.tagsByCategory, isEmpty);
      expect(e.hasTags, isFalse);
    });

    test('basename with no recognized tag → id keeps underscores', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/some_random_clip.jpg',
      );
      expect(e!.id, 'some_random_clip');
      expect(e.tags, isEmpty);
    });

    test('single position tag', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_throat.png',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'throat'});
      expect(
        e.tagsByCategory[BackgroundTagCategory.position],
        {'throat'},
      );
    });

    test('mode + position', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_hold_full.png',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'hold', 'full'});
      expect(e.tagsByCategory[BackgroundTagCategory.mode], {'hold'});
      expect(e.tagsByCategory[BackgroundTagCategory.position], {'full'});
    });

    test('balls position tag (zone latérale, lick/hold/beg uniquement)', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_lick_balls.png',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'lick', 'balls'});
      expect(e.tagsByCategory[BackgroundTagCategory.mode], {'lick'});
      expect(e.tagsByCategory[BackgroundTagCategory.position], {'balls'});
    });

    test('coach + mode (Lina beg)', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_lina_beg.png',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'lina', 'beg'});
      expect(e.tagsByCategory[BackgroundTagCategory.coach], {'lina'});
      expect(e.tagsByCategory[BackgroundTagCategory.mode], {'beg'});
    });

    test('post-final phase tag (with hyphen)', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_post-final_lick.png',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'post-final', 'lick'});
      expect(
        e.tagsByCategory[BackgroundTagCategory.phase],
        {'post-final'},
      );
      expect(e.tagsByCategory[BackgroundTagCategory.mode], {'lick'});
    });

    test('coach Victoria + breath', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_victoria_breath.jpeg',
      );
      expect(e!.id, 'clip01');
      expect(e.tags, {'victoria', 'breath'});
    });

    test('unknown segment between id and known tag stops parsing', () {
      // basename = porn_misc_throat → "misc" inconnu, donc on stoppe
      // après throat : id = "porn_misc", tags = {throat}.
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/porn_misc_throat.png',
      );
      expect(e!.id, 'porn_misc');
      expect(e.tags, {'throat'});
    });

    test('id with underscores preserved', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/cool_video_42_hold_throat.png',
      );
      expect(e!.id, 'cool_video_42');
      expect(e.tags, {'hold', 'throat'});
    });

    test('all three categories at once (coach + mode + position)', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/scene_lina_hold_throat.png',
      );
      expect(e!.id, 'scene');
      expect(e.tags, {'lina', 'hold', 'throat'});
      expect(e.tagsByCategory.length, 3);
    });

    test('uppercase normalized to lowercase for tags', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip_LINA_THROAT.png',
      );
      expect(e!.tags, {'lina', 'throat'});
    });

    test('extension filter: unsupported extension → null', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_throat.mp4',
      );
      expect(e, isNull);
    });

    test('subdirectory ignored', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/sub/clip01.png',
      );
      expect(e, isNull);
    });

    test('out-of-prefix path → null', () {
      final e = BackgroundsLoader.parseEntry('assets/sessions/clip.png');
      expect(e, isNull);
    });

    test('gif extension flagged as gif type', () {
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/clip01_hold_full.gif',
      );
      expect(e!.type, BackgroundMediaType.gif);
    });

    test('only one segment after split → no tag possible (id only)', () {
      // basename = "throat" tout seul : pas assez de segments pour avoir
      // un id + un tag, l'id complet est conservé.
      final e = BackgroundsLoader.parseEntry(
        'assets/backgrounds/throat.png',
      );
      expect(e!.id, 'throat');
      expect(e.tags, isEmpty);
    });
  });

  group('BackgroundTagVocabulary', () {
    test('categorizes known tags', () {
      expect(
        BackgroundTagVocabulary.categorize('rhythm'),
        BackgroundTagCategory.mode,
      );
      expect(
        BackgroundTagVocabulary.categorize('throat'),
        BackgroundTagCategory.position,
      );
      expect(
        BackgroundTagVocabulary.categorize('lina'),
        BackgroundTagCategory.coach,
      );
      expect(
        BackgroundTagVocabulary.categorize('final'),
        BackgroundTagCategory.phase,
      );
      expect(
        BackgroundTagVocabulary.categorize('post-final'),
        BackgroundTagCategory.phase,
      );
    });

    test('returns null for unknown tag', () {
      expect(BackgroundTagVocabulary.categorize('nope'), isNull);
      expect(BackgroundTagVocabulary.isKnown('nope'), isFalse);
    });
  });
}
