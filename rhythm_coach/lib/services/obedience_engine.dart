/// Score d'obéissance. **Persisté entre sessions** via
/// `StatsService.obedienceLevel`. Démarre à 0 (nouvelle utilisatrice
/// désobéissante par défaut), monte ~2× plus vite que l'humiliation,
/// pas de borne haute.
///
/// **Pénalisé en session** par :
/// - fail manuel : −2 (×2 dans la dernière minute)
/// - punition abandonnée : −5 (×2 dans la dernière minute), en plus du fail
///   qui l'a déclenchée
///
/// **Récompensé en session** par :
/// - tick automatique : +1 toutes les 120s
/// - punition complétée : +2
/// - session sans fail : +3 (au `_finish`)
///
/// **Effets cross-system** :
/// - **Accélère la montée d'humiliation** : `HumiliationEngine.onTickSecond`
///   consulte `obedienceLevel` pour raccourcir l'intervalle de tick. À
///   obed=100, humil tick toutes les 120s au lieu de 240s.
/// - **Tier de phrase auto-bumpé** dans `_pickPhrase` du générateur :
///   plus l'obéissance est haute, plus la coach pioche dans `medium`/`hard`.
/// - **Recovery threshold** côté générateur : recovery déclenchée plus tôt
///   pour les obéissantes (respect endurance).
///
/// La barre debug intra-session affiche le score live ; le score persiste
/// au `_finish` via `StatsService.setObedienceLevel`.
class ObedienceEngine {
  /// Période entre deux bumps automatiques en cours de session (2 min).
  /// Deux fois plus rapide que `HumiliationEngine.tickInterval` (4 min).
  static const Duration tickInterval = Duration(seconds: 120);

  static const double bumpPerInterval = 1.0;
  static const double bumpPunishmentCompleted = 2.0;
  static const double bumpSessionClean = 3.0;
  static const double malusFail = 2.0;
  static const double malusPunishmentAbandoned = 5.0;

  double _score = 0.0;
  double get score => _score;

  /// Secondes écoulées dans la session courante depuis le dernier bump.
  /// Sert au tick automatique (+1 toutes les `tickInterval`).
  int _secondsSinceLastBump = 0;

  /// Initialise depuis le score persisté. Appelé par le SessionController
  /// au start (une fois la valeur récupérée de StatsService).
  void seed(double persisted) {
    _score = persisted < 0 ? 0 : persisted;
    _secondsSinceLastBump = 0;
  }

  /// Tick par seconde. Tous les `tickInterval`, +1 au score. Pas de
  /// modulation par humiliation côté obédiance — c'est obédiance qui
  /// accélère humil, pas l'inverse, pour éviter une boucle de feedback.
  void onTickSecond() {
    _secondsSinceLastBump++;
    if (_secondsSinceLastBump >= tickInterval.inSeconds) {
      _secondsSinceLastBump = 0;
      _bump(bumpPerInterval);
    }
  }

  void onPunishmentCompleted() => _bump(bumpPunishmentCompleted);
  void onSessionCleanFinish() => _bump(bumpSessionClean);
  void onFail({double multiplier = 1.0}) => _bump(-malusFail * multiplier);
  void onPunishmentAbandoned({double multiplier = 1.0}) =>
      _bump(-malusPunishmentAbandoned * multiplier);

  void _bump(double delta) {
    final next = _score + delta;
    _score = next < 0 ? 0 : next;
  }

  /// Reset complet (utilisé par le SessionController au cas où on démarre
  /// sans seed persistée). Préférer `seed(0)` qui fait la même chose et
  /// garde l'API cohérente avec les autres engines persistants.
  void reset() {
    _score = 0.0;
    _secondsSinceLastBump = 0;
  }
}
