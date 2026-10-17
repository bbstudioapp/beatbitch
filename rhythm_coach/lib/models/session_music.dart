import 'dart:math' as math;

/// Morceau joué en fond d'une séance, avec la grille de ses temps.
class SessionMusic {
  static const double defaultVolume = 0.85;
  static const double defaultBeepGain = 0.4;

  /// Relatif à `assets/`, comme un `AssetSource`.
  final String asset;
  final double bpm;

  /// Instant du temps n°0 dans le fichier, en secondes.
  final double firstBeatSeconds;
  final double volume;

  /// Facteur appliqué au volume des bips pendant la séance.
  final double beepGain;

  const SessionMusic({
    required this.asset,
    required this.bpm,
    required this.firstBeatSeconds,
    this.volume = defaultVolume,
    this.beepGain = defaultBeepGain,
  });

  Duration get beatPeriod => Duration(microseconds: (60e6 / bpm).round());

  /// Chaque temps est calculé depuis son index : additionner des périodes
  /// arrondies dériverait.
  Duration beatTime(int index) => Duration(
        microseconds: (firstBeatSeconds * 1e6 + index * 60e6 / bpm).round(),
      );

  /// Premier temps d'index multiple de [stride], à [position] ou après, jamais
  /// avant le temps n°0.
  int beatIndexAtOrAfter(Duration position, {int stride = 1}) {
    final fromFirst = position.inMicroseconds - firstBeatSeconds * 1e6;
    final index = math.max(0, (fromFirst * bpm / 60e6 - 1e-5).ceil());
    return (index + stride - 1) ~/ stride * stride;
  }

  /// Nombre de temps de la grille par mouvement pour un step à [stepBpm] :
  /// 122 → 1, 61 → 2. Le BPM d'un step est entier, celui du morceau ne l'est pas.
  int strideForStepBpm(int stepBpm) =>
      stepBpm <= 0 ? 1 : math.max(1, (bpm / stepBpm).round());

  static SessionMusic? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final asset = raw['asset'];
    final bpm = raw['bpm'];
    final firstBeat = raw['first_beat'];
    final volume = raw['volume'];
    final beepGain = raw['beep_gain'];
    if (asset is! String || asset.isEmpty) return null;
    if (bpm is! num || bpm <= 0) return null;
    if (firstBeat is! num || firstBeat < 0) return null;
    return SessionMusic(
      asset: asset,
      bpm: bpm.toDouble(),
      firstBeatSeconds: firstBeat.toDouble(),
      volume: volume is num ? volume.toDouble().clamp(0.0, 1.0) : defaultVolume,
      beepGain: beepGain is num
          ? beepGain.toDouble().clamp(0.0, 1.0)
          : defaultBeepGain,
    );
  }

  Map<String, dynamic> toJson() => {
        'asset': asset,
        'bpm': bpm,
        'first_beat': firstBeatSeconds,
        if (volume != defaultVolume) 'volume': volume,
        if (beepGain != defaultBeepGain) 'beep_gain': beepGain,
      };

  @override
  bool operator ==(Object other) =>
      other is SessionMusic &&
      other.asset == asset &&
      other.bpm == bpm &&
      other.firstBeatSeconds == firstBeatSeconds &&
      other.volume == volume &&
      other.beepGain == beepGain;

  @override
  int get hashCode =>
      Object.hash(asset, bpm, firstBeatSeconds, volume, beepGain);
}
