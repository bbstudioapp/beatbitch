import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';
import '../models/session_step.dart';

/// Compteurs cumulés persistants. Toutes les sessions y contribuent
/// (carrière comme statiques). Lecture/écriture via shared_preferences.
class StatsService {
  static const String _kTotalSeconds = 'stats.total_seconds';
  static const String _kThroatfucks = 'stats.throatfucks';
  static const String _kBiffles = 'stats.biffles';
  static const String _kHoldThroatSec = 'stats.hold_throat_seconds';
  static const String _kHoldFullSec = 'stats.hold_full_seconds';
  static const String _kSessionsCompleted = 'stats.sessions_completed';
  static const String _kSessionsNoFail = 'stats.sessions_no_fail_streak';
  static const String _kModesUsedMask = 'stats.modes_used_mask';
  static const String _kMaxHoldFullSecAtomic = 'stats.max_hold_full_atomic';
  static const String _kLastSessionDay = 'stats.last_session_day';
  static const String _kDailyStreak = 'stats.daily_streak';
  static const String _kEncoresAsked = 'stats.encores_asked';
  static const String _kQuickiesCompleted = 'stats.quickies_completed';
  static const String _kHumiliationLevel = 'stats.humiliation_level';
  static const String _kObedienceLevel = 'stats.obedience_level';

  // Compteurs des badges de fin de séance (final / post-final). Incrémentés
  // par `SessionController._finish` quand la session se termine sans fail.
  static const String _kFinalsBouchePleine = 'stats.finals_bouche_pleine';
  static const String _kFinalsRepeinte = 'stats.finals_repeinte';
  static const String _kFinalsGobeuse = 'stats.finals_gobeuse';
  static const String _kPostFinalsNettoyeuse = 'stats.post_finals_nettoyeuse';
  static const String _kPostFinalsSuppliante = 'stats.post_finals_suppliante';

  Future<StatsSnapshot> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return StatsSnapshot(
      totalSeconds: prefs.getInt(_kTotalSeconds) ?? 0,
      throatfucks: prefs.getInt(_kThroatfucks) ?? 0,
      biffles: prefs.getInt(_kBiffles) ?? 0,
      holdThroatSeconds: prefs.getInt(_kHoldThroatSec) ?? 0,
      holdFullSeconds: prefs.getInt(_kHoldFullSec) ?? 0,
      sessionsCompleted: prefs.getInt(_kSessionsCompleted) ?? 0,
      sessionsNoFailStreak: prefs.getInt(_kSessionsNoFail) ?? 0,
      modesUsedMask: prefs.getInt(_kModesUsedMask) ?? 0,
      maxHoldFullAtomic: prefs.getInt(_kMaxHoldFullSecAtomic) ?? 0,
      dailyStreak: prefs.getInt(_kDailyStreak) ?? 0,
      encoresAsked: prefs.getInt(_kEncoresAsked) ?? 0,
      quickiesCompleted: prefs.getInt(_kQuickiesCompleted) ?? 0,
      humiliationLevel: prefs.getDouble(_kHumiliationLevel) ?? 0.0,
      obedienceLevel: prefs.getDouble(_kObedienceLevel) ?? 0.0,
      finalsBouchePleine: prefs.getInt(_kFinalsBouchePleine) ?? 0,
      finalsRepeinte: prefs.getInt(_kFinalsRepeinte) ?? 0,
      finalsGobeuse: prefs.getInt(_kFinalsGobeuse) ?? 0,
      postFinalsNettoyeuse: prefs.getInt(_kPostFinalsNettoyeuse) ?? 0,
      postFinalsSuppliante: prefs.getInt(_kPostFinalsSuppliante) ?? 0,
    );
  }

  /// Lecture rapide du score d'humiliation persisté (0..100). Appelé au
  /// start de chaque session pour seeder l'`HumiliationEngine`.
  Future<double> getHumiliationLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kHumiliationLevel) ?? 0.0;
  }

  /// Persiste le score d'humiliation atteint à la fin d'une session.
  /// Le score est un thermomètre cumulé entre sessions, sans borne haute
  /// (les longues carrières peuvent dépasser 100). Borne basse : 0.
  Future<void> setHumiliationLevel(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _kHumiliationLevel,
      value < 0 ? 0 : value,
    );
  }

  /// Lit le score d'obéissance persisté. Démarre à 0 (nouvelle utilisatrice
  /// désobéissante par défaut). Score persistant entre sessions, monte ~2×
  /// plus vite que l'humiliation, sans borne haute.
  Future<double> getObedienceLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kObedienceLevel) ?? 0.0;
  }

  /// Persiste le score d'obéissance atteint à la fin d'une session.
  /// Borne basse 0, pas de borne haute.
  Future<void> setObedienceLevel(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _kObedienceLevel,
      value < 0 ? 0 : value,
    );
  }

  /// Comptabilise un appui sur le bouton « J'en veux encore ». Cumul
  /// global, alimente le badge JamaisRassasiee. Le bump d'humiliation
  /// transit désormais via la conservation du `sessionScore` au start
  /// de la session-encore enchaînée et le delta career intégré au
  /// `_finish` (cf. `HumiliationEngine.applyEndOfSessionDelta`).
  Future<void> recordEncoreAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kEncoresAsked,
      (prefs.getInt(_kEncoresAsked) ?? 0) + 1,
    );
  }

  /// Comptabilise un final de séance selon son mode. Incrémente le compteur
  /// de la famille de badge correspondante (Bouche pleine / Repeinte /
  /// Gobeuse). À appeler dans `_finish`, uniquement sur les sessions
  /// menées à terme sans fail. Modes hors {`hold`, `biffle`, `lick`} →
  /// no-op (les autres finals sont possibles mais ne sont pas badgés).
  Future<void> recordFinalMode(SessionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (mode) {
      SessionMode.hold => _kFinalsBouchePleine,
      SessionMode.biffle => _kFinalsRepeinte,
      SessionMode.lick => _kFinalsGobeuse,
      _ => null,
    };
    if (key == null) return;
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  /// Comptabilise un post-final de séance selon son mode. Incrémente le
  /// compteur de la famille de badge correspondante (Nettoyeuse pour
  /// `lick`, Suppliante pour `beg`). Mêmes contraintes que [recordFinalMode] :
  /// session terminée sans fail, modes hors {`lick`, `beg`} = no-op.
  Future<void> recordPostFinalMode(SessionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final key = switch (mode) {
      SessionMode.lick => _kPostFinalsNettoyeuse,
      SessionMode.beg => _kPostFinalsSuppliante,
      _ => null,
    };
    if (key == null) return;
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  /// Comptabilise une session bâclée menée à terme (toggle "Session bâclée"
  /// en Carrière). Cumul global, alimente le badge VideCouilles.
  Future<void> recordQuickieCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kQuickiesCompleted,
      (prefs.getInt(_kQuickiesCompleted) ?? 0) + 1,
    );
  }

  Future<void> addElapsedSeconds(int n) async {
    if (n <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kTotalSeconds,
      (prefs.getInt(_kTotalSeconds) ?? 0) + n,
    );
  }

  /// Comptabilise un beat de rhythm/lick selon sa cible. Retourne le
  /// type de beat compté (utile pour la jauge d'excitation).
  Future<void> recordBeat({
    required SessionMode mode,
    Position? to,
    Position? from,
  }) async {
    if (mode != SessionMode.rhythm &&
        mode != SessionMode.lick &&
        mode != SessionMode.biffle &&
        mode != SessionMode.hand) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (mode == SessionMode.biffle) {
      await prefs.setInt(_kBiffles, (prefs.getInt(_kBiffles) ?? 0) + 1);
      return;
    }
    // Throatfuck = bip qui touche throat ou full (cible profonde).
    final reaches = to ?? from;
    if (reaches == Position.throat || reaches == Position.full) {
      await prefs.setInt(
        _kThroatfucks,
        (prefs.getInt(_kThroatfucks) ?? 0) + 1,
      );
    }
  }

  /// Une seconde tenue dans un hold. Comptabilise selon la position.
  Future<void> recordHoldSecond(Position position) async {
    final prefs = await SharedPreferences.getInstance();
    if (position == Position.throat) {
      await prefs.setInt(
        _kHoldThroatSec,
        (prefs.getInt(_kHoldThroatSec) ?? 0) + 1,
      );
    } else if (position == Position.full) {
      await prefs.setInt(
        _kHoldFullSec,
        (prefs.getInt(_kHoldFullSec) ?? 0) + 1,
      );
    }
  }

  /// Mémorise un hold full mené à terme (sans fail) — sert au badge IronLungs.
  Future<void> recordHoldFullCompleted(int durationSeconds) async {
    if (durationSeconds <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_kMaxHoldFullSecAtomic) ?? 0;
    if (durationSeconds > current) {
      await prefs.setInt(_kMaxHoldFullSecAtomic, durationSeconds);
    }
  }

  /// Marque un mode comme utilisé (badge ToutTerrain).
  Future<void> markModeUsed(SessionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    final mask = prefs.getInt(_kModesUsedMask) ?? 0;
    final bit = 1 << mode.index;
    if ((mask & bit) == 0) {
      await prefs.setInt(_kModesUsedMask, mask | bit);
    }
  }

  /// À appeler à la fin d'une session menée à son terme.
  /// [hadFail] = au moins un appui sur le bouton rouge.
  Future<void> recordSessionCompleted({required bool hadFail}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kSessionsCompleted,
      (prefs.getInt(_kSessionsCompleted) ?? 0) + 1,
    );
    if (hadFail) {
      await prefs.setInt(_kSessionsNoFail, 0);
    } else {
      await prefs.setInt(
        _kSessionsNoFail,
        (prefs.getInt(_kSessionsNoFail) ?? 0) + 1,
      );
    }
    await _bumpDailyStreak(prefs);
  }

  /// Met à jour le streak quotidien : +1 si la veille avait une session,
  /// reset à 1 si trou, no-op si déjà une session aujourd'hui.
  Future<void> _bumpDailyStreak(SharedPreferences prefs) async {
    final today = _epochDay(DateTime.now());
    final last = prefs.getInt(_kLastSessionDay);
    if (last == today) return;
    final current = prefs.getInt(_kDailyStreak) ?? 0;
    final next = (last != null && today - last == 1) ? current + 1 : 1;
    await prefs.setInt(_kLastSessionDay, today);
    await prefs.setInt(_kDailyStreak, next);
  }

  static int _epochDay(DateTime d) {
    final utc = DateTime.utc(d.year, d.month, d.day);
    return utc.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }

  /// Efface tous les compteurs cumulés. Appelé par le bouton « tout
  /// remettre à zéro » du ProfileScreen.
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    const keys = [
      _kTotalSeconds,
      _kThroatfucks,
      _kBiffles,
      _kHoldThroatSec,
      _kHoldFullSec,
      _kSessionsCompleted,
      _kSessionsNoFail,
      _kModesUsedMask,
      _kMaxHoldFullSecAtomic,
      _kLastSessionDay,
      _kDailyStreak,
      _kEncoresAsked,
      _kQuickiesCompleted,
      _kHumiliationLevel,
      _kObedienceLevel,
      _kFinalsBouchePleine,
      _kFinalsRepeinte,
      _kFinalsGobeuse,
      _kPostFinalsNettoyeuse,
      _kPostFinalsSuppliante,
    ];
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}

/// Snapshot immuable des compteurs cumulés à un instant T.
class StatsSnapshot {
  final int totalSeconds;
  final int throatfucks;
  final int biffles;
  final int holdThroatSeconds;
  final int holdFullSeconds;
  final int sessionsCompleted;
  final int sessionsNoFailStreak;
  final int modesUsedMask;
  final int maxHoldFullAtomic;
  final int dailyStreak;
  final int encoresAsked;
  final int quickiesCompleted;
  final double humiliationLevel;
  final double obedienceLevel;
  final int finalsBouchePleine;
  final int finalsRepeinte;
  final int finalsGobeuse;
  final int postFinalsNettoyeuse;
  final int postFinalsSuppliante;

  const StatsSnapshot({
    required this.totalSeconds,
    required this.throatfucks,
    required this.biffles,
    required this.holdThroatSeconds,
    required this.holdFullSeconds,
    required this.sessionsCompleted,
    required this.sessionsNoFailStreak,
    required this.modesUsedMask,
    required this.maxHoldFullAtomic,
    required this.dailyStreak,
    required this.encoresAsked,
    required this.quickiesCompleted,
    required this.humiliationLevel,
    required this.obedienceLevel,
    this.finalsBouchePleine = 0,
    this.finalsRepeinte = 0,
    this.finalsGobeuse = 0,
    this.postFinalsNettoyeuse = 0,
    this.postFinalsSuppliante = 0,
  });

  bool isModeUsed(SessionMode mode) => (modesUsedMask & (1 << mode.index)) != 0;

  int get distinctModesUsed {
    var n = 0;
    var m = modesUsedMask;
    while (m != 0) {
      n += m & 1;
      m >>= 1;
    }
    return n;
  }
}
