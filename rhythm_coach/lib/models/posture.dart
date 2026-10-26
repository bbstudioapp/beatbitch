import 'dart:math';

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
/// (`intro_posture_*`).
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

/// Pause active scénarisée. Pendant un
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
  /// posture.
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

/// Changement de position hors pause : la coach annonce [pose] et la séance
/// attend que la joueuse s'y mette. Transient comme [ScriptedBreak].
class PostureChange {
  final int time;
  final Posture pose;

  const PostureChange({required this.time, required this.pose});
}

/// Pauses et changements de position d'une séance, regroupés pour passer d'une
/// séance en cours à la suite régénérée qui les rejoue. Les temps sont ceux de
/// la timeline qui le porte : absolus en sortie du contrôleur, relatifs au
/// début de la suite en entrée du générateur ([shifted] fait le passage).
class PostureScript {
  final List<ScriptedBreak> breaks;
  final List<PostureChange> changes;

  const PostureScript({this.breaks = const [], this.changes = const []});

  static const none = PostureScript();

  bool get isEmpty => breaks.isEmpty && changes.isEmpty;

  /// Somme des durées de pause, hors effort.
  int get pauseSeconds => breaks.fold(0, (sum, b) => sum + b.durationSeconds);

  /// Mêmes pauses et changements décalés de [delta] secondes, jamais avant 0.
  PostureScript shifted(int delta) => PostureScript(
        breaks: [
          for (final b in breaks)
            ScriptedBreak(
              time: max(0, b.time + delta),
              durationSeconds: b.durationSeconds,
              newPose: b.newPose,
              orders: b.orders,
            ),
        ],
        changes: [
          for (final c in changes)
            PostureChange(time: max(0, c.time + delta), pose: c.pose),
        ],
      );
}
