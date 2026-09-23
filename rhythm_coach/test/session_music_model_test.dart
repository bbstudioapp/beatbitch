import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = SessionMusic(
  asset: 'audio/music/montee_en_puissance.mp3',
  bpm: 121.96,
  firstBeatSeconds: 16.934,
);

Map<String, dynamic> _sessionJson({Object? music}) => {
      'id': 'x',
      'name': 'x',
      'duration_seconds': 60,
      'mode': 'rhythm',
      'steps': [
        {'time': 0, 'mode': 'rhythm', 'from': 'head', 'to': 'mid', 'bpm': 60},
      ],
      if (music != null) 'music': music,
    };

void main() {
  group('Session.music — JSON', () {
    test('aller-retour avec un morceau', () {
      final session = Session.fromJson(_sessionJson(music: _track.toJson()));
      expect(session.music, _track);

      final again = Session.fromJson(
        json.decode(json.encode(session.toJson())) as Map<String, dynamic>,
      );
      expect(again.music, _track);
    });

    test('sans morceau : le JSON écrit n\'a pas de clé music', () {
      final session = Session.fromJson(_sessionJson());
      expect(session.music, isNull);
      expect(session.toJson().containsKey('music'), isFalse);
    });

    test('toutes les séances livrées sans morceau se relisent à l\'identique',
        () {
      final files = Directory('assets/sessions')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .where((f) => !f.path.contains('montee_puissance'))
          .toList();
      expect(files, isNotEmpty);
      for (final f in files) {
        final raw = json.decode(f.readAsStringSync()) as Map<String, dynamic>;
        final session = Session.fromJson(raw);
        expect(session.music, isNull, reason: f.path);
        expect(session.toJson().containsKey('music'), isFalse, reason: f.path);
        expect(session.toJson()['steps'], hasLength(session.steps.length));
      }
    });

    test('un bloc music incomplet est ignoré, la séance s\'ouvre quand même',
        () {
      for (final bad in <Object>[
        {'asset': 'audio/music/x.mp3'},
        {'asset': '', 'bpm': 120, 'first_beat': 1},
        {'asset': 'audio/music/x.mp3', 'bpm': 0, 'first_beat': 1},
        {'asset': 'audio/music/x.mp3', 'bpm': 120, 'first_beat': -1},
        'pas un objet',
      ]) {
        final session = Session.fromJson(_sessionJson(music: bad));
        expect(session.music, isNull, reason: '$bad');
        expect(session.steps, hasLength(1));
      }
    });

    test('le volume par défaut n\'est pas écrit, un volume explicite oui', () {
      expect(_track.toJson().containsKey('volume'), isFalse);
      const quiet =
          SessionMusic(asset: 'a', bpm: 120, firstBeatSeconds: 0, volume: 0.4);
      expect(quiet.toJson()['volume'], 0.4);
      expect(SessionMusic.tryParse(quiet.toJson())?.volume, 0.4);
    });
  });

  group('SessionMusic — grille des temps', () {
    test('le temps n°0 tombe sur first_beat', () {
      expect(_track.beatTime(0), const Duration(milliseconds: 16934));
    });

    test('pas de dérive : le dernier temps suit le tempo réel du morceau', () {
      // 320 temps ≈ 157 s : 60/122 au lieu de 60/121,96 décalerait de 50 ms.
      const period = 60 / 121.96;
      const expected = 16.934 + 320 * period;
      expect(
          _track.beatTime(320).inMicroseconds / 1e6, closeTo(expected, 1e-6));

      const integerBpmGrid = 16.934 + 320 * (60 / 122);
      expect((expected - integerBpmGrid).abs(), greaterThan(0.04),
          reason: 'garde-fou : l\'écart que la grille du morceau évite');
    });

    test('beatIndexAtOrAfter : exactement sur un temps, juste après, avant',
        () {
      expect(_track.beatIndexAtOrAfter(_track.beatTime(37)), 37);
      expect(
        _track.beatIndexAtOrAfter(
            _track.beatTime(37) + const Duration(milliseconds: 1)),
        38,
      );
      expect(_track.beatIndexAtOrAfter(Duration.zero), 0);
      expect(_track.beatIndexAtOrAfter(const Duration(seconds: 10)), 0);
    });

    test('beatIndexAtOrAfter respecte le pas : 1 mouvement / 2 temps', () {
      expect(_track.beatIndexAtOrAfter(_track.beatTime(37), stride: 2), 38);
      expect(_track.beatIndexAtOrAfter(_track.beatTime(38), stride: 2), 38);
      expect(_track.beatIndexAtOrAfter(_track.beatTime(39), stride: 2), 40);
    });

    test('le pas se déduit du BPM entier du step', () {
      expect(_track.strideForStepBpm(122), 1);
      expect(_track.strideForStepBpm(61), 2);
      expect(_track.strideForStepBpm(0), 1);
      expect(_track.strideForStepBpm(300), 1);
    });
  });
}
