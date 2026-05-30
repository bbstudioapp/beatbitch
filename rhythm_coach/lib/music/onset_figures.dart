import 'beat_pattern.dart';

/// Banque **curée** de figures rythmiques (axe onset, cf. `specs/music_mode.md`
/// §8). Une figure est une suite de **gestes** `(up, down)` qui garantit la
/// grammaire du mouvement :
/// - `up` ≥ 1 battements à l'**ancre** (le 1ᵉʳ = remontée, les suivants = repos
///   en haut) ;
/// - `down` ≥ 1 battements **en bas** (le 1ᵉʳ = la **frappe**, les suivants =
///   des **holds**).
///
/// Conséquence garantie par construction : jamais deux plongées sans ancre
/// entre elles, et toute plongée (frappe + holds) est encadrée par des ancres
/// — une ancre avant la frappe et une ancre après le dernier hold.
class OnsetFigure {
  final String id;

  /// Niveau de difficulté (densité / holds) — sert au gating par phrase.
  final int level;

  final List<({int up, int down})> gestures;

  const OnsetFigure(this.id, this.level, this.gestures);

  /// Déploie les gestes en suite de slots (toujours grammaticalement valide).
  List<SlotOnset> expand() => [
        for (final g in gestures) ...[
          for (var i = 0; i < g.up; i++) SlotOnset.release,
          SlotOnset.strike,
          for (var i = 1; i < g.down; i++) SlotOnset.hold,
        ],
      ];
}

/// Banque de départ (PR1). Petite et lisible — on l'étoffe au fil des retours.
const List<OnsetFigure> onsetFigureBank = [
  // Niveau 1 — pompe régulière, une ancre entre chaque plongée.
  OnsetFigure('steady', 1, [
    (up: 1, down: 1),
    (up: 1, down: 1),
    (up: 1, down: 1),
    (up: 1, down: 1),
  ]),
  OnsetFigure('breath', 1, [
    (up: 2, down: 1),
    (up: 1, down: 1),
    (up: 2, down: 1),
  ]),
  OnsetFigure('hold_soft', 1, [
    (up: 1, down: 2),
    (up: 1, down: 1),
    (up: 1, down: 2),
  ]),
  // Niveau 2 — respirations contrastées, holds courts.
  OnsetFigure('swing', 2, [
    (up: 2, down: 1),
    (up: 1, down: 2),
    (up: 1, down: 1),
  ]),
  OnsetFigure('hold_mid', 2, [
    (up: 1, down: 3),
    (up: 1, down: 1),
    (up: 1, down: 2),
  ]),
  OnsetFigure('drive', 2, [
    (up: 1, down: 1),
    (up: 1, down: 1),
    (up: 2, down: 2),
  ]),
  // Niveau 3 — holds longs / contrastes marqués.
  OnsetFigure('deep_hold', 3, [
    (up: 1, down: 4),
    (up: 2, down: 1),
    (up: 1, down: 2),
  ]),
  OnsetFigure('stutter', 3, [
    (up: 1, down: 1),
    (up: 1, down: 1),
    (up: 1, down: 1),
    (up: 1, down: 2),
  ]),
  OnsetFigure('build', 3, [
    (up: 2, down: 1),
    (up: 1, down: 2),
    (up: 1, down: 3),
  ]),
];
