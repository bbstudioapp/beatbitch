import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/session_step.dart' show Position;
import '../services/beep_engine.dart';
import '../services/capability_service.dart' show CapabilityProfile;
import 'beat_clock.dart';
import 'beat_pattern.dart';
import 'mic_capture.dart';
import 'mic_tempo_source.dart';
import 'music_pattern_generator.dart';
import 'music_session_engine.dart';
import 'slot_action.dart';
import 'tap_tempo.dart';

/// Contrôleur autonome du mode Music (cf. `specs/music_mode.md`). Câble une
/// source de tempo (**tap** ou **micro**) → `MusicSessionEngine` → `BeepEngine`.
///
/// Mapping audio des actions de slot :
/// - frappe simple → impact positionnel (`playPositionOnce`)
/// - frappe amorçant un hold → overlay tenu (`playHoldOnce`), 1 fois
/// - hold (temps suivants) → muet
/// - ancre (`release`) → tick léger (`playPositionOnce(tip)`)
class MusicSessionController extends ChangeNotifier {
  final BeepEngine beep;

  /// Vraie pour la source **micro** (détection auto), fausse pour le **tap**.
  final bool useMic;

  late final BeatClock _clock;
  TapTempoSource? _tap;
  MicTempoSource? _mic;
  MicCapture? _capture;

  late final MusicSessionEngine _engine;
  StreamSubscription<SlotAction>? _actionSub;

  /// Fenêtre de gating (ms) appliquée au micro autour de chaque bip joué.
  static const int _gateMs = 70;

  MusicSessionController({
    required this.beep,
    CapabilityProfile? profile,
    bool ignoreGating = false,
    this.useMic = false,
  }) {
    if (useMic) {
      _mic = MicTempoSource();
      _capture = MicCapture();
      _clock = _mic!;
    } else {
      _tap = TapTempoSource();
      _clock = _tap!;
    }
    _engine = MusicSessionEngine(
      generator: MusicPatternGenerator(
        profile: profile,
        ignoreGating: ignoreGating,
      ),
    );
    _actionSub = _engine.actions.listen(_onAction);
    _engine.attach(_clock);
  }

  double? get bpm => _clock.bpm;
  bool get isRunning => _clock.isRunning;

  /// Micro : vrai pendant l'intro (écoute jusqu'au verrou du tempo).
  bool get isCalibrating => _mic?.isCalibrating ?? false;

  // Spécifiques au tap.
  bool get hasTempo => _tap?.hasTempo ?? false;
  bool get isStable => _tap?.isStable ?? false;
  int get tapCount => _tap?.tapCount ?? 0;

  /// Figure courante (pour l'affichage du pattern).
  BeatPattern? get currentPattern => _engine.currentPattern;

  /// Slot en cours de lecture (tête de lecture sur le pattern).
  int get currentSlot => _engine.cursor;

  /// Durée d'un slot (pour animer la tête de lecture). `null` sans tempo.
  Duration? get slotInterval {
    final b = _clock.bpm;
    if (b == null || b <= 0) return null;
    return Duration(milliseconds: (_engine.beatsPerSlot * 60000 / b).round());
  }

  /// Tap (mode tap uniquement).
  void tap() {
    _tap?.tap();
    notifyListeners();
  }

  /// Démarre. Tap : nécessite un tempo établi. Micro : lance la capture
  /// (demande la permission) ; retourne `false` si la permission est refusée.
  Future<bool> start() async {
    if (useMic) {
      final ok = await _capture!.start(_mic!.feedPcm);
      notifyListeners();
      return ok;
    }
    if (!_tap!.hasTempo) return false;
    _tap!.start();
    notifyListeners();
    return true;
  }

  void stop() {
    if (useMic) {
      _capture!.stop();
    } else {
      _tap!.stop();
    }
    notifyListeners();
  }

  void _onAction(SlotAction a) {
    switch (a.kind) {
      case SlotActionKind.strike:
        if (a.sustained) {
          beep.playHoldOnce(a.depth);
        } else {
          beep.playPositionOnce(a.depth);
        }
      case SlotActionKind.hold:
        break; // temps de hold suivants : muets
      case SlotActionKind.release:
        beep.playPositionOnce(Position.tip); // l'ancre sonne (tick léger)
    }
    // Gating : on vient de jouer un bip → ignorer le micro un court instant.
    _mic?.gate(_gateMs);
    notifyListeners();
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    _engine.dispose();
    _capture?.dispose();
    _clock.dispose();
    super.dispose();
  }
}
