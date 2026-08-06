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

  /// Nombre de **boucles** complètes de la figure avant d'en régénérer une.
  /// On ne change qu'en **fin de boucle** (jamais au milieu d'un pattern).
  final int repeatLoops;

  final StreamController<SlotAction> _ctrl =
      StreamController<SlotAction>.broadcast();
  StreamSubscription<BeatTick>? _sub;

  BeatPattern? _pattern;
  int _cursor = 0;
  int _beatsPerSlot = 1;
  int _beatsSinceSlot = 0;
  int _loops = 0;
  Position _lastDepth = Position.head;

  MusicSessionEngine({required this.generator, this.repeatLoops = 4});

  Stream<SlotAction> get actions => _ctrl.stream;

  /// Figure courante — lue par l'UI (affichage du pattern).
  BeatPattern? get currentPattern => _pattern;

  /// Index du slot en cours de lecture (tête de lecture du pattern).
  int get cursor => _cursor;

  /// Nombre de battements par slot (1 en 1×, 2 en ½×) — pour la durée d'un slot.
  int get beatsPerSlot => _beatsPerSlot;

  /// Aperçu (lecture seule) des [count] prochains slots, pour l'anticipation
  /// visuelle. Suppose la figure courante répétée — ne régénère pas (la phrase
  /// suivante n'est pas encore connue). Vide tant qu'aucune figure n'existe.
  List<({SlotActionKind kind, Position depth})> peek(int count) {
    final p = _pattern;
    if (p == null) return const [];
    final out = <({SlotActionKind kind, Position depth})>[];
    var depth = _lastDepth;
    for (var i = 1; i <= count; i++) {
      final slot = p.slots[(_cursor + i) % p.slots.length];
      switch (slot.onset) {
        case SlotOnset.strike:
          depth = slot.to!;
          out.add((kind: SlotActionKind.strike, depth: depth));
        case SlotOnset.hold:
          out.add((kind: SlotActionKind.hold, depth: depth));
        case SlotOnset.release:
          out.add((kind: SlotActionKind.release, depth: p.anchor));
      }
    }
    return out;
  }

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
    if (_pattern == null) {
      _regenerate(tick);
      return _emit(tick); // 1ʳᵉ frappe de la 1ʳᵉ figure, sur le temps
    }
    // Cadence du slot : n'avance qu'une fois tous les [_beatsPerSlot] battements.
    if (++_beatsSinceSlot < _beatsPerSlot) return null;
    _beatsSinceSlot = 0;
    // Avance le curseur ; en **fin de boucle** seulement, on régénère après
    // [repeatLoops] boucles (jamais au milieu d'un pattern).
    if (_cursor + 1 >= _pattern!.slots.length) {
      _loops++;
      if (_loops >= repeatLoops) {
        _regenerate(tick);
        return _emit(tick);
      }
      _cursor = 0;
    } else {
      _cursor++;
    }
    return _emit(tick);
  }

  void _regenerate(BeatTick tick) {
    _pattern = generator.next(
      musicBpm: tick.bpm.round(),
      phraseIndex: tick.phraseIndex,
    );
    _cursor = 0;
    _beatsSinceSlot = 0;
    _loops = 0;
    final pb = _pattern!.bpm;
    _beatsPerSlot = pb <= 0 ? 1 : max(1, (tick.bpm / pb).round());
  }

  SlotAction _emit(BeatTick tick) {
    final slots = _pattern!.slots;
    final slot = slots[_cursor];
    return switch (slot.onset) {
      SlotOnset.strike => SlotAction(
          kind: SlotActionKind.strike,
          depth: _lastDepth = slot.to!,
          beatIndex: tick.beatIndex,
          bpm: tick.bpm,
          // Frappe qui amorce un hold (slot suivant = hold) → son de hold.
          sustained:
              slots[(_cursor + 1) % slots.length].onset == SlotOnset.hold,
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
