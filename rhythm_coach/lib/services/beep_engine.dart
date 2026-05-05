import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/final_category.dart';
import '../models/session.dart';
import '../models/session_step.dart';

/// Moteur audio des bips de guidage rythmique.
///
/// Implémentation : pool de [_poolSize] AudioPlayer par sample, en round-robin.
/// À chaque beat on prend le player suivant — le précédent peut donc finir
/// son décay sans être interrompu, ce qui supprime le côté saccadé du
/// pattern stop()+resume() sur un seul player.
///
/// Une étape « text-only » ne reconfigure jamais le loop courant.
class BeepEngine {
  static const String _tipAsset = 'tip_beep';
  static const String _headAsset = 'head_beep';
  static const String _midAsset = 'mid_beep';
  static const String _throatAsset = 'throat_beep';
  static const String _fullAsset = 'full_beep';
  static const String _holdAsset = 'hold_beep';
  static const String _biffleAsset = 'biffle_beep';
  static const String _breathAsset = 'breath_beep';
  static const String _handAsset = 'hand_beep';
  static const String _freestyleStartAsset = 'freestyle_start';
  static const String _freestyleEndAsset = 'freestyle_end';
  static const String _finaleChimeAsset = 'finale_chime';

  static const List<String> _allAssets = [
    _tipAsset,
    _headAsset,
    _midAsset,
    _throatAsset,
    _fullAsset,
    _holdAsset,
    _biffleAsset,
    _breathAsset,
    _handAsset,
    _freestyleStartAsset,
    _freestyleEndAsset,
    _finaleChimeAsset,
  ];

  // Lick = volume réduit pour le ressenti « plus léger / wet ».
  // Hand = volume médian (entre rhythm et lick).
  static const double _rhythmVolume = 1.0;
  static const double _lickVolume = 0.65;
  static const double _handVolume = 0.85;
  static const double _holdLayerVolume = 0.9;
  static const double _breathVolume = 0.9;

  /// 3 players par sample : couvre BPM jusqu'à ~200 même avec hold (450 ms).
  static const int _poolSize = 3;

  final Map<String, _PlayerPool> _pools = {};
  final Random _random = Random();
  bool _initialized = false;

  /// Variantes de `finale_chime` par catégorie. Chargé depuis
  /// `assets/audio/finale_chimes.json` au boot. Vide si JSON absent ou
  /// invalide → fallback sur le sample historique unique `finale_chime`.
  Map<FinalCategory, List<String>> _finaleVariants =
      const <FinalCategory, List<String>>{};

  // État du loop courant.
  SessionMode _mode = SessionMode.rhythm;
  Position _from = Position.head;
  Position? _to;
  int _bpm = 60;
  bool _alternateToggle = false;

  Timer? _loopTimer;

  /// Timer de fin de freestyle : déclenche le bip de fin après `duration`.
  Timer? _freestyleEndTimer;

  /// Callback notifié à chaque beat émis par un loop (rhythm/lick/biffle/hand).
  /// Le SessionController s'y abonne pour comptabiliser stats + excitation.
  void Function(BeatEvent event)? onBeat;

  /// Stream broadcast des beats (rhythm/lick/biffle/hand). Permet à plusieurs
  /// consommateurs (UI animation, debug overlays) de réagir à chaque bip
  /// sans monopoliser [onBeat]. Émis exactement au même instant que [onBeat].
  final StreamController<BeatEvent> _beatController =
      StreamController<BeatEvent>.broadcast();
  Stream<BeatEvent> get beatStream => _beatController.stream;

  Future<void> init() async {
    if (_initialized) return;
    final assetsToLoad = <String>{..._allAssets};
    _finaleVariants = await _loadFinaleVariants();
    // Inclure dans les chargements toutes les variantes déclarées qui ne
    // sont pas déjà couvertes par `_allAssets` (cas du sample historique).
    for (final list in _finaleVariants.values) {
      assetsToLoad.addAll(list);
    }
    for (final name in assetsToLoad) {
      final players = <AudioPlayer>[];
      // Les variantes de finale sont jouées une seule fois par session →
      // 1 player suffit. Les autres samples (boucles BPM) gardent _poolSize.
      final isFinaleVariant = _finaleVariants.values
          .any((list) => list.contains(name) && name != _finaleChimeAsset);
      final poolSize = isFinaleVariant ? 1 : _poolSize;
      // Les samples de finale (variantes incluses) sont rangés dans le
      // sous-dossier `audio/finale/` pour ne pas polluer la racine. Le
      // sample historique reste à la racine pour rétrocompat.
      final assetPath = isFinaleVariant
          ? 'audio/finale/$name.mp3'
          : 'audio/$name.mp3';
      for (var i = 0; i < poolSize; i++) {
        try {
          final p = AudioPlayer(playerId: 'beep_${name}_$i');
          // ReleaseMode.stop : à la fin du sample, le player se met en pause
          // et la position revient à 0, prêt pour le prochain resume().
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
    _initialized = true;
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

  /// Applique une étape au moteur. Les étapes text-only sont ignorées
  /// (elles ne touchent pas au loop courant).
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    if (step.isTextOnly) return;
    if (!_initialized) await init();

    final mode = step.mode ?? sessionMode;
    _mode = mode;
    if (step.bpm != null) _bpm = step.bpm!.clamp(20, 300);

    // Hold et beg : la position cible vient de `step.to` (sémantique « tenir
    // jusqu'à ce point »). On la stocke dans `_from` pour rester compatible
    // avec les consommateurs UI (currentFrom). Pour rhythm/lick/hand/biffle :
    // `_from` = step.from (point de départ de l'alternance).
    if (mode == SessionMode.hold || mode == SessionMode.beg) {
      if (step.to != null) _from = step.to!;
    } else if (step.from != null) {
      _from = step.from!;
    }
    _to = step.to;

    // En rythme/lick avec from == to (ex: throat/throat), on relève `from`
    // vers une position plus haute au hasard pour créer une alternance.
    if ((mode == SessionMode.rhythm || mode == SessionMode.lick) &&
        _to != null &&
        _to == _from) {
      _from = _pickShallowerThan(_from);
    }

    _alternateToggle = false;
    _stopLoop();
    _freestyleEndTimer?.cancel();
    _freestyleEndTimer = null;

    switch (mode) {
      case SessionMode.rhythm:
        _startBeatLoop(volume: _rhythmVolume, beatAsset: null);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume, beatAsset: null);
      case SessionMode.hand:
        // Sample dédié, volume médian. Sinon même mécanique d'alternance
        // from→to que rhythm.
        _startBeatLoop(volume: _handVolume, beatAsset: _handAsset);
      case SessionMode.biffle:
        _startBiffleLoop();
      case SessionMode.hold:
        _playHoldOneShot(_from);
      case SessionMode.breath:
        _playBreathOneShot();
      case SessionMode.freestyle:
        // Marqueur début, et marqueur fin programmé après `duration`.
        _trigger(_freestyleStartAsset, _rhythmVolume);
        final dur = step.duration;
        if (dur != null && dur > 0) {
          _freestyleEndTimer = Timer(Duration(seconds: dur), () {
            _trigger(_freestyleEndAsset, _rhythmVolume);
          });
        }
      case SessionMode.beg:
        // Sans `to` : récup vocale pure, pas de bip.
        // Avec `to` : la position doit être tenue pendant la supplique
        // → on joue le bip du hold correspondant en one-shot, comme
        // ancrage tactile / sonore de la position.
        if (step.to != null) {
          _playHoldOneShot(step.to!);
        }
        break;
    }
  }

  /// [beatAsset] : si non-null, ce sample remplace le sample de position
  /// pour chaque beat (utilisé par hand qui a un son fixe).
  void _startBeatLoop({required double volume, String? beatAsset}) {
    final intervalMs = (60000 / _bpm).round();
    _emitPositionBeat(volume, beatAsset);
    _loopTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _emitPositionBeat(volume, beatAsset);
    });
  }

  void _emitPositionBeat(double volume, String? beatAsset) {
    final pos = _pickPosition();
    _trigger(beatAsset ?? _assetForPosition(pos), volume);
    _notifyBeat(_mode, pos);
  }

  void _notifyBeat(SessionMode mode, Position pos) {
    // Pour rhythm/lick/hand : pos = la position effectivement jouée ce beat
    // (alternance from/to). Pour biffle : on fournit `to` si dispo, sinon
    // `from`, à titre informatif (pas de notion de profondeur acoustique).
    final event = BeatEvent(mode: mode, position: pos, from: _from, to: _to);
    onBeat?.call(event);
    if (!_beatController.isClosed) _beatController.add(event);
  }

  /// Retourne une position strictement plus haute (plus aiguë) que [p].
  /// Si [p] est déjà tip (le plus haut), retourne tip.
  Position _pickShallowerThan(Position p) {
    final shallower =
        Position.values.where((x) => x.index < p.index).toList();
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
    final intervalMs = (60000 / _bpm).round();
    _trigger(_biffleAsset, _rhythmVolume);
    _notifyBeat(SessionMode.biffle, _to ?? _from);
    _loopTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _trigger(_biffleAsset, _rhythmVolume);
      _notifyBeat(SessionMode.biffle, _to ?? _from);
    });
  }

  void _playHoldOneShot(Position position) {
    _trigger(_assetForPosition(position), _rhythmVolume);
    _trigger(_holdAsset, _holdLayerVolume);
  }

  void _playBreathOneShot() {
    _trigger(_breathAsset, _breathVolume);
  }

  /// Déclenche un sample en utilisant le prochain player du pool round-robin.
  /// Fire-and-forget : le ticker n'attend pas la fin de l'opération audio.
  void _trigger(String assetName, double volume) {
    final pool = _pools[assetName];
    if (pool == null) return;
    final player = pool.next();
    () async {
      try {
        await player.setVolume(volume);
        await player.resume();
      } catch (e) {
        if (kDebugMode) debugPrint('[BeepEngine] trigger error : $e');
      }
    }();
  }

  String _assetForPosition(Position p) => switch (p) {
        Position.tip => _tipAsset,
        Position.head => _headAsset,
        Position.mid => _midAsset,
        Position.throat => _throatAsset,
        Position.full => _fullAsset,
      };

  void _stopLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
  }

  // ─── API publique pour la page démo ─────────────────────────────────────

  Future<void> ensureReady() => init();

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

  void startRhythmDemo({
    required Position from,
    Position? to,
    required int bpm,
  }) {
    if (!_initialized) return;
    _mode = SessionMode.rhythm;
    _from = from;
    _to = to;
    _bpm = bpm.clamp(20, 300);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = false;
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
    _bpm = bpm.clamp(20, 300);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = false;
    _stopLoop();
    _startBeatLoop(volume: _lickVolume, beatAsset: null);
  }

  void startHandDemo({
    required Position from,
    Position? to,
    required int bpm,
  }) {
    if (!_initialized) return;
    _mode = SessionMode.hand;
    _from = from;
    _to = to;
    _bpm = bpm.clamp(20, 300);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = false;
    _stopLoop();
    _startBeatLoop(volume: _handVolume, beatAsset: _handAsset);
  }

  void startBiffleDemo({required int bpm}) {
    if (!_initialized) return;
    _mode = SessionMode.biffle;
    _bpm = bpm.clamp(20, 300);
    _stopLoop();
    _startBiffleLoop();
  }

  void playHandPositionOnce(Position p) {
    if (!_initialized) return;
    _trigger(_handAsset, _handVolume);
  }

  void playFreestyleStartOnce() {
    if (!_initialized) return;
    _trigger(_freestyleStartAsset, _rhythmVolume);
  }

  void playFreestyleEndOnce() {
    if (!_initialized) return;
    _trigger(_freestyleEndAsset, _rhythmVolume);
  }

  /// Joue le son de clôture de séance (cloche/chime joué pile au moment
  /// où l'utilisatrice termine sa dernière action). Volume plein, sample
  /// long (~1.4s avec fade-out de 0.7s) — penser à laisser le TTS muet
  /// pendant cette durée pour ne pas le couper.
  ///
  /// Si [category] est fourni et qu'au moins une variante existe pour
  /// cette catégorie, on en pioche une au hasard. Sinon fallback sur
  /// le sample historique unique `finale_chime`.
  ///
  /// Le `Future` retourné complète à la fin du sample : le caller peut
  /// `await` pour enchaîner une transition d'écran après la fin du chime
  /// (sinon le son chevauche le rendu suivant). Timeout de sécurité à 5 s
  /// pour ne jamais bloquer indéfiniment si `onPlayerComplete` ne fire pas.
  Future<void> playFinaleChime(
      {FinalCategory? category, double volume = 1.0}) async {
    if (!_initialized) return;
    final variants = category != null ? _finaleVariants[category] : null;
    final asset = (variants != null && variants.isNotEmpty)
        ? variants[_random.nextInt(variants.length)]
        : _finaleChimeAsset;
    final pool = _pools[asset];
    if (pool == null) return;
    final player = pool.next();
    try {
      await player.setVolume(volume.clamp(0.0, 1.0));
      await player.resume();
      await player.onPlayerComplete.first
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (e) {
      if (kDebugMode) debugPrint('[BeepEngine] finale chime error : $e');
    }
  }

  bool get isLooping => _loopTimer != null;

  // ─── État courant exposé pour l'affichage UI ───────────────────────────

  SessionMode get currentMode => _mode;
  Position get currentFrom => _from;
  Position? get currentTo => _to;
  int get currentBpm => _bpm;

  // ─── Cycle de vie ──────────────────────────────────────────────────────

  /// Met en pause la lecture : on stoppe le ticker. On stoppe aussi tous
  /// les players du pool pour couper net (utile en pause/stop session).
  Future<void> pause() async {
    _stopLoop();
    _freestyleEndTimer?.cancel();
    _freestyleEndTimer = null;
    for (final pool in _pools.values) {
      for (final p in pool.players) {
        try {
          await p.stop();
        } catch (_) {}
      }
    }
  }

  Future<void> resume() async {
    _stopLoop();
    switch (_mode) {
      case SessionMode.rhythm:
        _startBeatLoop(volume: _rhythmVolume, beatAsset: null);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume, beatAsset: null);
      case SessionMode.hand:
        _startBeatLoop(volume: _handVolume, beatAsset: _handAsset);
      case SessionMode.biffle:
        _startBiffleLoop();
      case SessionMode.hold:
      case SessionMode.breath:
      case SessionMode.beg:
      case SessionMode.freestyle:
        // Modes one-shot ou silencieux — rien à reprendre.
        break;
    }
  }

  Future<void> stop() async {
    await pause();
  }

  Future<void> dispose() async {
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

/// Événement émis à chaque beat d'un loop (rhythm/lick/biffle/hand).
/// Consommé par SessionController pour alimenter compteurs + jauge.
class BeatEvent {
  final SessionMode mode;
  final Position position;
  final Position from;
  final Position? to;

  const BeatEvent({
    required this.mode,
    required this.position,
    required this.from,
    required this.to,
  });
}

/// Pool round-robin d'AudioPlayer pour un même sample.
class _PlayerPool {
  final List<AudioPlayer> players;
  int _idx = 0;

  _PlayerPool(this.players);

  AudioPlayer next() {
    final p = players[_idx];
    _idx = (_idx + 1) % players.length;
    return p;
  }
}
