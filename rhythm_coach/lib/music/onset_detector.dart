/// Détection d'onsets (attaques) dans un flux PCM mono (pur, testable).
///
/// Méthode simple et robuste : **flux d'énergie** par trame + **seuil
/// adaptatif**. Pour chaque trame on calcule l'énergie ; la montée d'énergie
/// (flux, demi-rectifiée) dépassant une moyenne glissante × `threshold`
/// déclenche un onset (avec période réfractaire `minIntervalMs`). Suffisant
/// pour suivre le kick/snare d'une musique ; le spectral-flux (FFT) pourra
/// l'améliorer plus tard.
class OnsetDetector {
  final int sampleRate;
  final int frameSize;
  final double threshold;
  final int minIntervalMs;
  final double alpha; // lissage EMA du flux

  double _prevEnergy = 0;
  double _fluxAvg = 0;
  int _lastOnsetMs = -1 << 30;
  int _samplePos = 0;
  final List<double> _buf = [];

  OnsetDetector({
    this.sampleRate = 44100,
    this.frameSize = 1024,
    this.threshold = 2.0,
    this.minIntervalMs = 120,
    this.alpha = 0.9,
  });

  /// Pousse des samples PCM mono (−1..1) ; rend les timestamps (ms) des onsets
  /// détectés. Les trames incomplètes sont gardées entre les appels (streaming).
  List<int> process(List<double> samples) {
    final onsets = <int>[];
    _buf.addAll(samples);
    while (_buf.length >= frameSize) {
      var energy = 0.0;
      for (var i = 0; i < frameSize; i++) {
        final s = _buf[i];
        energy += s * s;
      }
      energy /= frameSize;
      _buf.removeRange(0, frameSize);

      final flux = energy > _prevEnergy ? energy - _prevEnergy : 0.0;
      _prevEnergy = energy;
      final frameMs = (_samplePos * 1000 / sampleRate).round();
      _samplePos += frameSize;

      if (flux > _fluxAvg * threshold &&
          flux > 1e-5 &&
          frameMs - _lastOnsetMs >= minIntervalMs) {
        onsets.add(frameMs);
        _lastOnsetMs = frameMs;
      }
      _fluxAvg = alpha * _fluxAvg + (1 - alpha) * flux;
    }
    return onsets;
  }

  /// Temps courant (ms) selon les samples consommés — utile pour caler une
  /// horloge sur la même base temporelle que les onsets.
  int get elapsedMs => (_samplePos * 1000 / sampleRate).round();

  void reset() {
    _prevEnergy = 0;
    _fluxAvg = 0;
    _lastOnsetMs = -1 << 30;
    _samplePos = 0;
    _buf.clear();
  }
}
