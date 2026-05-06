import '../services/saliva_engine.dart';
import 'session.dart';

/// Position cible d'une étape. Détermine la tonalité du bip joué.
enum Position {
  tip,
  head,
  mid,
  throat,
  full;

  static Position? fromString(String? raw) {
    if (raw == null) return null;
    return switch (raw.toLowerCase()) {
      'tip' => Position.tip,
      'head' => Position.head,
      'mid' => Position.mid,
      'throat' => Position.throat,
      'full' => Position.full,
      _ => null,
    };
  }

  String get serialized => name;
}

class SessionStep {
  /// Démarrage de l'étape, en secondes depuis le début de la session.
  final int time;

  /// Phrase TTS optionnelle. Vide = pas de TTS pour cette étape.
  final String text;

  /// Position de départ. Utilisée par rhythm, hold, lick.
  final Position? from;

  /// Position d'arrivée. Utilisée par rhythm et lick — toujours > from
  /// (alternance from → to pendant le loop).
  final Position? to;

  /// Tempo en battements par minute. Utilisé par rhythm, lick, biffle.
  /// Pour une rampe (cf. [bpmEnd]), c'est la valeur de **départ** du step.
  final int? bpm;

  /// Tempo de **fin** de step pour les rampes BPM intra-step. Quand non
  /// null et différent de [bpm], le BeepEngine interpole linéairement
  /// entre `bpm` (début) et `bpmEnd` (fin) sur la durée du step. Utilisé
  /// pour les phases longues (≥ 30 s) où un tempo constant devient
  /// monotone — une rampe 90→120 raconte une montée. Null = comportement
  /// classique (BPM constant).
  final int? bpmEnd;

  /// Durée de l'étape en secondes. Sert pour la vibration des holds
  /// et comme indication de durée du loop courant.
  final int? duration;

  /// Mode override pour cette étape ; sinon le mode par défaut de la
  /// session est utilisé.
  final SessionMode? mode;

  /// Action enchaînée optionnelle. Utilisé pour les beg « guidés »
  /// (« dis X et continue à me sucer ») où la supplique s'accompagne
  /// d'une action immédiate (rhythm/lick/hold). Le `time` interne du
  /// chainAction est ignoré : il est repositionné à `time + duration`
  /// du parent par le loader (milestone) ou le générateur. Le combo
  /// complet n'est jouable que si parent ET chainAction sont unlocked.
  final SessionStep? chainAction;

  /// Bascule l'état de déglutition de la session courante. Sticky : reste
  /// actif jusqu'à un nouveau step qui le change. `null` = pas de
  /// changement, hérite du courant. Le forçage à `forbidden` est ignoré
  /// par le `SessionController` si la compétence `sloppySwallowControl`
  /// n'est pas acquise — cohérent avec le gating standard via UnlockKey.
  final SwallowMode? swallowMode;

  const SessionStep({
    required this.time,
    this.text = '',
    this.from,
    this.to,
    this.bpm,
    this.bpmEnd,
    this.duration,
    this.mode,
    this.chainAction,
    this.swallowMode,
  });

  /// True quand l'étape ne fait QUE déclencher une phrase TTS et n'apporte
  /// aucune configuration de bip — le loop courant continue intact.
  ///
  /// Le champ [swallowMode] ne compte pas comme « configuration de bip » :
  /// un step text-only peut quand même porter un changement sticky du
  /// toggle de déglutition (cohérent avec sa nature : ce n'est pas un
  /// override audio, c'est une règle de jeu).
  bool get isTextOnly =>
      from == null && to == null && bpm == null && mode == null;

  factory SessionStep.fromJson(Map<String, dynamic> json) {
    final chainRaw = json['chainAction'];
    final chain = chainRaw is Map<String, dynamic>
        ? SessionStep.fromJson({
            // chainAction.time est sans signification dans le JSON source —
            // le loader le repositionnera. On met 0 pour passer le parser
            // non-nullable de `time`.
            'time': 0,
            ...chainRaw,
          })
        : null;
    final time = _asInt(json['time']);
    if (time == null) {
      throw FormatException(
          'SessionStep.fromJson: champ "time" manquant ou non-numérique '
          '(reçu: ${json['time']?.runtimeType} = ${json['time']})');
    }
    final rawText = json['text'];
    return SessionStep(
      time: time,
      text: rawText is String ? rawText : '',
      from: Position.fromString(_asString(json['from'])),
      to: Position.fromString(_asString(json['to'])),
      bpm: _asInt(json['bpm']),
      bpmEnd: _asInt(json['bpmEnd'] ?? json['bpm_end']),
      duration: _asInt(json['duration']),
      mode: _asString(json['mode']) == null
          ? null
          : SessionMode.fromString(json['mode'] as String),
      chainAction: chain,
      swallowMode: _swallowModeFromString(_asString(json['swallow_mode'])),
    );
  }

  static SwallowMode? _swallowModeFromString(String? raw) {
    if (raw == null) return null;
    switch (raw.toLowerCase()) {
      case 'allowed':
        return SwallowMode.allowed;
      case 'forbidden':
        return SwallowMode.forbidden;
      default:
        return null;
    }
  }

  /// Parser tolérant : accepte int, double, ou string numérique.
  /// Retourne null pour absent, non-numérique ou string non parseable.
  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static String? _asString(dynamic v) => v is String ? v : null;

  Map<String, dynamic> toJson() => {
        'time': time,
        if (text.isNotEmpty) 'text': text,
        if (from != null) 'from': from!.serialized,
        if (to != null) 'to': to!.serialized,
        if (bpm != null) 'bpm': bpm,
        if (bpmEnd != null) 'bpmEnd': bpmEnd,
        if (duration != null) 'duration': duration,
        if (mode != null) 'mode': mode!.serialized,
        if (chainAction != null)
          'chainAction': chainAction!.toJsonForChain(),
        if (swallowMode != null) 'swallow_mode': swallowMode!.name,
      };

  /// Sérialisation `chainAction` : on omet `time` (recalculé par le
  /// consommateur) pour ne pas faire fuiter une valeur arbitraire dans le
  /// fichier source.
  Map<String, dynamic> toJsonForChain() => {
        if (text.isNotEmpty) 'text': text,
        if (from != null) 'from': from!.serialized,
        if (to != null) 'to': to!.serialized,
        if (bpm != null) 'bpm': bpm,
        if (bpmEnd != null) 'bpmEnd': bpmEnd,
        if (duration != null) 'duration': duration,
        if (mode != null) 'mode': mode!.serialized,
      };
}
