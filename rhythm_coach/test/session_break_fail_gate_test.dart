import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime de la machine de break scénarisé (issue #77), sur les chemins qui
/// rebattent la timeline **sans** passer par `_exitBreak`.
///
/// La sortie d'un break qui impose une nouvelle posture arme un gate
/// (`_awaitingReady`) : la séance se fige jusqu'au « JE SUIS EN PLACE » ou au
/// timeout de sécurité de 90 s. Ce gel est délibéré — tant qu'il est armé,
/// `_checkSteps()` retourne tôt et `_onTick` décrémente `_timelineOffset`,
/// donc plus aucun step n'est consommé et l'horloge logique n'avance plus.
///
/// Trois chemins peuvent traverser cette fenêtre : le bouton « je peux pas »
/// (le seul contrôle de séance visible en production, jamais masqué par le
/// break ni par le gate), le bouton « Utilise-moi » et la régénération de
/// retry milestone (toutes deux via `requestUpgrade`). Aucun ne passe par
/// `_exitBreak` : sans nettoyage explicite, le gate survit intact au saut de
/// timeline et le gel délibéré devient un gel définitif — ticker actif, plus
/// rien qui avance, jusqu'au timeout.
///
/// Le dernier test couvre l'autre versant : le retour d'arrière-plan
/// (notification, appel, écran verrouillé) relançait le loop d'effort en
/// pleine pause scénarisée.
///
/// Tests en temps réel : le `Stopwatch` du controller n'est pas simulé par
/// `flutter_test`, `pump()` n'avance pas son horloge. Les fenêtres sont donc
/// tenues courtes (break de 2 s) — c'est la durée du flow fail (phrase +
/// respiration + punition) qui domine le temps d'exécution.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();

  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  /// Moteur TTS factice qui complète toujours : sans lui, l'anti-coupure de
  /// `_checkSteps` différerait les steps et brouillerait la mesure.
  void installFakeTtsEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      switch (call.method) {
        case 'speak':
          unawaited(pushFromEngine('speak.onStart', true));
          Timer(const Duration(milliseconds: 40),
              () => pushFromEngine('speak.onComplete', true));
          return 1;
        case 'stop':
          unawaited(pushFromEngine('speak.onCancel', true));
          return 1;
        case 'getVoices':
          return <dynamic>[];
        default:
          return 1;
      }
    });
  }

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    installFakeTtsEngine();
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
        .setMockMethodCallHandler(ttsChannel, null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  const punishments = PunishmentBundle(
    failPhrases: ['tu craques'],
    punishments: [
      Punishment(
        id: 'p',
        name: 'p',
        durationSeconds: 1,
        steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
      ),
    ],
  );

  // Break [1,3) imposant `kneeling` à la reprise, et le step d'effort que le
  // générateur pose toujours juste après le trou. Profil de stamina plein :
  // la respiration du flow fail est alors tirée dans sa fourchette courte.
  SessionController buildController({BeepEngine? beep}) => SessionController(
        staminaProfile: List<double>.filled(120, 100),
        session: const Session(
          id: 'break-gate',
          name: 'break-gate',
          description: '',
          durationSeconds: 60,
          defaultMode: SessionMode.rhythm,
          initialPose: Posture.free,
          breaks: [
            ScriptedBreak(
              time: 1,
              durationSeconds: 2,
              newPose: Posture.kneeling,
            ),
          ],
          steps: [
            SessionStep(
                time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
            SessionStep(
                time: 3,
                text: 'apres-break',
                mode: SessionMode.rhythm,
                bpm: 90),
            SessionStep(
                time: 30, text: 'suite', mode: SessionMode.rhythm, bpm: 100),
          ],
        ),
        tts: TtsService(),
        beep: beep ?? _SilentBeepEngine(),
        ambience: _SilentAmbienceEngine(),
        punishmentBundle: punishments,
        randomComments: const RandomCommentsBundle(
          comments: [],
          minIntervalSeconds: 999,
          maxIntervalSeconds: 999,
          scriptedCooldownSeconds: 4,
        ),
      );

  /// Amène la séance jusqu'au gate armé à la sortie du break.
  Future<void> reachPostureGate(SessionController ctrl) async {
    await ctrl.start();
    await Future<void>.delayed(const Duration(milliseconds: 3600));
    expect(ctrl.breakActive, isFalse, reason: 'break fini à t≈3,6 s');
    expect(ctrl.awaitingPostureReady, isTrue,
        reason: 'newPose=kneeling → le gate s\'arme à la sortie du break');
  }

  test(
      'un « je peux pas » pendant l\'attente de mise en place ne gèle pas '
      'la séance', () async {
    final ctrl = buildController();
    await reachPostureGate(ctrl);

    // Le bouton n'est masqué ni par la bannière de pause ni par l'attente de
    // mise en place : ce sont des blocs indépendants empilés au-dessus de lui.
    expect(ctrl.canTriggerFail, isTrue);

    await ctrl.triggerFail();

    expect(ctrl.isRunning, isTrue, reason: 'le flow fail est allé à son terme');
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'le flow fail rebat la timeline sans passer par `_exitBreak` : '
            'il doit lever le gate lui-même, sinon `_checkSteps` ne consomme '
            'plus jamais de step');

    // L'horloge logique doit repartir. Sans le nettoyage, `_onTick` décrémente
    // `_timelineOffset` à chaque tick et `elapsedSeconds` reste figé à la
    // valeur posée par le saut de section.
    final resumedAt = ctrl.elapsedSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.elapsedSeconds, greaterThan(resumedAt),
        reason: 'la séance progresse à nouveau après le flow fail');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('un « je peux pas » pendant une pause scénarisée ne gèle pas la séance',
      () async {
    final ctrl = buildController();
    await ctrl.start();

    // t≈1,6 s : dans la fenêtre du break, avant sa fin naturelle à t=3.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.breakActive, isTrue);
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'le gate ne s\'arme qu\'à la SORTIE du break');
    expect(ctrl.canTriggerFail, isTrue);

    await ctrl.triggerFail();

    expect(ctrl.isRunning, isTrue);
    expect(ctrl.breakActive, isFalse,
        reason: 'le flow fail a sauté la timeline hors du trou d\'effort : le '
            'break ne peut pas rester actif derrière lui');

    // Sans nettoyage, `_exitBreak` rattrapait son retard au tick suivant et
    // armait un gate pour un step déjà consommé par le saut de section.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'aucun gate ne doit s\'armer après coup pour un break que le '
            'flow fail a déjà annulé');

    final resumedAt = ctrl.elapsedSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.elapsedSeconds, greaterThan(resumedAt),
        reason: 'la séance progresse à nouveau après le flow fail');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'une régénération mi-séance pendant l\'attente de mise en place ne gèle '
      'pas la séance', () async {
    final ctrl = buildController();
    await reachPostureGate(ctrl);

    // Chemin du bouton « Utilise-moi » et du retry milestone : la suite est
    // remplacée, l'état de break est remis à zéro — le gate doit tomber avec.
    await ctrl.requestUpgrade(
      insistentBeg: const SessionStep(
        time: 0,
        text: 'supplie',
        mode: SessionMode.beg,
        duration: 2,
      ),
      upcomingSession: const Session(
        id: 'upgrade',
        name: 'upgrade',
        description: '',
        durationSeconds: 30,
        defaultMode: SessionMode.rhythm,
        steps: [
          SessionStep(
              time: 0, text: 'suite-regen', mode: SessionMode.rhythm, bpm: 95),
        ],
      ),
    );

    expect(ctrl.awaitingPostureReady, isFalse,
        reason: 'la régénération remet l\'état de break à zéro : le gate posé '
            'par ce break doit tomber avec lui');

    final resumedAt = ctrl.elapsedSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.elapsedSeconds, greaterThan(resumedAt),
        reason: 'la séance progresse à nouveau après la régénération');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));

  test(
      'le retour d\'arrière-plan pendant une pause scénarisée ne relance pas '
      'l\'audio d\'effort', () async {
    final beep = _TrackingBeepEngine();
    final ctrl = buildController(beep: beep);
    await ctrl.start();

    // t≈1,6 s : `_enterBreak` a déjà coupé le loop d'effort.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.breakActive, isTrue);
    expect(beep.pauseCalls, greaterThanOrEqualTo(1));
    final resumesBefore = beep.resumeCalls;

    // Exactement ce que fait `didChangeAppLifecycleState` sur `paused` /
    // `inactive` / `hidden` — ce handler n'est gaté par aucun flag de debug,
    // une notification suffit à le déclencher.
    await ctrl.pause();
    expect(ctrl.isPaused, isTrue);
    await ctrl.resume();

    expect(ctrl.breakActive, isTrue, reason: 'toujours dans le break (t<3)');
    expect(beep.resumeCalls, resumesBefore,
        reason: 'le loop d\'effort a été coupé par l\'entrée dans le break : '
            'le reprendre ferait repartir l\'effort en pleine pause');

    // Et il doit bien repartir ensuite : c'est le step d'effort posé après le
    // trou qui le reconfigure, une fois la mise en place validée.
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.awaitingPostureReady, isTrue);
    ctrl.confirmPostureReady();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(beep.appliedSteps.map((s) => s.text), contains('apres-break'),
        reason: 'la séance n\'est pas restée muette pour autant');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 40)));
}

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

class _TrackingBeepEngine extends BeepEngine {
  int pauseCalls = 0;
  int resumeCalls = 0;
  final List<SessionStep> appliedSteps = [];

  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    appliedSteps.add(step);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
  }

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
