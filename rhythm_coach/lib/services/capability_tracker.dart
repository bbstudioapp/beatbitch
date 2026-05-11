import 'package:flutter/foundation.dart';

import '../models/session.dart';
import '../models/session_step.dart';
import 'capability_axis.dart';
import 'capability_service.dart';
import 'saliva_engine.dart';

/// Suivi **live** du profil de capacités sur une session carrière.
///
/// Phase 1 — télémétrie pure : on accumule des streaks à la seconde, on fige
/// des records de durée / vitesse / profondeur, on snapshot des plafonds sur
/// fail, et on produit un [SessionCapabilityReport] à la fin. Aucun pilotage
/// du générateur n'en dépend encore. Le tracker n'est câblé QUE pour les
/// sessions carrière — Custom et scénarios JSON ne l'instancient pas.
///
/// Intégration côté `SessionController` :
/// - `onSessionStart()` au `start()` (idempotent, reset complet) ;
/// - `onStepApplied(...)` à chaque step de config appliqué dans `_checkSteps`
///   (et à `_restorePreviousLoop`) — c'est l'événement « changement de
///   config » ;
/// - `onTickSecond(...)` une fois par seconde écoulée (depuis
///   `_accrueHoldSecond`) ;
/// - `onSalivaOverflow()` quand un débordement de salive est traité ;
/// - `onFail()` à l'appui sur FAIL — fige les plafonds, vide les streaks ;
/// - `finalizeReport()` au `_finish` — clôt proprement les streaks encore
///   actifs et retourne le rapport à committer.
///
/// Simplifications assumées en Phase 1 (à raffiner quand ces axes piloteront
/// vraiment, cf. spec) :
/// - les changements de config en moins d'une seconde sont invisibles
///   (les steps font ≥ ~7 s en pratique) ;
/// - `breath.min_dose` est enregistrée dès la reprise, sans attendre de
///   confirmer « pas de fail immédiat » ;
/// - les franchissements `crossings_lifetime` sont estimés à `bpm/60` par
///   seconde sur un pattern franchissant, l'entrée d'un hold/beg profond
///   n'est pas comptée à part ;
/// - les axes dérivés `rhythm.to[X]` / `rhythm.from[X]` ne sont pas
///   matérialisés — P2/P3 (`engagement`/`apnée`) couvrent l'essentiel ;
/// - les fenêtres BPM lick et les 10 paires `rhythm.pair[from→to]` ne sont
///   pas suivies (enregistrées seulement, faible valeur en Phase 1) ;
/// - un `breath` recovery du flow fail n'est jamais vu (le ticker est arrêté
///   pendant le fail), donc jamais compté comme dose.
class CapabilityTracker {
  /// Durée min pour qu'un record de profondeur / vitesse compte (§11
  /// `kSustainedRecordSeconds`).
  static const int sustainedRecordSeconds = 3;

  // ── état « config courante » ──────────────────────────────────────────
  _ConfigState? _config;
  int _configSeconds = 0;
  bool _configRecordsLogged = false;

  // ── streaks live (secondes) ───────────────────────────────────────────
  double _apnea = 0;
  double _engagement = 0;
  double _motion = 0;
  double _holdThroat = 0;
  double _holdFull = 0;
  double _noswallow = 0;
  bool _noswallowHadOverflow = false;
  double _biffleStreak = 0;
  double _lickStreak = 0;
  double _handStreak = 0;
  double _effortNoBreath = 0;

  // ── divers ────────────────────────────────────────────────────────────
  double _crossingsAccum = 0;

  // ── rapport en construction ───────────────────────────────────────────
  final Map<CapabilityAxis, double> _reached = {};
  final Map<CapabilityAxis, double> _ceilings = {};

  /// Plafonds figés sur les appuis FAIL de la session en cours (§6) — vue
  /// non modifiable, lue par `SessionController.capabilitySessionCeilings`
  /// pour borner les régénérations en cours de séance. Vide tant qu'aucun
  /// fail n'a eu lieu.
  Map<CapabilityAxis, double> get sessionCeilings =>
      Map.unmodifiable(_ceilings);

  /// Reset complet — appelé au démarrage d'une session (le tracker est créé
  /// frais par session, mais `start()` peut être rejoué depuis idle/finished).
  void onSessionStart() {
    _config = null;
    _configSeconds = 0;
    _configRecordsLogged = false;
    _apnea = _engagement = _motion = 0;
    _holdThroat = _holdFull = 0;
    _noswallow = 0;
    _noswallowHadOverflow = false;
    _biffleStreak = _lickStreak = _handStreak = _effortNoBreath = 0;
    _crossingsAccum = 0;
    _reached.clear();
    _ceilings.clear();
  }

  /// Un step de config vient d'être appliqué (changement de mode/profondeur/
  /// BPM). Clôt les streaks que la nouvelle config casse, puis bascule.
  void onStepApplied({
    required SessionMode mode,
    Position? from,
    Position? to,
    int? bpm,
    int? duration,
  }) {
    final next = _ConfigState(
      mode: mode,
      from: from,
      to: to,
      bpm: bpm,
    );
    final prev = _config;

    // Clôtures de streaks : un streak qui se casse « proprement » (= pas par
    // un fail) est enregistré comme record.
    if (!next.airless) _flushStreak(CapabilityAxis.gorgeApneeStreak, _apnea);
    if (!next.engagesThroat) {
      _flushStreak(CapabilityAxis.gorgeEngagementStreak, _engagement);
    }
    if (!next.isMotion) {
      _flushStreak(CapabilityAxis.rhythmMotionStreak, _motion);
    }
    if (next.heldPos != Position.throat) {
      _flushStreak(CapabilityAxis.holdThroatStreak, _holdThroat);
    }
    if (next.heldPos != Position.full) {
      _flushStreak(CapabilityAxis.holdFullStreak, _holdFull);
    }
    if (!next.isBiffle) {
      _flushStreak(CapabilityAxis.biffleStreak, _biffleStreak);
    }
    if (!next.isLick) _flushStreak(CapabilityAxis.lickStreak, _lickStreak);
    if (!next.isHand) _flushStreak(CapabilityAxis.handStreak, _handStreak);

    // Souffle : un step `breath` casse l'effort-sans-pause. La dose mini =
    // durée effectivement écoulée du `breath` qu'on quitte.
    if (next.isBreath) {
      _flushStreak(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
      _effortNoBreath = 0;
    }
    if ((prev?.isBreath ?? false) && !next.isBreath && _configSeconds > 0) {
      _recordReached(
        CapabilityAxis.breathMinDose,
        _configSeconds.toDouble(),
        minimize: true,
      );
    }

    // Reset des streaks réellement cassés (ceux laissés intacts cumulent).
    if (!next.airless) _apnea = 0;
    if (!next.engagesThroat) _engagement = 0;
    if (!next.isMotion) _motion = 0;
    if (next.heldPos != Position.throat) _holdThroat = 0;
    if (next.heldPos != Position.full) _holdFull = 0;
    if (!next.isBiffle) _biffleStreak = 0;
    if (!next.isLick) _lickStreak = 0;
    if (!next.isHand) _handStreak = 0;

    _config = next;
    _configSeconds = 0;
    _configRecordsLogged = false;
  }

  /// Une seconde de session vient de s'écouler. [swallowMode] = état sticky
  /// effectif au moment du tick (peut avoir changé via un step text-only).
  void onTickSecond({required SwallowMode swallowMode}) {
    // Streak « sans avaler » : indépendant de la config, piloté par le
    // toggle. Se casse quand l'avalement est ré-autorisé.
    if (swallowMode == SwallowMode.forbidden) {
      _noswallow += 1;
    } else if (_noswallow > 0) {
      if (!_noswallowHadOverflow) {
        _flushStreak(CapabilityAxis.noswallowStreak, _noswallow);
      }
      _noswallow = 0;
      _noswallowHadOverflow = false;
    }

    final c = _config;
    if (c == null) return;
    _configSeconds += 1;

    if (c.airless) _apnea += 1;
    if (c.engagesThroat) _engagement += 1;
    if (c.isMotion) _motion += 1;
    if (c.heldPos == Position.throat) _holdThroat += 1;
    if (c.heldPos == Position.full) _holdFull += 1;
    if (c.isBiffle) _biffleStreak += 1;
    if (c.isLick) _lickStreak += 1;
    if (c.isHand) _handStreak += 1;
    if (!c.isBreath) _effortNoBreath += 1;
    if (c.isCrossingPattern) _crossingsAccum += (c.bpm ?? 60) / 60.0;

    // Records de profondeur / vitesse : ne comptent qu'une fois la config
    // tenue ≥ N s. On les fige au passage du seuil (constants dans un step).
    if (!_configRecordsLogged && _configSeconds >= sustainedRecordSeconds) {
      _configRecordsLogged = true;
      _logSustainedConfigRecords(c);
    }
  }

  /// Un débordement de salive a été traité — le streak « sans avaler » en
  /// cours ne pourra plus produire de record propre (un débordement = elle
  /// n'a pas tenu).
  void onSalivaOverflow() {
    if (_noswallow > 0) _noswallowHadOverflow = true;
  }

  /// Appui sur FAIL : on fige la valeur live de tous les streaks actifs dans
  /// les plafonds de session (`sessionCeilings`), puis on vide tout — un
  /// streak interrompu par un fail ne devient jamais un record (cf. §3/§6).
  void onFail() {
    _ceilFrom(CapabilityAxis.gorgeApneeStreak, _apnea);
    _ceilFrom(CapabilityAxis.gorgeEngagementStreak, _engagement);
    _ceilFrom(CapabilityAxis.rhythmMotionStreak, _motion);
    _ceilFrom(CapabilityAxis.holdThroatStreak, _holdThroat);
    _ceilFrom(CapabilityAxis.holdFullStreak, _holdFull);
    _ceilFrom(CapabilityAxis.biffleStreak, _biffleStreak);
    _ceilFrom(CapabilityAxis.lickStreak, _lickStreak);
    _ceilFrom(CapabilityAxis.handStreak, _handStreak);
    _ceilFrom(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
    _ceilFrom(CapabilityAxis.noswallowStreak, _noswallow);

    _apnea = _engagement = _motion = 0;
    _holdThroat = _holdFull = 0;
    _noswallow = 0;
    _noswallowHadOverflow = false;
    _biffleStreak = _lickStreak = _handStreak = _effortNoBreath = 0;
    _config = null;
    _configSeconds = 0;
    _configRecordsLogged = false;
  }

  /// La session s'est terminée proprement : on clôt tous les streaks encore
  /// actifs (ils comptent — elle les a tenus jusqu'au bout) et on rend le
  /// rapport à committer.
  SessionCapabilityReport finalizeReport() {
    _flushStreak(CapabilityAxis.gorgeApneeStreak, _apnea);
    _flushStreak(CapabilityAxis.gorgeEngagementStreak, _engagement);
    _flushStreak(CapabilityAxis.rhythmMotionStreak, _motion);
    _flushStreak(CapabilityAxis.holdThroatStreak, _holdThroat);
    _flushStreak(CapabilityAxis.holdFullStreak, _holdFull);
    _flushStreak(CapabilityAxis.biffleStreak, _biffleStreak);
    _flushStreak(CapabilityAxis.lickStreak, _lickStreak);
    _flushStreak(CapabilityAxis.handStreak, _handStreak);
    _flushStreak(CapabilityAxis.effortNoBreathStreak, _effortNoBreath);
    if (_noswallow > 0 && !_noswallowHadOverflow) {
      _flushStreak(CapabilityAxis.noswallowStreak, _noswallow);
    }
    final crossings = _crossingsAccum.floor();
    if (crossings > 0) {
      _reached[CapabilityAxis.gorgeCrossingsLifetime] = crossings.toDouble();
    }
    final report = SessionCapabilityReport(
      reached: Map.unmodifiable(_reached),
      sessionCeilings: Map.unmodifiable(_ceilings),
    );
    if (kDebugMode && !report.isEmpty) {
      debugPrint('[Capability] report reached=${report.reached} '
          'ceilings=${report.sessionCeilings}');
    }
    return report;
  }

  // ── interne ───────────────────────────────────────────────────────────

  void _logSustainedConfigRecords(_ConfigState c) {
    if (c.mode == SessionMode.rhythm) {
      final to = c.to;
      if (to != null) {
        _recordReached(CapabilityAxis.rhythmDepthMax, to.index.toDouble());
        final bpm = (c.bpm ?? 60).toDouble();
        final band = _rhythmBand(to);
        _recordReached(band.$1, bpm); // ceiling
        _recordReached(band.$2, bpm, minimize: true); // floor
      }
    } else if (c.mode == SessionMode.lick) {
      final to = c.to;
      if (to != null) {
        _recordReached(CapabilityAxis.lickDepthMax, to.index.toDouble());
      }
    }
    if (c.isCrossingPattern) {
      final bpm = (c.bpm ?? 60).toDouble();
      if (c.to == Position.throat) {
        _recordReached(CapabilityAxis.gorgeCrossingsBpmThroat, bpm);
      } else if (c.to == Position.full) {
        _recordReached(CapabilityAxis.gorgeCrossingsBpmFull, bpm);
      }
    }
    if (c.isBiffle) {
      _recordReached(CapabilityAxis.biffleBpmMax, (c.bpm ?? 80).toDouble());
    }
  }

  /// (ceilingAxis, floorAxis) pour la bande de profondeur de `to`.
  (CapabilityAxis, CapabilityAxis) _rhythmBand(Position to) {
    if (to.index <= Position.mid.index) {
      return (
        CapabilityAxis.rhythmBpmCeilShallow,
        CapabilityAxis.rhythmBpmFloorShallow
      );
    }
    if (to == Position.throat) {
      return (
        CapabilityAxis.rhythmBpmCeilThroat,
        CapabilityAxis.rhythmBpmFloorThroat
      );
    }
    return (
      CapabilityAxis.rhythmBpmCeilFull,
      CapabilityAxis.rhythmBpmFloorFull
    );
  }

  void _flushStreak(CapabilityAxis axis, double value) {
    if (value <= 0) return;
    _recordReached(axis, value);
  }

  void _recordReached(CapabilityAxis axis, double value,
      {bool minimize = false}) {
    final current = _reached[axis];
    if (current == null) {
      _reached[axis] = value;
    } else if (minimize) {
      if (value < current) _reached[axis] = value;
    } else {
      if (value > current) _reached[axis] = value;
    }
  }

  void _ceilFrom(CapabilityAxis axis, double value) {
    if (value <= 0) return;
    final current = _ceilings[axis];
    if (current == null || value < current) _ceilings[axis] = value;
  }
}

/// État dérivé d'un step de config — porte les prédicats de classification
/// du modèle « gorge » et des axes rythme. **Hand est exclu de tous les axes
/// de difficulté** : il ne contribue qu'à `hand.streak`.
@immutable
class _ConfigState {
  final SessionMode mode;
  final Position? from;
  final Position? to;
  final int? bpm;

  const _ConfigState({
    required this.mode,
    this.from,
    this.to,
    this.bpm,
  });

  /// Composantes rythmées prises en compte par le modèle gorge (hand exclu).
  bool get _isRhythmic =>
      mode == SessionMode.rhythm || mode == SessionMode.lick;

  /// Position « tenue » d'un hold/beg (convention uniforme : `to`, repli sur
  /// `from` pour les begs ancrés des scénarios JSON). `null` pour tout autre
  /// mode (rien n'occupe la gorge).
  Position? get heldPos => (mode == SessionMode.hold || mode == SessionMode.beg)
      ? (to ?? from)
      : null;

  bool get isBreath => mode == SessionMode.breath;
  bool get isBiffle => mode == SessionMode.biffle;
  bool get isLick => mode == SessionMode.lick;
  bool get isHand => mode == SessionMode.hand;

  /// Mouvement rythmé ininterrompu = rhythm OU lick (hand exclu).
  bool get isMotion => _isRhythmic;

  /// P2 — la gorge est en jeu : hold/beg ≥ throat, ou rhythm/lick `to ≥ throat`.
  bool get engagesThroat {
    final h = heldPos;
    if (h != null && h.index >= Position.throat.index) return true;
    final t = to;
    return _isRhythmic && t != null && t.index >= Position.throat.index;
  }

  /// P3 — zéro fenêtre de respiration : hold/beg ≥ throat, ou rhythm/lick
  /// `from ≥ throat` (stroke `throat↔full`). Un `mid→full` n'est PAS airless
  /// (elle respire au point haut à chaque beat).
  bool get airless {
    final h = heldPos;
    if (h != null && h.index >= Position.throat.index) return true;
    final f = from;
    return _isRhythmic && f != null && f.index >= Position.throat.index;
  }

  /// P1 — pattern franchissant : rhythm/lick avec `from ≤ mid` ET `to ≥ throat`.
  bool get isCrossingPattern {
    final f = from;
    final t = to;
    return _isRhythmic &&
        f != null &&
        t != null &&
        f.index <= Position.mid.index &&
        t.index >= Position.throat.index;
  }
}
