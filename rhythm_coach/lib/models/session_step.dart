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
  final int? bpm;

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

  const SessionStep({
    required this.time,
    this.text = '',
    this.from,
    this.to,
    this.bpm,
    this.duration,
    this.mode,
    this.chainAction,
  });

  /// True quand l'étape ne fait QUE déclencher une phrase TTS et n'apporte
  /// aucune configuration de bip — le loop courant continue intact.
  bool get isTextOnly =>
      from == null && to == null && bpm == null && mode == null;

  factory SessionStep.fromJson(Map<String, dynamic> json) {
    final chainRaw = json['chainAction'];
    final chain = chainRaw is Map<String, dynamic>
        ? SessionStep.fromJson({
            // chainAction.time est sans signification dans le JSON source —
            // le loader le repositionnera. On met 0 pour passer le `time
            // as int` non-nullable du parser.
            'time': 0,
            ...chainRaw,
          })
        : null;
    return SessionStep(
      time: json['time'] as int,
      text: (json['text'] as String?) ?? '',
      from: Position.fromString(json['from'] as String?),
      to: Position.fromString(json['to'] as String?),
      bpm: (json['bpm'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      mode: json['mode'] is String
          ? SessionMode.fromString(json['mode'] as String)
          : null,
      chainAction: chain,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time,
        if (text.isNotEmpty) 'text': text,
        if (from != null) 'from': from!.serialized,
        if (to != null) 'to': to!.serialized,
        if (bpm != null) 'bpm': bpm,
        if (duration != null) 'duration': duration,
        if (mode != null) 'mode': mode!.serialized,
        if (chainAction != null)
          'chainAction': chainAction!.toJsonForChain(),
      };

  /// Sérialisation `chainAction` : on omet `time` (recalculé par le
  /// consommateur) pour ne pas faire fuiter une valeur arbitraire dans le
  /// fichier source.
  Map<String, dynamic> toJsonForChain() => {
        if (text.isNotEmpty) 'text': text,
        if (from != null) 'from': from!.serialized,
        if (to != null) 'to': to!.serialized,
        if (bpm != null) 'bpm': bpm,
        if (duration != null) 'duration': duration,
        if (mode != null) 'mode': mode!.serialized,
      };
}
