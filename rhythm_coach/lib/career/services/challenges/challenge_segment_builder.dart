/// Phase B — Refonte défis en streaming.
///
/// Un `ChallengeSegmentBuilder` produit la séquence de sous-steps d'un défi
/// **à la volée**, en temps réel. Le générateur de session ne pose plus que
/// le step trigger (un breath de countdown) à la position du défi ; le
/// `SessionController` instancie le builder à l'entrée en phase `live` et
/// lui demande un nouveau segment à chaque transition (durée du segment
/// courant écoulée).
///
/// Pour les axes monolithiques (PR-B.1.a — `holdThroatStreak`,
/// `holdFullStreak`, `biffleBpmMax`, `rhythmDepthMax`), le builder émet un
/// unique segment puis `null`. Pour les axes streaming (PR-B.1.c+), le
/// builder continue à émettre des segments tant que la joueuse tient.
///
/// Spec complète : doc local `~/perso/bbstudio/BBStudio/perso/bb/specs/
/// challenges_streaming_refonte.md` § 5.1.
library;

import 'dart:math';

import '../../../models/session_step.dart';
import '../../../services/capability_axis.dart';
import '../../../services/capability_service.dart';
import '../../models/challenge.dart';
import '../../models/unlock_key.dart';
import 'builders/biffle_bpm_max_builder.dart';
import 'builders/hold_full_streak_builder.dart';
import 'builders/hold_throat_streak_builder.dart';
import 'builders/rhythm_bpm_ceil_full_builder.dart';
import 'builders/rhythm_bpm_ceil_shallow_builder.dart';
import 'builders/rhythm_bpm_ceil_throat_builder.dart';
import 'builders/rhythm_depth_max_builder.dart';

/// Interface de construction des sous-steps d'un défi.
abstract class ChallengeSegmentBuilder {
  /// Configure le builder pour ce défi. Appelé une fois à l'entrée
  /// `phase = live` (= après les 3-2-1 du countdown). Les builders simples
  /// peuvent ignorer [profile], [unlocks] et [rng] ; les builders streaming
  /// (endurance, modèle gorge) en consomment pour filtrer le pool de
  /// descriptors.
  void start({
    required Challenge challenge,
    required CapabilityProfile? profile,
    required Set<UnlockKey> unlocks,
    required Random rng,
  });

  /// Produit le prochain segment à jouer. Le contrôleur appelle cette
  /// méthode au démarrage de `live`, puis à chaque transition (durée du
  /// segment courant écoulée). Retourne `null` quand le builder n'a plus
  /// rien à émettre (cas monolithique après le seul segment ; axes
  /// streaming continuent à émettre tant que la joueuse tient).
  ///
  /// Le segment retourné est un `SessionStep` **sans position dans la
  /// timeline** (le contrôleur le joue manuellement via `_beep.applyStep`
  /// — la timeline session reste freezée pendant le défi).
  SessionStep? next();

  /// `true` dès que le builder a émis suffisamment de segments pour
  /// considérer le seuil cible atteint. Le contrôleur bascule alors en
  /// `phase = atSeuil` ; les segments suivants sont des « extensions ».
  bool get thresholdReached;

  /// Durée cumulée jouée jusqu'ici (somme des `duration` des segments
  /// émis et joués). Sert au calcul de l'avancement vers le seuil et au
  /// reporting (banner UI / debug).
  int get elapsedSegmentSeconds;
}

/// Factory : retourne le builder dédié à l'axe du défi.
///
/// Throws `StateError` pour un axe non encore couvert — les PRs suivantes
/// (B.1.c → B.1.f) compléteront la table. PR-B.1.a a livré les 4 axes
/// monolithiques ; PR-B.1.b ajoute les 3 axes rythme BPM avec choix
/// d'amplitude.
ChallengeSegmentBuilder builderForAxis(CapabilityAxis axis) {
  switch (axis) {
    case CapabilityAxis.holdThroatStreak:
      return HoldThroatStreakBuilder();
    case CapabilityAxis.holdFullStreak:
      return HoldFullStreakBuilder();
    case CapabilityAxis.biffleBpmMax:
      return BiffleBpmMaxBuilder();
    case CapabilityAxis.rhythmDepthMax:
      return RhythmDepthMaxBuilder();
    case CapabilityAxis.rhythmBpmCeilShallow:
      return RhythmBpmCeilShallowBuilder();
    case CapabilityAxis.rhythmBpmCeilThroat:
      return RhythmBpmCeilThroatBuilder();
    case CapabilityAxis.rhythmBpmCeilFull:
      return RhythmBpmCeilFullBuilder();
    // ignore: no_default_cases
    default:
      throw StateError(
        'ChallengeSegmentBuilder : aucun builder enregistré pour $axis '
        '(PR-B.1.a/b couvrent les 4 axes monolithiques et les 3 axes '
        'rythme BPM — les autres axes arriveront dans PR-B.1.c à PR-B.1.f).',
      );
  }
}
