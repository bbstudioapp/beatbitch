import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/ambience_pack.dart';
import '../models/session.dart';

/// Lecteur d'ambiance sonore en arrière-plan : un seul AudioPlayer en
/// `ReleaseMode.loop`, volume volontairement bas pour rester sous les
/// bips de [BeepEngine] (qui jouent à 1.0).
///
/// Le plafond [maxVolume] empêche l'utilisateur de monter trop haut et
/// de masquer les bips de guidage.
///
/// Porte aussi le pack d'ambiance courant ([currentPack]) pour qu'il soit
/// partagé entre l'écran de jeu et l'écran SONS (la sélection se fait
/// depuis ce dernier).
class AmbienceEngine {
  /// Volume max autorisé pour l'ambiance — au-delà ça commence à masquer
  /// les bips de guidage selon les samples.
  static const double maxVolume = 0.5;
  static const double defaultVolume = 0.15;

  final AudioPlayer _player = AudioPlayer(playerId: 'ambience_loop');

  String? _currentAsset;
  double _volume = defaultVolume;
  bool _initialized = false;
  bool _isPlaying = false;

  /// Pack actif. Modifiable via [setPack] depuis n'importe quel écran.
  AmbiencePack _pack = AmbiencePack.none;

  String? get currentAsset => _currentAsset;
  double get volume => _volume;
  bool get isPlaying => _isPlaying;
  AmbiencePack get currentPack => _pack;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(_volume);
    _initialized = true;
  }

  /// Lance ou change l'ambiance. Asset relatif au dossier `assets/`
  /// (ex: `audio/ambience/rain.mp3`). Si [assetPath] est null, équivaut
  /// à [stop].
  Future<void> play(String? assetPath) async {
    if (assetPath == null || assetPath.isEmpty) {
      await stop();
      return;
    }
    await _ensureInit();
    if (_currentAsset == assetPath && _isPlaying) return;

    try {
      await _player.stop();
      await _player.setSource(AssetSource(assetPath));
      await _player.setVolume(_volume);
      await _player.resume();
      _currentAsset = assetPath;
      _isPlaying = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] play error : $e');
      _isPlaying = false;
    }
  }

  Future<void> pause() async {
    if (!_initialized || !_isPlaying) return;
    try {
      await _player.pause();
      _isPlaying = false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] pause error : $e');
    }
  }

  Future<void> resume() async {
    if (!_initialized || _currentAsset == null || _isPlaying) return;
    try {
      await _player.resume();
      _isPlaying = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] resume error : $e');
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
  }

  /// Change le pack actif. Si une lecture est en cours, ne touche pas
  /// directement à l'asset courant — l'appelant fait `playForMode` ensuite
  /// si besoin (typiquement après un changement de mode). Pour un test
  /// d'écoute (page SONS), passer par [playForMode] directement.
  void setPack(AmbiencePack pack) {
    _pack = pack;
  }

  /// Joue l'ambiance correspondant à [mode] selon le pack courant.
  /// Si le pack n'a pas de track pour ce mode, coupe l'ambiance.
  Future<void> playForMode(SessionMode mode) async {
    await play(_pack.assetFor(mode));
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, maxVolume);
    if (!_initialized) return;
    try {
      await _player.setVolume(_volume);
    } catch (e) {
      if (kDebugMode) debugPrint('[AmbienceEngine] setVolume error : $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
    _initialized = false;
    _isPlaying = false;
  }
}
