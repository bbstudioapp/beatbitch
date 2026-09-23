import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/session_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const _files = {
  'fr': 'assets/sessions/session_montee_puissance.json',
  'en': 'assets/sessions/session_montee_puissance_en.json',
  'de': 'assets/sessions/session_montee_puissance_de.json',
  'es': 'assets/sessions/session_montee_puissance_es.json',
};

const _track = SessionMusic(
  asset: 'audio/music/montee_en_puissance.mp3',
  bpm: 121.96,
  firstBeatSeconds: 16.934,
);

/// Instants mesurés dans le morceau (ffmpeg + numpy, session du 23/09) : temps
/// de la grille → seconde. Un step de changement se pose à la seconde entière
/// qui précède l'événement.
const _events = {
  0: 16.934,
  78: 55.31,
  126: 78.92,
  158: 94.67,
  190: 110.41,
  222: 126.15,
  254: 141.9,
  275: 152.2,
  298: 163.54,
  321: 174.86,
};

/// « tiens / hold / halten » et leurs équivalents : réservés aux tenues.
final _holdVerbs = RegExp(
  r'\b(tiens|maintiens|tenir|hold|halt|halte|halten|mantén|mantenlo|'
  r'mantenla|aguanta)\b',
  caseSensitive: false,
);

Session _load(String lang) =>
    Session.fromJson(json.decode(File(_files[lang]!).readAsStringSync())
        as Map<String, dynamic>);

int _depth(Position p) => p.index;

void main() {
  test('la grille du modèle retombe sur les instants mesurés du morceau', () {
    for (final e in _events.entries) {
      final seconds = _track.beatTime(e.key).inMicroseconds / 1e6;
      expect((seconds - e.value).abs(), lessThan(0.03),
          reason: 'temps ${e.key}');
    }
  });

  group('les quatre langues', () {
    test('même identifiant, même morceau, même durée', () {
      for (final lang in _files.keys) {
        final s = _load(lang);
        expect(s.id, 'montee_en_puissance', reason: lang);
        expect(s.lang, lang);
        expect(s.durationSeconds, 179, reason: lang);
        expect(s.music, _track, reason: lang);
        expect(s.name, isNotEmpty);
        expect(s.description, isNotEmpty);
      }
    });

    test('mêmes temps et mêmes consignes de bip dans les quatre langues', () {
      final reference = _load('fr').steps;
      for (final lang in ['en', 'de', 'es']) {
        final steps = _load(lang).steps;
        expect(steps, hasLength(reference.length), reason: lang);
        for (var i = 0; i < steps.length; i++) {
          final a = reference[i];
          final b = steps[i];
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

    test('« tiens / hold / halten » : dans les tenues, jamais ailleurs', () {
      for (final lang in _files.keys) {
        final session = _load(lang);
        for (final step in session.steps.where((s) => s.text.isNotEmpty)) {
          final where = '$lang t=${step.time} « ${step.text} »';
          if (step.mode == SessionMode.hold) {
            expect(_holdVerbs.hasMatch(step.text), isTrue, reason: where);
          } else {
            expect(_holdVerbs.hasMatch(step.text), isFalse, reason: where);
          }
        }
        expect(_holdVerbs.hasMatch(session.intro ?? ''), isFalse,
            reason: '$lang intro');
      }
    });
  });

  group('le déroulé validé', () {
    late final Session fr = _load('fr');
    List<SessionStep> config() => fr.steps.where((s) => !s.isTextOnly).toList();

    test('les changements tombent juste avant les événements du morceau', () {
      final changes = {
        16: 0,
        55: 78,
        78: 126,
        94: 158,
        110: 190,
        126: 222,
        141: 254,
        152: 275,
        163: 298,
      };
      final times = config().map((s) => s.time).toSet();
      for (final e in changes.entries) {
        expect(times, contains(e.key));
        final beat = _events[e.value]!;
        expect(e.key, lessThanOrEqualTo(beat), reason: 'temps ${e.value}');
        expect(beat - e.key, lessThan(1.0), reason: 'temps ${e.value}');
      }
    });

    test('1 mouvement / 2 temps puis 1 / temps : 61 BPM puis 122 BPM', () {
      int bpmAt(int t) =>
          config().lastWhere((s) => s.time <= t && s.bpm != null).bpm!;
      expect(bpmAt(30), 61);
      expect(bpmAt(60), 61);
      expect(bpmAt(90), 122);
      expect(bpmAt(120), 122);
      expect(bpmAt(145), 122);
      expect(bpmAt(160), 61, reason: 'redescente : 1 mouvement / 2 temps');
      expect(_track.strideForStepBpm(61), 2);
      expect(_track.strideForStepBpm(122), 1);
    });

    test('premier suspens : tenue à la gorge, 16 s, sur les temps 158 → 190',
        () {
      final hold = fr.steps.firstWhere((s) => s.time == 94);
      expect(hold.mode, SessionMode.hold);
      expect(hold.to, Position.throat);
      expect(hold.duration, 16);
      expect(
          fr.steps.firstWhere((s) => s.time > 94 && !s.isTextOnly).time, 110);
    });

    test('suspens final : l\'explosion est une tenue au fond, step final', () {
      final last = config().last;
      expect(fr.steps.where((s) => s.time >= 176 && !s.isTextOnly).single.mode,
          SessionMode.breath);
      final holds = config().where((s) => s.mode == SessionMode.hold).toList();
      expect(holds.last.time, 163);
      expect(holds.last.to, Position.full);
      expect(holds.last.duration, 12);
      expect(last.mode, SessionMode.breath, reason: 'la fin remonte');
    });

    test(
        'l\'amplitude finit à la gorge : le fond n\'est atteint que par la '
        'tenue finale', () {
      for (final s in config().where((s) => s.mode == SessionMode.rhythm)) {
        expect(_depth(s.to!), lessThanOrEqualTo(_depth(Position.throat)),
            reason: 't=${s.time}');
        expect(_depth(s.from!), lessThan(_depth(s.to!)),
            reason: 'from strictement au-dessus de to, t=${s.time}');
      }
      final rise = config()
          .where((s) => s.mode == SessionMode.rhythm && s.time >= 110)
          .where((s) => s.time <= 141)
          .map((s) => _depth(s.to!))
          .toList();
      expect(rise, orderedEquals([...rise]..sort()),
          reason: 'de plus en plus profond de 110 à 141 s');
    });

    test('aucun défi, aucune pause scénarisée, aucune posture imposée', () {
      for (final lang in _files.keys) {
        final s = _load(lang);
        expect(s.challenges, isEmpty, reason: lang);
        expect(s.steps.where((x) => x.awaitReady), isEmpty, reason: lang);
        expect(s.steps.where((x) => x.chainAction != null), isEmpty,
            reason: lang);
        expect(s.steps.last.time, lessThan(s.durationSeconds));
      }
    });
  });

  group('SessionLoader', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<List<Session>> load(String lang, {required bool bundled}) =>
        SessionLoader(isAssetBundled: (_) async => bundled)
            .loadAll(locale: Locale(lang));

    test('sans le fichier du morceau la séance est masquée, les autres restent',
        () async {
      for (final lang in _files.keys) {
        final sessions = await load(lang, bundled: false);
        expect(sessions.where((s) => s.id == 'montee_en_puissance'), isEmpty,
            reason: lang);
        expect(sessions, isNotEmpty, reason: lang);
      }
    });

    test('avec le fichier du morceau la séance est proposée dans sa langue',
        () async {
      for (final lang in _files.keys) {
        final sessions = await load(lang, bundled: true);
        final music = sessions.where((s) => s.id == 'montee_en_puissance');
        expect(music, hasLength(1), reason: lang);
        expect(music.single.lang, lang);
      }
    });

    test('le loader demande la clé complète de l\'asset du morceau', () async {
      final asked = <String>[];
      await SessionLoader(isAssetBundled: (key) async {
        asked.add(key);
        return true;
      }).loadAll(locale: const Locale('fr'));
      expect(asked.toSet(), {'assets/audio/music/montee_en_puissance.mp3'});
    });
  });
}
