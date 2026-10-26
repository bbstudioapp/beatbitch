import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_music.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _music = SessionMusic(
  asset: 'audio/music/test_track.mp3',
  bpm: 121.96,
  firstBeatSeconds: 16.934,
);

class _SilentBeep extends BeepEngine {
  @override
  Future<void> init() async {}
}

SessionStep _rhythm(int bpm, {Position from = Position.head}) => SessionStep(
      time: 0,
      mode: SessionMode.rhythm,
      from: from,
      to: Position.mid,
      bpm: bpm,
    );

typedef _Beat = ({Duration wall, Duration position});

/// Position de lecture simulée à partir du temps mural (faux). Un morceau qui
/// démarre en retard, se fige ou saute se décrit par cette seule fonction.
class _Harness {
  _Harness(this.async, this.positionAt, {BeepEngine? beep})
      : beep = beep ?? _SilentBeep() {
    this.beep.attachMusic(_music, () => positionAt(async.elapsed));
    this.beep.onBeat = (_) => beats.add(
          (wall: async.elapsed, position: positionAt(async.elapsed)),
        );
  }

  final FakeAsync async;
  final Duration Function(Duration wall) positionAt;
  final BeepEngine beep;
  final List<_Beat> beats = [];

  void elapse(Duration d) => async.elapse(d);

  static int nearestBeat(Duration position) =>
      _music.beatIndexAtOrAfter(position - const Duration(milliseconds: 30));
}

Duration _seconds(num s) => Duration(microseconds: (s * 1e6).round());

void _expectOnGrid(List<_Beat> beats, {Duration tolerance = _oneMs}) {
  for (final b in beats) {
    final k = _Harness.nearestBeat(b.position);
    final off = (b.position - _music.beatTime(k)).abs();
    expect(off, lessThanOrEqualTo(tolerance),
        reason: 'bip à la position ${b.position} : temps n°$k est à '
            '${_music.beatTime(k)}');
  }
}

const _oneMs = Duration(milliseconds: 1);

void main() {
  test(
      '1 mouvement / temps sur toute la durée : chaque bip sur son temps, '
      'sans dérive', () {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(179));

      expect(h.beats, hasLength(330));
      _expectOnGrid(h.beats);
      final indices = h.beats.map((b) => _Harness.nearestBeat(b.position));
      expect(indices.toList(), List.generate(330, (i) => i),
          reason: 'aucun temps sauté ni doublé');
      expect(h.beats.last.position, _music.beatTime(329),
          reason: 'le dernier bip ne porte pas les 46 ms qu\'un intervalle '
              'de 60/122 s aurait accumulés');
    });
  });

  test('1 mouvement / 2 temps : un temps sur deux, toujours les pairs', () {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      h.beep.applyStep(_rhythm(61), SessionMode.rhythm);
      h.elapse(_seconds(179));

      _expectOnGrid(h.beats);
      final indices =
          h.beats.map((b) => _Harness.nearestBeat(b.position)).toList();
      expect(indices, List.generate(165, (i) => i * 2));
    });
  });

  test(
      'un lecteur qui démarre en retard : les bips suivent la musique, pas '
      'le chronomètre', () {
    fakeAsync((async) {
      const late = Duration(milliseconds: 1300);
      final h =
          _Harness(async, (wall) => wall < late ? Duration.zero : wall - late);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(30));

      expect(h.beats, isNotEmpty);
      expect(h.beats.first.wall, _music.beatTime(0) + late,
          reason: 'le premier bip attend le temps n°0 du morceau, 1,3 s plus '
              'tard sur l\'horloge murale');
      _expectOnGrid(h.beats);
    });
  });

  test(
      'l\'horloge du lecteur va 0,1 % plus vite que l\'horloge murale : les '
      'bips restent sur les temps du morceau', () {
    fakeAsync((async) {
      final h = _Harness(async,
          (wall) => Duration(microseconds: wall.inMicroseconds * 1001 ~/ 1000));
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(178));

      expect(h.beats.length, greaterThan(320));
      _expectOnGrid(h.beats, tolerance: const Duration(milliseconds: 2));
    });
  });

  test(
      'un morceau qui se fige (tampon vide) : aucun bip pendant le gel, '
      'puis retour sur la grille', () {
    fakeAsync((async) {
      Duration positionAt(Duration wall) {
        if (wall < _seconds(50)) return wall;
        if (wall < _seconds(52)) return _seconds(50);
        return wall - _seconds(2);
      }

      final h = _Harness(async, positionAt);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(60));

      expect(
        h.beats
            .where((b) => b.wall > _seconds(50.05) && b.wall < _seconds(52.05)),
        isEmpty,
      );
      expect(h.beats.where((b) => b.wall > _seconds(52.2)), isNotEmpty);
      _expectOnGrid(h.beats);
    });
  });

  test('un saut arrière de la position : le loop repart sur la grille', () {
    fakeAsync((async) {
      Duration positionAt(Duration wall) =>
          wall < _seconds(40) ? wall : wall - _seconds(5);

      final h = _Harness(async, positionAt);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(60));

      _expectOnGrid(h.beats);
      final afterJump = h.beats.where((b) => b.wall > _seconds(40));
      expect(afterJump.first.position.inSeconds, greaterThanOrEqualTo(35));
      expect(afterJump.length, greaterThan(30),
          reason: 'le loop n\'a pas attendu que la position rattrape le '
              'dernier temps joué avant le saut');
    });
  });

  test(
      'un step appliqué en cours de morceau démarre sur le prochain temps '
      'de la grille, pas sur l\'instant de l\'appel', () {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      h.elapse(_seconds(70.123));
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(5));

      expect(h.beats, isNotEmpty);
      _expectOnGrid(h.beats);
      final first = h.beats.first;
      expect(first.position - _seconds(70.123),
          lessThan(_music.beatPeriod + const Duration(milliseconds: 400)));
      expect(first.wall - _seconds(70.123), greaterThan(Duration.zero));
    });
  });

  test(
      'pause puis reprise du loop : repart sur la grille à la position de '
      'lecture', () async {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(30));
      final before = h.beats.length;

      h.beep.pause();
      h.elapse(_seconds(4));
      expect(h.beats.length, before, reason: 'pas de bip en pause');

      h.beep.resume();
      h.elapse(_seconds(10));
      expect(h.beats.length, greaterThan(before));
      _expectOnGrid(h.beats);
    });
  });

  group('gain des bips', () {
    test('appliqué au volume de chaque bip pendant la séance musicale', () {
      fakeAsync((async) {
        final h = _Harness(async, (wall) => wall);
        final volumes = <double>[];
        h.beep.debugOnTrigger = (_, v) => volumes.add(v);
        h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
        h.beep.applyStep(
          const SessionStep(
            time: 0,
            mode: SessionMode.lick,
            from: Position.head,
            to: Position.mid,
            bpm: 122,
          ),
          SessionMode.rhythm,
        );
        h.elapse(_seconds(25));

        expect(volumes, isNotEmpty);
        expect(volumes.every((v) => v <= _music.beepGain + 1e-9), isTrue,
            reason: 'aucun bip plus fort que le gain de la séance');
        expect(volumes.last, closeTo(1.0 * _music.beepGain, 1e-9));
      });
    });

    test('détaché : bips à pleine puissance et loop classique, immédiat', () {
      fakeAsync((async) {
        final beep = _SilentBeep();
        final volumes = <double>[];
        final beatWalls = <Duration>[];
        beep.debugOnTrigger = (_, v) => volumes.add(v);
        beep.onBeat = (_) => beatWalls.add(async.elapsed);
        beep.attachMusic(_music, () => async.elapsed);
        beep.detachMusic();

        beep.applyStep(_rhythm(120), SessionMode.rhythm);
        async.elapse(const Duration(seconds: 3));

        expect(volumes.toSet(), {1.0});
        expect(beatWalls.first, lessThan(const Duration(seconds: 1)),
            reason: 'le loop classique joue son premier bip tout de suite, '
                'pas au temps n°0 du morceau (16,9 s)');
        expect((beatWalls[1] - beatWalls[0]).inMilliseconds, closeTo(500, 30));
      });
    });
  });

  test(
      'avance de 120 ms : chaque bip part 120 ms avant son temps de grille, '
      'sans temps sauté ni doublé', () {
    fakeAsync((async) {
      const advance = Duration(milliseconds: 120);
      final h = _Harness(async, (wall) => wall);
      h.beep.musicBeepAdvance = advance;
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(60));

      expect(h.beats, isNotEmpty);
      for (var i = 0; i < h.beats.length; i++) {
        expect(h.beats[i].position, _music.beatTime(i) - advance,
            reason: 'bip n°$i à la position ${h.beats[i].position}, temps de '
                'grille ${_music.beatTime(i)}');
      }
    });
  });

  test('avance = 0 : les bips tombent exactement sur les temps, comme avant',
      () {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      expect(h.beep.musicBeepAdvance, Duration.zero);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(60));

      expect(h.beats, isNotEmpty);
      for (var i = 0; i < h.beats.length; i++) {
        expect(h.beats[i].position, _music.beatTime(i));
      }
    });
  });

  test('l\'avance se règle en cours de séance : le bip suivant la prend', () {
    fakeAsync((async) {
      final h = _Harness(async, (wall) => wall);
      h.beep.applyStep(_rhythm(122), SessionMode.rhythm);
      h.elapse(_seconds(30));
      final before = h.beats.length;
      h.beep.musicBeepAdvance = const Duration(milliseconds: 200);
      h.elapse(_seconds(30));

      final after = h.beats.skip(before + 1).toList();
      expect(after, isNotEmpty);
      for (final b in after) {
        final k = _music.beatIndexAtOrAfter(b.position);
        expect(
            _music.beatTime(k) - b.position, const Duration(milliseconds: 200));
      }
    });
  });
}
