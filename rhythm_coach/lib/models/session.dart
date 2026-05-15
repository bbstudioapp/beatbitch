import 'final_category.dart';
import 'session_step.dart';

/// Mode global de la session. Peut être surchargé par étape.
enum SessionMode {
  /// Bips à BPM constants, ton selon la position. from/to alternés si différents.
  rhythm,

  /// Bip + couche overlay "lourde" sustainée pendant `duration` + vibration.
  hold,

  /// Variante de rhythm, ressenti plus léger / "wet".
  lick,

  /// Bip spécifique répété au BPM, sans notion de position.
  biffle,

  /// One-shot "libérateur" basé sur la tonalité tip, plus long.
  breath,

  /// Mode purement vocal : exécuter un ou plusieurs ordres pendant
  /// `duration` (supplier, répéter une phrase, action random). Pas de
  /// BPM, pas de `to`. `from` optionnel : sans from ou avec from=head,
  /// la difficulté équivaut à du repos ; avec from=mid/throat/full,
  /// équivaut à un hold à cette profondeur. Jamais from=tip.
  beg,

  /// Phase libre, neutre côté excitation. Un bip de marqueur début +
  /// un bip de marqueur fin encadrent la durée. Pas de loop intermédiaire.
  freestyle,

  /// Stimulation à la main. Variante de rythme : loop BPM identique à
  /// rhythm/lick mais sample dédié et volume médian. Sert à laisser la
  /// bouche se reposer tout en faisant monter doucement l'excitation.
  /// Désactivable à la génération (carrière) via un flag.
  hand,

  /// Aspiration / téter : geste actif-statique. La bouche reste en place
  /// sur la position visée (head ou balls), mais aspire au lieu de
  /// bouger. Audio = un sample wet pulsé toutes ~1.2s pendant `duration`,
  /// pas de loop BPM, pas d'amplitude. Visuel = `_StaticPosition` orb
  /// pulsé (comme hold/beg). Positions valides : `head` (sloppy modéré)
  /// et `balls` (sloppy soumis, gated anatomy). Interdit sur
  /// tip/mid/throat/full.
  suckle;

  static SessionMode fromString(String raw) => switch (raw.toLowerCase()) {
        'rhythm' => SessionMode.rhythm,
        'hold' => SessionMode.hold,
        'lick' => SessionMode.lick,
        'biffle' => SessionMode.biffle,
        'breath' => SessionMode.breath,
        'beg' => SessionMode.beg,
        'freestyle' => SessionMode.freestyle,
        'hand' => SessionMode.hand,
        'suckle' => SessionMode.suckle,
        _ => SessionMode.rhythm,
      };

  String get serialized => name;
}

class Session {
  final String id;
  final String name;
  final String description;
  final int durationSeconds;

  /// Mode par défaut appliqué quand une étape ne précise pas son propre `mode`.
  final SessionMode defaultMode;

  final List<SessionStep> steps;

  /// Texte d'introduction lu par la coach avant le démarrage. Si non
  /// vide, l'écran de session affiche d'abord un briefing avec un bouton
  /// « Je suis prête » à valider pour lancer réellement la séance.
  final String intro;

  /// Code langue ISO-639 du contenu textuel de la session (`fr`, `en`, …).
  /// Sert au filtrage par locale active dans `SessionLoader`. Défaut `fr`
  /// pour rester rétro-compatible avec les fichiers historiques.
  final String lang;

  /// Si la session contient une milestone d'apprentissage, son id. Le
  /// SessionController s'en sert pour appeler `MilestoneService.markCompleted`
  /// quand la fenêtre de séquence est traversée sans fail.
  final String? milestoneId;

  /// Temps absolu (en secondes depuis le début de la session) où démarre la
  /// séquence imposée de la milestone, et durée. Permet au controller de
  /// détecter la sortie de la fenêtre.
  final int? milestoneStartTime;
  final int? milestoneDurationSeconds;

  /// Sessions longues (≥ 18 min, niveau 8+) : 2ᵉ milestone d'apprentissage
  /// insérée dans le même corps de séance, généralement vers 65 % de la
  /// durée. `null` si une seule body a été insérée (cas par défaut). Mêmes
  /// règles d'acquittement / détection de fenêtre que [milestoneId].
  final String? secondMilestoneId;
  final int? secondMilestoneStartTime;
  final int? secondMilestoneDurationSeconds;

  /// Si la session contient une **milestone-final** (placement
  /// `finalApotheose`), son id et sa fenêtre temporelle. Distincte de la
  /// milestone-body : les deux peuvent coexister dans une même séance.
  /// `_finish` appelle `markCompleted` pour les deux. Pas de retry V1
  /// sur la final (apothéose = on ne rate pas, ou on rate la séance).
  final String? finalMilestoneId;
  final int? finalMilestoneStartTime;
  final int? finalMilestoneDurationSeconds;

  /// Catégorie du final pour piocher la bonne variante de `finale_chime`.
  /// Renseignée par `CareerSessionGenerator._pickFinal`. Null pour les
  /// sessions chargées depuis JSON ne le précisant pas → fallback sur le
  /// sample historique unique.
  final FinalCategory? finalCategory;

  /// Temps (en secondes depuis le début) à partir duquel les commentaires
  /// aléatoires sont coupés. Sert à protéger la fenêtre finish (boosts +
  /// step final + son d'orgasme) des phrases random qui se chevauchent
  /// avec les phrases scriptées dramaturgiques. Null = pas de coupure
  /// (sessions hors carrière).
  final int? silentFinishStartTime;

  /// Temps (en secondes depuis le début) où démarre le step final (= step
  /// qui porte la phrase d'action « ouvre ta bouche / sors ta langue / avale
  /// tout » et qui déclenche le `finale_chime` pendant son exécution). Le
  /// `SessionController` compare le `time` du step appliqué à cette valeur
  /// pour identifier le step final et déclencher le chime fire-and-forget
  /// après le speak du texte. Null = pas de step final dédié (sessions hors
  /// carrière), le contrôleur retombe sur l'ancien comportement (chime joué
  /// dans `_finish`).
  final int? finalStepTime;

  /// Si true, le `SessionController` n'écrit rien dans le `StatsService`
  /// pendant la séance : pas de cumul de temps, pas de comptage des beats,
  /// pas de bump humiliation/obéissance persisté, pas de réconciliation
  /// badges. Sert pour les scénarios pédagogiques (tutoriel) qui ne doivent
  /// laisser aucune trace dans le profil. Default false.
  final bool noStats;

  const Session({
    required this.id,
    required this.name,
    required this.description,
    required this.durationSeconds,
    required this.defaultMode,
    required this.steps,
    this.intro = '',
    this.lang = 'fr',
    this.milestoneId,
    this.milestoneStartTime,
    this.milestoneDurationSeconds,
    this.secondMilestoneId,
    this.secondMilestoneStartTime,
    this.secondMilestoneDurationSeconds,
    this.finalMilestoneId,
    this.finalMilestoneStartTime,
    this.finalMilestoneDurationSeconds,
    this.finalCategory,
    this.silentFinishStartTime,
    this.finalStepTime,
    this.noStats = false,
  });

  Duration get duration => Duration(seconds: durationSeconds);

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (seconds == 0) return '$minutes min';
    return '$minutes min $seconds s';
  }

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        durationSeconds: (json['duration_seconds'] as num).toInt(),
        defaultMode:
            SessionMode.fromString((json['mode'] as String?) ?? 'rhythm'),
        steps: (json['steps'] as List<dynamic>)
            .map((s) => SessionStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        intro: (json['intro'] as String?) ?? '',
        lang: (json['lang'] as String?) ?? 'fr',
        noStats: (json['no_stats'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'lang': lang,
        'id': id,
        'name': name,
        'description': description,
        'duration_seconds': durationSeconds,
        'mode': defaultMode.serialized,
        if (intro.isNotEmpty) 'intro': intro,
        if (noStats) 'no_stats': true,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}
