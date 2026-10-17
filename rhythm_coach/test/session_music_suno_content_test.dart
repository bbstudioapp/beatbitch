import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Durées des morceaux mesurées (ffprobe) : la séance ne finit jamais avant
/// la musique.
const _songs = {
  'fin_de_nuit': 213.888,
  'houle': 246.408,
  'ressac': 215.976,
  'rouleau_compresseur': 223.224,
  'sous_pression': 241.968,
};

const _langs = ['fr', 'en', 'de', 'es'];

final _holdVerbs = RegExp(
  r'\b(tiens|maintiens|tenir|hold|halt|halte|halten|mantén|mantenlo|'
  r'mantenla|aguanta)\b',
  caseSensitive: false,
);

Session _load(String id, String lang) => Session.fromJson(
      json.decode(
        File(
          'assets/sessions/session_$id${lang == 'fr' ? '' : '_$lang'}.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>,
    );

void main() {
  for (final entry in _songs.entries) {
    final id = entry.key;
    group(id, () {
      test('même morceau, même durée, mêmes steps dans les quatre langues', () {
        final reference = _load(id, 'fr');
        for (final lang in _langs) {
          final s = _load(id, lang);
          expect(s.id, id, reason: lang);
          expect(s.lang, lang);
          expect(s.music, reference.music, reason: lang);
          expect(s.durationSeconds, reference.durationSeconds, reason: lang);
          expect(s.name, isNotEmpty);
          expect(s.steps, hasLength(reference.steps.length), reason: lang);
          for (var i = 0; i < s.steps.length; i++) {
            final a = reference.steps[i];
            final b = s.steps[i];
            final where = '$lang step $i';
            expect(b.time, a.time, reason: where);
            expect(b.mode, a.mode, reason: where);
            expect(b.from, a.from, reason: where);
            expect(b.to, a.to, reason: where);
            expect(b.bpm, a.bpm, reason: where);
            expect(b.duration, a.duration, reason: where);
            expect(b.text.isEmpty, a.text.isEmpty, reason: where);
          }
        }
      });

      test('la séance couvre tout le morceau', () {
        final s = _load(id, 'fr');
        expect(s.durationSeconds, greaterThanOrEqualTo(entry.value));
        expect(s.durationSeconds - entry.value, lessThan(1));
        final last = s.steps.last;
        expect(last.time, lessThan(s.durationSeconds));
      });

      test(
        'chaque changement tombe dans la seconde qui précède une mesure',
        () {
          final s = _load(id, 'fr');
          final music = s.music!;
          final end = s.steps.indexWhere((x) => x.isTextOnly);
          for (final step in s.steps.take(end).where((x) => !x.isTextOnly)) {
            final bar = music.beatIndexAtOrAfter(
              Duration(seconds: step.time),
              stride: 4,
            );
            final gap = music.beatTime(bar).inMicroseconds / 1e6 - step.time;
            expect(gap, inInclusiveRange(0, 1), reason: 't=${step.time}');
          }
        },
      );

      test('le BPM de chaque step tombe juste sur la grille du morceau', () {
        final s = _load(id, 'fr');
        final music = s.music!;
        for (final step in s.steps.where((x) => x.bpm != null)) {
          final stride = music.strideForStepBpm(step.bpm!);
          expect(
            (music.bpm / stride - step.bpm!).abs(),
            lessThan(1),
            reason: 't=${step.time} bpm ${step.bpm}',
          );
        }
      });

      test('tenues et respirations finissent au step suivant', () {
        final steps = _load(id, 'fr').steps;
        final config = steps.where((x) => !x.isTextOnly).toList();
        for (var i = 0; i < config.length - 1; i++) {
          final st = config[i];
          if (st.mode == SessionMode.hold || st.mode == SessionMode.breath) {
            expect(
              st.time + st.duration!,
              anyOf(config[i + 1].time, config[i + 1].time - 1),
              reason: 't=${st.time}',
            );
          }
        }
      });

      test('amplitude : from strictement moins profond que to', () {
        for (final st in _load(
          id,
          'fr',
        ).steps.where((x) => x.mode == SessionMode.rhythm)) {
          expect(
            st.from!.index,
            lessThan(st.to!.index),
            reason: 't=${st.time}',
          );
        }
      });

      test('« tiens / hold / halten » : dans les tenues, jamais ailleurs', () {
        for (final lang in _langs) {
          final session = _load(id, lang);
          for (final step in session.steps.where((x) => x.text.isNotEmpty)) {
            final where = '$lang t=${step.time} « ${step.text} »';
            expect(
              _holdVerbs.hasMatch(step.text),
              step.mode == SessionMode.hold,
              reason: where,
            );
          }
          expect(
            _holdVerbs.hasMatch(session.intro),
            isFalse,
            reason: '$lang intro',
          );
        }
      });
    });
  }
}
