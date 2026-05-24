// Library autonome — outils de pacing BPM.
//
// Regroupe les helpers de pacing rythmique **sans état d'instance**,
// sortis de `career_session_generator.dart` pour la même raison que
// `StaminaModel` : leurs formules sont denses et leurs entrées sont
// des scalaires explicites, donc passer en statiques pures clarifie
// ce qu'ils consomment.
//
// Préalable à l'extraction de `gen_facade.dart` (la facade délègue
// `capRhythmDurationByPulses` à cette classe ; elle doit pouvoir
// l'importer sans passer par le `part of` du générateur).
//
// Restent côté instance dans le générateur :
//   * `_applyBpmDiversity` — écrit `_state.lastBpm`, ne peut pas être pure
//   * `_diversifyAmplitude` — lit/écrit `_state.lastFrom/_state.lastTo` +
//     consulte `_patternBuffer.wouldBeFlat`
// Elles utilisent les fonctions de cette classe en passant l'état requis.

import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_step.dart';
import '../../models/specialization.dart';
import 'session_config.dart';
import 'step_draft.dart';

/// Pacing rythmique : diversification BPM/profondeur, rampe, cap pulses
/// pour les profondeurs gorgées. Toutes les méthodes sont statiques + pures.
///
/// Le caller passe explicitement l'état nécessaire (`lastBpm`, `rng`,
/// `level`, `humiliationCareer`, points de spé). Permet à terme une
/// couverture par tests unitaires dédiés.
class BpmPacing {
  /// Force une variation de BPM si le proposé est dans ±10 du précédent.
  /// Décale de 18–30 BPM dans la direction opposée (clampé [40, 200]).
  ///
  /// Fenêtre élargie par rapport à la v1 (±5/15-25) — sinon enchaîner 2
  /// rythmes à 95 et 100 BPM passe pour deux fois la même chose à
  /// l'oreille. La diversité du tempo est l'un des leviers principaux de
  /// variabilité perçue dans la même session.
  static int diversifyBpm(int proposed, int? lastBpm, Random rng) {
    if (lastBpm == null) return proposed;
    if ((proposed - lastBpm).abs() > 10) return proposed;
    final shift = 18 + rng.nextInt(13);
    final delta = proposed <= lastBpm ? -shift : shift;
    return (proposed + delta).clamp(40, 200);
  }

  /// Si [d] est un step long (>40s) en mode rythmique (rhythm/lick/hand),
  /// le découpe en 2 ou 3 sous-segments contigus, chacun avec une variation
  /// de BPM (±10-20) ou de profondeur cible (+/-1 cran). Sert à éviter
  /// qu'une phase d'1 minute sonne comme un loop monotone : chaque sous-
  /// segment se distingue, et la transition entre eux est l'occasion idéale
  /// pour une phrase « plus vite », « plus profond » (cf. C2).
  ///
  /// Les variations restent **égales ou plus douces** que le draft d'origine
  /// (BPM ne dépasse jamais le BPM initial, profondeur ne descend pas
  /// au-delà du `to` initial). Cap de difficulté préservé : pas besoin de
  /// re-passer par `_enforceHumiliationRequired`.
  ///
  /// Retourne `[d]` si pas de split applicable.
  static List<StepDraft> diversifyLongSegment(StepDraft d, Random rng) {
    final dur = d.duration ?? 0;
    if (dur < 40) return [d];
    final mode = d.mode;
    if (mode != SessionMode.rhythm &&
        mode != SessionMode.lick &&
        mode != SessionMode.hand) {
      return [d];
    }
    final parts = dur >= 60 ? 3 : 2;
    final basePart = dur ~/ parts;
    final result = <StepDraft>[];
    for (var i = 0; i < parts; i++) {
      var bpm = d.bpm;
      var to = d.to;
      if (i > 0) {
        // Variation : alterner entre BPM (down ou up dans la limite) et to.
        if (bpm != null && rng.nextBool()) {
          // Décalage BPM entre -20 et +20, sans dépasser le BPM initial
          // de plus de 10. On accepte de descendre jusqu'à 30 BPM sous le
          // base pour offrir un vrai contraste.
          final shift = -20 + rng.nextInt(31); // [-20, 10]
          bpm = (d.bpm! + shift).clamp(40, d.bpm! + 10);
        } else if (to != null &&
            d.from != null &&
            to.index > d.from!.index + 1) {
          // Décale `to` d'un cran vers from. Condition stricte
          // `to.index > from.index + 1` : il faut au moins 2 crans d'écart
          // pour pouvoir descendre to sans collision. À head→mid (écart 1),
          // on n'a pas la marge → on garde to inchangé pour ce sous-segment
          // (la variation se fera via BPM uniquement).
          to = Position.values[to.index - 1];
        }
      }
      final partDur = i == parts - 1 ? dur - i * basePart : basePart;
      result.add(StepDraft(
        mode: d.mode,
        bpm: bpm,
        from: d.from,
        to: to,
        duration: partDur,
      ));
    }
    return result;
  }

  /// Pose une rampe BPM intra-step (`bpmEnd` distinct de `bpm`) pour les
  /// steps longs (≥ 30 s) sur amplitude moyenne (≤ mid), avec une chance
  /// de 50 %. Sert à raconter une montée / descente dans un step qui
  /// sinon resterait à BPM constant pendant une minute.
  ///
  /// **Skip throat/full** : la profondeur porte déjà la tension, pas besoin
  /// d'ajouter une rampe ; et surtout, accélérer un step throat/full
  /// ferait dépasser le cap pulses calculé sur le BPM de départ (cf.
  /// [capRhythmDurationByPulses]).
  ///
  /// **Bornes** : le BPM cible est clampé entre 50 et le cap niveau pour
  /// le mode (plafond très haut à 300 — c'est le `comfort` du profil de
  /// capacités qui borne en pratique, le cap n'est qu'un garde-fou pour
  /// les modes hors carrière).
  static StepDraft maybeApplyBpmRamp(
    StepDraft d,
    double progress,
    Random rng,
    int level,
  ) {
    if (d.mode != SessionMode.rhythm &&
        d.mode != SessionMode.lick &&
        d.mode != SessionMode.hand) {
      return d;
    }
    final bpm = d.bpm;
    final dur = d.duration;
    final to = d.to;
    if (bpm == null || dur == null || to == null) return d;
    if (dur < 30) return d;
    if (to.index > Position.mid.index) return d;
    if (rng.nextDouble() >= 0.5) return d;

    // Direction : 70 % montée passé la moitié de la séance, sinon 50/50.
    final goesUp = progress > 0.5 ? rng.nextDouble() < 0.70 : rng.nextBool();
    final delta = 15 + rng.nextInt(11); // [15, 25]
    // Cap BPM par mode + niveau, miroir de la logique boost (`110 +
    // (level-1)*4` pour hand, `130 + ...` pour rhythm). Lick suit rhythm
    // — c'est aussi un mode rythmé bouche.
    final hardCap = d.mode == SessionMode.hand
        ? (110 + (level - 1) * 4).clamp(60, 300)
        : (130 + (level - 1) * 4).clamp(60, 300);
    final raw = goesUp ? bpm + delta : bpm - delta;
    final clamped = raw.clamp(50, hardCap);
    if (clamped == bpm) return d; // Rampe nulle = pas la peine.
    return StepDraft(
      mode: d.mode,
      bpm: d.bpm,
      bpmEnd: clamped,
      from: d.from,
      to: d.to,
      duration: d.duration,
      chainNext: d.chainNext,
    );
  }

  /// Cap la durée d'un step rythmé par le **nombre d'aller-retours** sur
  /// la profondeur cible. Évite qu'un step `to=throat` à 90 bpm dure 60 s
  /// (= 45 pulses = la joueuse n'a aucune respi). Au-delà de mid, on borne
  /// le nombre de pulses par step. Mid et plus haut : pas de cap.
  ///
  /// La fenêtre de pulses dépend de :
  /// - profondeur visée : throat ≤ 6 + bonus, full ≤ 4 + bonus
  /// - humil career : à mesure que la joueuse aborde la profondeur, son
  ///   humil career est faible (juste au seuil de la milestone : ~10 pour
  ///   throat, ~25 pour full), donc cap bas (6/4 pulses). À mesure qu'elle
  ///   accumule l'humil, le cap monte
  /// - spé : rythmeBiffle pour les pulses, profondeur pour la durée
  ///   d'engagement profond. Coefs modérés pour ne pas écraser la diff.
  ///
  /// On se base sur l'humil plutôt que le niveau global parce que c'est
  /// l'humil qui mesure la pratique réelle de la profondeur, pas le passage
  /// de palier (un niveau 20 spé sloppy a peu d'humil profondeur, un
  /// niveau 12 spé profondeur en a beaucoup plus).
  static int capRhythmDurationByPulses(
    int dur,
    int bpm,
    Position? to, {
    required SessionConfig config,
  }) {
    if (to == null || bpm <= 0) return dur;
    if (to != Position.throat && to != Position.full) return dur;
    // Seuil d'humil au déblocage (approx les `humilRequired` des milestones
    // throat_pulse / full_pulse).
    final unlockHumil = to == Position.full ? 25.0 : 10.0;
    final humilBonus = max(0.0, config.humiliationCareer - unlockHumil);
    final rythmePts = config.pts(SpecializationBranch.rythmeBiffle);
    final profondeurPts = config.pts(SpecializationBranch.profondeur);
    final maxPulses = to == Position.full
        ? 4 + humilBonus * 0.18 + profondeurPts * 1.0 + rythmePts * 0.4
        : 6 + humilBonus * 0.30 + rythmePts * 0.7 + profondeurPts * 0.5;
    final cap = (maxPulses * 120 / bpm).floor().clamp(3, 60);
    return min(dur, cap);
  }
}
