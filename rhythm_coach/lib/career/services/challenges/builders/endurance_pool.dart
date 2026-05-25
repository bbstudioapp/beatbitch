import 'dart:math';

import '../../../../models/session.dart' show SessionMode;
import '../../../../models/session_step.dart';
import '../../../../services/capability_axis.dart';
import '../../../../services/capability_service.dart';
import '../../../models/unlock_key.dart';

/// Descripteur d'un sous-segment d'un défi streaming. Le builder en
/// matérialise un en `SessionStep` à chaque appel `next()`.
///
/// Pour les segments rythmés (`rhythm`/`lick`), `from` < `to` strict
/// (convention rythme). Pour les holds, `from == to`.
class EnduranceDescriptor {
  final SessionMode mode;
  final Position from;
  final Position to;

  const EnduranceDescriptor({
    required this.mode,
    required this.from,
    required this.to,
  });

  bool sameKindAs(EnduranceDescriptor? other) {
    if (other == null) return false;
    return mode == other.mode && from == other.from && to == other.to;
  }
}

/// Calcule le `to` max autorisé pour un sous-step rythmé en endurance,
/// en croisant les unlocks (`throatPulse` / `fullPulse`) et la
/// profondeur prouvée du profil (`rhythm.depth_max.comfort`).
///
/// Retourne `Position.mid.index` (socle de base) si rien n'est débloqué
/// ou si le profil n'a pas encore poussé la profondeur. Sert au pool de
/// descriptors rythmés.
int resolveMaxDepthIdx({
  required Set<UnlockKey> unlocks,
  required CapabilityProfile? profile,
}) {
  var maxIdx = Position.mid.index;
  if (unlocks.contains(UnlockKey.fullPulse)) {
    maxIdx = Position.full.index;
  } else if (unlocks.contains(UnlockKey.throatPulse)) {
    maxIdx = Position.throat.index;
  }
  if (profile != null) {
    final depthComfort = profile.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (depthComfort != null) {
      final fromProfile =
          depthComfort.round().clamp(0, Position.values.length - 1);
      maxIdx = min(maxIdx, fromProfile);
    }
  }
  // Plancher : on s'assure d'avoir au moins `mid` accessible pour que le
  // pool ne soit jamais vide (les amplitudes shallow `head→mid` sont
  // toujours valides).
  if (maxIdx < Position.mid.index) maxIdx = Position.mid.index;
  return maxIdx;
}

/// Construit le pool de descriptors rythmés (`rhythm` + `lick`) bornés
/// par [maxDepthIdx]. Toujours non-vide grâce au plancher `mid`.
///
/// - `head→mid` (toujours présent — baseline shallow).
/// - `head→throat` (si maxDepth ≥ throat).
/// - `mid→full` (si maxDepth ≥ full).
List<EnduranceDescriptor> buildRhythmLickPool({required int maxDepthIdx}) {
  final pool = <EnduranceDescriptor>[];
  for (final mode in const [SessionMode.rhythm, SessionMode.lick]) {
    pool.add(
        EnduranceDescriptor(mode: mode, from: Position.head, to: Position.mid));
    if (maxDepthIdx >= Position.throat.index) {
      pool.add(EnduranceDescriptor(
          mode: mode, from: Position.head, to: Position.throat));
    }
    if (maxDepthIdx >= Position.full.index) {
      pool.add(EnduranceDescriptor(
          mode: mode, from: Position.mid, to: Position.full));
    }
  }
  return pool;
}

/// Construit le pool de holds disponibles : `throat` si `throatPulse`,
/// `full` si `fullPulse`, sinon vide. Sert à [EffortNoBreathStreakBuilder]
/// qui intercale des holds entre les rythmés.
List<EnduranceDescriptor> buildHoldPool({required Set<UnlockKey> unlocks}) {
  final pool = <EnduranceDescriptor>[];
  if (unlocks.contains(UnlockKey.throatPulse)) {
    pool.add(const EnduranceDescriptor(
        mode: SessionMode.hold, from: Position.throat, to: Position.throat));
  }
  if (unlocks.contains(UnlockKey.fullPulse)) {
    pool.add(const EnduranceDescriptor(
        mode: SessionMode.hold, from: Position.full, to: Position.full));
  }
  return pool;
}

/// Tire un descriptor du pool différent du dernier émis (anti-répétition
/// immédiate). Si le pool ne contient qu'un seul élément, le retourne tel
/// quel (pas le choix). Si le pool est vide, retourne `null`.
EnduranceDescriptor? pickNonRepeating({
  required List<EnduranceDescriptor> pool,
  required EnduranceDescriptor? last,
  required Random rng,
}) {
  if (pool.isEmpty) return null;
  if (pool.length == 1) return pool.first;
  while (true) {
    final pick = pool[rng.nextInt(pool.length)];
    if (!pick.sameKindAs(last)) return pick;
  }
}
