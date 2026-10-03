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

  /// Borne des appels de coupure au backend audio. Même valeur que le
  /// `player.stop()` de [BeepEngine] : c'est le même plugin `audioplayers` et
  /// le même type d'appel, sur un seul player au lieu de 4 par sample — il n'y
  /// a pas de raison qu'une réponse légitime y soit plus lente.
  static const Duration _callTimeout = Duration(milliseconds: 300);

  /// Borne du démarrage de lecture ([play]). Volontairement bien plus large
  /// que [_callTimeout] : la séquence enchaîne l'init du player et un
  /// `setSource` qui, sur Android, copie l'asset du bundle vers le cache puis
  /// prépare le décodeur natif. C'est de l'I/O disque sur les plus gros
  /// samples audio du projet (boucles d'ambiance), pas une commande de
  /// transport — 300 ms couperait l'ambiance sur un appareil lent.
  ///
  /// 3 s se place au-dessus des bornes « init / chargement » déjà en place
  /// (2 s pour `_tts.init()` et pour le `_beep.stop()` de `_finish`, qui
  /// n'ont pas d'I/O d'asset) et très en dessous du timeout de préparation
  /// interne d'`audioplayers` (30 s) — c'est précisément celui-là qu'on
  /// refuse de subir : le flow FAIL attend `playForMode` avant de reposer
  /// `_state = running`. Si la borne coupe à tort, l'ambiance de ce mode
  /// reste muette jusqu'au prochain step de config (`_currentAsset` n'est
  /// posé qu'en cas de succès, donc le no-op de tête ne bloque pas la
  /// retentative).
  static const Duration _startTimeout = Duration(seconds: 3);

  static const String finishMusicAsset = 'audio/finish_music.mp3';

  /// Instant du fichier où la musique de finish atteint son sommet, calé sur
  /// le début du final.
  static const Duration finishMusicPeak = Duration(seconds: 70);

  static const double _finishMusicVolume = 0.35;

  AmbienceEngine({Random? random}) : _random = random ?? Random();

  final Random _random;
  final AudioPlayer _player = AudioPlayer(playerId: 'ambience_loop');
  AudioPlayer? _finishPlayer;
  (SessionMode, bool)? _currentSlot;
  bool _finishInitialized = false;
  bool _finishPlaying = false;
  bool _finishPaused = false;
  int _finishGen = 0;
  String? _slotAsset;

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

  /// Lance ou change l'ambiance. Asset relatif au dossier `assets/`
  /// (ex: `audio/ambience/rain.mp3`). Si [assetPath] est null, équivaut
  /// à [stop].
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

  /// Séquence de démarrage, bornée en bloc par [play] — aucun de ces appels
  /// n'a de garde côté `audioplayers`, et un `try/catch` n'attrape que les
  /// exceptions, pas un appel qui ne rend jamais la main.
  ///
  /// Méthode séparée (et non privée) pour que les tests puissent simuler un
  /// backend audio muet en la surchargeant, sans avoir à émuler tout le
  /// protocole `audioplayers` : c'est [play] — donc la borne — qui reste
  /// exercée. Ne pas appeler directement en production.
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
      // `.timeout(300 ms)` : même garde-fou que `BeepEngine` (cf. 6ebdb84).
      // Sur un backend audio engorgé, `pause()` peut ne jamais rendre la main,
      // et `SessionController.pause()` l'attend avant de basculer en `paused`.
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
      // Borné comme [pause] / [stop] : commande de transport sur un player
      // déjà préparé, rien à charger. Sans la borne, `SessionController.resume`
      // ne rend jamais la main sur un backend engorgé — la séance repart quand
      // même (l'état bascule avant), mais tout appelant chaîné reste en attente.
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

  static const String _packPrefsKey = 'ambience.pack';
  static const String _volumePrefsKey = 'ambience.volume';

  /// Reprend le pack et le volume choisis au lancement précédent. Un pack qui
  /// n'est plus au catalogue retombe sur [AmbiencePack.none].
  Future<void> restore(List<AmbiencePack> packs) async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_packPrefsKey);
    _pack =
        packs.firstWhere((p) => p.id == id, orElse: () => AmbiencePack.none);
    final v = prefs.getDouble(_volumePrefsKey);
    if (v != null) await _applyVolume(v);
  }

  /// Change le pack actif. Si une lecture est en cours, ne touche pas
  /// directement à l'asset courant — l'appelant fait `playForMode` ensuite
  /// si besoin (typiquement après un changement de mode). Pour un test
  /// d'écoute (page SONS), passer par [playForMode] directement.
  void setPack(AmbiencePack pack) {
    _pack = pack;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_packPrefsKey, pack.id));
  }

  /// Joue l'ambiance correspondant à [mode] selon le pack courant, en tirant
  /// une variante du palier de [depth]. Tant que le mode et le palier ne
  /// changent pas, la variante en cours continue. Si le pack n'a pas de
  /// track pour ce mode, coupe l'ambiance.
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

  /// Démarre la musique de finish de façon que son sommet tombe dans
  /// [untilPeak]. Joue par-dessus l'ambiance, indépendamment du pack.
  Future<void> startFinishMusic(Duration untilPeak) async {
    final offset = finishMusicPeak - untilPeak;
    final gen = ++_finishGen;
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
    final player = _finishPlayer ??= AudioPlayer(playerId: 'finish_music');
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
    if (!_finishPlaying) return;
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
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
    _initialized = false;
    _isPlaying = false;
  }
}
