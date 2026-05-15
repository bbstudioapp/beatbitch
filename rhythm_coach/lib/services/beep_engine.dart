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
  // Zone latérale (testicules). Sample plus grave que `full` (~180Hz)
  // pour évoquer une zone "en-dessous" anatomiquement, sans interférer
  // avec la rampe `tip→full` qui reste la zone verge.
  static const String _ballsAsset = 'balls_beep';
  static const String _holdAsset = 'hold_beep';
  static const String _biffleAsset = 'biffle_beep';
  static const String _breathAsset = 'breath_beep';
  // Hand : 2 samples alternés à chaque beat — down (coup descendant, plus
  // grave et modulé en volume par la profondeur de `to`) et up (coup
  // remontant, plus bref et discret). Donne le ressenti d'un va-et-vient
  // sans avoir besoin d'un sample par position, et reste acoustiquement
  // distinct du pool bouche pour parser les combos hand+rhythm/lick.
  static const String _handDownAsset = 'hand_down_beep';
  static const String _handUpAsset = 'hand_up_beep';
  // Suckle : sample wet à fade-out mou, rejoué en pulse régulier (~1.2s)
  // pendant `duration` pour évoquer l'aspiration. Pas de loop BPM, pas
  // d'amplitude — la position est tenue, la bouche bosse sur place.
  static const String _suckleAsset = 'suckle_beep';
  static const String _freestyleStartAsset = 'freestyle_start';
  static const String _freestyleEndAsset = 'freestyle_end';
  static const String _finaleChimeAsset = 'finale_chime';

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
  ];

  // Lick = volume réduit pour le ressenti « plus léger / wet ».
  // Hand = volume médian (entre rhythm et lick).
  static const double _rhythmVolume = 1.0;
  static const double _lickVolume = 0.65;
  static const double _handVolume = 0.85;
  static const double _holdLayerVolume = 0.9;
  static const double _breathVolume = 0.9;
  // Suckle : un peu plus doux qu'un rhythm — la bouche aspire au lieu
  // de frapper, le rendu reste wet sans dominer la piste.
  static const double _suckleVolume = 0.75;

  /// Intervalle entre deux pulsations d'aspiration en mode suckle.
  /// ~50 BPM perçu, mais sans alternance from↔to (la position est tenue).
  /// Cf. doc de [SessionMode.suckle].
  static const Duration _sucklePulse = Duration(milliseconds: 1200);

  /// 4 players par sample. Round-robin : un bip ne réutilise jamais un player
  /// avant ses 3 voisins, donc le décay du précédent n'est jamais coupé même
  /// si le sample n'a pas fini — c'est la « superposition de canaux ». 4 (vs 3
  /// historique) donne de la marge en haut du spectre BPM (boosts carrière
  /// jusqu'à 180) et quand un step combine deux samples (hold = position +
  /// hold_beep ~450 ms) : sans cette marge des bips manquaient par moments.
  static const int _poolSize = 4;

  /// Samples ≥ 200 ms pour lesquels on force un `seek(Duration.zero)` avant
  /// chaque `resume()`. Sur Android, `audioplayers` ne remet pas toujours la
  /// position à 0 entre deux `resume()` rapprochés si le plugin n'a pas encore
  /// vu `onPlayerComplete` (le canal natif considère le player encore en
  /// lecture) → le `resume()` passe sans erreur mais ne re-déclenche rien : le
  /// bip est silencieusement perdu. Symptôme observé : « bip de gorge qui ne
  /// sonne pas » par moments. Le pool round-robin de 4 dilue déjà le problème
  /// mais ne le supprime pas quand le sample est long (le player suivant peut
  /// hériter du même état "playing" mal réinitialisé).
  ///
  /// Coût : un appel canal natif de plus par bip sur ces assets. Les samples
  /// courts (tip/head/mid 110–160 ms, hand_down/up 60–90 ms, biffle 140 ms)
  /// gardent le chemin rapide — leur durée laisse au plugin le temps de voir
  /// la complétion entre deux beats même à 180 BPM.
  ///
  /// Freestyle start/end et finale_chime sont longs aussi mais joués une seule
  /// fois par session → pas de risque de chevauchement.
  static const Set<String> _longSampleAssets = {
    _throatAsset,
    _fullAsset,
    _ballsAsset,
    _holdAsset,
    _breathAsset,
    _suckleAsset,
  };

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

  /// BPM **cible** en fin de step pour les rampes intra-step. Null = pas
  /// de rampe, le loop tourne à `_bpm` constant. Quand non null et
  /// différent de `_bpm`, le BPM utilisé pour planifier chaque tick est
  /// interpolé linéairement entre `_bpm` (à `t=0`) et `_bpmEnd` (à
  /// `t=_loopDurationMs`). Cf. `_currentInterpolatedBpm`.
  int? _bpmEnd;

  /// Durée du step rythmé en cours, en millisecondes. Sert au calcul
  /// d'interpolation BPM. Null = pas de rampe (la rampe a besoin d'une
  /// fenêtre temporelle pour avoir du sens).
  int? _loopDurationMs;

  /// Toggle d'alternance from↔to du loop rythmé. Initialisé à `true` pour
  /// que le **premier beat tombe sur `to`** (cf. `_pickPosition` :
  /// `_alternateToggle ? to : _from`). Démarrer sur la profondeur cible —
  /// pas sur le point de départ — colle au phrasé naturel d'une cadence
  /// (« mid mid mid… » et pas « head mid head mid… ») et fait que l'orbe
  /// visuel atteint `to` dès le premier bip. Réarmé à `true` à chaque
  /// `applyStep` / `startRhythmDemo` / `startLickDemo`.
  bool _alternateToggle = true;

  /// Hand : alternance down/up indépendante du toggle de position.
  /// Utilisé seulement quand `_to` est null ou égal à `_from` (pas
  /// d'amplitude → on dérive le sens du stroke d'un compteur dédié).
  /// Sinon, le sens est dérivé de la position effective émise (deeper ⇒ down).
  bool _handStrokeFallbackDown = true;

  Timer? _loopTimer;

  /// Token incrémenté par [_stopLoop] : sert à invalider les callbacks
  /// en vol des loops qui se replanifient eux-mêmes (cf. `_startBeatLoop` /
  /// `_startBiffleLoop`). Sans ce token, un Timer one-shot replanifié dans
  /// son propre callback peut s'exécuter une fois après l'annulation
  /// (race entre `cancel()` et le tick déjà en file).
  int _loopGen = 0;

  /// Timer de fin de freestyle : déclenche le bip de fin après `duration`.
  Timer? _freestyleEndTimer;

  /// Timer périodique du mode suckle : rejoue [_suckleAsset] toutes les
  /// [_sucklePulse]. Indépendant de [_loopTimer] / [_loopGen] : pas de
  /// rampe BPM ni d'alternance, juste un pulse régulier annulé sur
  /// pause/stop ou changement de step.
  Timer? _suckleTimer;

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
      final assetPath =
          isFinaleVariant ? 'audio/finale/$name.mp3' : 'audio/$name.mp3';
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

  /// Pause minimale entre deux modes distincts (cas continuité corporelle :
  /// rythme/hold/beg-non-libre — la salope reste en place, le bip enchaîne
  /// sans temps mort). Laisse juste au sample précédent le temps de finir
  /// son décay.
  static const Duration _modeTransitionGap = Duration(milliseconds: 600);

  /// Pause de transition « grosse » : appliquée quand le nouveau mode
  /// requiert un changement physique côté utilisatrice (sortir la langue,
  /// passer à la main, respirer, lâcher pour supplier librement). 1.5 s
  /// — assez pour que le TTS de l'annonce ait posé l'instruction et que
  /// le geste change avant le premier bip. Le TTS lui-même ne dépend pas
  /// de cette pause (le contrôleur speak en parallèle d'`applyStep`).
  static const Duration _modeTransitionGapBig = Duration(milliseconds: 1500);

  /// Pause minimale entre deux steps consécutifs **du même mode** (changement
  /// BPM/from/to). Sans gap du tout, l'enchaînement est trop serré et la
  /// nouvelle config démarre par-dessus la fin du beat précédent — surtout
  /// audible à BPM modéré. Plus court que `_modeTransitionGap` (le geste
  /// physique ne change pas) mais non nul.
  static const Duration _sameModeTransitionGap = Duration(milliseconds: 300);

  /// Modes pour lesquels l'arrivée demande un changement physique audible
  /// → on prend la grosse pause. Beg sans `to` (libre) en fait partie ;
  /// beg avec `to` (gardé en position) reste sur la pause courte.
  bool _needsBigGap(SessionMode incoming, Position? incomingTo) {
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

  /// Applique une étape au moteur. Les étapes text-only sont ignorées
  /// (elles ne touchent pas au loop courant).
  Future<void> applyStep(SessionStep step, SessionMode sessionMode) async {
    if (step.isTextOnly) return;
    if (!_initialized) await init();

    final mode = step.mode ?? sessionMode;
    final previousMode = _mode;
    _mode = mode;
    if (step.bpm != null) _bpm = step.bpm!.clamp(20, 300);
    // Rampe BPM intra-step : on n'arme `_bpmEnd` / `_loopDurationMs` que
    // si la valeur cible est explicitement différente du BPM de départ ET
    // qu'on a une durée connue. Sinon on retombe en mode constant — un
    // step sans `bpmEnd` ou avec `bpmEnd == bpm` ne change rien à
    // l'ancien comportement.
    if (step.bpmEnd != null &&
        step.bpmEnd != step.bpm &&
        step.duration != null &&
        step.duration! > 0) {
      _bpmEnd = step.bpmEnd!.clamp(20, 300);
      _loopDurationMs = step.duration! * 1000;
    } else {
      _bpmEnd = null;
      _loopDurationMs = null;
    }

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

    _alternateToggle = true;
    _handStrokeFallbackDown = true;
    _stopLoop();
    _freestyleEndTimer?.cancel();
    _freestyleEndTimer = null;
    _suckleTimer?.cancel();
    _suckleTimer = null;

    // Gap de transition : silence avant le démarrage du nouveau mode pour
    // fluidifier l'enchaînement et laisser le temps physique de changer
    // (sortir la langue, passer à la main, respirer). Deux durées :
    // - Modes qui demandent un changement de geste (lick/hand/biffle/
    //   breath/freestyle/beg-libre) : 1.5 s.
    // - Modes en continuité (rythme/hold/beg-non-libre) : 600 ms — juste
    //   le décay du sample précédent.
    // Pas de pause si on reste sur le même mode (changements bpm/position
    // doivent rester continus). Le TTS du step a été lancé en parallèle
    // par le contrôleur, donc cette pause ne le bloque pas — elle ne fait
    // que retarder les bips, ce qui laisse l'annonce vocale en clair.
    if (mode != previousMode) {
      final gap = _needsBigGap(mode, step.to)
          ? _modeTransitionGapBig
          : _modeTransitionGap;
      await Future<void>.delayed(gap);
      // Si un autre `applyStep` a passé entretemps (changement de mode très
      // rapide), c'est lui qui doit gagner — on abandonne ce démarrage.
      if (_mode != mode) return;
    } else {
      // Même mode : petite respiration pour démarquer la nouvelle config
      // (ex: rhythm 80 BPM head→mid → rhythm 100 BPM mid→throat). Sans
      // ce gap, le passage est mécanique et on entend le tempo « sauter ».
      await Future<void>.delayed(_sameModeTransitionGap);
      if (_mode != mode) return;
    }

    switch (mode) {
      case SessionMode.rhythm:
        _startBeatLoop(volume: _rhythmVolume);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume);
      case SessionMode.hand:
        // Mécanique d'alternance from→to identique à rhythm. La résolution
        // sample + volume est faite dans `_emitPositionBeat` (down/up + volume
        // modulé par profondeur de `to`).
        _startBeatLoop(volume: _handVolume);
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
      case SessionMode.suckle:
        // Aspiration / téter : pulse régulier ~1.2s, pas de loop BPM,
        // pas d'amplitude. Le sample wet est rejoué pendant `duration`,
        // le visuel se charge du pulse du curseur via le AnimationController
        // côté MovementAnimation.
        _startSuckleLoop(step.duration);
        break;
    }
  }

  /// Lance le pulse périodique d'aspiration. Le 1er coup tombe immédiatement
  /// (cohérence avec rhythm/biffle qui jouent à `t=0`), puis toutes les
  /// [_sucklePulse] jusqu'à la fin de [durationSec] ou à l'arrivée du step
  /// suivant. `duration == null` ou <= 0 → pulse indéfini, stoppé seulement
  /// par le prochain `applyStep` / `pause` / `stop`.
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

  /// Loop principal pour les modes rythmés (rhythm/lick/hand). Le sample joué
  /// à chaque beat dépend du mode :
  /// - rhythm/lick : sample correspondant à la position effective du beat
  ///   (alternance from↔to via [_pickPosition]).
  /// - hand : sample stroke down/up dérivé de la position effective ou,
  ///   à amplitude nulle, d'un toggle dédié [_handStrokeFallbackDown]. Le
  ///   volume du down est modulé par la profondeur de `to` (cf. `_resolveHandBeat`).
  ///
  /// **Anti-drift** : on ne s'appuie pas sur `Timer.periodic` (intervalle
  /// fixe, qui drifte de qq ms par tick à cause du scheduler). À la place,
  /// chaque beat planifie le suivant à `start + n × intervalMs` (temps
  /// cible absolu). Si un tick arrive avec retard, le suivant rattrape.
  /// Le visuel (orbe) est piloté par `beatStream` → si l'audio est régulier,
  /// le visuel l'est aussi.
  void _startBeatLoop({required double volume}) {
    final myGen = ++_loopGen;
    final startMs = DateTime.now().millisecondsSinceEpoch;
    _emitPositionBeat(volume);
    // `lastTargetMs` accumule les intervalles idéaux successifs. Sans
    // rampe, `currentInterval` est constant et on retrouve le calcul
    // historique `startMs + n × intervalMs`. Avec rampe, l'intervalle
    // change à chaque tick (cf. `_currentInterpolatedBpm`), donc on cumule
    // explicitement plutôt que d'utiliser `n * intervalMs`.
    var lastTargetMs = startMs;
    void scheduleNext() {
      if (myGen != _loopGen) return;
      final elapsedMs = lastTargetMs - startMs;
      final currentBpm = _currentInterpolatedBpm(elapsedMs);
      final intervalMs = (60000 / currentBpm).round();
      lastTargetMs += intervalMs;
      final delayMs =
          max(1, lastTargetMs - DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), () {
        if (myGen != _loopGen) return;
        _emitPositionBeat(volume);
        scheduleNext();
      });
    }

    scheduleNext();
  }

  /// BPM courant à `elapsedMs` du démarrage du loop. Retourne `_bpm`
  /// (constant) si pas de rampe armée. Sinon interpolation linéaire entre
  /// `_bpm` (t=0) et `_bpmEnd` (t=`_loopDurationMs`), clampée — au-delà
  /// de la durée annoncée (le step a duré plus que prévu, cas rare mais
  /// possible si un fail/pause a glissé), on reste sur `_bpmEnd` plutôt
  /// que d'extrapoler.
  double _currentInterpolatedBpm(int elapsedMs) {
    final bpmEnd = _bpmEnd;
    final dur = _loopDurationMs;
    if (bpmEnd == null || dur == null || dur <= 0) {
      return _bpm.toDouble();
    }
    final t = (elapsedMs / dur).clamp(0.0, 1.0);
    return _bpm + (bpmEnd - _bpm) * t;
  }

  void _emitPositionBeat(double baseVolume) {
    final pos = _pickPosition();
    if (_mode == SessionMode.hand) {
      final (asset, vol) = _resolveHandBeat(pos, baseVolume);
      _trigger(asset, vol);
    } else {
      _trigger(_assetForPosition(pos), baseVolume);
    }
    _notifyBeat(_mode, pos);
  }

  /// Choisit le sample (down/up) et son volume pour un beat de hand.
  /// - Avec amplitude (`_to != null && _to != _from`) : la position effective
  ///   du beat décide. Quand le beat tombe sur l'extrémité la plus profonde →
  ///   down, sinon → up. Le visuel (orbe sur ladder) flippe sur la même base,
  ///   donc l'audio reste calé sur l'arrivée de l'orbe.
  /// - Sans amplitude (single position) : on alterne via [_handStrokeFallbackDown]
  ///   pour garder la sensation de stroke.
  /// Volume du down : modulé par la profondeur de `to` ou de `_from` (à défaut),
  /// 0.7× au tip → 1.0× au full. Volume du up : constant à 0.85× du baseVolume.
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
    _trigger(_biffleAsset, _rhythmVolume);
    _notifyBeat(SessionMode.biffle, _to ?? _from);
    // Cumul des intervalles successifs (cf. `_startBeatLoop`) — supporte
    // la rampe BPM intra-step quand `_bpmEnd` / `_loopDurationMs` sont
    // armés. Comportement strictement identique sans rampe.
    var lastTargetMs = startMs;
    void scheduleNext() {
      if (myGen != _loopGen) return;
      final elapsedMs = lastTargetMs - startMs;
      final currentBpm = _currentInterpolatedBpm(elapsedMs);
      final intervalMs = (60000 / currentBpm).round();
      lastTargetMs += intervalMs;
      final delayMs =
          max(1, lastTargetMs - DateTime.now().millisecondsSinceEpoch);
      _loopTimer = Timer(Duration(milliseconds: delayMs), () {
        if (myGen != _loopGen) return;
        _trigger(_biffleAsset, _rhythmVolume);
        _notifyBeat(SessionMode.biffle, _to ?? _from);
        scheduleNext();
      });
    }

    scheduleNext();
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
    final picked = pool.next(volume);
    final needsReplaySeek = _longSampleAssets.contains(assetName);
    () async {
      // setVolume, seek et resume dans des `try` indépendants : un échec sur
      // une étape (PlatformException ponctuelle observée sur certains Android
      // quand les appels canal s'enchaînent vite) ne doit pas court-circuiter
      // les suivantes — sinon le bip est silencieusement perdu, exactement le
      // « bip qui manque de temps à autre » signalé. Et on saute carrément le
      // `setVolume` quand le volume n'a pas changé sur ce player (cas courant
      // d'un loop rythmé) → un appel canal de moins par bip, moins de
      // contention donc moins de bips en retard/perdus.
      if (picked.volumeChanged) {
        try {
          await picked.player.setVolume(volume);
        } catch (e) {
          if (kDebugMode) debugPrint('[BeepEngine] setVolume error : $e');
        }
      }
      if (needsReplaySeek) {
        // Sur les samples longs, on force la position à 0 avant `resume()` :
        // sans ça, si le plugin n'a pas encore vu `onPlayerComplete` (Android
        // peut avoir un hoquet de scheduling), le `resume()` ne redéclenche
        // rien et le bip de gorge/full/hold manque. Cf. doc de
        // [_longSampleAssets].
        try {
          await picked.player.seek(Duration.zero);
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

  void _stopLoop() {
    _loopTimer?.cancel();
    _loopTimer = null;
    // Invalide tout callback en file pour les loops self-rescheduling :
    // un Timer en cours d'exécution ne peut plus être annulé, mais sa
    // continuation (scheduleNext suivant) verra `myGen != _loopGen` et
    // s'arrêtera proprement.
    _loopGen++;
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

  /// Joue un seul coup du sample d'aspiration. Pour la démo SoundDemoScreen :
  /// pas de pulse, juste un slurp ponctuel pour identifier le son.
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
    _bpm = bpm.clamp(20, 300);
    if (_to != null && _to == _from) {
      _from = _pickShallowerThan(_from);
    }
    _alternateToggle = true;
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
    _alternateToggle = true;
    _stopLoop();
    _startBeatLoop(volume: _lickVolume);
  }

  void startBiffleDemo({required int bpm}) {
    if (!_initialized) return;
    _mode = SessionMode.biffle;
    _bpm = bpm.clamp(20, 300);
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
    final player = pool.next().player;
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
    _suckleTimer?.cancel();
    _suckleTimer = null;
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
        _startBeatLoop(volume: _rhythmVolume);
      case SessionMode.lick:
        _startBeatLoop(volume: _lickVolume);
      case SessionMode.hand:
        _startBeatLoop(volume: _handVolume);
      case SessionMode.biffle:
        _startBiffleLoop();
      case SessionMode.hold:
      case SessionMode.breath:
      case SessionMode.beg:
      case SessionMode.freestyle:
        // Modes one-shot ou silencieux — rien à reprendre.
        break;
      case SessionMode.suckle:
        // Reprend le pulse à partir de zéro (le timer a été annulé par
        // pause). On n'a pas la durée résiduelle ici → repulse indéfini,
        // de toute façon le prochain step coupera proprement.
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

  /// Dernier volume effectivement poussé sur chaque player (même indexation
  /// que [players]). `null` = jamais réglé. Sert à sauter le `setVolume`
  /// quand rien n'a changé (cf. [BeepEngine._trigger]).
  final List<double?> _lastVolume;
  int _idx = 0;

  _PlayerPool(this.players)
      : _lastVolume = List<double?>.filled(players.length, null);

  /// Avance le curseur round-robin et renvoie le player choisi + un flag
  /// indiquant s'il faut (re)pousser [volume] dessus. Si [volume] est `null`,
  /// l'appelant gère le volume lui-même → flag toujours `true`.
  ({AudioPlayer player, bool volumeChanged}) next([double? volume]) {
    final i = _idx;
    _idx = (_idx + 1) % players.length;
    if (volume == null) return (player: players[i], volumeChanged: true);
    final changed = _lastVolume[i] != volume;
    if (changed) _lastVolume[i] = volume;
    return (player: players[i], volumeChanged: changed);
  }
}
