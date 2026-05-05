import 'dart:math';

import '../../models/session.dart';

/// Type de transition entre deux steps consécutifs du même mode. Sert à
/// déclencher une phrase de coach sur un changement de paramètre précis
/// (vitesse / profondeur), pour que les phrases « plus vite », « plus
/// profond » correspondent à un vrai changement et pas à un tirage random.
enum TransitionKind {
  speedUp,
  speedDown,
  depthUp,
  depthDown;

  String get serialized => switch (this) {
        TransitionKind.speedUp => 'speed_up',
        TransitionKind.speedDown => 'speed_down',
        TransitionKind.depthUp => 'depth_up',
        TransitionKind.depthDown => 'depth_down',
      };
}

/// Banque de phrases pour la génération procédurale. Indexée par mode
/// puis par tier d'intensité ('soft' / 'medium' / 'hard' / 'any' / 'finale').
/// La clé top-level [_congrats] contient les phrases de fin de séance,
/// [_intros] les textes d'introduction pré-séance (mode Carrière).
class PhraseBank {
  final Map<SessionMode, Map<String, List<String>>> _byMode;
  final List<String> _congrats;
  final List<String> _intros;

  /// Phrases TTS déclenchées au franchissement d'un seuil de la jauge
  /// d'excitation. Indexé par seuil (25/50/75/90).
  final Map<int, List<String>> _excitation;

  /// Phrases d'ouverture pour les sessions « encore » (régénération
  /// post-finished). Remplace l'intro vocale habituelle.
  final List<String> _encore;

  /// Phrases de transition déclenchées sur un changement de paramètre
  /// (BPM, profondeur) entre deux steps successifs du même mode.
  final Map<TransitionKind, List<String>> _transitions;

  /// Phrases de l'orgasme final (post finale chime). Plus crues que les
  /// `congrats`, jouées juste après le son de clôture pour souligner que
  /// la session est terminée et accomplie.
  final List<String> _finishOrgasm;

  /// Annonces dites sur la step pré-finale quand le mode change pour le
  /// final (ex: hand → lick → "sors ta langue, j'arrive"). Indexées par
  /// la clé `<preMode>_to_<finalMode>`. `hold` n'est PAS qualifié par la
  /// position : les phrases sont assez génériques pour couvrir toutes les
  /// profondeurs (« ouvre la bouche, fige-toi »).
  final Map<String, List<String>> _finalAnnouncements;

  const PhraseBank({
    required Map<SessionMode, Map<String, List<String>>> byMode,
    required List<String> congrats,
    required List<String> intros,
    Map<int, List<String>> excitation = const {},
    List<String> encore = const [],
    Map<TransitionKind, List<String>> transitions = const {},
    List<String> finishOrgasm = const [],
    Map<String, List<String>> finalAnnouncements = const {},
  })  : _byMode = byMode,
        _congrats = congrats,
        _intros = intros,
        _excitation = excitation,
        _encore = encore,
        _transitions = transitions,
        _finishOrgasm = finishOrgasm,
        _finalAnnouncements = finalAnnouncements;

  /// Tire une phrase pour [mode] dans le tier demandé. Si le tier est absent,
  /// fallback sur 'medium' puis 'any' puis première liste non vide. Retourne
  /// `''` si la banque ne contient rien pour ce mode.
  String pickFor(SessionMode mode, String tier, Random rng) {
    final tiers = _byMode[mode];
    if (tiers == null || tiers.isEmpty) return '';
    final candidates = tiers[tier] ?? tiers['medium'] ?? tiers['any'];
    if (candidates != null && candidates.isNotEmpty) {
      return candidates[rng.nextInt(candidates.length)];
    }
    for (final list in tiers.values) {
      if (list.isNotEmpty) return list[rng.nextInt(list.length)];
    }
    return '';
  }

  /// Tire une phrase de félicitations pour la fin de séance.
  String pickCongrats(Random rng) {
    if (_congrats.isEmpty) return 'Terminé.';
    return _congrats[rng.nextInt(_congrats.length)];
  }

  /// Tire un texte d'introduction pré-séance (mode Carrière).
  /// Retourne `null` si la banque ne contient aucune intro.
  String? pickIntro(Random rng) {
    if (_intros.isEmpty) return null;
    return _intros[rng.nextInt(_intros.length)];
  }

  /// Tire une phrase pour le seuil d'excitation [threshold] (25/50/75/90).
  /// Retourne null si la banque ne contient rien pour ce seuil.
  String? pickExcitation(int threshold, Random rng) {
    final list = _excitation[threshold];
    if (list == null || list.isEmpty) return null;
    return list[rng.nextInt(list.length)];
  }

  /// Tire une phrase d'ouverture pour une session « encore » (relance
  /// post-finished). Retourne null si la banque est vide.
  String? pickEncore(Random rng) {
    if (_encore.isEmpty) return null;
    return _encore[rng.nextInt(_encore.length)];
  }

  /// Tire une phrase de transition pour un changement de vitesse ou de
  /// profondeur. Retourne null si la banque ne contient rien pour ce kind.
  String? pickTransition(TransitionKind kind, Random rng) {
    final list = _transitions[kind];
    if (list == null || list.isEmpty) return null;
    return list[rng.nextInt(list.length)];
  }

  /// Tire une phrase de clôture jouée après le `finale_chime`. Retourne
  /// null si la banque ne contient pas de section `finish_orgasm`.
  String? pickFinishOrgasm(Random rng) {
    if (_finishOrgasm.isEmpty) return null;
    return _finishOrgasm[rng.nextInt(_finishOrgasm.length)];
  }

  /// Tire une annonce de transition vers le step final. Joué sur la step
  /// pré-finale (dernier boost) quand le mode du final diffère du mode du
  /// boost — pour préparer l'utilisatrice au changement physique. Pour
  /// `hold`, la position n'est pas qualifiée : les phrases sont génériques.
  /// Retourne `null` si la paire (preMode, finalMode) n'a pas d'entrée.
  String? pickFinalAnnouncement({
    required SessionMode preMode,
    required SessionMode finalMode,
    required Random rng,
  }) {
    final key = '${preMode.name}_to_${finalMode.name}';
    final list = _finalAnnouncements[key];
    if (list == null || list.isEmpty) return null;
    return list[rng.nextInt(list.length)];
  }
}
