// Library autonome — sous-système « fatigue de chaîne rythme ».
//
// Le rythme soutenu (steps `rhythm` consécutifs) doit être borné pour
// que la joueuse n'enchaîne pas 3 minutes de loop sans rupture. Le
// tracker porte le compteur muté à chaque step poussé et expose :
//   * `canChain()` — vrai s'il reste au moins `_minStepSeconds` de marge ;
//     le dispatcher s'en sert pour retirer `rhythm` des candidats au
//     tirage avant que `capDuration` n'ait à tronquer.
//   * `capDuration(dur)` — borne la durée d'un step rythme à la marge
//     restante (no-op si la marge couvre la durée demandée).
//   * `onStepPushed(mode, duration)` — appelé par `_trackPushedStep` à
//     chaque step émis : cumule pour `rhythm`, reset pour tout autre
//     mode (breath compris — c'est une vraie pause de souffle).
//
// Plus de méthode `reset()` : le tracker est **recréé** à chaque
// `generate()` (comme `_capClamps`, `_facade`, `_positionPickers`).
// Cette voie de composition explicite a remplacé l'ancien handle
// `gen: CareerSessionGenerator` : la facade et les sous-systèmes
// auxquels accédait le tracker (`gen._config`, `gen._capClamps`,
// `gen._state`) sont projetés en deux scalaires (`motionStreakComfort`,
// `motionStreakOverloadFactor`) et une référence sur `SessionRuntimeState`
// (pour lire `unlockedKeys` muté en cours de séance).
//
// Le cap effectif (`effectiveCapSeconds`) a deux régimes :
//   * Profil capacités renseigné (carrière) → `motion_streak.comfort` de
//     la joueuse (surchargé si `motion_streak` est l'axe poussé de la
//     séance), planché à `_capFloorSeconds` pour qu'une donnée
//     anormalement courte ne hache pas tout le rythme.
//   * Sinon (Custom, scénarios, profil neuf) → comportement historique :
//     `_capSeconds` (60 s), levé à virtuellement illimité par l'unlock
//     `rhythmHeadMidSustained` (milestone `intro_rhythm_sustained`).

import 'dart:math';

import '../../../models/session.dart';
import '../../models/unlock_key.dart';
import 'session_runtime_state.dart';

/// Tracker de la chaîne `rhythm` consécutive. Détient le compteur de
/// secondes cumulées, expose la marge restante et le cap effectif au
/// caller (le dispatcher pour `canChain()`, `RhythmRules.build` pour
/// `capDuration()`).
///
/// Recréé à chaque `generate()` (compteur naturellement à 0). Les
/// collaborateurs (`SessionRuntimeState` pour la lecture courante de
/// `unlockedKeys`, `motion_streak` comfort + overload factor projetés
/// par le générateur) sont passés au constructeur.
class RhythmChainTracker {
  RhythmChainTracker({
    required SessionRuntimeState state,
    required double? motionStreakComfort,
    required double motionStreakOverloadFactor,
  })  : _state = state,
        _motionStreakComfort = motionStreakComfort,
        _motionStreakOverloadFactor = motionStreakOverloadFactor;

  final SessionRuntimeState _state;
  final double? _motionStreakComfort;
  final double _motionStreakOverloadFactor;

  /// Durée cumulée (en secondes) des steps `rhythm` poussés
  /// consécutivement. Tout step d'un autre mode (breath compris) reset
  /// à 0.
  int _consecutiveSeconds = 0;

  /// Plafond (en secondes) de la chaîne `rhythm` consécutive en régime
  /// **historique** (profil capacités absent). Tant que
  /// `rhythmHeadMidSustained` n'est pas acquis, le générateur force une
  /// rupture au-delà ; la milestone `intro_rhythm_sustained` lève ce mur.
  static const int _capSeconds = 60;

  /// Borne basse du cap de chaîne rythme dérivé du profil — qu'une
  /// donnée `motion_streak` anormalement courte ne hache pas tout le
  /// rythme.
  static const int _capFloorSeconds = 24;

  /// Plancher de durée d'un step `rhythm` poussé via
  /// `_mapDifficultyToStep`. Sert à éviter qu'un step soit tronqué à
  /// 1-2 s par `capDuration` quand on est presque au cap. En dessous,
  /// le dispatcher retire `rhythm` des candidats au tirage via
  /// `canChain()`.
  static const int _minStepSeconds = 8;

  /// Cap effectif (en secondes) de la chaîne `rhythm` consécutive :
  /// régime profil-pilotant si `motion_streak` est renseigné dans le
  /// profil de capacités ; régime historique sinon.
  int get effectiveCapSeconds {
    final c = _motionStreakComfort;
    if (c != null) {
      final v = (c * _motionStreakOverloadFactor).round();
      return v < _capFloorSeconds ? _capFloorSeconds : v;
    }
    return _state.unlockedKeys.contains(UnlockKey.rhythmHeadMidSustained)
        ? 1 << 20 // de fait illimité
        : _capSeconds;
  }

  /// Vrai si on peut encore ajouter un step `rhythm` à la chaîne sans
  /// dépasser le cap.
  bool canChain() {
    return _consecutiveSeconds + _minStepSeconds <= effectiveCapSeconds;
  }

  /// Tronque la durée d'un step `rhythm` pour respecter le cap chaîne
  /// consécutive. No-op si la marge restante est suffisante.
  int capDuration(int dur) {
    final remaining = effectiveCapSeconds - _consecutiveSeconds;
    if (remaining <= 0) return dur; // canChain aurait dû filtrer
    return min(dur, remaining);
  }

  /// Met à jour le compteur après l'émission d'un step. Appelé par
  /// `_trackPushedStep` à chaque step poussé dans la séance.
  void onStepPushed(SessionMode mode, int? duration) {
    if (mode == SessionMode.rhythm) {
      _consecutiveSeconds += duration ?? 0;
    } else {
      _consecutiveSeconds = 0;
    }
  }
}
