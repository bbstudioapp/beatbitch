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

/// Invariant de comptabilité du temps de séance — deux horloges, trois
/// consommateurs, et qui lit laquelle :
///
/// 1. **La fin de séance** est décidée par l'horloge de timeline, gelée
///    pendant les défis : la joueuse joue la durée de **contenu** qu'elle a
///    choisie, un défi ne la rogne pas.
/// 2. **Le chiffre affiché en fin de séance** compte tout, défis compris.
/// 3. **Le temps crédité aux statistiques** (points de spécialisation,
///    déblocages de coach, badges d'endurance) compte tout, défis compris.
///
/// C'est une décision produit, pas un détail d'implémentation : ramener
/// l'affichage ou le crédit sur l'horloge gelée reviendrait à ne pas payer
/// la joueuse pour le temps qu'elle vient de jouer (retour utilisateur
/// 0.6.1). `session_played_time_test.dart` prouve le correctif d'origine ;
/// ce test-ci protège la décision.
///
/// La clause 2 se lit sur le chiffre effectivement rendu par l'écran, dans
/// `session_finished_duration_render_test.dart` — celui-ci s'arrête à ce
/// que le contrôleur expose.
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
    for (final name in wakelockChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(name, null);
    }
  });

  test(
      'la fin de séance ignore le temps de défi, le temps exposé et le crédit '
      'le comptent', () async {
    final ctrl = _buildController();
    await ctrl.start();

    // Le défi s'arme à `challengeTriggerTimes[0]` = 2 s de timeline. À partir
    // de là et jusqu'à la fin du breath de récup, la timeline est gelée.
    await _waitUntil(() => ctrl.challengePhase == ChallengePhase.breath);
    final timelineAtArming = ctrl.elapsedSeconds;
    final playedAtArming = ctrl.playedSeconds;
    final contentBefore = ctrl.session.durationSeconds;

    // Temps passé sur l'écran du défi avant d'y répondre : du temps de jeu
    // qui ne doit pas être décompté du contenu de la séance.
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(ctrl.elapsedSeconds, timelineAtArming,
        reason: "l'horloge de contenu est gelée pendant le défi");
    expect(ctrl.playedSeconds, greaterThanOrEqualTo(playedAtArming + 4),
        reason: 'le temps joué, lui, continue de courir');

    ctrl.triggerChallengePass();
    // La fenêtre réservée au défi (breath de countdown + enveloppe) sort de
    // la timeline : le contenu restant est celui de la durée choisie.
    expect(ctrl.session.durationSeconds,
        contentBefore - (13 + _challenge.nominalDurationSeconds));
    final contentAfter = ctrl.session.durationSeconds;

    await _waitUntil(() => ctrl.isFinished,
        timeout: const Duration(minutes: 1));

    final played = ctrl.playedSeconds;

    // 1. La fin de séance est décidée par l'horloge de contenu.
    expect(ctrl.elapsedSeconds, contentAfter,
        reason: 'la séance se termine sur le contenu, pas sur la montre : '
            'sinon le défi rognerait la durée choisie');

    // 2 + 3. Ce qui alimente l'affichage et ce qui est crédité comptent le
    // temps de défi. La marge
    // (4 s d'attente + 10 s de breath de récup, joués horloge gelée) est le
    // minimum structurel : c'est elle qui disparaîtrait si l'un des deux
    // repassait sur l'horloge de contenu.
    expect(played, greaterThanOrEqualTo(ctrl.elapsedSeconds + 13),
        reason: 'temps joué $played s pour ${ctrl.elapsedSeconds} s de '
            'contenu : le temps passé en défi doit être compté');
    final credited = await StatsService().getTotalSeconds();
    expect(credited, played,
        reason: 'les statistiques du joueur créditent le temps réellement '
            'joué — points de spécialisation, déblocages de coach, badges');
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

/// Neutralise le backend audio : le sujet du test est la comptabilité du
/// temps, et `audioplayers` n'a pas d'implémentation en test.
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
