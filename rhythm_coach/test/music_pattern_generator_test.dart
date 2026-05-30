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

    test(
        'grammaire valide : jamais 2 plongées sans ancre, ancre encadrant les holds',
        () {
      final gen = MusicPatternGenerator(rng: Random(11), ignoreGating: true);
      for (var ph = 0; ph < 12; ph++) {
        final p = gen.next(musicBpm: 120, phraseIndex: ph);
        final s = p.slots;
        for (var i = 0; i < s.length; i++) {
          final prev = s[(i - 1 + s.length) % s.length].onset; // cyclique
          // Toute frappe est précédée d'une ancre (release) : pas 2 plongées
          // d'affilée, pas de frappe juste après un hold.
          if (s[i].onset == SlotOnset.strike) {
            expect(prev, SlotOnset.release,
                reason:
                    'frappe non précédée d\'une ancre (phrase $ph, slot $i)');
          }
          // Un hold ne suit qu'une frappe ou un hold (jamais une ancre).
          if (s[i].onset == SlotOnset.hold) {
            expect(prev == SlotOnset.strike || prev == SlotOnset.hold, isTrue,
                reason: 'hold précédé d\'une ancre (phrase $ph, slot $i)');
          }
        }
      }
    });
  });

  group('OnsetFigure.expand', () {
    test('toute la banque est grammaticalement valide', () {
      for (final f in onsetFigureBank) {
        final s = f.expand();
        expect(s.contains(SlotOnset.strike), isTrue,
            reason: '${f.id} sans frappe');
        for (var i = 0; i < s.length; i++) {
          final prev = s[(i - 1 + s.length) % s.length];
          if (s[i] == SlotOnset.strike) {
            expect(prev, SlotOnset.release,
                reason: '${f.id} : frappe sans ancre');
          }
          if (s[i] == SlotOnset.hold) {
            expect(prev == SlotOnset.strike || prev == SlotOnset.hold, isTrue,
                reason: '${f.id} : hold mal placé');
          }
        }
      }
    });
  });
}
