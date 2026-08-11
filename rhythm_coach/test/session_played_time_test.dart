import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/stats_service.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-régression du retour utilisateur 0.6.1 : « la séance a duré 30-35 min
/// et l'écran de fin affiche 15 min 59 ».
///
/// L'horloge de timeline est gelée pendant tout le défi (breath d'annonce,
/// countdown, défi, breath de récup) — choix assumé, non remis en cause ici :
/// le défi ne consomme pas de temps de séance. Mais c'est cette horloge que
/// l'écran de fin affichait et que `_finish` créditait au temps de jeu cumulé,
/// si bien qu'un défi de dix minutes ne rapportait ni point de spécialisation,
/// ni déblocage de coach, ni badge d'endurance.
///
/// Le temps réellement joué (pauses exclues) est porté par
/// `SessionController.playedSeconds`, que l'écran de fin affiche et que
/// `_finish` crédite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    // Sans override, `defaultTargetPlatform` vaut `linux` sur la machine de
    // CI/dev et `TtsService` bypasserait le plugin (piper / spd-say).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
    for (final name in wakelockChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        name,
        (_) async =>
            const StandardMessageCodec().encodeMessage(<Object?>[null]),
      );
    }
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  test(
      'le temps gelé par un défi est crédité au temps de jeu et rapporté en '
      'fin de séance', () async {
    final ctrl = _buildController();
    final wallclock = Stopwatch()..start();
    await ctrl.start();

    // Le défi s'arme à `challengeTriggerTimes[0]` = 2 s de timeline.
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
    final durationBefore = ctrl.session.durationSeconds;
    ctrl.triggerChallengePass();
    // Le PASSE excise la fenêtre du défi (breath de countdown + enveloppe
    // réservée) de la timeline : c'est ce raccourcissement que la joueuse
    // lisait sur son écran de fin.
    expect(ctrl.session.durationSeconds,
        durationBefore - (13 + _challenge.nominalDurationSeconds));

    await _waitUntil(() => ctrl.isFinished,
        timeout: const Duration(minutes: 1));
    wallclock.stop();

    final played = ctrl.playedSeconds;
    final timeline = ctrl.elapsedSeconds;
    expect(timeline, ctrl.session.durationSeconds,
        reason: "la séance s'arrête bien sur le seuil de timeline");
    // Le breath de récup post-défi (10 s) est joué horloge gelée : le temps
    // joué doit le compter, la timeline non.
    expect(played, greaterThanOrEqualTo(timeline + 9),
        reason: 'joué $played s pour $timeline s de timeline');
    expect(played, closeTo(wallclock.elapsed.inSeconds, 2),
        reason: 'le temps joué suit le temps réel de la séance');

    final credited = await StatsService().getTotalSeconds();
    expect(credited, played,
        reason: 'le temps de jeu cumulé (points de spécialisation, déblocages '
            "de coach, badge d'endurance) crédite le temps réellement joué");
  }, timeout: const Timeout(Duration(seconds: 120)));
}

/// Défi de test : enveloppe de 18 s (13 s de breath de countdown + 5 s de
/// durée nominale) sur une séance de 25 s — de quoi rendre le gel visible sans
/// faire durer le test.
const _challenge = Challenge(
  axis: CapabilityAxis.holdThroatStreak,
  kind: ChallengeAxisKind.duration,
  targetThreshold: 5,
  mode: SessionMode.hold,
  from: Position.throat,
  to: Position.throat,
  comfortAtCalibration: 4,
);

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition non atteinte en ${timeout.inSeconds} s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

SessionController _buildController() {
  return SessionController(
    session: const Session(
      id: 'defi',
      name: 'defi',
      description: '',
      durationSeconds: 25,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 40, duration: 2),
        SessionStep(time: 2, mode: SessionMode.breath, duration: 13),
        SessionStep(time: 20, mode: SessionMode.rhythm, bpm: 40, duration: 5),
      ],
      challenges: [_challenge],
      challengeTriggerTimes: [2],
    ),
    tts: TtsService(),
    beep: _SilentBeepEngine(),
    ambience: _SilentAmbienceEngine(),
    punishmentBundle: const PunishmentBundle(failPhrases: [], punishments: []),
    randomComments: const RandomCommentsBundle(
      comments: [],
      minIntervalSeconds: 999,
      maxIntervalSeconds: 999,
      scriptedCooldownSeconds: 4,
    ),
  );
}

/// Neutralise le backend audio : le sujet du test est la timeline, et
/// `audioplayers` n'a pas d'implémentation dans l'environnement de test.
class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> playForMode(SessionMode mode) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
