import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beat_bitch/career/models/phrase_bank.dart';
import 'package:beat_bitch/controllers/session_controller.dart';
import 'package:beat_bitch/models/ambience_pack.dart';
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
/// Trois gardes couvrent ce cas depuis `fix/session-freeze-tts-guard` :
///  - le report d'un step est borné à `_maxTtsDeferTicks` (5 s), après quoi le
///    step est consommé quoi qu'il arrive (au pire une phrase est coupée) ;
///  - tous les chemins qui coupent le TTS avant de basculer d'état passent par
///    `_stopTtsBounded()` — `pause()`, `stop()`, `triggerFail()`,
///    `_runMiniPunishmentFlow()` et `requestUpgrade()` — pour que la séance
///    reste pilotable canal muet. (`start()` ne fait pas partie de ces
///    chemins : elle ne coupe rien, elle borne `_tts.init()`, un mécanisme
///    distinct.) ;
///  - les deux `speak` **attendus avant** une bascule d'état (phrase de fail,
///    phrase finale) passent par `_speakBounded()` — `SessionController
///    .ttsSpeakTimeout`, 20 s. C'est le Future de `speak()` lui-même qui ne se
///    résout jamais sur un moteur en panne : le watchdog de `TtsService` repose
///    `isSpeaking` mais ne le débloque pas.
///
/// Le dernier test couvre le même mode de panne sur l'autre canal attendu
/// avant une bascule d'état : le moteur d'ambiance.
///
/// Le premier test est calibré sur la valeur de `_maxTtsDeferTicks` : le faire
/// évoluer demande de recalculer les instants commentés dans son corps.
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

  /// Reproduit le plugin Android quand il a perdu sa connexion au service
  /// TTS : il remet `ttsStatus = null` et met TOUS les appels suivants en
  /// file d'attente sans jamais renvoyer de réponse. Ici seul `stop` est
  /// muet — c'est l'appel que tous les chemins de contrôle de séance
  /// attendent avant de basculer d'état.
  void installMuteStopTtsEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'stop') return Completer<Object?>().future;
      return 1;
    });
  }

  /// Même plugin en panne, côté `speak` cette fois : l'appel part, l'énoncé
  /// est annoncé (`speak.onStart`) et la réponse ne vient jamais. Avec
  /// `awaitSpeakCompletion(true)` (actif sur Android/iOS), c'est ce Future-là
  /// que les deux sites de bascule attendent — le watchdog de `TtsService` ne
  /// le débloque pas, il ne repose que le flag `isSpeaking`. `stop` répond
  /// normalement : c'est bien `speak` qu'on veut exercer ici, pas les gardes
  /// de coupure déjà couvertes plus haut.
  void installMuteSpeakTtsEngine() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVoices') return <dynamic>[];
      if (call.method == 'speak') {
        unawaited(pushFromEngine('speak.onStart', true));
        return Completer<Object?>().future;
      }
      return 1;
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
    // t≈1 s puis différé 5 s (borne) → consommé à t≈6 s ; step `trois`
    // (time=2) atteint à t≈7 s (l'horloge logique a pris 5 s de retard) puis
    // différé jusqu'à t≈12 s. À 8,5 s on est donc sur `deux`, avec ~2,5 s de
    // marge avant et ~3,5 s après.
    await Future<void>.delayed(const Duration(milliseconds: 8500));

    expect(ctrl.currentDisplayText, 'deux',
        reason: 'la séance progresse malgré un moteur TTS muet');
    expect(ctrl.elapsedSeconds, greaterThanOrEqualTo(1),
        reason: "l'horloge logique avance : le report est borné");
    expect(ctrl.isRunning, isTrue);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un canal TTS qui ne répond plus n\'empêche plus la bascule en pause',
      () async {
    installMuteStopTtsEngine();
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

  // ─── Les autres chemins qui coupent le TTS avant de basculer d'état ────
  //
  // Même schéma que l'ancien `pause()` : chronomètre et ticker arrêtés,
  // `await _tts.stop()`, puis seulement `_state = ...`. Tous passent
  // désormais par `_stopTtsBounded()`.

  test('un canal TTS muet n\'empêche pas le déclenchement du FAIL', () async {
    installMuteStopTtsEngine();
    // C'est le seul contrôle de séance visible en production : play/pause/stop
    // vivent derrière le toggle debug `showSessionControls`, off par défaut.
    final ctrl = _buildController(punishments: _punishmentBundle);
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // Non awaité : le flow fail enchaîne phrase + respiration + punition,
    // bien au-delà de la bascule d'état qui nous intéresse ici.
    unawaited(ctrl.triggerFail());
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(ctrl.isFailing, isTrue,
        reason: 'l\'état bascule malgré le canal muet');
    expect(ctrl.isRunning, isFalse);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un canal TTS muet n\'empêche pas une mini-punition de basculer',
      () async {
    installMuteStopTtsEngine();
    // Déclenchée automatiquement (~1 fois par minute en carrière), sans
    // aucune action de l'utilisatrice : une séance qui progresse bien peut
    // se figer spontanément au premier tirage.
    final ctrl = _buildController(punishments: _punishmentBundle);
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    unawaited(ctrl.debugRunMiniPunishment(_punishmentBundle.punishments.first));
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(ctrl.isFailing, isTrue);
    expect(ctrl.failPhase, FailPhase.punishment);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('un canal TTS muet n\'empêche pas la régénération « Utilise-moi »',
      () async {
    installMuteStopTtsEngine();
    final ctrl = _buildController();
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // Awaité volontairement : sans borne, `requestUpgrade` ne rend jamais la
    // main et le test tombe sur son timeout.
    await ctrl.requestUpgrade(
      insistentBeg: const SessionStep(
        time: 0,
        text: 'supplie',
        mode: SessionMode.beg,
        duration: 12,
      ),
      upcomingSession: const Session(
        id: 'up',
        name: 'up',
        description: '',
        durationSeconds: 600,
        defaultMode: SessionMode.rhythm,
        steps: [SessionStep(time: 0, text: 'apres', mode: SessionMode.rhythm)],
      ),
    );

    // `_nextStepIndex = 0` a bien été atteint, et le `_checkSteps()` de fin
    // de méthode a consommé le beg insistant posé à `elapsedSeconds`.
    expect(ctrl.currentDisplayText, 'supplie');
    expect(ctrl.isRunning, isTrue);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ─── Même mode de panne, canal d'ambiance ─────────────────────────────
  //
  // `_syncAmbienceToCurrentMode()` (→ `playForMode` → `play`) est attendue à
  // trois endroits du flow FAIL, tous en amont de `_state = running` : la
  // phase breath de `triggerFail`, et `_restorePreviousLoop` (appelée depuis
  // `triggerFail` et depuis le flow mini-punition). Un backend audio engorgé
  // y laissait la séance en `failing` pour toujours — ticker mort,
  // chronomètre mort, aucun recours : le symptôme d'origine sur un autre
  // canal.

  test(
      "un moteur d'ambiance qui ne répond plus n'empêche pas le flow FAIL de "
      'revenir en running', () async {
    installFakeTtsEngine(completesUtterances: true);
    final ambience = _StuckAmbienceEngine()..setPack(_stuckAmbiencePack);
    final ctrl = _buildController(
      punishments: _shortPunishmentBundle,
      ambience: ambience,
      // Stamina pleine → le flow fail prend la branche courte de sa phase
      // breath (3-5 s au lieu de 8-15 s). Ne change rien au chemin testé,
      // raccourcit juste le test.
      staminaProfile: List<double>.filled(600, 100),
    );

    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // Awaité volontairement : sans borne côté `AmbienceEngine.play`, le flow
    // ne rend jamais la main et le test tombe sur son timeout.
    await ctrl.triggerFail();

    expect(ctrl.isRunning, isTrue,
        reason: 'le flow FAIL repose bien la séance en running');
    expect(ctrl.isFailing, isFalse);
    expect(ambience.startAttempts, greaterThan(0),
        reason: 'le chemin bloquant a bien été emprunté');

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));

  // ─── Même mode de panne, sur `speak` cette fois ───────────────────────
  //
  // Deux `speak` sont attendus AVANT une bascule d'état — les seuls du
  // contrôleur dans ce cas, les autres sont fire-and-forget ou post-bascule.
  // Le canal n'a pas besoin d'être muet sur `stop` pour ça : il suffit que
  // l'énoncé démarre et ne se termine jamais.

  test(
      'un moteur qui ne rend jamais la main sur speak() ne fige plus le flow '
      'FAIL', () async {
    installMuteSpeakTtsEngine();
    final ctrl = _buildController(
      punishments: _shortPunishmentBundle,
      // Stamina pleine → branche courte de la phase breath, comme pour le
      // test d'ambiance. Ne change rien au chemin testé.
      staminaProfile: List<double>.filled(600, 100),
    );
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // Awaité volontairement : sans borne sur la phrase de fail, `triggerFail`
    // ne rend jamais la main et le test tombe sur son timeout — la séance
    // resterait en `failing`, ticker et chronomètre déjà arrêtés.
    await ctrl.triggerFail();

    expect(ctrl.isRunning, isTrue,
        reason: 'le flow FAIL repose bien la séance en running');
    expect(ctrl.isFailing, isFalse);

    await ctrl.stop();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
      'un moteur qui ne rend jamais la main sur speak() ne prive plus de '
      "l'écran de fin", () async {
    installMuteSpeakTtsEngine();
    // Une banque avec un pool `finale` pour le mode du dernier step de config
    // (rhythm) : sans elle, `_finish` ne prononce rien et ne traverse pas le
    // chemin testé.
    final ctrl = _buildController(phraseBank: _finalePhraseBank);
    await ctrl.start();
    await Future<void>.delayed(const Duration(seconds: 1));

    // Awaité volontairement, même raison : la phrase finale précède le chime
    // et `_state = finished` de dix lignes.
    await ctrl.debugFinishSuccess();

    expect(ctrl.isFinished, isTrue,
        reason: "l'écran de fin s'affiche malgré la phrase finale sans retour");
    expect(ctrl.isRunning, isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));

  // ─── Garde-fou de la valeur de la borne ───────────────────────────────
  //
  // `ttsSpeakTimeout` est serrée volontairement (20 s, pas les 60 s du
  // watchdog) : sur ces deux chemins l'utilisatrice vient d'agir. Ce qui rend
  // ce choix tenable, c'est que le contenu réellement atteignable par ces deux
  // sites en reste loin. Ce test échoue le jour où une phrase ajoutée s'en
  // approche — c'est alors un arbitrage à reprendre, pas une coupure à subir.

  test(
      "le contenu prononcé avant une bascule d'état reste loin sous la borne "
      'de speak', () {
    // Débit de référence du projet : le briefing du tutoriel (384 caractères)
    // tient en une trentaine de secondes au débit configuré. Même repère que
    // le watchdog de `TtsService`.
    const charsPerSecond = 384 / 30;
    // `{name}` est résolu AVANT le speak (`_tts.resolveText`). Le plus long
    // surnom livré fait 18 caractères ; on budgète large.
    const nameBudget = 24;
    // 70 % de la borne : les 30 % restants absorbent l'écart entre ce débit
    // estimé et le débit réel d'un moteur, qu'aucun test ne peut mesurer ici.
    final budget = SessionController.ttsSpeakTimeout * 0.7;
    final maxChars = (budget.inMilliseconds / 1000 * charsPerSecond).floor();

    final worst = _longestSpokenBeforeStateSwitch(nameBudget: nameBudget);

    expect(worst.length, lessThanOrEqualTo(maxChars),
        reason:
            'cette phrase demande ~${(worst.length / charsPerSecond).toStringAsFixed(1)} s '
            'à énoncer, pour une borne de '
            '${SessionController.ttsSpeakTimeout.inSeconds} s : la raccourcir, '
            'ou relever `SessionController.ttsSpeakTimeout` en connaissance de '
            'cause.\n${worst.origin} → « ${worst.text} »');
  });

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

/// Bundle minimal mais non vide : `triggerFail` a besoin d'une phrase de fail
/// et d'une punition à jouer, `debugRunMiniPunishment` d'une punition courte.
const _punishmentBundle = PunishmentBundle(
  failPhrases: ['tu craques'],
  punishments: [
    Punishment(
      id: 'p',
      name: 'p',
      durationSeconds: 6,
      steps: [SessionStep(time: 0, text: 'punition', mode: SessionMode.breath)],
    ),
  ],
);

/// Punition d'une seconde : le test d'ambiance traverse tout le flow FAIL,
/// on ne veut pas y ajouter la durée nominale de la punition partagée.
const _shortPunishmentBundle = PunishmentBundle(
  failPhrases: ['tu craques'],
  punishments: [
    Punishment(
      id: 'court',
      name: 'court',
      durationSeconds: 1,
      steps: [SessionStep(time: 0, mode: SessionMode.breath, duration: 1)],
    ),
  ],
);

/// Pack qui déclare un asset pour tous les modes : sans ça, `playForMode`
/// résout `null` (pack `none`) et n'atteint jamais la séquence bloquante.
final _stuckAmbiencePack = AmbiencePack(
  id: 'stuck',
  name: 'stuck',
  tracksByMode: {
    for (final m in SessionMode.values) m: 'audio/ambience/stuck.mp3',
  },
);

/// Banque minimale portant un pool `finale` pour `rhythm` — le mode du dernier
/// step de config de la session de test, celui que `_findFinalStep` retient.
/// Sans elle, `_finish` ne prononce pas de phrase finale.
const _finalePhraseBank = PhraseBank(
  byMode: {
    SessionMode.rhythm: {
      'finale': [PhraseEntry(text: 'je jouis')],
    },
  },
  congrats: [],
  intros: [],
);

/// Parcourt les pools que les deux `speak` bornés peuvent atteindre et retourne
/// l'énoncé le plus long, mesuré **après** résolution de `{name}` (c'est le
/// texte résolu qui part au moteur). Trois familles, et rien d'autre — c'est ce
/// qui rend la borne calibrable sur le contenu :
///  - `fail_phrases` / `fail_phrases_swallow` et les variantes
///    `progressPhrases.*.tapout` des coachs, pour la phrase de `triggerFail` ;
///  - le pool `finale`, global et surchargé par coach, pour `_finish`.
({String text, String origin, int length}) _longestSpokenBeforeStateSwitch({
  required int nameBudget,
}) {
  final root = Directory.current.path;
  final namePattern = RegExp(r'\{\s*name\s*\}', caseSensitive: false);
  ({String text, String origin, int length})? worst;

  void consider(Object? node, String origin) {
    if (node is! List) return;
    for (final raw in node) {
      final text = raw is String
          ? raw
          : (raw is Map && raw['text'] is String
              ? raw['text'] as String
              : null);
      if (text == null) continue;
      final grown =
          namePattern.allMatches(text).length * (nameBudget - '{name}'.length);
      final length = text.length + grown;
      if (worst == null || length > worst!.length) {
        worst = (text: text, origin: origin, length: length);
      }
    }
  }

  Map<String, dynamic> read(String path) =>
      jsonDecode(File('$root/$path').readAsStringSync())
          as Map<String, dynamic>;

  for (final suffix in const ['', '_de', '_en', '_es']) {
    final punishments = read('assets/punishments$suffix.json');
    consider(
        punishments['fail_phrases'], 'punishments$suffix.json fail_phrases');
    consider(punishments['fail_phrases_swallow'],
        'punishments$suffix.json fail_phrases_swallow');

    read('assets/career/phrases$suffix.json').forEach((mode, tiers) {
      if (tiers is Map) {
        consider(tiers['finale'], 'phrases$suffix.json $mode.finale');
      }
    });
  }

  for (final file in Directory('$root/assets/career/coaches')
      .listSync()
      .whereType<File>()) {
    if (!file.path.endsWith('.json')) continue;
    final name = file.uri.pathSegments.last;
    final coach = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final progress = coach['progressPhrases'];
    if (progress is Map) {
      progress.forEach((axis, tiers) {
        if (tiers is Map) consider(tiers['tapout'], '$name $axis.tapout');
      });
    }
    final byMode = coach['phrases'];
    if (byMode is Map) {
      byMode.forEach((mode, tiers) {
        if (tiers is Map) consider(tiers['finale'], '$name $mode.finale');
      });
    }
  }

  return worst!;
}

SessionController _buildController({
  PunishmentBundle? punishments,
  AmbienceEngine? ambience,
  List<double>? staminaProfile,
  PhraseBank? phraseBank,
}) {
  return SessionController(
    staminaProfile: staminaProfile,
    phraseBank: phraseBank,
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
    ambience: ambience ?? _SilentAmbienceEngine(),
    punishmentBundle:
        punishments ?? const PunishmentBundle(failPhrases: [], punishments: []),
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

/// Moteur d'ambiance dont le **backend** ne répond plus : la séquence de
/// démarrage (`stop` / `setSource` / `setVolume` / `resume` sur
/// `audioplayers`) ne se résout jamais.
///
/// Contrairement à [_SilentAmbienceEngine], `play` / `playForMode` ne sont
/// PAS surchargées — c'est `play` qui porte la borne, donc c'est elle qu'on
/// doit exercer. Un double qui remplace `play` par un no-op est exactement ce
/// qui a rendu ce trou invisible aux passes précédentes.
class _StuckAmbienceEngine extends AmbienceEngine {
  int startAttempts = 0;

  @override
  Future<void> startPlayback(String assetPath) {
    startAttempts++;
    return Completer<void>().future;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
