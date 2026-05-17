// Fichier part de `career_session_generator.dart` — buffer roulant des
// 3 derniers steps rythmés émis + détecteur de pattern plat.
//
// L'oreille perçoit comme « plat » une série de 3 steps consécutifs
// même mode + même profondeur cible + variance BPM < 10. Le check
// classique de `_diversifyAmplitude` ne regardait que le step
// strictement précédent et laissait passer `head→mid 90 / 92 / 88`
// (BPMs « différents ») alors que c'est uniforme à l'oreille.
//
// Concerne uniquement les 4 modes à amplitude rythmée (rhythm / lick /
// hand / biffle). Les hold / beg n'ont pas de BPM et leur monotonie
// est gérée ailleurs (variation de position dans `_pickHoldPosition`
// / `_lastFrom`). Les steps transit (breath / freestyle) sont
// transparents — un breath de récup au milieu d'une série rythmée ne
// casse pas la perception du pattern, on veut qu'il continue à compter.

part of 'career_session_generator.dart';

/// Snapshot léger d'un step rythmé déjà émis, conservé dans le buffer
/// roulant de `_RhythmicPatternBuffer`.
typedef _RecentEmit = ({
  SessionMode mode,
  Position? from,
  Position? to,
  int? bpm,
});

/// Buffer roulant des 3 derniers steps rythmés émis + détecteur de
/// pattern plat. État par-session : `clear()` au début de chaque
/// `generate()`. Méthode `record(...)` filtre elle-même les modes
/// non-rythmés (no-op si `mode` n'est pas dans le quatuor à amplitude).
class _RhythmicPatternBuffer {
  _RhythmicPatternBuffer();

  /// Taille du buffer (3 derniers émis). Combinée au draft candidat,
  /// `wouldBeFlat` raisonne sur une fenêtre de 4 valeurs.
  static const int _windowSize = 3;

  /// Variance BPM (en BPM) en dessous de laquelle on considère le
  /// pattern « plat » à l'oreille. 10 BPM = seuil serré, on n'intervient
  /// que vraiment en dessous.
  static const int _flatBpmSpread = 10;

  final List<_RecentEmit> _emits = [];

  /// Vide le buffer. Appelé au début de chaque `generate()`.
  void clear() => _emits.clear();

  /// Enregistre un step poussé. No-op si `mode` n'est pas un mode
  /// rythmé (rhythm / lick / hand / biffle) — le caller peut appeler
  /// mode-blind, le filtre est interne.
  void record(SessionMode mode, {Position? from, Position? to, int? bpm}) {
    if (mode != SessionMode.rhythm &&
        mode != SessionMode.lick &&
        mode != SessionMode.hand &&
        mode != SessionMode.biffle) {
      return;
    }
    _emits.add((mode: mode, from: from, to: to, bpm: bpm));
    while (_emits.length > _windowSize) {
      _emits.removeAt(0);
    }
  }

  /// Vrai si le draft proposé prolongerait un **pattern plat** : les 3
  /// derniers émis + le draft sont tous (a) du même mode rythmé,
  /// (b) à la même profondeur cible `to`, (c) avec une variance BPM
  /// < `_flatBpmSpread` sur les 4 valeurs.
  bool wouldBeFlat(_StepDraft d) {
    if (_emits.length < _windowSize) return false;
    if (d.bpm == null || d.to == null) return false;
    if (!_emits.every((e) => e.mode == d.mode)) return false;
    if (!_emits.every((e) => e.to == d.to)) return false;
    final bpms = <int>[
      for (final e in _emits)
        if (e.bpm != null) e.bpm!,
      d.bpm!,
    ];
    if (bpms.length < _windowSize + 1) return false;
    final maxB = bpms.reduce(max);
    final minB = bpms.reduce(min);
    return (maxB - minB) < _flatBpmSpread;
  }
}
