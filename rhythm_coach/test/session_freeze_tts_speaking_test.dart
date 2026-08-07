import 'dart:async';

import 'package:beat_bitch/controllers/session_controller.dart';
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

/// Non-régression du gel de séance signalé en 0.6.0 : « la première consigne
/// reste affichée pour toujours, la seconde n'arrive jamais ».
///
/// La progression d'une séance est portée par `_onTick` → `_checkSteps`. Ce
/// dernier diffère tout step porteur de texte tant que `TtsService.isSpeaking`
/// est vrai, en reculant l'horloge logique d'un tick à chaque passage. Le flag
/// n'est remis à `false` que par un callback du moteur TTS
/// (`speak.onComplete` / `onCancel` / `onError`). Si le moteur ne rappelle
/// jamais — service TTS Android déconnecté, `onend` avalé par Safari/PWA — le
/// flag reste collé à `true`.
///
/// Deux gardes couvrent ce cas depuis `fix/session-freeze-tts-guard` :
///  - le report d'un step est borné à `_maxTtsDeferTicks` (~3 s), après quoi le
///    step est consommé quoi qu'il arrive (au pire une phrase est coupée) ;
///  - les appels au canal de synthèse dans `pause()` / `stop()` / `start()`
///    sont bornés, pour que la séance reste pilotable même canal muet.
///
/// Les deux premiers tests ci-dessous ne diffèrent QUE par l'émission (ou non)
/// de `speak.onComplete` par le faux moteur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  const codec = StandardMethodCodec();

  /// Simule un callback entrant du moteur TTS vers le plugin Dart.
  Future<void> pushFromEngine(String method, [Object? args]) {
    return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'flutter_tts',
      codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  /// Installe un faux moteur TTS. [completesUtterances] à `false` reproduit un
  /// moteur qui démarre l'énoncé (`speak.onStart`) et ne signale jamais sa fin.
  void installFakeTtsEngine({required bool completesUtterances}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'speak':
          unawaited(pushFromEngine('speak.onStart', true));
          if (completesUtterances) {
            Timer(
              const Duration(milliseconds: 120),
              () => pushFromEngine('speak.onComplete', true),
            );
          }
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

  /// `AmbienceEngine` instancie un `AudioPlayer` dès son constructeur : sans
  /// ces stubs, la création native échoue et l'erreur remonte hors du flux
  /// du test.
  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];

  /// `start()` appelle `WakelockPlus.enable()` (best-effort) : le canal pigeon
  /// doit répondre, sinon l'échec remonte à la zone du test.
  const wakelockChannels = [
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
        '.isEnabled',
  ];

  setUp(() {
    // Sans override, `defaultTargetPlatform` vaut `linux` sur la machine de
    // CI/dev et `TtsService` bypasserait le plugin (piper / spd-say).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
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
        .setMockMethodCallHandler(channel, null);
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
  });

  test(
      'un moteur TTS qui ne signale jamais la fin de son énoncé ne fige plus '
      'la séance', () async {
    installFakeTtsEngine(completesUtterances: false);
    final ctrl = _buildController();

    await ctrl.start();
    // Déroulé attendu, `isSpeaking` restant collé à `true` après le premier
    // énoncé : step `un` consommé à t=0 ; step `deux` (time=1) atteint à
    // t≈1 s puis différé 3 s (borne) → consommé à t≈4 s ; step `trois`
    // (time=2) atteint à t≈5 s (l'horloge logique a pris 3 s de retard) puis
    // différé jusqu'à t≈8 s. À 6 s on est donc sur `deux`, avec 2 s de marge
    // de chaque côté.
    await Future<void>.delayed(const Duration(seconds: 6));

    expect(ctrl.currentDisplayText, 'deux',
        reason: 'la séance progresse malgré un moteur TTS muet');
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(1),
        reason: "l'horloge logique avance : le report est borné");
    expect(ctrl.isRunning, isTrue);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un canal TTS qui ne répond plus n\'empêche plus la bascule en pause',
      () async {
    // Reproduit le plugin Android quand il a perdu sa connexion au service
    // TTS : il remet `ttsStatus = null` et met TOUS les appels suivants en
    // file d'attente sans jamais renvoyer de réponse.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'stop') return Completer<Object?>().future;
      return 1;
    });
    final ctrl = _buildController();
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // `pause()` rend la main sur le timeout du canal (300 ms).
    await ctrl.pause();

    expect(ctrl.isPaused, isTrue,
        reason: 'l\'état bascule quand même : l\'overlay « reprendre » '
            's\'affiche');
    expect(ctrl.isRunning, isFalse);

    // Et la séance repart : `resume()` agit puisque l'état est bien `paused`.
    final before = ctrl.elapsedSeconds;
    await ctrl.resume();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(ctrl.elapsedSeconds, greaterThan(before),
        reason: 'resume() relance le ticker');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('le même scénario progresse normalement dès que le moteur complète',
      () async {
    installFakeTtsEngine(completesUtterances: true);
    final ctrl = _buildController();

    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 3));

    expect(ctrl.currentDisplayText, 'trois');
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(2));

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));
}

SessionController _buildController() {
  return SessionController(
    session: const Session(
      id: 'freeze',
      name: 'freeze',
      description: '',
      durationSeconds: 600,
      defaultMode: SessionMode.rhythm,
      steps: [
        SessionStep(time: 0, text: 'un', mode: SessionMode.rhythm),
        SessionStep(time: 1, text: 'deux', mode: SessionMode.rhythm),
        SessionStep(time: 2, text: 'trois', mode: SessionMode.rhythm),
      ],
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
/// `audioplayers` n'a pas d'implémentation dans l'environnement de test
/// (chaque `setSource` attendrait son timeout de préparation de 30 s).
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
