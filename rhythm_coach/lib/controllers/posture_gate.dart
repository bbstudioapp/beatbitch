import 'package:flutter/foundation.dart';

import '../models/session.dart';

/// Ce qui **justifie** le gel de posture (issue #77), et rien d'autre.
///
/// Le gel n'est pas un drapeau qu'on arme d'un côté et qu'on pense à baisser
/// de l'autre : c'est une conséquence de la scène qui l'a ordonné, et il
/// cesse d'exister dès que cette scène n'est plus la scène courante.
/// [stillHolds] rejoue la justification à chaque lecture — un chemin qui
/// rebat la timeline n'a rien à lever, le gel tombe parce que ce qui le
/// tenait debout a disparu. C'est la propriété qui compte : elle vaut pour
/// les chemins qui existent aujourd'hui **comme pour ceux qu'on écrira
/// demain**, sans qu'ils aient à connaître ce gel.
///
/// Les trois premières composantes sont **les seules variables qui portent la
/// progression d'une séance** (`elapsed = _stopwatch + _timelineOffset`, step
/// courant = `_session.steps[_nextStepIndex]`) : rebattre la timeline sans en
/// toucher aucune est impossible. La quatrième couvre le flow d'échec, qui
/// n'a pas besoin de rebattre la timeline pour annuler la mise en scène de la
/// pause (cf. `triggerFail`).
///
/// **Cette impossibilité repose sur une hypothèse** : une [Session] et ses
/// listes (`steps`, `breaks`, `challenges`) ne sont jamais modifiées après
/// construction — toute réécriture de la timeline en vol produit une nouvelle
/// instance (cf. `_excisChallengeFromSession`). La clause d'identité ne voit
/// pas une mutation en place : un `session.steps[i] = …` sur une séance déjà
/// démarrée rebattrait la timeline sans faire tomber le gel, et rien ne le
/// signalerait.
@immutable
class PostureGate {
  const PostureGate({
    required this.session,
    required this.nextStepIndex,
    required this.timelineOffset,
    required this.failGeneration,
  });

  /// Identité — pas égalité — de la timeline sur laquelle l'ordre a été
  /// donné. Toute régénération en vol construit une nouvelle `Session`.
  final Session session;

  /// Prochain step à consommer au moment de l'ordre. Le gel interdit
  /// justement toute consommation : s'il a bougé, c'est que quelqu'un
  /// d'autre a déplacé la tête de lecture.
  final int nextStepIndex;

  /// Décalage d'horloge au moment de l'ordre. Un gel ne fait que le
  /// **décrémenter** (un tick par battement, comme le report TTS) : toute
  /// valeur supérieure signe un saut en avant dans la timeline.
  final Duration timelineOffset;

  /// Numéro du dernier flow d'échec démarré (monotone croissant, jamais
  /// remis à zéro).
  final int failGeneration;

  /// Rejoue la justification contre la situation courante.
  ///
  /// [otherSceneActive] : une autre mise en scène tient l'écran (défi en
  /// cours, respiration post-défi). L'ordre de posture n'est alors plus la
  /// scène courante — deux consignes concurrentes ne s'empilent pas.
  bool stillHolds({
    required Session session,
    required int nextStepIndex,
    required Duration timelineOffset,
    required int failGeneration,
    required bool otherSceneActive,
  }) {
    if (!identical(session, this.session)) return false;
    if (nextStepIndex != this.nextStepIndex) return false;
    if (timelineOffset > this.timelineOffset) return false;
    if (failGeneration != this.failGeneration) return false;
    return !otherSceneActive;
  }
}
