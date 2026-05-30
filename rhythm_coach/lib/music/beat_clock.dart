// Mode Music — horloge musicale (cf. `specs/music_mode.md` §4.1).
//
// Le `BeatClock` émet un [BeatTick] par battement ; le consommateur
// (`MusicSessionEngine`) réagit aux frontières de mesure / phrase via les
// drapeaux du tick plutôt qu'à des événements séparés.

/// Un battement de l'horloge. `beatIndex` est un compteur global depuis
/// l'ancre (le 1er tap). Les drapeaux disent si ce battement ouvre une
/// mesure / une phrase.
class BeatTick {
  /// Index global du battement depuis l'ancre (0-based).
  final int beatIndex;

  /// Index de la mesure (`beatIndex ~/ beatsPerBar`).
  final int barIndex;

  /// Position du battement dans la mesure (`0..beatsPerBar-1`).
  final int beatInBar;

  /// Index de la phrase (`beatIndex ~/ beatsPerPhrase`).
  final int phraseIndex;

  /// Vrai si ce battement ouvre une mesure (point de bascule naturel).
  final bool isBarStart;

  /// Vrai si ce battement ouvre une phrase.
  final bool isPhraseStart;

  /// Tempo courant (battements/minute).
  final double bpm;

  const BeatTick({
    required this.beatIndex,
    required this.barIndex,
    required this.beatInBar,
    required this.phraseIndex,
    required this.isBarStart,
    required this.isPhraseStart,
    required this.bpm,
  });
}

/// Source de tempo branchable. Implémentations : `TapTempoSource` (PR1),
/// `MicTempoSource` (PR2).
abstract class BeatClock {
  /// Flux des battements (broadcast).
  Stream<BeatTick> get ticks;

  /// Tempo courant, ou `null` tant qu'aucun tempo n'est établi.
  double? get bpm;

  /// Vrai quand l'horloge émet activement des ticks.
  bool get isRunning;

  /// Démarre l'émission (nécessite un tempo établi).
  void start();

  /// Arrête l'émission sans détruire l'état de tempo.
  void stop();

  /// Libère les ressources (timer, stream).
  void dispose();
}
