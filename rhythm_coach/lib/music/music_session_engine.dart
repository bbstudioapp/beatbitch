import 'dart:async';
import 'dart:math';

import '../models/session_step.dart' show Position;
import 'beat_clock.dart';
import 'beat_pattern.dart';
import 'music_pattern_generator.dart';
import 'slot_action.dart';

/// Générateur live câblé à l'horloge (cf. `specs/music_mode.md` §4.2).
///
/// S'abonne au flux de [BeatTick], régénère un [BeatPattern] à chaque nouvelle
/// **phrase** (via [MusicPatternGenerator]), et traduit chaque battement en
/// une [SlotAction]. Aucun audio ici : le binding sonore consomme `actions`.
///
/// Alignement slots ↔ battements (décision PR1) : 1 slot = 1 battement en 1× ;
/// quand le générateur a dû ralentir (`pattern.bpm < musicBpm`, soupape ½×),
/// le curseur n'avance qu'un slot tous les `beatsPerSlot` battements — les
/// frappes profondes s'espacent au lieu de retempo l'audio. Le double-temps
/// (sub-battement) est reporté (PR3).
class MusicSessionEngine {
  final MusicPatternGenerator generator;

  final StreamController<SlotAction> _ctrl =
      StreamController<SlotAction>.broadcast();
  StreamSubscription<BeatTick>? _sub;

  BeatPattern? _pattern;
  int _cursor = 0;
  int _beatsPerSlot = 1;
  int _beatsSinceSlot = 0;
  Position _lastDepth = Position.head;

  MusicSessionEngine({required this.generator});

  Stream<SlotAction> get actions => _ctrl.stream;

  /// Figure courante — lue par l'UI (courbe de profondeur).
  BeatPattern? get currentPattern => _pattern;

  /// Branche le moteur sur une horloge : chaque battement produit (ou non) une
  /// action poussée dans [actions].
  void attach(BeatClock clock) {
    _sub = clock.ticks.listen((t) {
      final a = onBeat(t);
      if (a != null) _ctrl.add(a);
    });
  }

  /// Cœur testable. Traduit un battement en [SlotAction], ou `null` sur les
  /// battements intercalaires quand un slot dure plusieurs battements (½×).
  SlotAction? onBeat(BeatTick tick) {
    final fresh = _pattern == null;
    if (fresh || tick.isPhraseStart) {
      _regenerate(tick);
      return _emit(tick); // 1ʳᵉ frappe de la nouvelle figure, sur le temps
    }
    // Cadence du slot : n'avance qu'une fois tous les [_beatsPerSlot] battements.
    if (++_beatsSinceSlot < _beatsPerSlot) return null;
    _beatsSinceSlot = 0;
    _cursor = (_cursor + 1) % _pattern!.slots.length;
    return _emit(tick);
  }

  void _regenerate(BeatTick tick) {
    _pattern = generator.next(
      musicBpm: tick.bpm.round(),
      phraseIndex: tick.phraseIndex,
    );
    _cursor = 0;
    _beatsSinceSlot = 0;
    final pb = _pattern!.bpm;
    _beatsPerSlot = pb <= 0 ? 1 : max(1, (tick.bpm / pb).round());
  }

  SlotAction _emit(BeatTick tick) {
    final slot = _pattern!.slots[_cursor];
    return switch (slot.onset) {
      SlotOnset.strike => SlotAction(
          kind: SlotActionKind.strike,
          depth: _lastDepth = slot.to!,
          beatIndex: tick.beatIndex,
          bpm: tick.bpm,
        ),
      SlotOnset.hold => SlotAction(
          kind: SlotActionKind.hold,
          depth: _lastDepth,
          beatIndex: tick.beatIndex,
          bpm: tick.bpm,
        ),
      SlotOnset.release => SlotAction(
          kind: SlotActionKind.release,
          depth: _pattern!.anchor,
          beatIndex: tick.beatIndex,
          bpm: tick.bpm,
        ),
    };
  }

  void dispose() {
    _sub?.cancel();
    _ctrl.close();
  }
}
