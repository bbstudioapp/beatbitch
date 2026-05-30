import '../career/services/generation/capability_clamps.dart';
import '../models/session_step.dart' show Position;
import '../services/capability_axis.dart';
import '../services/capability_service.dart';

/// Lecture du profil de capacités comme **bornes** pour le mode Music
/// (cf. `specs/music_mode.md` §6). Aucune écriture : music mode ne ratchete
/// rien, il lit seulement ce que la joueuse a prouvé tenir en carrière.
///
/// `comfort` (la cible du générateur carrière) sert de plafond. `null` = pas
/// de donnée → aucune contrainte (joueuse neuve : on retombe sur les défauts).
class MusicCapabilityBounds {
  final CapabilityProfile? profile;

  /// Mode debug : ignore complètement le gating (profondeur libre jusqu'à
  /// `full`, aucun plafond BPM, aucune limite de hold). Pour la mise au point.
  final bool ignoreGating;

  const MusicCapabilityBounds(this.profile, {this.ignoreGating = false});

  /// Profondeur d'impact max autorisée. Plancher `mid`, plafond `full`
  /// (`balls` est latéral, hors music mode). `mid` par défaut.
  Position maxDepth() {
    if (ignoreGating) return Position.full;
    final c = profile?.comfortOf(CapabilityAxis.rhythmDepthMax);
    if (c == null) return Position.mid;
    final idx = c.round().clamp(Position.mid.index, Position.full.index);
    return Position.values[idx];
  }

  /// Plafond BPM pour une profondeur d'impact donnée (réutilise le mapping
  /// carrière `rhythmBpmCeilShallow/Throat/Full`). `null` = pas de contrainte.
  int? bpmCeilFor(Position to) {
    if (ignoreGating) return null;
    final axis = CapabilityClamps.rhythmBpmCeilAxisFor(to);
    return profile?.comfortOf(axis)?.round();
  }

  /// Endurance prouvée (secondes) à **tenir** cette profondeur (hold).
  /// `null` pour les profondeurs sans axe de hold (≤ mid) ou sans donnée.
  double? holdSecondsFor(Position to) {
    if (ignoreGating) return null;
    final axis = switch (to) {
      Position.full || Position.balls => CapabilityAxis.holdFullStreak,
      Position.throat => CapabilityAxis.holdThroatStreak,
      _ => null,
    };
    if (axis == null) return null;
    return profile?.comfortOf(axis);
  }
}
