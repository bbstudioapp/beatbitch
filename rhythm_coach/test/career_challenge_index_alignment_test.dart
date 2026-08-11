import 'dart:async';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `session.challenges` et `session.challengeTriggerTimes` sont indexées par
/// la même position côté contrôleur (`_updateChallengePhase` lit
/// `challengeTriggerTimes[i]` pour `challenges[i]`). Le générateur découpait
/// la première sur un curseur qui avance **aussi** quand un défi est écarté
/// faute de place, alors que la seconde ne reçoit une entrée que pour les
/// défis réellement insérés : un seul défi écarté suffisait à décaler les
/// deux listes, et l'indexation croisée sortait des bornes dans le ticker.
///
/// Le cas structurel : les trigger times sont répartis à 20/50/80 % du budget
/// sans tenir compte de la taille du défi, donc un gros défi (endurance
/// 530 s) planifié en dernier n'a jamais la place de s'insérer.
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

  Session generateWithBigChallengeLast(int seed) =>
      CareerSessionGenerator(seed: seed)
          .generate(
            level: 8,
            bank: _bank(),
            unlockedKeys: _allUnlocks,
            lengthChoice: SessionLengthChoice.moyenne,
            sessionsCompleted: 40,
            challenge: const ChallengeInputs(challenges: _bigLast),
          )
          .session;

  for (final seed in [1, 7, 42]) {
    test('seed $seed : les défis annoncés sont ceux qui ont un trigger time',
        () {
      final session = generateWithBigChallengeLast(seed);
      expect(
        session.challenges,
        hasLength(session.challengeTriggerTimes.length),
        reason: 'un défi sans trigger time ne peut jamais être armé : le '
            'contrôleur indexe les deux listes par la même position, '
            'challenges=${session.challenges.length} '
            'triggerTimes=${session.challengeTriggerTimes.length}',
      );
    });
  }

  test('le ticker ne sort pas des bornes sur une séance à défi écarté',
      () async {
    final session = generateWithBigChallengeLast(1);
    final ctrl = SessionController(
      session: session,
      tts: TtsService(),
      beep: _SilentBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle:
          const PunishmentBundle(failPhrases: [], punishments: []),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
    );

    Object? caught;
    await runZonedGuarded(() async {
      await ctrl.start();
      // Quelques ticks (200 ms) suffisent : la boucle d'armement balaie
      // toute la liste des défis dès le premier.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await ctrl.stop();
    }, (error, _) => caught ??= error);

    expect(caught, isNull,
        reason: 'le ticker principal ne doit lever aucune erreur : une '
            'exception dans `Timer.periodic` ne s\'auto-annule pas, la '
            'séance gèle ou plante');
  }, timeout: const Timeout(Duration(seconds: 60)));
}

/// Le trio du retour utilisateur, gros défi **en dernier** : le tirage de
/// `ChallengeService.buildForSession` n'ordonne rien par taille, cet ordre
/// est aussi probable que les cinq autres.
const _bigLast = [
  Challenge(
    axis: CapabilityAxis.holdThroatStreak,
    kind: ChallengeAxisKind.duration,
    targetThreshold: 25,
    mode: SessionMode.hold,
    from: Position.throat,
    to: Position.throat,
    comfortAtCalibration: 17,
  ),
  Challenge(
    axis: CapabilityAxis.rhythmBpmCeilThroat,
    kind: ChallengeAxisKind.bpm,
    targetThreshold: 120,
    mode: SessionMode.rhythm,
    from: Position.head,
    to: Position.throat,
    bpm: 80,
    bpmEnd: 120,
    comfortAtCalibration: 80,
  ),
  Challenge(
    axis: CapabilityAxis.rhythmMotionStreak,
    kind: ChallengeAxisKind.duration,
    targetThreshold: 530,
    mode: SessionMode.rhythm,
    from: Position.head,
    to: Position.throat,
    bpm: 60,
    comfortAtCalibration: 353,
  ),
];

List<PhraseEntry> _p(List<String> texts) =>
    texts.map((t) => PhraseEntry(text: t)).toList();

PhraseBank _bank() => PhraseBank(
      byMode: {
        for (final m in SessionMode.values)
          m: {
            'soft': _p(['s']),
            'medium': _p(['m']),
            'hard': _p(['h']),
            'finale': _p(['f']),
          },
      },
      congrats: _p(['bravo']),
      intros: _p(['intro']),
    );

final Set<UnlockKey> _allUnlocks = UnlockKey.values.toSet();

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
