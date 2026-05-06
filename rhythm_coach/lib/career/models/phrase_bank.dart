import 'dart:math';

import '../../models/session.dart';
import '../../models/session_step.dart';

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

  /// Phrases TTS déclenchées au franchissement d'un seuil de progression
  /// de la session (ratio temps écoulé / durée totale). Indexé par seuil
  /// en pourcent (25/50/75/90).
  final Map<int, List<String>> _progress;

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

  /// Phrases impératives prononcées AU DÉBUT du step final, juste avant
  /// le `finale_chime`. Indexées par mode (`hand`/`lick`/`biffle`) ou par
  /// `hold_<position>` pour qualifier la profondeur du hold final. La
  /// phrase doit décrire l'action concrète à exécuter à l'instant t (ex:
  /// « ouvre ta bouche », « sors ta langue », « avale tout ») — le chime
  /// est joué dès qu'elle est terminée, pendant le step.
  final Map<String, List<String>> _finalActions;

  /// Phrases de compliment douces prononcées sur le step de post-final
  /// (action calme de quelques secondes après l'orgasme). Plus tendres
  /// que `congrats` qui ferme la séance, plus douces que `finish_orgasm`
  /// qui souligne la décharge.
  final List<String> _postFinal;

  /// Suppliques imposées par la coach quand le post-final est un step
  /// `beg` (« remercie-moi », « supplie-moi de revenir », « demande
  /// pardon »…). Distinct de `_postFinal` car le contexte est inversé :
  /// ce n'est plus un compliment mais une consigne adressée à
  /// l'utilisatrice.
  final List<String> _postFinalBeg;

  const PhraseBank({
    required Map<SessionMode, Map<String, List<String>>> byMode,
    required List<String> congrats,
    required List<String> intros,
    Map<int, List<String>> progress = const {},
    List<String> encore = const [],
    Map<TransitionKind, List<String>> transitions = const {},
    List<String> finishOrgasm = const [],
    Map<String, List<String>> finalAnnouncements = const {},
    Map<String, List<String>> finalActions = const {},
    List<String> postFinal = const [],
    List<String> postFinalBeg = const [],
  })  : _byMode = byMode,
        _congrats = congrats,
        _intros = intros,
        _progress = progress,
        _encore = encore,
        _transitions = transitions,
        _finishOrgasm = finishOrgasm,
        _finalAnnouncements = finalAnnouncements,
        _finalActions = finalActions,
        _postFinal = postFinal,
        _postFinalBeg = postFinalBeg;

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

  /// Tire une phrase pour le seuil de progression [threshold] (25/50/75/90)
  /// — déclenchée au franchissement du ratio `elapsedSeconds /
  /// session.durationSeconds` correspondant. Retourne null si la banque ne
  /// contient rien pour ce seuil.
  String? pickProgress(int threshold, Random rng) {
    final list = _progress[threshold];
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

  /// Tire la phrase impérative dite AU DÉBUT du step final. Pour `hold`,
  /// on qualifie par la position (`hold_tip`, `hold_head`, …) parce que
  /// l'action concrète varie selon la profondeur (langue / lèvres / gorge).
  /// Pour les autres modes, la clé est juste le nom du mode. Fallback en
  /// cascade : clé exacte → clé mode (sans position) → null. Retourne
  /// `null` si rien n'est défini.
  String? pickFinalAction({
    required SessionMode mode,
    Position? holdPosition,
    required Random rng,
  }) {
    final keys = <String>[];
    if (mode == SessionMode.hold && holdPosition != null) {
      keys.add('hold_${holdPosition.name}');
    }
    keys.add(mode.name);
    for (final key in keys) {
      final list = _finalActions[key];
      if (list != null && list.isNotEmpty) {
        return list[rng.nextInt(list.length)];
      }
    }
    return null;
  }

  /// Tire une phrase de compliment doux jouée sur le step post-final
  /// (l'action calme qui suit l'orgasme). Retourne `null` si la banque
  /// est vide.
  String? pickPostFinal(Random rng) {
    if (_postFinal.isEmpty) return null;
    return _postFinal[rng.nextInt(_postFinal.length)];
  }

  /// Tire une consigne de supplique pour un step post-final en mode `beg`
  /// (« remercie-moi », « supplie-moi de revenir », « demande pardon »…).
  /// Retourne `null` si la banque est vide.
  String? pickPostFinalBeg(Random rng) {
    if (_postFinalBeg.isEmpty) return null;
    return _postFinalBeg[rng.nextInt(_postFinalBeg.length)];
  }
}
