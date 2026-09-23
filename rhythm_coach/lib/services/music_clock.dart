enum _ClockState { idle, waiting, playing, paused, stopped }

/// Position de lecture du morceau, extrapolée entre deux rapports du lecteur.
///
/// Chaque rapport ré-ancre l'extrapolation : l'écart de la position affichée
/// avec celle du lecteur ne dépasse jamais l'intervalle entre deux rapports, et
/// aucune erreur ne s'accumule.
class MusicClock {
  MusicClock({Duration Function()? now}) : _now = now ?? _stopwatchClock();

  static Duration Function() _stopwatchClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  final Duration Function() _now;

  _ClockState _state = _ClockState.idle;
  _ClockState _pausedFrom = _ClockState.idle;
  Duration _anchorPosition = Duration.zero;
  Duration _anchorWall = Duration.zero;
  Duration _frozen = Duration.zero;
  bool _synced = false;

  /// Vrai dès que le lecteur a rapporté une position depuis [start].
  bool get isSynced => _synced;

  Duration get position => switch (_state) {
        _ClockState.idle || _ClockState.waiting => Duration.zero,
        _ClockState.playing => _anchorPosition + (_now() - _anchorWall),
        _ClockState.paused || _ClockState.stopped => _frozen,
      };

  /// Attend le premier rapport du lecteur : la position reste à zéro tant que
  /// le morceau ne joue pas.
  void start() {
    _state = _ClockState.waiting;
    _synced = false;
    _frozen = Duration.zero;
  }

  void report(Duration position) {
    if (_state != _ClockState.waiting && _state != _ClockState.playing) return;
    _anchor(position);
    _synced = true;
    _state = _ClockState.playing;
  }

  /// Le lecteur ne rapportera rien : l'horloge court seule à partir de zéro.
  void freeRun() {
    if (_state != _ClockState.waiting) return;
    _anchor(Duration.zero);
    _state = _ClockState.playing;
  }

  void pause() {
    if (_state != _ClockState.waiting && _state != _ClockState.playing) return;
    _frozen = position;
    _pausedFrom = _state;
    _state = _ClockState.paused;
  }

  void resume() {
    if (_state != _ClockState.paused) return;
    if (_pausedFrom == _ClockState.playing) {
      _anchor(_frozen);
      _state = _ClockState.playing;
    } else {
      _state = _ClockState.waiting;
    }
  }

  /// Fige la position à sa dernière valeur : l'écran de fin la relit.
  void stop() {
    if (_state == _ClockState.idle || _state == _ClockState.stopped) return;
    _frozen = position;
    _state = _ClockState.stopped;
  }

  void _anchor(Duration position) {
    _anchorPosition = position;
    _anchorWall = _now();
  }
}
