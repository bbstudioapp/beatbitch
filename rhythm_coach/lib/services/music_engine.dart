import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/session_music.dart';
import 'music_clock.dart';

/// Ce que [MusicEngine] attend d'un lecteur audio.
abstract class MusicPlayerPort {
  Stream<Duration> get positions;
  Future<void> load(String asset, {required double volume});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

class AudioplayersMusicPort implements MusicPlayerPort {
  final AudioPlayer _player = AudioPlayer(playerId: 'session_music');

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Future<void> load(String asset, {required double volume}) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    // Sans ça, le focus audio Android pris par chaque bip retire le focus au
    // morceau, qui se met en pause à la première mesure.
    if (!kIsWeb) {
      try {
        await _player.setAudioContext(AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build());
      } catch (e) {
        if (kDebugMode) debugPrint('[MusicEngine] setAudioContext : $e');
      }
    }
    await _player.setVolume(volume);
    await _player.setSource(AssetSource(asset));
  }

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// Joue le morceau d'une séance et expose sa position de lecture, qui sert
/// d'horloge à la séance.
class MusicEngine {
  MusicEngine({
    MusicPlayerPort? port,
    MusicClock? clock,
    this.syncTimeout = const Duration(seconds: 3),
  })  : _portOrNull = port,
        _clock = clock ?? MusicClock();

  /// Attente du premier rapport de position après le lancement de la lecture.
  final Duration syncTimeout;

  /// Même borne que les commandes de transport de `AmbienceEngine` : un canal
  /// qui ne répond pas ne doit jamais retarder la séance.
  static const Duration _transportTimeout = Duration(milliseconds: 300);

  /// Chargement de l'asset : I/O disque (copie du bundle, décodeur natif).
  static const Duration _loadTimeout = Duration(seconds: 3);

  final MusicPlayerPort? _portOrNull;
  MusicPlayerPort? _createdPort;
  final MusicClock _clock;
  StreamSubscription<Duration>? _subscription;

  MusicPlayerPort get _port =>
      _portOrNull ?? (_createdPort ??= AudioplayersMusicPort());

  MusicPlayerPort? get _existingPort => _portOrNull ?? _createdPort;

  Duration get position => _clock.position;

  /// Faux quand le lecteur n'a jamais rapporté de position : la séance tourne
  /// alors sur l'horloge murale, sans musique.
  bool get isSynced => _clock.isSynced;

  /// Lance le morceau et attend qu'il joue réellement. Renvoie faux si le
  /// lecteur n'a rien rapporté à temps : la position court alors seule.
  Future<bool> start(SessionMusic music) async {
    await _release();
    _clock.start();
    final firstReport = Completer<void>();
    _subscription = _port.positions.listen((p) {
      _clock.report(p);
      if (!firstReport.isCompleted) firstReport.complete();
    });
    try {
      await _port.load(music.asset, volume: music.volume).timeout(_loadTimeout);
      await _port.play().timeout(_loadTimeout);
      await firstReport.future.timeout(syncTimeout);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicEngine] démarrage : $e');
      await _release();
      _clock.freeRun();
      return false;
    }
  }

  Future<void> pause() async {
    _clock.pause();
    final port = _existingPort;
    if (port != null) await _bounded(port.pause, 'pause');
  }

  Future<void> resume() async {
    _clock.resume();
    final port = _existingPort;
    if (port != null) await _bounded(port.play, 'resume');
  }

  Future<void> stop() async {
    _clock.stop();
    await _release();
  }

  Future<void> dispose() async {
    await stop();
    final port = _existingPort;
    if (port != null) await _bounded(port.dispose, 'dispose');
  }

  Future<void> _release() async {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final port = _existingPort;
    if (port != null) await _bounded(port.stop, 'stop');
  }

  Future<void> _bounded(Future<void> Function() call, String what) async {
    try {
      await call().timeout(_transportTimeout);
    } catch (e) {
      if (kDebugMode) debugPrint('[MusicEngine] $what : $e');
    }
  }
}
