import 'dart:math';

import '../models/career_level.dart';
import '../models/session_length_choice.dart';

/// Point d'extraction unique des paramètres de difficulté de carrière.
///
/// **Phase 19.1** : posé comme wrapper trivial sur [CareerLevel.forLevel]
/// (no-op fonctionnel, `resolve(level)` exposé pour Custom + tests).
///
/// **Phase 19.6** : le rewire sémantique introduit [resolveForCareer]
/// qui dérive les 4 paramètres depuis `(sessionsCompleted, lengthChoice)`
/// au lieu de `level`. Le `level` retourné est désormais un **synthLevel**
/// calculé (= `1 + sessionsCompleted / 2`, clampé à 30) qui sert de proxy
/// interne pour les call sites du générateur qui consomment encore un int
/// (BpmPacing, finalPicker, finishPhase, etc.).
///
/// La difficulté réelle dérive du `CapabilityProfile` **via les clamps
/// Phase 16** (`_clampToCapability`) — `maxDifficultyCap` reste le cap
/// moteur global, monté avec l'expérience joueuse pour ne pas plafonner
/// le moteur d'humiliation.
class CareerDifficultyResolver {
  const CareerDifficultyResolver._();

  /// Résout la config de difficulté pour un niveau donné. Délègue
  /// strictement à [CareerLevel.forLevel]. Conservé pour le Mode Custom
  /// (qui injecte un `level` virtuel mappé sur facile/normal/difficile/
  /// extrême) et les écrans de debug.
  static CareerLevel resolve(int level) => CareerLevel.forLevel(level);

  /// Résout la config de difficulté carrière depuis les compteurs
  /// d'investissement (sessions) et le palier de durée choisi.
  ///
  /// Mappings (Phase 19.6, calibrés pour rester équivalents à l'ancien
  /// `level = 1 + sessions/2` jusqu'aux plafonds) :
  /// - `maxDifficultyCap = min(0.25 + 0.025 × sessions, 1.0)`
  /// - `regenEndMultiplier = min(1.35 + 0.075 × sessions, 3.0)`
  /// - `boostsCount` : 2 (≤ 6 sessions) / 3 (≤ 14) / 4 (≤ 24) / 5 (25+)
  ///   + 1 si palier `longue` (apothéose étoffée)
  /// - `durationSeconds = lengthChoice.durationSeconds` (cf. Phase 19.3)
  /// - `level = synthLevel = min(1 + sessions/2, 30)` — proxy interne
  static CareerLevel resolveForCareer({
    required int sessionsCompleted,
    required SessionLengthChoice lengthChoice,
  }) {
    return CareerLevel(
      level: _synthLevelFor(sessionsCompleted),
      maxDifficultyCap: _maxDifficultyCapFor(sessionsCompleted),
      regenEndMultiplier: _regenEndMultiplierFor(sessionsCompleted),
      durationSeconds: lengthChoice.durationSeconds,
      boostsCount: _boostsCountFor(sessionsCompleted, lengthChoice),
    );
  }

  /// SynthLevel = proxy entier pour les call sites qui consomment encore
  /// un `level` (BpmPacing, gates de phrase, etc.). 1 → 30, monte par
  /// tranches de 2 sessions.
  static int _synthLevelFor(int sessionsCompleted) {
    final n = sessionsCompleted < 0 ? 0 : sessionsCompleted;
    return min(1 + n ~/ 2, 30);
  }

  static double _maxDifficultyCapFor(int sessionsCompleted) {
    final n = sessionsCompleted < 0 ? 0 : sessionsCompleted;
    return min(0.25 + 0.025 * n, 1.0);
  }

  static double _regenEndMultiplierFor(int sessionsCompleted) {
    final n = sessionsCompleted < 0 ? 0 : sessionsCompleted;
    return min(1.35 + 0.075 * n, 3.0);
  }

  static int _boostsCountFor(
    int sessionsCompleted,
    SessionLengthChoice lengthChoice,
  ) {
    final n = sessionsCompleted < 0 ? 0 : sessionsCompleted;
    int base;
    if (n <= 6) {
      base = 2;
    } else if (n <= 14) {
      base = 3;
    } else if (n <= 24) {
      base = 4;
    } else {
      base = 5;
    }
    // Bonus longue : apothéose étoffée pour matcher les 45 min de séance.
    if (lengthChoice == SessionLengthChoice.longue) {
      base = min(base + 1, 6);
    }
    return base;
  }
}
