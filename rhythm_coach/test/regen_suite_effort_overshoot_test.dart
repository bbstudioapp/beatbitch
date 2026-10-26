import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/career/services/generation/career_session_generator.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/punishment.dart';
import 'package:beat_bitch/models/session.dart';
import 'package:beat_bitch/services/ambience_engine.dart';
import 'package:beat_bitch/services/beep_engine.dart';
import 'package:beat_bitch/services/punishment_loader.dart';
import 'package:beat_bitch/services/random_comments_loader.dart';
import 'package:beat_bitch/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, (call) async => null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      return 1;
    });
  });

  tearDown(() {
    for (final c in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(c, null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  List<PhraseEntry> phrases(List<String> t) =>
      t.map((s) => PhraseEntry(text: s)).toList();

  PhraseBank bank() => PhraseBank(
        byMode: {
          for (final m in SessionMode.values)
            m: {
              'soft': phrases(['s']),
              'medium': phrases(['m']),
              'hard': phrases(['h']),
              'finale': phrases(['f']),
            },
        },
        congrats: phrases(['bravo']),
        intros: phrases(['intro']),
      );

  test(
      'une suite régénérée sur l\'effort restant ne rallonge pas la séance '
      '(pauses éteintes)', () {
    final gaps = <int>[];
    final overshoots = <int>[];
    for (final choice in [
      SessionLengthChoice.courte,
      SessionLengthChoice.moyenne,
      SessionLengthChoice.longue,
    ]) {
      for (final cut in [300, 600]) {
        for (var seed = 0; seed < 20; seed++) {
          final original = CareerSessionGenerator(seed: seed)
              .generate(
                level: 10,
                bank: bank(),
                lengthChoice: choice,
                unlockedKeys: UnlockKey.values.toSet(),
              )
              .session;
          if (cut + 120 > original.durationSeconds) continue;
          overshoots.add(original.durationSeconds - choice.durationSeconds);
          final ctrl = _controller(original);
          final suite = CareerSessionGenerator(seed: seed + 1000)
              .generate(
                level: 10,
                bank: bank(),
                durationSeconds: ctrl.effortSecondsLeftFrom(cut),
                durationExcludesFinish: true,
                carry: ctrl.postureCarryFrom(cut),
                unlockedKeys: UnlockKey.values.toSet(),
              )
              .session;
          final regen = SessionController.buildPostChallengeRegenSession(
            previous: original,
            upcoming: suite,
            breathEnd: cut,
          );
          gaps.add(regen.durationSeconds - original.durationSeconds);
        }
      }
    }
    gaps.sort();
    overshoots.sort();
    // ignore: avoid_print
    print('écart suite − origine (s) : min ${gaps.first} '
        'médiane ${gaps[gaps.length ~/ 2]} max ${gaps.last} '
        '(n=${gaps.length}) ; dépassement de l\'origine sur le palier : '
        'min ${overshoots.first} médiane ${overshoots[overshoots.length ~/ 2]} '
        'max ${overshoots.last}');
    expect(gaps.length, greaterThan(50),
        reason: 'le balayage doit régénérer des suites');
    expect(gaps[gaps.length ~/ 2], lessThanOrEqualTo(15),
        reason: 'la suite rejoue la phase de fin déjà comptée dans la '
            'durée d\'origine : la séance rallonge à chaque régénération');
  });
}

SessionController _controller(Session session) => SessionController(
      session: session,
      tts: TtsService(),
      beep: _SilentBeepEngine(),
      ambience: _SilentAmbienceEngine(),
      punishmentBundle: const PunishmentBundle(
        failPhrases: ['tu craques'],
        punishments: [
          Punishment(id: 'p1', name: 'p1', durationSeconds: 0, steps: []),
        ],
      ),
      randomComments: const RandomCommentsBundle(
        comments: [],
        minIntervalSeconds: 999,
        maxIntervalSeconds: 999,
        scriptedCooldownSeconds: 4,
      ),
    );

class _SilentBeepEngine extends BeepEngine {
  @override
  Future<void> init() async {}
  @override
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {}
  @override
  Future<void> dispose() async {}
}

class _SilentAmbienceEngine extends AmbienceEngine {
  @override
  Future<void> play(String? assetPath) async {}
  @override
  Future<void> dispose() async {}
}
