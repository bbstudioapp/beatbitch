import 'package:shared_preferences/shared_preferences.dart';

import 'capability_axis.dart';

/// État persistant d'un axe du profil de capacités.
///
/// - [best] : meilleure valeur **complétée proprement** (sans fail, sans
///   « je peux pas », sans débordement de salive pour les axes concernés).
///   `null` tant qu'aucune donnée n'a été enregistrée. Monotone (croissant
///   pour `maximize` / `accumulate`, décroissant pour `minimize`).
/// - [comfort] : la cible autour de laquelle le générateur travaille. En
///   Phase 1 elle est posée naïvement à `best` ; les phases suivantes la
///   rendent adaptative (ratchet ↑/↓, decay).
/// - [successRate] : EMA des réussites/échecs récents sur cet axe (0..1).
///   Inerte en Phase 1 (reste à la valeur de départ).
/// - [lastSeenSession] : index de la dernière session où l'axe a été
///   sollicité. Sert au decay « use it or lose it » (phases ultérieures).
class CapabilityAxisState {
  final double? best;
  final double? comfort;
  final double successRate;
  final int lastSeenSession;

  const CapabilityAxisState({
    this.best,
    this.comfort,
    this.successRate = CapabilityService.defaultSuccessRate,
    this.lastSeenSession = -1,
  });

  bool get hasData => best != null;
}

/// Vue lecture seule du profil complet, passée (à terme) au générateur de
/// session. En Phase 1 seul le ProfileScreen la consomme pour l'affichage.
class CapabilityProfile {
  final Map<CapabilityAxis, CapabilityAxisState> _states;

  const CapabilityProfile(this._states);

  CapabilityAxisState stateOf(CapabilityAxis axis) =>
      _states[axis] ?? const CapabilityAxisState();

  double? bestOf(CapabilityAxis axis) => stateOf(axis).best;
  double? comfortOf(CapabilityAxis axis) => stateOf(axis).comfort;

  /// `true` si au moins un axe porte des données — sert au ProfileScreen
  /// pour décider d'afficher (ou non) la section « Capacités ».
  bool get hasAnyData => _states.values.any((s) => s.hasData);

  Iterable<CapabilityAxis> get axesWithData =>
      CapabilityAxis.displayOrder.where((a) => stateOf(a).hasData);
}

/// Rapport produit par `CapabilityTracker` à la fin d'une session.
///
/// [reached] : pour chaque axe sollicité proprement, la valeur atteinte
/// (max streak / max BPM / cran max ; min pour les axes `minimize` ;
/// somme de la session pour les axes `accumulate`).
///
/// [sessionCeilings] : valeurs figées lors d'un appui FAIL (cf. §6 de la
/// spec). En Phase 1 elles sont collectées mais pas encore consommées —
/// le générateur ne les lira qu'en Phase 2.
class SessionCapabilityReport {
  final Map<CapabilityAxis, double> reached;
  final Map<CapabilityAxis, double> sessionCeilings;

  const SessionCapabilityReport({
    required this.reached,
    required this.sessionCeilings,
  });

  bool get isEmpty => reached.isEmpty && sessionCeilings.isEmpty;
}

/// Persistance du profil de capacités (`shared_preferences`).
///
/// Mode **carrière uniquement** : Custom et scénarios JSON n'écrivent rien
/// (le `CapabilityTracker` n'y est tout simplement pas câblé).
class CapabilityService {
  static const String _prefix = 'cap.';
  static const String _suffixBest = '.best';
  static const String _suffixComfort = '.comfort';
  static const String _suffixSuccessRate = '.sr';
  static const String _suffixLastSeen = '.seen';

  /// Clé legacy de `StatsService` migrée vers `holdFullStreak.best` au 1er
  /// lancement. On lit la valeur directement depuis `shared_preferences`
  /// pour ne pas créer de dépendance sur `StatsService` — la clé reste en
  /// place (le badge IronLungs continue de la consommer).
  static const String _kLegacyMaxHoldFullAtomic = 'stats.max_hold_full_atomic';

  /// Drapeau « migration legacy déjà tentée » — évite de re-seeder si la
  /// joueuse a depuis fait reculer son record (impossible aujourd'hui, mais
  /// défensif) ou si le seed a été volontairement effacé.
  static const String _kLegacyMigrated = 'cap.legacy_migrated';

  static const double defaultSuccessRate = 0.5;

  /// Lit l'état persisté de tous les axes (après migration legacy).
  Future<CapabilityProfile> snapshotProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    final states = <CapabilityAxis, CapabilityAxisState>{};
    for (final axis in CapabilityAxis.values) {
      states[axis] = _readState(prefs, axis);
    }
    return CapabilityProfile(states);
  }

  /// Intègre un rapport de fin de session dans le profil persisté.
  ///
  /// [sessionIndex] = compteur de sessions carrière complétées (utilisé
  /// comme horloge de decay ; en Phase 1 on se contente de le mémoriser
  /// dans `lastSeenSession`).
  ///
  /// Phase 1 : `comfort` est posé naïvement à `best` après mise à jour ;
  /// `successRate` n'est pas touché.
  Future<void> commit(
    SessionCapabilityReport report, {
    required int sessionIndex,
  }) async {
    if (report.reached.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    report.reached.forEach((axis, reached) {
      final current = _readState(prefs, axis);
      final double? prevBest = current.best;
      final double newBest;
      switch (axis.recordKind) {
        case CapabilityRecordKind.maximize:
          newBest = prevBest == null
              ? reached
              : (reached > prevBest ? reached : prevBest);
        case CapabilityRecordKind.minimize:
          newBest = prevBest == null
              ? reached
              : (reached < prevBest ? reached : prevBest);
        case CapabilityRecordKind.accumulate:
          newBest = (prevBest ?? 0) + reached;
      }
      _writeState(
        prefs,
        axis,
        best: newBest,
        comfort: newBest, // Phase 1 : comfort naïf = best.
        successRate: current.successRate,
        lastSeenSession: sessionIndex,
      );
    });
  }

  /// Efface tout le profil de capacités (bouton « tout remettre à zéro » du
  /// ProfileScreen). Ne touche pas la clé legacy `stats.max_hold_full_atomic`
  /// (gérée par `StatsService.resetAll`), mais reset le drapeau de migration
  /// pour qu'un éventuel reset partiel se re-seede correctement.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final axis in CapabilityAxis.values) {
      await prefs.remove('$_prefix${axis.storageKey}$_suffixBest');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixComfort');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixSuccessRate');
      await prefs.remove('$_prefix${axis.storageKey}$_suffixLastSeen');
    }
    await prefs.remove(_kLegacyMigrated);
  }

  // ── interne ───────────────────────────────────────────────────────────

  CapabilityAxisState _readState(SharedPreferences prefs, CapabilityAxis axis) {
    final base = '$_prefix${axis.storageKey}';
    return CapabilityAxisState(
      best: prefs.getDouble('$base$_suffixBest'),
      comfort: prefs.getDouble('$base$_suffixComfort'),
      successRate:
          prefs.getDouble('$base$_suffixSuccessRate') ?? defaultSuccessRate,
      lastSeenSession: prefs.getInt('$base$_suffixLastSeen') ?? -1,
    );
  }

  void _writeState(
    SharedPreferences prefs,
    CapabilityAxis axis, {
    required double best,
    required double comfort,
    required double successRate,
    required int lastSeenSession,
  }) {
    final base = '$_prefix${axis.storageKey}';
    prefs.setDouble('$base$_suffixBest', best);
    prefs.setDouble('$base$_suffixComfort', comfort);
    prefs.setDouble('$base$_suffixSuccessRate', successRate);
    prefs.setInt('$base$_suffixLastSeen', lastSeenSession);
  }

  /// Migration au 1er lancement : `StatsService.maxHoldFullAtomic` (« plus
  /// long hold full sans fail ») n'est rien d'autre qu'un axe de ce profil.
  /// On l'importe dans `holdFullStreak` si l'axe n'a pas encore de donnée.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (prefs.getBool(_kLegacyMigrated) ?? false) return;
    await prefs.setBool(_kLegacyMigrated, true);
    final legacy = prefs.getInt(_kLegacyMaxHoldFullAtomic) ?? 0;
    if (legacy <= 0) return;
    final base = '$_prefix${CapabilityAxis.holdFullStreak.storageKey}';
    if (prefs.getDouble('$base$_suffixBest') != null) return;
    final v = legacy.toDouble();
    prefs.setDouble('$base$_suffixBest', v);
    prefs.setDouble('$base$_suffixComfort', v);
    prefs.setDouble('$base$_suffixSuccessRate', defaultSuccessRate);
    prefs.setInt('$base$_suffixLastSeen', -1);
  }
}
