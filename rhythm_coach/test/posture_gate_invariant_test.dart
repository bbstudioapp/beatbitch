import 'dart:async';
import 'dart:io';

import 'package:beat_bitch/career/models/challenge.dart';
import 'package:beat_bitch/controllers/posture_gate.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/posture.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/models/session_step.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/capability_axis.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **Invariant du gel de posture (issue #77)** : un gel dont la justification
/// est tombée ne survit pas.
///
/// Ce fichier ne teste pas une liste de chemins — quatre chemins distincts ont
/// déjà laissé un gel orphelin derrière eux, et chaque correctif ciblé n'a
/// jamais rien dit du suivant. Il teste la *propriété* qui les rend tous
/// inoffensifs, y compris ceux qu'on écrira demain :
///
///   1. la justification elle-même, composante par composante ([PostureGate]) ;
///   2. son branchement en séance, sur un chemin de production auquel aucune
///      ligne de code ne parle du gel (la clôture d'un défi) ;
///   3. une garde qui devient rouge si quelqu'un recrée le motif — un chemin
///      qui « pense à lever le gate » plutôt que de le laisser tomber seul.
///
/// Tests runtime en temps réel : le `Stopwatch` du controller n'est pas simulé
/// par `flutter_test`, `pump()` n'avance pas son horloge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la justification, composante par composante', () {
    // Deux instances distinctes au contenu identique : c'est bien l'identité
    // de la timeline qui compte, pas son égalité de valeur. Deux `const
    // Session` identiques seraient canonicalisées en une seule instance et le
    // test ne dirait plus rien.
    // ignore: prefer_const_constructors
    Session buildSession() => Session(
          id: 'anchor',
          name: 'anchor',
          description: '',
          durationSeconds: 60,
          defaultMode: SessionMode.rhythm,
          steps: const [
            SessionStep(time: 0, mode: SessionMode.rhythm, bpm: 80),
          ],
        );

    final session = buildSession();
    final gate = PostureGate(
      session: session,
      nextStepIndex: 3,
      timelineOffset: const Duration(seconds: -2),
      failGeneration: 1,
    );

    bool holdsWith({
      Session? session_,
      int? nextStepIndex,
      Duration? timelineOffset,
      int? failGeneration,
      bool otherSceneActive = false,
    }) =>
        gate.stillHolds(
          session: session_ ?? session,
          nextStepIndex: nextStepIndex ?? 3,
          timelineOffset: timelineOffset ?? const Duration(seconds: -2),
          failGeneration: failGeneration ?? 1,
          otherSceneActive: otherSceneActive,
        );

    test('la situation où l\'ordre a été donné : le gel tient', () {
      expect(holdsWith(), isTrue);
    });

    test('horloge reculée d\'un tick : le gel tient — c\'est lui qui recule',
        () {
      expect(
          holdsWith(
              timelineOffset: const Duration(seconds: -2, milliseconds: -200)),
          isTrue);
    });

    test('timeline remplacée : le gel tombe', () {
      expect(holdsWith(session_: buildSession()), isFalse);
    });

    test('tête de lecture déplacée : le gel tombe', () {
      expect(holdsWith(nextStepIndex: 4), isFalse);
      expect(holdsWith(nextStepIndex: 2), isFalse);
    });

    test('horloge avancée : le gel tombe', () {
      expect(holdsWith(timelineOffset: const Duration(seconds: -1)), isFalse);
    });

    test('un flow d\'échec a pris la main : le gel tombe', () {
      expect(holdsWith(failGeneration: 2), isFalse);
    });

    test('une autre mise en scène tient l\'écran : le gel tombe', () {
      expect(holdsWith(otherSceneActive: true), isFalse);
    });
  });

  group('en séance, sur un chemin qui ignore tout du gel', () {
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
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi'
          '.toggle',
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

    // Pause [1,3) imposant `kneeling` à la reprise, et un défi dont le trigger
    // tombe exactement à `break.endTime` — ce que le générateur produisait
    // avant l'espacement des deux plannings, et ce qu'un décalage d'horloge
    // peut encore produire. Rien dans la clôture d'un défi
    // (`_completeChallenge` → `_excisChallengeFromSession`) ne connaît le gel
    // de posture : c'est précisément ce qui en fait un bon test d'invariant.
    SessionController buildController() => SessionController(
          staminaProfile: List<double>.filled(400, 100),
          session: const Session(
            id: 'gate-vs-challenge',
            name: 'gate-vs-challenge',
            description: '',
            durationSeconds: 300,
            defaultMode: SessionMode.rhythm,
            initialPose: Posture.free,
            breaks: [
              ScriptedBreak(
                time: 1,
                durationSeconds: 2,
                newPose: Posture.kneeling,
              ),
              // Pause encore à venir au moment du défi : elle doit lui
              // survivre, décalée comme les steps.
              ScriptedBreak(
                time: 100,
                durationSeconds: 60,
                newPose: Posture.standing,
              ),
            ],
            challenges: [
              Challenge(
                axis: CapabilityAxis.holdThroatStreak,
                kind: ChallengeAxisKind.duration,
                targetThreshold: 5,
                mode: SessionMode.hold,
              ),
            ],
            challengeTriggerTimes: [3],
            steps: [
              SessionStep(
                  time: 0, text: 'debut', mode: SessionMode.rhythm, bpm: 80),
              SessionStep(
                  time: 200, text: 'suite', mode: SessionMode.rhythm, bpm: 100),
            ],
          ),
          tts: TtsService(),
          beep: _SilentBeepEngine(),
          ambience: _SilentAmbienceEngine(),
          punishmentBundle: const PunishmentBundle(
            failPhrases: ['tu craques'],
            punishments: [],
          ),
          randomComments: const RandomCommentsBundle(
            comments: [],
            minIntervalSeconds: 999,
            maxIntervalSeconds: 999,
            scriptedCooldownSeconds: 4,
          ),
        );

    test(
        'une consigne concurrente n\'empile pas son bandeau sur l\'ordre de '
        'posture', () async {
      final ctrl = buildController();
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 3600));

      expect(ctrl.breakActive, isFalse, reason: 'pause finie à t≈3,6 s');
      expect(ctrl.challengePhase, ChallengePhase.breath,
          reason: 'le trigger défi est planifié à `break.endTime` : il s\'arme '
              'au même tick que la sortie de pause');
      expect(ctrl.awaitingPostureReady, isFalse,
          reason: 'le défi tient l\'écran : l\'ordre de posture n\'est plus la '
              'scène courante, deux consignes ne s\'empilent pas');

      await ctrl.stop();
    }, timeout: const Timeout(Duration(seconds: 40)));

    test(
        'la clôture d\'un défi ne laisse pas de gel derrière elle — et rien '
        'dans cette clôture ne parle du gel', () async {
      final ctrl = buildController();
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 3600));
      expect(ctrl.challengePhase, ChallengePhase.breath);

      // PASSE : `_completeChallenge` → `_startPostChallengeBreath` →
      // `_excisChallengeFromSession`. Ce chemin remplace la timeline sans
      // rien savoir de la pause qui vient de finir.
      ctrl.triggerChallengePass();
      expect(ctrl.challengePhase, ChallengePhase.ended);
      expect(ctrl.awaitingPostureReady, isFalse);

      // Respiration post-défi (10 s) puis reprise : c'est le gel lui-même
      // qu'on mesure, pas son drapeau — sans l'invariant, `_checkSteps`
      // retournerait tôt et `_onTick` décrémenterait l'horloge à chaque tick.
      final frozenAt = ctrl.elapsedSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 11500));
      expect(ctrl.awaitingPostureReady, isFalse);
      expect(ctrl.elapsedSeconds, greaterThan(frozenAt),
          reason: 'la séance repart après la respiration post-défi');

      await ctrl.stop();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('les pauses encore à venir survivent au défi', () async {
      final ctrl = buildController();
      await ctrl.start();
      await Future<void>.delayed(const Duration(milliseconds: 3600));
      expect(ctrl.challengePhase, ChallengePhase.breath);

      ctrl.triggerChallengePass();

      // L'excision reconstruit la séance ; sans report explicite,
      // `Session.breaks` retombait à `const []` et toute la mise en scène
      // restante disparaissait dès qu'un défi avait eu lieu.
      expect(ctrl.session.breaks.length, 2,
          reason: 'la liste garde sa longueur — `_nextBreakIndex` pointe '
              'dedans');
      // Fenêtre excisée = countdown (13 s) + durée nominale du défi (5 s) :
      // la pause d'après suit le même décalage que les steps.
      expect(ctrl.session.breaks[1].time, 100 - (13 + 5));
      expect(ctrl.session.breaks[1].newPose, Posture.standing);

      await ctrl.stop();
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  test('rien d\'autre que la scène qui l\'ordonne ne touche au gel de posture',
      () {
    // Le motif qui a produit les quatre gels orphelins : un chemin qui rebat
    // la timeline et qu'on corrige en lui faisant lever le gate. La garde
    // porte sur le **champ**, pas sur le nom d'une méthode : `_postureGate`
    // est privé à la library de `session_controller.dart`, donc chacun de ses
    // `part` peut y écrire sans jamais taper `confirmPostureReady`.
    const owner = 'lib/controllers/session_controller.dart';
    final library = <String>[owner];
    for (final line in File(owner).readAsLinesSync()) {
      final part = RegExp(r"^part '([^']+)';").firstMatch(line);
      if (part != null) library.add('lib/controllers/${part.group(1)}');
    }

    // Naissance de l'ancre, validation joueuse, ramasse-miettes du battement,
    // et les trois bornes de vie d'une séance. Ailleurs, il n'y a rien à
    // lever : le gel tombe seul quand sa justification tombe.
    const authorized = {
      '_enterAwaitReady',
      'confirmPostureReady',
      '_burySpentPostureGate',
      'start',
      'stop',
      '_finish',
    };

    final touchedBy = <String, List<String>>{};
    final write = RegExp(r'_postureGate\s*=(?!=)');
    // Une déclaration de membre, et rien du corps qui la suit : `dart format`
    // pose les membres à exactement deux espaces et tout leur contenu plus
    // loin — d'où le « pas d'espace de plus » qui distingue les deux.
    final member = RegExp(r'^  (?=\S)[\w<>?,\s\[\]]*\b(\w+)\s*\(');
    for (final path in library) {
      final lines = File(path).readAsLinesSync();
      var current = '<hors membre>';
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final signature = member.firstMatch(line);
        if (signature != null) current = signature.group(1)!;
        if (!write.hasMatch(line) && !line.contains('confirmPostureReady')) {
          continue;
        }
        touchedBy
            .putIfAbsent(current, () => <String>[])
            .add('$path:${i + 1} — ${line.trim()}');
      }
    }

    final detail = touchedBy.entries
        .map((e) => '  ${e.key}\n    ${e.value.join('\n    ')}')
        .join('\n');
    expect(touchedBy.keys.toSet(), authorized,
        reason: 'le gel de posture est dérivé de la scène qui l\'a ordonné : '
            'un chemin qui rebat la timeline n\'a rien à lever, et aucun '
            'autre n\'a à y toucher.\nSites trouvés :\n$detail');
  });
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
