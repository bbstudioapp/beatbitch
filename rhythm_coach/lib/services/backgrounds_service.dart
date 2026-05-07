import 'dart:math';

import 'package:flutter/foundation.dart';

import 'backgrounds_loader.dart';

/// Singleton qui pilote le fond média de l'écran de jeu.
///
/// **Modes de mise à jour** :
/// - `setById(id)` : override explicite (consommé par `step.background`).
/// - `pickRandom()` : pioche un fond aléatoire dans le catalogue, en
///   excluant l'entrée courante pour ne jamais re-tomber sur le même
///   visuel deux steps de suite.
/// - `clear()` : retire le fond courant (le widget retombe sur le
///   placeholder animé).
///
/// **État** : `current` est un `ValueNotifier<BackgroundEntry?>` que le
/// widget `SessionBackground` écoute. Pas de stream — un seul observateur
/// (l'écran de jeu actif), pas besoin de broadcast.
class BackgroundsService {
  BackgroundsService._();

  static final BackgroundsService instance = BackgroundsService._();

  final ValueNotifier<BackgroundEntry?> current =
      ValueNotifier<BackgroundEntry?>(null);

  BackgroundsBundle _bundle = BackgroundsBundle.empty;
  final Random _rng = Random();

  /// Charge ou recharge le catalogue. Appelé une fois au démarrage de
  /// l'app, idempotent.
  void setBundle(BackgroundsBundle bundle) {
    _bundle = bundle;
    // Si l'entrée courante n'existe plus dans le nouveau bundle, on la
    // clear pour ne pas pointer vers un id orphelin.
    final cur = current.value;
    if (cur != null && _bundle.byId(cur.id) == null) {
      current.value = null;
    }
  }

  bool get hasEntries => _bundle.entries.isNotEmpty;

  /// Override explicite par id (typiquement appelé par `SessionController`
  /// quand un step a `background: "..."`). No-op si l'id est inconnu —
  /// on ne casse pas la session pour un asset manquant, on garde le fond
  /// courant.
  void setById(String id) {
    final entry = _bundle.byId(id);
    if (entry == null) return;
    current.value = entry;
  }

  /// Pioche aléatoire **différente** de l'entrée courante (anti-doublon
  /// immédiat). Appelé par `SessionController` à chaque step de config
  /// pour faire vivre l'arrière-plan visuellement. Si le bundle a une
  /// seule entrée, on retombe forcément dessus ; si le bundle est vide,
  /// no-op (le widget reste sur son placeholder animé).
  void pickRandom() {
    final n = _bundle.entries.length;
    if (n == 0) return;
    if (n == 1) {
      current.value = _bundle.entries.first;
      return;
    }
    final cur = current.value;
    final curIdx = cur == null ? -1 : _bundle.entries.indexOf(cur);
    if (curIdx < 0) {
      current.value = _bundle.entries[_rng.nextInt(n)];
      return;
    }
    // Tire dans [0, n-1] en excluant curIdx. Astuce : tirer dans
    // [0, n-2] et décaler de 1 si on tombe sur curIdx ou plus haut.
    final draw = _rng.nextInt(n - 1);
    final pick = draw >= curIdx ? draw + 1 : draw;
    current.value = _bundle.entries[pick];
  }

  /// Reset complet (sortie de session, retour au placeholder).
  void clear() {
    current.value = null;
  }
}
