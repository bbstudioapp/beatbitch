import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/beep_engine.dart';
import '../services/capability_service.dart';
import 'beat_pattern.dart';
import 'music_pattern_generator.dart';
import 'music_session_engine.dart';
import 'slot_action.dart';
import 'tap_tempo.dart';

/// Contrôleur autonome du mode Music (cf. `specs/music_mode.md`). Ne réutilise
/// **pas** le `SessionController` carrière : il câble simplement
/// `TapTempoSource` → `MusicSessionEngine` → `BeepEngine`.
///
/// Mapping audio des actions de slot (PR1) :
/// - `strike` → impact positionnel (`playPositionOnce`)
/// - `hold`   → overlay tenu (`playHoldOnce`)
/// - `release`→ muet (la remontée est silencieuse, cf. §5.1)
class MusicSessionController extends ChangeNotifier {
  final BeepEngine beep;
  final TapTempoSource _clock = TapTempoSource();
  late final MusicSessionEngine _engine;
  StreamSubscription<SlotAction>? _actionSub;

  MusicSessionController({required this.beep, CapabilityProfile? profile}) {
    _engine = MusicSessionEngine(
      generator: MusicPatternGenerator(profile: profile),
    );
    _actionSub = _engine.actions.listen(_onAction);
    _engine.attach(_clock);
  }

  double? get bpm => _clock.bpm;
  bool get isRunning => _clock.isRunning;
  bool get hasTempo => _clock.hasTempo;
  bool get isStable => _clock.isStable;
  int get tapCount => _clock.tapCount;

  /// Figure courante (pour l'affichage du pattern).
  BeatPattern? get currentPattern => _engine.currentPattern;

  /// Slot en cours de lecture (tête de lecture sur le pattern).
  int get currentSlot => _engine.cursor;

  /// Enregistre un tap (la joueuse tape le rythme de sa musique).
  void tap() {
    _clock.tap();
    notifyListeners();
  }

  /// Démarre l'émission (nécessite un tempo établi).
  void start() {
    if (!_clock.hasTempo) return;
    _clock.start();
    notifyListeners();
  }

  void stop() {
    _clock.stop();
    notifyListeners();
  }

  void _onAction(SlotAction a) {
    switch (a.kind) {
      case SlotActionKind.strike:
        beep.playPositionOnce(a.depth);
      case SlotActionKind.hold:
        beep.playHoldOnce(a.depth);
      case SlotActionKind.release:
        break; // remontée muette
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _engine.dispose();
    _clock.dispose();
    super.dispose();
  }
}
