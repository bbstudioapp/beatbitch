import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:beat_bitch/models/session_step.dart' show Position;
import 'package:beat_bitch/music/beat_pattern.dart';
import 'package:beat_bitch/music/depth_contour.dart';
import 'package:beat_bitch/music/music_capability_bounds.dart';
import 'package:beat_bitch/music/music_pattern_generator.dart';
import 'package:beat_bitch/music/onset_figures.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/capability_service.dart';

CapabilityProfile _profile(Map<CapabilityAxis, double> comforts) =>
    CapabilityProfile({
      for (final e in comforts.entries)
        e.key: CapabilityAxisState(best: e.value, comfort: e.value),
    });

List<Position> _strikes(BeatPattern p) => [
      for (final s in p.slots)
        if (s.onset == SlotOnset.strike) s.to!
    ];

void main() {
  group('MusicCapabilityBounds', () {
    test('maxDepth : défaut mid, lu, plancher mid, plafond full', () {
      expect(const MusicCapabilityBounds(null).maxDepth(), Position.mid);
      expect(
        MusicCapabilityBounds(_profile({
          CapabilityAxis.rhythmDepthMax: Position.throat.index.toDouble()
        })).maxDepth(),
        Position.throat,
      );
      // au-delà de full → clampé full ; en-deçà de mid → plancher mid
      expect(
        MusicCapabilityBounds(_profile({CapabilityAxis.rhythmDepthMax: 99}))
            .maxDepth(),
        Position.full,
      );
      expect(
        MusicCapabilityBounds(_profile({CapabilityAxis.rhythmDepthMax: 0}))
            .maxDepth(),
        Position.mid,
      );
    });

    test('bpmCeilFor mappe la bonne bande', () {
      final b = MusicCapabilityBounds(_profile({
        CapabilityAxis.rhythmBpmCeilShallow: 130,
        CapabilityAxis.rhythmBpmCeilThroat: 90,
        CapabilityAxis.rhythmBpmCeilFull: 70,
      }));
      expect(b.bpmCeilFor(Position.head), 130);
      expect(b.bpmCeilFor(Position.mid), 130);
      expect(b.bpmCeilFor(Position.throat), 90);
      expect(b.bpmCeilFor(Position.full), 70);
    });
  });

  group('DepthContour — invariants', () {
    test('strictement > ancre, ≤ maxDepth, frappes adjacentes différentes', () {
      final rng = Random(1);
      for (final fam in ContourFamily.values) {
        for (var n = 1; n <= 8; n++) {
          final depths = DepthContour.generate(
            strikeCount: n,
            anchor: Position.head,
            maxDepth: Position.full,
            family: fam,
            rng: rng,
          );
          expect(depths.length, n);
          for (final d in depths) {
            expect(d.index, greaterThan(Position.head.index));
            expect(d.index, lessThanOrEqualTo(Position.full.index));
          }
          for (var i = 1; i < depths.length; i++) {
            expect(depths[i], isNot(depths[i - 1]),
                reason: 'bégaiement $fam à $i : $depths');
          }
        }
      }
    });
  });

  group('MusicPatternGenerator', () {
    test('sans profil : tempo brut, profondeur ≤ mid, aucun crash', () {
      final gen = MusicPatternGenerator(rng: Random(7));
      for (var ph = 0; ph < 12; ph++) {
        final p = gen.next(musicBpm: 120, phraseIndex: ph);
        expect(p.bpm, 120);
        for (final d in _strikes(p)) {
          expect(d.index, lessThanOrEqualTo(Position.mid.index));
          expect(d.index, greaterThan(p.anchor.index));
        }
      }
    });

    test('BPM toujours sous le plafond de la profondeur la plus profonde', () {
      final gen = MusicPatternGenerator(
        rng: Random(3),
        profile: _profile({
          CapabilityAxis.rhythmDepthMax: Position.full.index.toDouble(),
          CapabilityAxis.rhythmBpmCeilShallow: 130,
          CapabilityAxis.rhythmBpmCeilThroat: 90,
          CapabilityAxis.rhythmBpmCeilFull: 70,
        }),
      );
      final bounds = gen.bounds;
      for (var ph = 0; ph < 20; ph++) {
        final p = gen.next(musicBpm: 150, phraseIndex: ph);
        final deepest =
            _strikes(p).reduce((a, b) => a.index >= b.index ? a : b);
        expect(p.bpm, lessThanOrEqualTo(bounds.bpmCeilFor(deepest)!),
            reason: 'phrase $ph bpm=${p.bpm} > ceil($deepest)');
      }
    });

    test('mapping musical : 150 BPM sous plafond throat 90 → demi-temps 75',
        () {
      final gen = MusicPatternGenerator(
        rng: Random(0),
        profile: _profile({
          CapabilityAxis.rhythmDepthMax: Position.throat.index.toDouble(),
          CapabilityAxis.rhythmBpmCeilShallow: 130,
          CapabilityAxis.rhythmBpmCeilThroat: 90,
        }),
      );
      // Phrase assez avancée pour viser throat.
      final p = gen.next(musicBpm: 150, phraseIndex: 4);
      expect(_strikes(p).any((d) => d == Position.throat), isTrue);
      expect(p.bpm, 75); // 150 × 0.5, sous 90
    });

    test('profondeur escalade avec la phrase sans dépasser maxDepth', () {
      final gen = MusicPatternGenerator(
        rng: Random(5),
        profile: _profile({
          CapabilityAxis.rhythmDepthMax: Position.full.index.toDouble(),
          CapabilityAxis.rhythmBpmCeilShallow: 200,
          CapabilityAxis.rhythmBpmCeilThroat: 200,
          CapabilityAxis.rhythmBpmCeilFull: 200,
        }),
      );
      final early = gen.next(musicBpm: 100, phraseIndex: 0);
      for (final d in _strikes(early)) {
        expect(d.index, lessThanOrEqualTo(Position.mid.index));
      }
    });

    test('figure de phrase 0 : uniquement niveau 1', () {
      // On vérifie le gating de la banque, pas l'aléatoire : tous les ids
      // possibles à maxLevel=1 sont de niveau 1.
      final lvl1 = onsetFigureBank.where((f) => f.level <= 1).toList();
      expect(lvl1, isNotEmpty);
      expect(lvl1.every((f) => f.level == 1), isTrue);
    });

    test(
        'ignoreGating : profondeur libre (≥ throat) dès la phrase 0, sans plafond',
        () {
      // Aucun profil (joueuse neuve) : sans debug ce serait borné à mid.
      final gen = MusicPatternGenerator(rng: Random(3), ignoreGating: true);
      final p = gen.next(musicBpm: 150, phraseIndex: 0);
      final deepest = _strikes(p).reduce((a, b) => a.index >= b.index ? a : b);
      expect(deepest.index, greaterThanOrEqualTo(Position.throat.index),
          reason: 'le debug doit autoriser la profondeur tout de suite');
      expect(p.bpm, 150); // aucun plafond BPM en debug
    });

    test('grammaire valide : ancre unique 1/2, plongées impaires', () {
      final gen = MusicPatternGenerator(rng: Random(11), ignoreGating: true);
      for (var ph = 0; ph < 12; ph++) {
        _expectValidGrammar(
          gen
              .next(musicBpm: 120, phraseIndex: ph)
              .slots
              .map((s) => s.onset)
              .toList(),
        );
      }
    });
  });

  group('OnsetFigure.expand', () {
    test('toute la banque est grammaticalement valide (plongées impaires)', () {
      for (final f in onsetFigureBank) {
        expect(f.plunges.every((d) => d.isOdd && d >= 1), isTrue,
            reason: '${f.id} : plongée paire');
        _expectValidGrammar(f.expand(), label: f.id);
      }
    });
  });
}

/// Vérifie la grammaire : toute frappe précédée d'une ancre, toute ancre suivie
/// d'une frappe (ancre unique = « 1 fois sur 2 »), hold seulement après
/// frappe/hold, et longueur de plongée impaire (nb de holds pair).
void _expectValidGrammar(List<SlotOnset> s, {String label = ''}) {
  expect(s.contains(SlotOnset.strike), isTrue, reason: '$label sans frappe');
  final n = s.length;
  for (var i = 0; i < n; i++) {
    final prev = s[(i - 1 + n) % n];
    final next = s[(i + 1) % n];
    if (s[i] == SlotOnset.strike) {
      expect(prev, SlotOnset.release, reason: '$label frappe sans ancre ($i)');
    }
    if (s[i] == SlotOnset.release) {
      expect(next, SlotOnset.strike, reason: '$label ancre non unique ($i)');
    }
    if (s[i] == SlotOnset.hold) {
      expect(prev == SlotOnset.strike || prev == SlotOnset.hold, isTrue,
          reason: '$label hold mal placé ($i)');
    }
  }
  for (var i = 0; i < n; i++) {
    if (s[i] != SlotOnset.strike) continue;
    var len = 1;
    var j = (i + 1) % n;
    while (s[j] == SlotOnset.hold && j != i) {
      len++;
      j = (j + 1) % n;
    }
    expect(len.isOdd, isTrue, reason: '$label plongée paire à $i (len $len)');
  }
}
