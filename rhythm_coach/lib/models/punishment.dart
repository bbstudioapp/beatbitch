import 'session_step.dart';

/// Une punition est une mini-séquence d'étapes jouée après un fail.
/// Sa structure est volontairement identique à une session : on réutilise
/// le moteur de steps (TTS + bips selon mode/position/bpm) sans rien dupliquer.
class Punishment {
  final String id;
  final String name;

  /// Durée totale de la punition (en secondes). Sert de borne d'arrêt
  /// pour le runner — au-delà, la séance reprend.
  final int durationSeconds;

  /// Steps avec `time` relatif au début de la punition.
  final List<SessionStep> steps;

  const Punishment({
    required this.id,
    required this.name,
    required this.durationSeconds,
    required this.steps,
  });

  factory Punishment.fromJson(Map<String, dynamic> json) {
    final steps = (json['steps'] as List<dynamic>)
        .map((s) => SessionStep.fromJson(s as Map<String, dynamic>))
        .toList();
    // Si duration_seconds n'est pas fourni, on prend le max des `time` des
    // étapes + une marge — pratique pendant la phase de prototypage.
    final declared = (json['duration_seconds'] as num?)?.toInt();
    final fromSteps = steps.isEmpty
        ? 0
        : steps.map((s) => s.time + (s.duration ?? 0)).reduce(
              (a, b) => a > b ? a : b,
            );
    return Punishment(
      id: json['id'] as String,
      name: json['name'] as String,
      durationSeconds: declared ?? fromSteps,
      steps: steps,
    );
  }
}
