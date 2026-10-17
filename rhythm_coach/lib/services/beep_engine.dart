import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/final_category.dart';
import '../models/hold_move.dart';
import '../models/session.dart';
import '../models/session_music.dart';
import '../models/session_step.dart';
import 'step_resolution.dart';

class BeepEngine {
  static const String _tipAsset = 'tip_beep';
  static const String _headAsset = 'head_beep';
  static const String _midAsset = 'mid_beep';
  static const String _throatAsset = 'throat_beep';
  static const String _fullAsset = 'full_beep';
  static const String _ballsAsset = 'balls_beep';
  static const String _holdAsset = 'hold_beep';
  static const String _biffleAsset = 'biffle_beep';
  static const String _breathAsset = 'breath_beep';
  static const String _handDownAsset = 'hand_down_beep';
  static const String _handUpAsset = 'hand_up_beep';
  static const String _suckleAsset = 'suckle_beep';
  static const String _freestyleStartAsset = 'freestyle_start';
  static const String _freestyleEndAsset = 'freestyle_end';
  static const String _finaleChimeAsset = 'finale_chime';
  static const String _lickBallsAsset = 'lick_balls_beep';

  static const List<String> _allAssets = [
    _tipAsset,
    _headAsset,
    _midAsset,
    _throatAsset,
    _fullAsset,
    _ballsAsset,
    _holdAsset,
    _biffleAsset,
    _breathAsset,
    _handDownAsset,
    _handUpAsset,
    _suckleAsset,
    _freestyleStartAsset,
    _freestyleEndAsset,
    _finaleChimeAsset,
    _lickBallsAsset,
  ];

  static const double _rhythmVolume = 1.0;
  static const double _lickVolume = 0.65;
  static const double _handVolume = 0.85;
  static const double _holdLayerVolume = 0.9;
  static const double _breathVolume = 0.9;
  // Plus doux que rhythm : la bouche aspire, elle ne frappe pas.
  static const double _suckleVolume = 0.75;

  static const Duration _sucklePulse = Duration(milliseconds: 1200);

  /// Publiques : tout étage qui annonce un BPM (défis) doit s'aligner sur ce
  /// que le moteur peut jouer.
  static const int kMinBpm = 20;
  static const int kMaxBpm = 300;

  /// Round-robin : le décay d'un bip n'est jamais coupé par le suivant. À 3,
  /// des bips manquaient à BPM élevé et quand un hold superpose deux samples.
  static const int _poolSize = 4;

  /// `seek(Duration.zero)` forcé avant chaque `resume()` : sur Android,
  /// audioplayers ignore sans erreur un `resume()` tant qu'il n'a pas vu
  /// `onPlayerComplete`, et le bip est perdu. Les sons joués une seule fois
  /// par séance en sont exclus.
  static const Set<String> _longSampleAssets = {
    _tipAsset,
    _headAsset,
    _midAsset,
    _throatAsset,
    _fullAsset,
    _ballsAsset,
    _holdAsset,
    _biffleAsset,
    _breathAsset,
    _handDownAsset,
    _handUpAsset,
    _suckleAsset,
    _lickBallsAsset,
  };

  final Map<String, _PlayerPool> _pools = {};
  final Random _random = Random();
  bool _initialized = false;

  Map<FinalCategory, List<String>> _finaleVariants =
      const <FinalCategory, List<String>>{};

  SessionMode _mode = SessionMode.rhythm;
  Position _from = Position.head;
  Position? _to;
  int _bpm = 60;

  int? _bpmEnd;

  int? _loopDurationMs;

  /// À `true` : le premier beat tombe sur la profondeur cible `to`, pas sur
  /// le point de départ.
  bool _alternateToggle = true;

  BeatAnchor _anchor = BeatAnchor.none;

  int _ratio = 1;

  @visibleForTesting
  void Function(String asset, double volume)? debugOnTrigger;

  /// Temps écoulé hors pauses : une reprise replanifie les mouvements restants.
  List<HoldMove> _moves = const [];
  int _holdElapsedMs = 0;
  int? _holdResumedAtMs;

  bool _handStrokeFallbackDown = true;

  Timer? _loopTimer;

  SessionMusic? _music;
  Duration Function()? _musicPosition;
  double _beepGain = 1.0;

  /// Invalide la continuation d'un callback de loop déjà en cours
  /// d'exécution, que `cancel()` ne peut plus arrêter.
  int _loopGen = 0;

  Timer? _freestyleEndTimer;

  Timer? _suckleTimer;

  void Function(BeatEvent event)? onBeat;

  int _stepSerial = 0;
  final StreamController<BeatEvent> _beatController =
      StreamController<BeatEvent>.broadcast();
  Stream<BeatEvent> get beatStream => _beatController.stream;

  /// Aucun appel audioplayers du chargement n'est borné et le démarrage de
  /// séance attend cet init : un `setSource` muet la figerait avant son départ.
  static const Duration _initTimeout = Duration(seconds: 5);

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _loadPools().timeout(_initTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[BeepEngine] init interrompu : $e');
    }
    // Posé même après un timeout : sinon chaque `applyStep` relancerait un
    // chargement non borné.
    _initialized = true;
  }

  Future<void> _loadPools() async {
    final assetsToLoad = <String>{..._allAssets};
    _finaleVariants = await _loadFinaleVariants();
    for (final list in _finaleVariants.values) {
      assetsToLoad.addAll(list);
    }
    for (final name in assetsToLoad) {
      final players = <AudioPlayer>[];
      final isFinaleVariant = _finaleVariants.values
          .any((list) => list.contains(name) && name != _finaleChimeAsset);
      final poolSize = isFinaleVariant ? 1 : _poolSize;
      final assetPath =
          isFinaleVariant ? 'audio/finale/$name.mp3' : 'audio/$name.mp3';
      for (var i = 0; i < poolSize; i++) {
        try {
          final p = AudioPlayer(playerId: 'beep_${name}_$i')
            // Sans ça, audioplayers interroge la position de chaque lecteur
            // à chaque image tant qu'il joue, via le canal natif.
            ..positionUpdater = null;
          await p.setReleaseMode(ReleaseMode.stop);
          await p.setSource(AssetSource(assetPath));
          players.add(p);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[BeepEngine] échec chargement $name #$i : $e');
          }
        }
      }
      if (players.isNotEmpty) {
        _pools[name] = _PlayerPool(players);
      }
    }
  }

  Future<Map<FinalCategory, List<String>>> _loadFinaleVariants() async {
    try {
      final raw =
          await rootBundle.loadString('assets/audio/finale_chimes.json');
      final data = json.decode(raw) as Map<String, dynamic>;
      final out = <FinalCategory, List<String>>{};
      for (final cat in FinalCategory.values) {
        final list = data[cat.serialized];
        if (list is List && list.isNotEmpty) {
          out[cat] = list.whereType<String>().toList();
        }
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BeepEngine] finale_chimes.json absent ou invalide ($e)');
      }
      return const {};
    }
  }

  /// Assez pour que le sample précédent finisse son décay.
  static const Duration _modeTransitionGap = Duration(milliseconds: 600);

  /// Assez pour que l'annonce soit posée et que le geste change avant le
  /// premier bip.
  static const Duration _modeTransitionGapBig = Duration(milliseconds: 1500);

  /// Non nul : sans pause, la nouvelle config démarre par-dessus la fin du
  /// beat précédent.
  static const Duration _sameModeTransitionGap = Duration(milliseconds: 300);

  static bool _needsBigGap(SessionMode incoming, Position? incomingTo) {
    switch (incoming) {
      case SessionMode.lick:
      case SessionMode.hand:
      case SessionMode.biffle:
      case SessionMode.breath:
      case SessionMode.freestyle:
      case SessionMode.suckle:
        return true;
      case SessionMode.beg:
        return incomingTo == null;
      case SessionMode.rhythm:
      case SessionMode.hold:
        return false;
    }
  }

  static Duration transitionGap({
    required SessionMode incoming,
    required SessionMode? previous,
    Position? incomingTo,
  }) {
    if (incoming == previous) return _sameModeTransitionGap;
    return _needsBigGap(incoming, incomingTo)
        ? _modeTransitionGapBig
        : _modeTransitionGap;
  }

  /// L'ancrage vient de `step.anchor` et pas d'un paramètre : les reprises
  /// (fail flow, défis) rejouent un `SessionStep` déjà construit.
  Future<void> applyStep(
    SessionStep step,
    SessionMode sessionMode,
  ) async {
    if (step.isTextOnly) return;
    _stepSerial++;
    if (!_initialized) await init();

    final resolved = resolveStepConfig(
      step: step,
      defaultMode: sessionMode,
      currentFrom: _from,
      currentBpm: _bpm,
    );
    final mode = resolved.mode;
    final previousMode = _mode;
    _mode = mode;
    _anchor = step.anchor;
    _ratio = step.ratio;
    _moves = step.moves;
    _holdResumedAtMs = null;
    _bpm = resolved.bpm;
    if (step.bpmEnd != null &&
        step.bpmEnd != step.bpm &&
        step.duration != null &&
        step.duration! > 0) {
      _bpmEnd = step.bpmEnd!.clamp(kMinBpm, kMaxBpm);
      _loopDurationMs = step.duration! * 1000;
    } else {
      _bpmEnd = null;
      _loopDurationMs = null;
    }

    _from = resolved.from;
    _to = resolved.to;

    if ((mode == SessionMode.rhythm || mode == SessionMode.lick) &&
        _to != null &&
        _to == _from) {
      _from = _pickShallowerThan(_from);
    }

    _alternateToggle = true;
    _handStrokeFallbackDown = true;
    _stopLoop();
    _freestyleEndTimer?.cancel();
    _freestyleEndTimer = null;
    _suckleTimer?.cancel();
    _suckleTimer = null;

    await Future<void>.delayed(
      transitionGap(
          incoming: mode, previous: previousMode, incomingTo: step.to),
    );
    // Un `applyStep` plus récent a pu passer pendant la pause : il gagne.
    if (_mode != mode) return;

    switch (mode) {
      case SessionMode.rhythm:
        _startBeatLoop(volume: _rhythmVolume);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume);
      case SessionMode.hand:
        _startBeatLoop(volume: _handVolume);
      case SessionMode.biffle:
        _startBiffleLoop();
      case SessionMode.hold:
        // En hold, `_to` porte la position tenue ; sans position plus aiguë,
        // pas d'aller-retour possible.
        if (_anchor == BeatAnchor.to && _to != null && _to!.index > 0) {
          _startHoldSwingLoop(_to!);
        } else {
          _playHoldOneShot(_from);
          _holdElapsedMs = 0;
          _startHoldMoves();
        }
      case SessionMode.breath:
        _playBreathOneShot();
      case SessionMode.freestyle:
        _trigger(_freestyleStartAsset, _rhythmVolume);
        final dur = step.duration;
        if (dur != null && dur > 0) {
          _freestyleEndTimer = Timer(Duration(seconds: dur), () {
            _trigger(_freestyleEndAsset, _rhythmVolume);
          });
        }
      case SessionMode.beg:
        if (step.to != null) {
          _playHoldOneShot(step.to!);
        }
        break;
      case SessionMode.suckle:
        _startSuckleLoop(step.duration);
        break;
    }
  }

  void _startSuckleLoop(int? durationSec) {
    _trigger(_suckleAsset, _suckleVolume);
    final endMs = (durationSec != null && durationSec > 0)
        ? DateTime.now().millisecondsSinceEpoch + durationSec * 1000
        : null;
    _suckleTimer = Timer.periodic(_sucklePulse, (timer) {
      if (endMs != null && DateTime.now().millisecondsSinceEpoch >= endMs) {
        timer.cancel();
        return;
      }
      _trigger(_suckleAsset, _suckleVolume);
    });
  }

  /// Chaque beat planifie le suivant sur un temps cible absolu, pas via
  /// `Timer.periodic` qui dérive de quelques ms par tick.
  void _startBeatLoop({required double volume}) {
    if (_music != null) {
      _startGridLoop(volume: volume);
      return;
    }
    final myGen = ++_loopGen;
    final startMs = DateTime.now().millisecondsSinceEpoch;
    // Cumul plutôt que `startMs + n × intervalMs` : rampe et ancrage font
    // varier l'intervalle d'un tick à l'autre.
    var lastTargetMs = startMs;
    void tick() {
      if (myGen != _loopGen) return;
      final elapsedMs = lastTargetMs - startMs;
      final currentBpm = _currentInterpolatedBpm(elapsedMs);
      final intervalMs = _emitPositionBeat(volume, currentBpm);
      lastTargetMs += intervalMs;
      final delayMs =
          max(1, lastTargetMs - DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), tick);
    }

    tick();
  }

  void _trigger(String assetName, double baseVolume) {
    final volume = baseVolume * _beepGain;
  double _currentInterpolatedBpm(int elapsedMs) {
    final bpmEnd = _bpmEnd;
    final dur = _loopDurationMs;
    if (bpmEnd == null || dur == null || dur <= 0) {
      return _bpm.toDouble();
    }
    final t = (elapsedMs / dur).clamp(0.0, 1.0);
    return _bpm + (bpmEnd - _bpm) * t;
  }

  int _emitPositionBeat(double baseVolume, double currentBpm) {
    final pos = _pickPosition();
    final intervalMs = _intervalAfter(pos, currentBpm);
    if (_mode == SessionMode.hand) {
      final (asset, vol) = _resolveHandBeat(pos, baseVolume);
      _trigger(asset, vol);
    } else {
      _trigger(_assetForPosition(pos), baseVolume);
    }
    _notifyBeat(_mode, pos, Duration(milliseconds: intervalMs), currentBpm);
    return intervalMs;
  }

  int _regularInterval(double bpm) => (60000 / bpm).round();

  /// Le court se déduit du long par soustraction, pas par un arrondi
  /// indépendant : leur somme reste exactement `2T` arrondi.
  int _intervalAfter(Position emittedPos, double bpm) {
    final to = _to;
    // Sans amplitude, ancrer rendrait tous les intervalles longs et le cycle
    // ne vaudrait plus `2T` ; un `ratio` ≤ 1 donnerait un intervalle ≤ 0.
    if (_anchor == BeatAnchor.none ||
        _ratio <= 1 ||
        to == null ||
        to == _from) {
      return _regularInterval(bpm);
    }
    final fullCycle = 2 * 60000 / bpm;
    final fullCycleMs = fullCycle.round();
    final longMs = (fullCycle * _ratio / (_ratio + 1)).round();
    final isAnchored = (_anchor == BeatAnchor.from && emittedPos == _from) ||
        (_anchor == BeatAnchor.to && emittedPos == _to);
    return isAnchored ? longMs : fullCycleMs - longMs;
  }

  @visibleForTesting
  void configureBeatSourceForTest({
    required SessionMode mode,
    required Position from,
    required Position? to,
    BeatAnchor anchor = BeatAnchor.none,
    int ratio = 1,
  }) {
    _mode = mode;
    _from = from;
    _to = to;
    _anchor = anchor;
    _ratio = ratio;
    _alternateToggle = true;
  }

  @visibleForTesting
  Duration emitOneBeatForTest(double bpm) =>
      Duration(milliseconds: _emitPositionBeat(_rhythmVolume, bpm));

  /// Capture via `onBeat` (synchrone), pas `beatStream` (broadcast
  /// asynchrone).
  @visibleForTesting
  List<BeatEvent> simulateBeatsForTest({
    required SessionMode mode,
    required Position from,
    required Position? to,
    required double bpm,
    BeatAnchor anchor = BeatAnchor.none,
    int ratio = 1,
    required int count,
  }) {
    configureBeatSourceForTest(
        mode: mode, from: from, to: to, anchor: anchor, ratio: ratio);
    final events = <BeatEvent>[];
    final previousOnBeat = onBeat;
    onBeat = events.add;
    for (var i = 0; i < count; i++) {
      emitOneBeatForTest(bpm);
    }
    onBeat = previousOnBeat;
    return events;
  }

  (String, double) _resolveHandBeat(Position pos, double baseVolume) {
    final to = _to;
    final bool isDown;
    final Position depthRef;
    if (to == null || to == _from) {
      isDown = _handStrokeFallbackDown;
      _handStrokeFallbackDown = !_handStrokeFallbackDown;
      depthRef = _from;
    } else {
      final deeper = to.index >= _from.index ? to : _from;
      isDown = pos == deeper;
      depthRef = deeper;
    }
    if (isDown) {
      final factor =
          0.7 + 0.3 * (depthRef.index / (Position.values.length - 1));
      return (_handDownAsset, baseVolume * factor);
    }
    return (_handUpAsset, baseVolume * 0.85);
  }

  void _notifyBeat(
      SessionMode mode, Position pos, Duration nextInterval, double bpm) {
    final event = BeatEvent(
      mode: mode,
      position: pos,
      from: _from,
      to: _to,
      nextInterval: nextInterval,
      bpm: bpm,
    );
    onBeat?.call(event);
    if (!_beatController.isClosed) _beatController.add(event);
  }

  Position _pickShallowerThan(Position p) {
    final shallower = Position.values.where((x) => x.index < p.index).toList();
    if (shallower.isEmpty) return p;
    return shallower[_random.nextInt(shallower.length)];
  }

  Position _pickPosition() {
    final to = _to;
    if (to == null || to == _from) return _from;
    final pos = _alternateToggle ? to : _from;
    _alternateToggle = !_alternateToggle;
    return pos;
  }

  void _startBiffleLoop() {
    final myGen = ++_loopGen;
    final startMs = DateTime.now().millisecondsSinceEpoch;
    // Biffle ignore l'ancrage : toujours l'intervalle régulier.
    var lastTargetMs = startMs;
    void tick() {
      if (myGen != _loopGen) return;
      final elapsedMs = lastTargetMs - startMs;
      final currentBpm = _currentInterpolatedBpm(elapsedMs);
      final intervalMs = _regularInterval(currentBpm);
      _trigger(_biffleAsset, _rhythmVolume);
      _notifyBeat(SessionMode.biffle, _to ?? _from,
          Duration(milliseconds: intervalMs), currentBpm);
      lastTargetMs += intervalMs;
      final delayMs =
          max(1, lastTargetMs - DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), tick);
    }

    tick();
  }

  void _playHoldOneShot(Position position) {
    _trigger(_assetForPosition(position), _rhythmVolume);
    _trigger(_holdAsset, _holdLayerVolume);
  }

  /// Fixe et non tiré au hasard : le hasard appartient au générateur, pas à
  /// ce moteur de lecture.
  static const int _holdFinalAnchorSwings = 4;

  /// Arithmétique de [_intervalAfter] dupliquée, pas réutilisée : lui lit
  /// `_from`/`_to`/`_anchor`, et `_from` doit rester la position tenue
  /// pendant le swing ([currentFrom] la lit).
  List<(Position, int)> _holdSwingSequence({
    required Position anchorPos,
    required double bpm,
    required int ratio,
    required int swings,
  }) {
    final upPos = Position.values[anchorPos.index - 1];
    final fullCycle = 2 * 60000 / bpm;
    final longMs = (fullCycle * ratio / (ratio + 1)).round();
    final shortMs = fullCycle.round() - longMs;
    final out = <(Position, int)>[];
    for (var i = 0; i < swings; i++) {
      out.add((upPos, longMs));
      out.add((anchorPos, shortMs));
    }
    return out;
  }

  void _startHoldSwingLoop(Position anchorPos) {
    _playHoldOneShot(anchorPos);
    final sequence = _holdSwingSequence(
      anchorPos: anchorPos,
      bpm: _bpm.toDouble(),
      ratio: _ratio,
      swings: _holdFinalAnchorSwings,
    );
    final myGen = ++_loopGen;
    var lastTargetMs = DateTime.now().millisecondsSinceEpoch;
    void scheduleAt(int i) {
      if (myGen != _loopGen || i >= sequence.length) return;
      final (pos, intervalMs) = sequence[i];
      lastTargetMs += intervalMs;
      final delayMs =
          max(1, lastTargetMs - DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), () {
        if (myGen != _loopGen) return;
        _trigger(_assetForPosition(pos), _rhythmVolume);
        scheduleAt(i + 1);
      });
    }

    scheduleAt(0);
  }

  @visibleForTesting
  List<(Position, int)> holdSwingSequenceForTest({
    required Position anchorPos,
    required double bpm,
    required int ratio,
    int swings = _holdFinalAnchorSwings,
  }) =>
      _holdSwingSequence(
          anchorPos: anchorPos, bpm: bpm, ratio: ratio, swings: swings);

  void _playBreathOneShot() {
    _trigger(_breathAsset, _breathVolume);
  }

  /// Déclenche un sample en utilisant le prochain player du pool round-robin.
  /// Fire-and-forget : le ticker n'attend pas la fin de l'opération audio.
  void _trigger(String assetName, double baseVolume) {
    final volume = baseVolume * _beepGain;
    debugOnTrigger?.call(assetName, volume);
    final pool = _pools[assetName];
    if (pool == null) return;
    final picked = pool.next(volume);
    final needsReplaySeek = _longSampleAssets.contains(assetName);
    () async {
      // `try` indépendants : une PlatformException ponctuelle d'Android sur
      // une étape ne doit pas sauter les suivantes. `setVolume` sauté s'il
      // n'a pas changé : un appel canal de moins, moins de bips perdus.
      if (picked.volumeChanged) {
        try {
          await picked.player.setVolume(volume);
        } catch (e) {
          if (kDebugMode) debugPrint('[BeepEngine] setVolume error : $e');
        }
      }
      if (needsReplaySeek) {
        // Borné : sous forte charge, le `MediaPlayer` natif ne répond plus au
        // `seek()`, qui n'aboutit qu'au timeout interne d'audioplayers (30 s).
        try {
          await picked.player
              .seek(Duration.zero)
              .timeout(const Duration(milliseconds: 250));
        } catch (e) {
          if (kDebugMode) debugPrint('[BeepEngine] seek error : $e');
        }
      }
      try {
        await picked.player.resume();
      } catch (e) {
        if (kDebugMode) debugPrint('[BeepEngine] resume error : $e');
      }
    }();
  }

  String _assetForPosition(Position p) => switch (p) {
        Position.tip => _tipAsset,
        Position.head => _headAsset,
        Position.mid => _midAsset,
        Position.throat => _throatAsset,
        Position.full => _fullAsset,
        Position.balls => _ballsAsset,
      };

  /// Instants pris dans [holdKeyframes], la source que dessine aussi la
  /// courbe.
  void _startHoldMoves() {
    final frames =
        holdKeyframes(_from, _moves).where((k) => k.beep != null).toList();
    if (frames.isEmpty) return;
    final myGen = ++_loopGen;
    final originMs = DateTime.now().millisecondsSinceEpoch - _holdElapsedMs;
    _holdResumedAtMs = originMs;
    void scheduleFrom(int i) {
      if (myGen != _loopGen) return;
      while (
          i < frames.length && frames[i].at.inMilliseconds < _holdElapsedMs) {
        i++;
      }
      if (i >= frames.length) return;
      final delayMs = max(
          0,
          originMs +
              frames[i].at.inMilliseconds -
              DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), () {
        if (myGen != _loopGen) return;
        _trigger(
            frames[i].tongue
                ? _lickBallsAsset
                : _assetForPosition(frames[i].beep!),
            _rhythmVolume * frames[i].volume);
        scheduleFrom(i + 1);
      });
    }

    scheduleFrom(0);
  }

  void _stopLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _loopGen++;
  }

  // ─── API publique pour la page démo ─────────────────────────────────────

  Future<void> ensureReady() => init();

  Future<void> setMixWithOthers(bool mix) async {
    final ctx = AudioContextConfig(
      focus: mix
          ? AudioContextConfigFocus.mixWithOthers
          : AudioContextConfigFocus.gain,
    ).build();
    // Le contexte global ne suffit pas : chaque player déjà créé garde le sien
    // et couperait le son en cours à sa première lecture.
    await AudioPlayer.global.setAudioContext(ctx);
    await Future.wait([
      for (final pool in _pools.values)
        for (final p in pool.players) p.setAudioContext(ctx),
    ]);
  }

  void playPositionOnce(Position p) {
    if (!_initialized) return;
    _trigger(_assetForPosition(p), _rhythmVolume);
  }

  void playLickPositionOnce(Position p) {
    if (!_initialized) return;
    _trigger(_assetForPosition(p), _lickVolume);
  }

  void playHoldOnce(Position p) {
    if (!_initialized) return;
    _playHoldOneShot(p);
  }

  void playBiffleOnce() {
    if (!_initialized) return;
    _trigger(_biffleAsset, _rhythmVolume);
  }

  void playBreathOnce() {
    if (!_initialized) return;
    _playBreathOneShot();
  }

  void playSuckleOnce() {
    if (!_initialized) return;
    _trigger(_suckleAsset, _suckleVolume);
  }

  void startRhythmDemo({
    required Position from,
    Position? to,
    required int bpm,
  }) {
    if (!_initialized) return;
    _mode = SessionMode.rhythm;
    _from = from;
    _to = to;
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = true;
    _anchor = BeatAnchor.none;
    _ratio = 1;
    _stopLoop();
    _startBeatLoop(volume: _rhythmVolume);
  }

  void startLickDemo({
    required Position from,
    Position? to,
    required int bpm,
  }) {
    if (!_initialized) return;
    _mode = SessionMode.lick;
    _from = from;
    _to = to;
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = true;
    _anchor = BeatAnchor.none;
    _ratio = 1;
    _stopLoop();
    _startBeatLoop(volume: _lickVolume);
  }

  void startBiffleDemo({required int bpm}) {
    if (!_initialized) return;
    _mode = SessionMode.biffle;
    _bpm = bpm.clamp(kMinBpm, kMaxBpm);
    _stopLoop();
    _startBiffleLoop();
  }

  void playFreestyleStartOnce() {
    if (!_initialized) return;
    _trigger(_freestyleStartAsset, _rhythmVolume);
  }

  void playFreestyleEndOnce() {
    if (!_initialized) return;
    _trigger(_freestyleEndAsset, _rhythmVolume);
  }

  /// Complète à la fin du sample, borné à 5 s : `onPlayerComplete` peut ne
  /// jamais arriver.
  Future<void> playFinaleChime(
      {FinalCategory? category, double volume = 1.0}) async {
    if (!_initialized) return;
    final variants = category != null ? _finaleVariants[category] : null;
    final asset = (variants != null && variants.isNotEmpty)
        ? variants[_random.nextInt(variants.length)]
        : _finaleChimeAsset;
    final pool = _pools[asset];
    if (pool == null) return;
    final player = pool.next().player;
    try {
      // Borné : la fin de séance attend ce chime, un backend muet la
      // laisserait sans écran de fin.
      await player
          .setVolume(volume.clamp(0.0, 1.0))
          .timeout(const Duration(milliseconds: 300));
      await player.resume().timeout(const Duration(milliseconds: 300));
      await player.onPlayerComplete.first
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (e) {
      if (kDebugMode) debugPrint('[BeepEngine] finale chime error : $e');
    }
  }

  bool get isLooping => _loopTimer != null;

  // ─── État courant exposé pour l'affichage UI ───────────────────────────

  SessionMode get currentMode => _mode;

  /// Distingue une réapplication à configuration identique, qui passe quand
  /// même par le gap de transition.
  int get stepSerial => _stepSerial;

  Position get currentFrom => _from;
  Position? get currentTo => _to;
  int get currentBpm => _bpm;
  List<HoldMove> get currentMoves => _moves;

  // ─── Cycle de vie ──────────────────────────────────────────────────────

  Future<void> pause() async {
    final resumedAt = _holdResumedAtMs;
    if (_mode == SessionMode.hold && resumedAt != null) {
      _holdElapsedMs = DateTime.now().millisecondsSinceEpoch - resumedAt;
      _holdResumedAtMs = null;
    }
    _stopLoop();
    _freestyleEndTimer?.cancel();
    _freestyleEndTimer = null;
    _suckleTimer?.cancel();
    _suckleTimer = null;
    for (final pool in _pools.values) {
      for (final p in pool.players) {
        try {
          // Borné : sur un backend audio engorgé, `stop()` peut ne jamais
          // rendre la main.
          await p.stop().timeout(const Duration(milliseconds: 300));
        } catch (_) {}
      }
    }
  }

  Future<void> resume() async {
    _stopLoop();
    switch (_mode) {
      case SessionMode.rhythm:
        _startBeatLoop(volume: _rhythmVolume);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume);
      case SessionMode.hand:
        _startBeatLoop(volume: _handVolume);
      case SessionMode.biffle:
        _startBiffleLoop();
      case SessionMode.hold:
        _startHoldMoves();
      case SessionMode.breath:
      case SessionMode.beg:
      case SessionMode.freestyle:
        break;
      case SessionMode.suckle:
        // Durée résiduelle inconnue ici : pulse indéfini, coupé par le step
        // suivant.
        _startSuckleLoop(null);
        break;
    }
  }

  Future<void> stop() async {
    await pause();
  }

  Future<void> dispose() async {
    if (!_initialized && _pools.isEmpty) return;
    await stop();
    for (final pool in _pools.values) {
      for (final p in pool.players) {
        try {
          await p.dispose();
        } catch (_) {}
      }
    }
    _pools.clear();
    _initialized = false;
  }
}

class BeatEvent {
  final SessionMode mode;
  final Position position;
  final Position from;
  final Position? to;

  final Duration nextInterval;

  /// BPM interpolé de ce beat sous rampe, pas le BPM de départ du step.
  final double bpm;

  const BeatEvent({
    required this.mode,
    required this.position,
    required this.from,
    required this.to,
    required this.nextInterval,
    required this.bpm,
  });
}

class _PlayerPool {
  final List<AudioPlayer> players;

  final List<double?> _lastVolume;
  int _idx = 0;

  _PlayerPool(this.players)
      : _lastVolume = List<double?>.filled(players.length, null);

  ({AudioPlayer player, bool volumeChanged}) next([double? volume]) {
    final i = _idx;
    _idx = (_idx + 1) % players.length;
    if (volume == null) return (player: players[i], volumeChanged: true);
    final changed = _lastVolume[i] != volume;
    if (changed) _lastVolume[i] = volume;
    return (player: players[i], volumeChanged: changed);
  }
}
