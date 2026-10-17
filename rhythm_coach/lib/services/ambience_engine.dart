import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ambience_pack.dart';
import '../models/session.dart';
import '../models/session_step.dart';

/// Lecteur d'ambiance sonore en arrière-plan : un seul AudioPlayer en
/// `ReleaseMode.loop`, volume volontairement bas pour rester sous les
/// bips de [BeepEngine] (qui jouent à 1.0).
class AmbienceEngine {
  /// Volume max autorisé pour l'ambiance — au-delà ça commence à masquer
  /// les bips de guidage selon les samples.
  static const double maxVolume = 0.5;
  static const double defaultVolume = 0.15;

  /// Borne des appels de coupure au backend audio, comme `player.stop()` de
  /// [BeepEngine].
  static const Duration _callTimeout = Duration(milliseconds: 300);

  /// Borne du démarrage de lecture : init du player et `setSource` (copie de
  /// l'asset sur Android) sont de l'I/O, pas une commande de transport — 300 ms
  /// couperait l'ambiance sur un appareil lent.
  static const Duration _startTimeout = Duration(seconds: 3);

  static const String finishMusicAsset = 'audio/music/finish_music.mp3';

  /// Instant du fichier où la musique de finish atteint son sommet, calé sur
  /// le début du final.
  static const Duration finishMusicPeak = Duration(seconds: 70);

  static const double _finishMusicVolume = 0.35;

  AmbienceEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  final AudioPlayer _player = AudioPlayer(playerId: 'ambience_loop')
    ..positionUpdater = null;
  AudioPlayer? _finishPlayer;
  AudioPlayer? _climaxPlayer;
  (SessionMode, bool)? _currentSlot;
  bool _finishInitialized = false;
  bool _finishPlaying = false;
  bool _finishPaused = false;
  int _finishGen = 0;

  /// Un fondu qui suit directement un démarrage encore en vol doit l'annuler :
  /// sinon la musique part après le fondu.
  int? _finishStartGen;
  String? _slotAsset;

  String? _currentAsset;
  double _volume = defaultVolume;
  bool _initialized = false;
  bool _isPlaying = false;

  AmbiencePack _pack = AmbiencePack.none;

  String? get currentAsset => _currentAsset;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;
  AmbiencePack get currentPack => _pack;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    // Un player qui tient le focus Android est mis en pause par audioplayers
    // dès qu'un bip le réclame. Android seul : sur iOS la session est globale
    // et écraserait le mixWithOthers du mode Music.
    await _withoutFocus(_player);
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(_volume);
    _initialized = true;
  }

  static Future<void> _withoutFocus(AudioPlayer player) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final ctx = AudioContextConfig().build();
      await player.setAudioContext(ctx.copy(
        android: ctx.android.copy(audioFocus: AndroidAudioFocus.none),
      ));
    }
  }

  /// [assetPath] est relatif à `assets/` ; null équivaut à [stop].
  Future<void> play(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) {
      await stop();
      return;
    }
    try {
      await startPlayback(assetPath).timeout(_startTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] play error : $e');
      _isPlaying = false;
    }
  }

  /// Séquence de démarrage, bornée en bloc par [play] : aucun appel n'a de garde
  /// côté `audioplayers`. Surchargée par les tests pour simuler un backend muet.
  @visibleForTesting
  Future<void> startPlayback(String assetPath) async {
    await _ensureInit();
    if (_currentAsset == assetPath && _isPlaying) return;
    await _player.stop();
    await _player.setSource(AssetSource(assetPath));
    await _player.setVolume(_volume);
    await _player.resume();
    _currentAsset = assetPath;
    _isPlaying = true;
  }

  Future<void> pause() async {
    if (_finishPlaying && !_finishPaused) {
      _finishPaused = true;
      try {
        await _finishPlayer?.pause().timeout(_callTimeout);
      } catch (_) {}
    }
    if (!_initialized || !_isPlaying) return;
    try {
      // Borné : sur un backend engorgé, `pause()` ne rend jamais la main et
      // `SessionController.pause()` l'attend.
      await _player.pause().timeout(_callTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] pause error : $e');
    }
    // Hors du `try` : l'état doit refléter l'intention même si le backend n'a
    // pas répondu. Un `_isPlaying` resté à `true` ferait sortir [resume] tôt
    // et l'ambiance ne repartirait jamais de la séance.
    _isPlaying = false;
  }

  Future<void> resume() async {
    if (_finishPlaying && _finishPaused) {
      _finishPaused = false;
      try {
        await _finishPlayer?.resume().timeout(_callTimeout);
      } catch (_) {}
    }
    if (!_initialized || _currentAsset == null || _isPlaying) return;
    try {
      // Borné comme [pause] / [stop] : sans borne, `SessionController.resume`
      // n'est jamais rendu sur un backend engorgé.
      await _player.resume().timeout(_callTimeout);
      _isPlaying = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] resume error : $e');
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _player.stop().timeout(_callTimeout);
    } catch (_) {}
    _isPlaying = false;
  }

  Future<void> playClimax() async {
    final clips = _pack.climax;
    if (clips.isEmpty) return;
    try {
      await startClimaxPlayback(clips[_random.nextInt(clips.length)])
          .timeout(_startTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] climax error : $e');
    }
  }

  /// Ne pas appeler directement en production : surchargée par les tests,
  /// comme [startPlayback].
  @visibleForTesting
  Future<void> startClimaxPlayback(String asset) async {
    final player = _climaxPlayer ??= AudioPlayer(playerId: 'ambience_climax')
      ..positionUpdater = null;
    await _withoutFocus(player);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(AssetSource(asset));
    await player.setVolume((_volume / maxVolume).clamp(0.0, 1.0));
    await player.resume();
  }

  static const String _packPrefsKey = 'ambience.pack';
  static const String _volumePrefsKey = 'ambience.volume';

  Future<void> restore(List<AmbiencePack> packs) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_packPrefsKey);
    _pack =
        packs.firstWhere((p) => p.id == id, orElse: () => AmbiencePack.none);
    final v = prefs.getDouble(_volumePrefsKey);
    if (v != null) await _applyVolume(v);
  }

  /// Ne touche pas à l'asset courant : l'appelant enchaîne [playForMode].
  void setPack(AmbiencePack pack) {
    _pack = pack;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_packPrefsKey, pack.id));
  }

  Future<void> playForMode(SessionMode mode, {Position? depth}) async {
    final deep = depth != null && depth.index >= Position.throat.index;
    final candidates = _pack.candidatesFor(mode, deep: deep);
    if (candidates.isEmpty) {
      _currentSlot = null;
      _slotAsset = null;
      await stop();
      return;
    }
    final slot = (mode, deep);
    final kept = _slotAsset;
    if (slot == _currentSlot && kept != null && candidates.contains(kept)) {
      await play(kept);
      return;
    }
    final fresh = candidates.length > 1
        ? candidates.where((a) => a != kept).toList()
        : candidates;
    final picked = fresh[_random.nextInt(fresh.length)];
    _currentSlot = slot;
    _slotAsset = picked;
    await play(picked);
  }

  Future<void> setVolume(double v) async {
    await _applyVolume(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumePrefsKey, _volume);
  }

  Future<void> _applyVolume(double v) async {
    _volume = v.clamp(0.0, maxVolume);
    if (!_initialized) return;
    try {
      await _player.setVolume(_volume);
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] setVolume error : $e');
    }
  }

  Future<void> startFinishMusic(Duration untilPeak) async {
    final offset = finishMusicPeak - untilPeak;
    final gen = ++_finishGen;
    _finishStartGen = gen;
    try {
      await startFinishPlayback(offset.isNegative ? Duration.zero : offset)
          .timeout(_startTimeout);
      if (gen != _finishGen) {
        await _finishPlayer?.stop().timeout(_callTimeout);
        return;
      }
      _finishPlaying = true;
      _finishPaused = false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] finish music error : $e');
    }
  }

  /// Ne pas appeler directement en production : surchargée par les tests,
  /// comme [startPlayback].
  @visibleForTesting
  Future<void> startFinishPlayback(Duration offset) async {
    final player = _finishPlayer ??= AudioPlayer(playerId: 'finish_music')
      ..positionUpdater = null;
    if (!_finishInitialized) {
      await _withoutFocus(player);
      await player.setReleaseMode(ReleaseMode.stop);
      _finishInitialized = true;
    }
    await player.setSource(AssetSource(finishMusicAsset));
    await player.setVolume(_finishMusicVolume);
    await player.seek(offset);
    await player.resume();
  }

  bool get isFinishMusicPlaying => _finishPlaying;

  Future<void> fadeOutFinishMusic(
      {Duration duration = const Duration(seconds: 3)}) async {
    if (!_finishPlaying) {
      if (_finishStartGen == _finishGen) _finishGen++;
      return;
    }
    final gen = ++_finishGen;
    _finishPlaying = false;
    _finishPaused = false;
    const steps = 12;
    try {
      for (var i = steps - 1; i >= 0; i--) {
        await Future<void>.delayed(duration ~/ steps);
        if (gen != _finishGen) return;
        await _finishPlayer
            ?.setVolume(_finishMusicVolume * i / steps)
            .timeout(_callTimeout);
      }
      await _finishPlayer?.stop().timeout(_callTimeout);
    } catch (_) {}
  }

  Future<void> stopFinishMusic() async {
    _finishGen++;
    _finishPlaying = false;
    _finishPaused = false;
    if (!_finishInitialized) return;
    try {
      await _finishPlayer?.stop().timeout(_callTimeout);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _finishGen++;
    _finishPlaying = false;
    try {
      await _finishPlayer?.dispose();
      await _climaxPlayer?.dispose();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    _initialized = false;
    _isPlaying = false;
  }
}
