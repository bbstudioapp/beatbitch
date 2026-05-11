import 'dart:math';

import '../../models/session.dart';
import '../../models/session_step.dart';
import 'phrase_entry.dart';

export 'phrase_entry.dart' show PhraseEntry, PhraseContext;

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
///
/// Chaque liste de phrases est une `List<PhraseEntry>` : chaque entrée
/// peut porter des contraintes (profondeur min/max, BPM min/max, unlocks
/// requis) qui filtrent le tirage en fonction du contexte du step courant
/// — passé via [PhraseContext] à [pickFor]. Les autres `pick*` ne
/// consomment pas de contexte pour l'instant et tirent uniformément.
class PhraseBank {
  final Map<SessionMode, Map<String, List<PhraseEntry>>> _byMode;
  final List<PhraseEntry> _congrats;
  final List<PhraseEntry> _intros;

  /// Phrases TTS déclenchées au franchissement d'un seuil de progression
  /// de la session (ratio temps écoulé / durée totale). Indexé par seuil
  /// en pourcent (25/50/75/90).
  final Map<int, List<PhraseEntry>> _progress;

  /// Phrases d'ouverture pour les sessions « encore » (régénération
  /// post-finished). Remplace l'intro vocale habituelle.
  final List<PhraseEntry> _encore;

  /// Phrases de transition déclenchées sur un changement de paramètre
  /// (BPM, profondeur) entre deux steps successifs du même mode.
  final Map<TransitionKind, List<PhraseEntry>> _transitions;

  /// Phrases de l'orgasme final (post finale chime). Plus crues que les
  /// `congrats`, jouées juste après le son de clôture pour souligner que
  /// la session est terminée et accomplie.
  final List<PhraseEntry> _finishOrgasm;

  /// Annonces dites sur la step pré-finale quand le mode change pour le
  /// final (ex: hand → lick → "sors ta langue, j'arrive"). Indexées par
  /// la clé `<preMode>_to_<finalMode>`. `hold` n'est PAS qualifié par la
  /// position : les phrases sont assez génériques pour couvrir toutes les
  /// profondeurs (« ouvre la bouche, fige-toi »).
  final Map<String, List<PhraseEntry>> _finalAnnouncements;

  /// Phrases impératives prononcées AU DÉBUT du step final, juste avant
  /// le `finale_chime`. Indexées par mode (`hand`/`lick`/`biffle`) ou par
  /// `hold_<position>` pour qualifier la profondeur du hold final. La
  /// phrase doit décrire l'action concrète à exécuter à l'instant t (ex:
  /// « ouvre ta bouche », « sors ta langue », « avale tout ») — le chime
  /// est joué dès qu'elle est terminée, pendant le step.
  final Map<String, List<PhraseEntry>> _finalActions;

  /// Phrases de compliment douces prononcées sur le step de post-final
  /// (action calme de quelques secondes après l'orgasme). Plus tendres
  /// que `congrats` qui ferme la séance, plus douces que `finish_orgasm`
  /// qui souligne la décharge.
  final List<PhraseEntry> _postFinal;

  /// Suppliques imposées par la coach quand le post-final est un step
  /// `beg` (« remercie-moi », « supplie-moi de revenir », « demande
  /// pardon »…). Distinct de `_postFinal` car le contexte est inversé :
  /// ce n'est plus un compliment mais une consigne adressée à
  /// l'utilisatrice.
  final List<PhraseEntry> _postFinalBeg;

  /// Consignes spécifiques au post-final lick (« lèche pour nettoyer »).
  /// Tirées en priorité sur `_postFinal` quand le step post-final résolu
  /// est un lick — typiquement biaisé par la spé sloppy en niveau avancé.
  /// Le pool générique `_postFinal` peut contenir quelques phrases lick
  /// (« lèche-le encore un peu, nettoie bien ») qui font fallback si
  /// vide. Distinct pour pouvoir varier sans diluer le pool générique.
  final List<PhraseEntry> _postFinalLick;

  /// Ordres de déglutition forcée (« avale tout », « déglutis », …)
  /// piochés par le générateur quand la sim salive sature en cours de
  /// séance. Step beg libre court attaché. Pool dédié pour pouvoir
  /// varier le ton (impératif sec) sans polluer les autres pools beg.
  final List<PhraseEntry> _swallowOrders;

  const PhraseBank({
    required Map<SessionMode, Map<String, List<PhraseEntry>>> byMode,
    required List<PhraseEntry> congrats,
    required List<PhraseEntry> intros,
    Map<int, List<PhraseEntry>> progress = const {},
    List<PhraseEntry> encore = const [],
    Map<TransitionKind, List<PhraseEntry>> transitions = const {},
    List<PhraseEntry> finishOrgasm = const [],
    Map<String, List<PhraseEntry>> finalAnnouncements = const {},
    Map<String, List<PhraseEntry>> finalActions = const {},
    List<PhraseEntry> postFinal = const [],
    List<PhraseEntry> postFinalBeg = const [],
    List<PhraseEntry> postFinalLick = const [],
    List<PhraseEntry> swallowOrders = const [],
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
        _postFinalBeg = postFinalBeg,
        _postFinalLick = postFinalLick,
        _swallowOrders = swallowOrders;

  /// Tire une phrase pour [mode] dans le tier demandé. Si le tier est absent,
  /// fallback sur 'medium' puis 'any' puis première liste non vide.
  ///
  /// Si [context] est fourni, la phrase est filtrée par les contraintes
  /// portées par chaque [PhraseEntry] (profondeur min/max, BPM min/max,
  /// unlocks). Si aucune phrase contrainte ne match, fallback sur les
  /// phrases sans contraintes du même pool ; si même ce fallback est vide,
  /// retourne `''`.
  ///
  /// [context] = null → tirage uniforme dans le pool sans filtrage,
  /// comportement historique. Utile pour les call sites qui n'ont pas de
  /// contexte (ex: tirage de phrase d'intro).
  String pickFor(
    SessionMode mode,
    String tier,
    Random rng, {
    PhraseContext? context,
  }) {
    final tiers = _byMode[mode];
    if (tiers == null || tiers.isEmpty) return '';
    final candidates = tiers[tier] ?? tiers['medium'] ?? tiers['any'];
    if (candidates != null && candidates.isNotEmpty) {
      final picked = pickPhraseEntry(candidates, rng, context: context);
      if (picked != null) return picked;
    }
    for (final list in tiers.values) {
      if (list.isNotEmpty) {
        final picked = pickPhraseEntry(list, rng, context: context);
        if (picked != null) return picked;
      }
    }
    return '';
  }

  /// Tire une phrase de félicitations pour la fin de séance.
  String pickCongrats(Random rng) {
    return pickPhraseEntry(_congrats, rng) ?? 'Terminé.';
  }

  /// Tire un texte d'introduction pré-séance (mode Carrière).
  /// Retourne `null` si la banque ne contient aucune intro.
  String? pickIntro(Random rng) => pickPhraseEntry(_intros, rng);

  /// Tire une phrase pour le seuil de progression [threshold] (25/50/75/90)
  /// — déclenchée au franchissement du ratio `elapsedSeconds /
  /// session.durationSeconds` correspondant. Retourne null si la banque ne
  /// contient rien pour ce seuil.
  String? pickProgress(int threshold, Random rng) {
    final list = _progress[threshold];
    if (list == null) return null;
    return pickPhraseEntry(list, rng);
  }

  /// Tire une phrase d'ouverture pour une session « encore » (relance
  /// post-finished). Retourne null si la banque est vide.
  String? pickEncore(Random rng) => pickPhraseEntry(_encore, rng);

  /// Tire une phrase de progression du **profil de capacités** (Phase 4 —
  /// coach audible parcimonieux) pour un axe (clé = `CapabilityAxis.storageKey`,
  /// ex. `"gorge.apnee_streak"`) et un tier (`attempt` / `record` / `tapout`).
  /// La banque globale n'en porte jamais → retourne toujours `null` (l'appelant
  /// reste alors silencieux) ; seul le pack d'un coach déclarant une section
  /// `progressPhrases` peut renvoyer du texte (override dans
  /// `_CoachComposedPhraseBank`).
  String? pickProgressPhrase(String axisStorageKey, String tier, Random rng) =>
      null;

  /// Tire une phrase de transition pour un changement de vitesse ou de
  /// profondeur. Retourne null si la banque ne contient rien pour ce kind.
  String? pickTransition(TransitionKind kind, Random rng) {
    final list = _transitions[kind];
    if (list == null) return null;
    return pickPhraseEntry(list, rng);
  }

  /// Tire une phrase de clôture jouée après le `finale_chime`. Retourne
  /// null si la banque ne contient pas de section `finish_orgasm`.
  String? pickFinishOrgasm(Random rng) => pickPhraseEntry(_finishOrgasm, rng);

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
    if (list == null) return null;
    return pickPhraseEntry(list, rng);
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
        final picked = pickPhraseEntry(list, rng);
        if (picked != null) return picked;
      }
    }
    return null;
  }

  /// Tire une phrase de compliment doux jouée sur le step post-final
  /// (l'action calme qui suit l'orgasme). Retourne `null` si la banque
  /// est vide.
  String? pickPostFinal(Random rng) => pickPhraseEntry(_postFinal, rng);

  /// Tire une consigne de supplique pour un step post-final en mode `beg`
  /// (« remercie-moi », « supplie-moi de revenir », « demande pardon »…).
  /// Retourne `null` si la banque est vide.
  String? pickPostFinalBeg(Random rng) => pickPhraseEntry(_postFinalBeg, rng);

  /// Tire une consigne pour un step post-final en mode `lick`
  /// (« lèche pour nettoyer », « astique-moi à la langue »…). Retourne
  /// `null` si le pool dédié est vide ; l'appelant peut alors retomber
  /// sur `pickPostFinal`.
  String? pickPostFinalLick(Random rng) => pickPhraseEntry(_postFinalLick, rng);

  /// Tire un ordre de déglutition forcée (« avale tout », « déglutis »…)
  /// pour un step beg libre court inséré quand la sim salive sature.
  /// Retourne `null` si le pool est vide — l'appelant peut alors
  /// retomber sur le tier `hard` du mode beg comme fallback.
  String? pickSwallowOrder(Random rng) => pickPhraseEntry(_swallowOrders, rng);
}
