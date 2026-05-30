import 'dart:math';

import '../models/session_step.dart' show Position;
import '../services/capability_service.dart';
import 'beat_pattern.dart';
import 'depth_contour.dart';
import 'music_capability_bounds.dart';
import 'onset_figures.dart';

/// Générateur live d'une figure de mesure pour le mode Music
/// (cf. `specs/music_mode.md` §4.2 / §5 / §6).
///
/// Fonction (quasi) pure : une figure onset piochée dans la banque + un contour
/// de profondeur généré, le tout borné par le profil de capacités et calé sur
/// le tempo de la musique. Pas d'audio, pas d'horloge ici — uniquement la
/// production de [BeatPattern].
class MusicPatternGenerator {
  final MusicCapabilityBounds bounds;
  final Random rng;
  final bool ignoreGating;

  MusicPatternGenerator({
    CapabilityProfile? profile,
    Random? rng,
    this.ignoreGating = false,
  })  : bounds = MusicCapabilityBounds(profile, ignoreGating: ignoreGating),
        rng = rng ?? Random();

  /// Ancre `from` fixe en PR1 (la remontée se fait toujours vers `head`).
  static const Position _anchor = Position.head;

  /// Génère la figure de la mesure courante.
  ///
  /// [musicBpm] : tempo détecté/tapé de la musique.
  /// [phraseIndex] : n° de phrase (≥ 0) — pilote l'escalade dans les bornes.
  BeatPattern next({required int musicBpm, required int phraseIndex}) {
    // Profondeur visée : démarre à `mid`, +1 cran toutes les 2 phrases, bornée
    // par ce que la joueuse a prouvé (`rhythmDepthMax`).
    final maxDepth = bounds.maxDepth();
    // En debug (ignoreGating) on vise direct le plus profond (pas d'escalade)
    // pour voir tout de suite la variété de profondeur.
    var targetIdx = ignoreGating
        ? maxDepth.index
        : (Position.mid.index + phraseIndex ~/ 2)
            .clamp(Position.mid.index, maxDepth.index);

    // Mapping BPM : multiple musical (½×/1×/2×) sous le plafond de la
    // profondeur visée. Soupape : si même ½× dépasse, on réduit la profondeur
    // d'un cran (un cran moins profond = plafond BPM plus haut).
    int bpm;
    while (true) {
      final ceil = bounds.bpmCeilFor(Position.values[targetIdx]);
      final m = _fitMultiple(musicBpm, ceil);
      if (m != null) {
        bpm = (musicBpm * m).round();
        break;
      }
      if (targetIdx > Position.mid.index) {
        targetIdx--;
        continue;
      }
      // Plancher `mid` atteint et toujours trop rapide : on ralentit au
      // plafond connu (ou au tempo brut faute de donnée).
      bpm = bounds.bpmCeilFor(Position.values[targetIdx]) ?? musicBpm;
      break;
    }
    final targetDepth = Position.values[targetIdx];

    // Figure onset gatée par niveau (monte avec la phrase ; tout en debug).
    final maxLevel = ignoreGating ? 3 : (1 + phraseIndex ~/ 2).clamp(1, 3);
    final pool = onsetFigureBank.where((f) => f.level <= maxLevel).toList();
    final figure = pool[rng.nextInt(pool.length)];

    // Contour de profondeur pour les frappes de la figure.
    final family =
        ContourFamily.values[rng.nextInt(ContourFamily.values.length)];
    final strikeCount =
        figure.onsets.where((o) => o == SlotOnset.strike).length;
    final depths = DepthContour.generate(
      strikeCount: strikeCount,
      anchor: _anchor,
      maxDepth: targetDepth,
      family: family,
      rng: rng,
    );

    // Assemblage des slots + soupape hold (un hold trop long pour l'endurance
    // prouvée retombe en release).
    final holdSecPerSlot = 60.0 / bpm;
    final slots = <BeatSlot>[];
    var si = 0;
    Position? lastTo;
    for (final o in figure.onsets) {
      switch (o) {
        case SlotOnset.strike:
          lastTo = depths[si++];
          slots.add(BeatSlot.strike(lastTo));
        case SlotOnset.hold:
          final hs = lastTo == null ? null : bounds.holdSecondsFor(lastTo);
          if (lastTo == null || (hs != null && holdSecPerSlot > hs)) {
            slots.add(const BeatSlot.release());
          } else {
            slots.add(const BeatSlot.hold());
          }
        case SlotOnset.release:
          slots.add(const BeatSlot.release());
      }
    }

    return BeatPattern(slots: slots, anchor: _anchor, bpm: bpm);
  }

  /// Plus grand multiple ∈ {2, 1, ½} tel que `musicBpm × m ≤ ceil`.
  /// `null` si aucun ne passe (même ½× est trop rapide). Sans plafond
  /// (`ceil == null`) on garde le tempo brut (1×).
  double? _fitMultiple(int musicBpm, int? ceil) {
    if (ceil == null) return 1.0;
    for (final m in const [2.0, 1.0, 0.5]) {
      if (musicBpm * m <= ceil) return m;
    }
    return null;
  }
}
