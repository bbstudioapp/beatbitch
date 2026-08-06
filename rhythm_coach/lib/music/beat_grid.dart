import 'beat_clock.dart';

/// Maths de grille (pure, testable) : convertit un temps écoulé en index de
/// battement et fabrique le [BeatTick] correspondant. Cf. `specs/music_mode.md`
/// §4.1.
class BeatGrid {
  final double bpm;

  /// Temps (ms, sur l'horloge interne de la source) du battement 0.
  final int anchorMs;

  final int beatsPerBar;
  final int barsPerPhrase;

  const BeatGrid({
    required this.bpm,
    required this.anchorMs,
    this.beatsPerBar = 4,
    this.barsPerPhrase = 4,
  });

  double get beatMs => 60000.0 / bpm;
  int get beatsPerPhrase => beatsPerBar * barsPerPhrase;

  /// Index du battement « en cours » à [ms] (peut être négatif avant l'ancre).
  int beatIndexAt(int ms) => ((ms - anchorMs) / beatMs).floor();

  /// Temps théorique du battement [i].
  double timeOfBeat(int i) => anchorMs + i * beatMs;

  BeatTick tickFor(int beatIndex) => BeatTick(
        beatIndex: beatIndex,
        barIndex: beatIndex ~/ beatsPerBar,
        beatInBar: beatIndex % beatsPerBar,
        phraseIndex: beatIndex ~/ beatsPerPhrase,
        isBarStart: beatIndex % beatsPerBar == 0,
        isPhraseStart: beatIndex % beatsPerPhrase == 0,
        bpm: bpm,
      );
}

/// Émetteur déterministe (pur) : à chaque [poll] avec le temps courant, rend
/// la liste des [BeatTick] des battements franchis depuis le dernier appel.
/// Rattrape plusieurs battements d'un coup si le poll est en retard, et
/// n'émet jamais deux fois le même battement.
class BeatScheduler {
  BeatGrid grid;
  int _lastEmittedBeat = -1;

  BeatScheduler(this.grid);

  List<BeatTick> poll(int nowMs) {
    final current = grid.beatIndexAt(nowMs);
    if (current <= _lastEmittedBeat) return const [];
    final out = <BeatTick>[];
    for (var b = _lastEmittedBeat + 1; b <= current; b++) {
      if (b < 0) continue; // rien avant l'ancre
      out.add(grid.tickFor(b));
    }
    _lastEmittedBeat = current;
    return out;
  }

  /// Re-cale le tempo (re-tap) sans rejouer les battements déjà émis.
  void retune(BeatGrid g, int nowMs) {
    grid = g;
    _lastEmittedBeat = g.beatIndexAt(nowMs);
  }
}
