/// Posture physique imposée par la coach pendant une session.
///
/// À ne pas confondre avec [Position] (`session_step.dart`), qui est la
/// profondeur anatomique (tip → full + balls). La posture est de la **mise
/// en scène pure** : elle n'affecte ni les steps ni la difficulté, et change
/// uniquement à l'intro ou pendant un [ScriptedBreak], jamais en plein effort.
///
/// `free` (« confort, au choix ») est toujours disponible et n'a pas de
/// milestone : c'est le défaut bas niveau, aucune contrainte. Les autres
/// postures se débloquent via leur milestone d'introduction dédiée
/// (`intro_posture_*`) — cf. spec locale `specs/scripted_breaks.md`.
enum Posture {
  /// Aucune posture imposée — l'utilisatrice s'installe comme elle veut.
  free,
  sitting,
  standing,
  kneeling,
  allFours,
  onBack;

  /// Clé d'unlock carrière associée, ou `null` pour [free] (toujours
  /// disponible). Sert à filtrer les postures débloquées contre les unlocks
  /// acquis. Chaîne stable (≠ enum `UnlockKey` de `career/` pour ne pas faire
  /// dépendre `models/` de `career/`).
  String? get unlockKey => switch (this) {
        Posture.free => null,
        Posture.sitting => 'posture_sitting',
        Posture.standing => 'posture_standing',
        Posture.kneeling => 'posture_kneeling',
        Posture.allFours => 'posture_all_fours',
        Posture.onBack => 'posture_on_back',
      };

  static Posture fromString(String? raw) {
    if (raw == null) return Posture.free;
    return switch (raw.toLowerCase()) {
      'free' => Posture.free,
      'sitting' => Posture.sitting,
      'standing' => Posture.standing,
      'kneeling' => Posture.kneeling,
      'all_fours' || 'allfours' => Posture.allFours,
      'on_back' || 'onback' => Posture.onBack,
      _ => Posture.free,
    };
  }

  String get serialized => switch (this) {
        Posture.allFours => 'all_fours',
        Posture.onBack => 'on_back',
        _ => name,
      };
}

/// Pause active scénarisée insérée sur les sessions longues. Pendant un
/// break, le moteur d'effort est gelé et la coach donne des ordres espacés
/// ([orders]) ; un break peut aussi changer de posture à la reprise
/// ([newPose]).
///
/// Transient comme `Challenge` : généré dynamiquement par le générateur de
/// carrière, jamais sérialisé dans un fichier de session. À ne pas confondre
/// avec les mini-vagues (`_buildMiniWave`), qui sont des micro-finishes
/// d'accélération, pas des pauses de récup.
class ScriptedBreak {
  /// Seconde (depuis le début de la session) où le break démarre.
  final int time;

  /// Durée du break en secondes (typiquement 60–120).
  final int durationSeconds;

  /// Posture appliquée à la reprise, ou `null` si le break ne change pas de
  /// posture (récup pure : 2ᵉ break d'une session très longue, ou aucune
  /// posture débloquée).
  final Posture? newPose;

  /// Ordres TTS (hors changement de posture) joués espacés pendant le break
  /// (« bois une gorgée », « respire à fond »…).
  final List<String> orders;

  const ScriptedBreak({
    required this.time,
    required this.durationSeconds,
    this.newPose,
    this.orders = const [],
  });

  /// Seconde de fin du break (exclusive de la fenêtre d'effort suivante).
  int get endTime => time + durationSeconds;
}
