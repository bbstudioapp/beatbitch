import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'stats_service.dart';
import 'surprise_notifications_bootstrap.dart';

/// Résultat d'une tentative d'arm. Permet à l'UI d'afficher un feedback
/// précis (snackbar avec lien vers les paramètres système si la permission
/// notif est manquante).
enum SurpriseArmResult {
  ok,
  notificationPermissionDenied,
  exactAlarmDenied,
}

enum _AlertStatus { pending, silenced, consumed, ignored }

class _SurpriseAlertEntry {
  final int id;
  final int scheduledAtEpoch;
  final String body;
  _AlertStatus status;

  _SurpriseAlertEntry({
    required this.id,
    required this.scheduledAtEpoch,
    required this.body,
    this.status = _AlertStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'scheduledAtEpoch': scheduledAtEpoch,
        'body': body,
        'status': status.name,
      };

  static _SurpriseAlertEntry fromJson(Map<String, dynamic> j) {
    return _SurpriseAlertEntry(
      id: j['id'] as int,
      scheduledAtEpoch: j['scheduledAtEpoch'] as int,
      body: (j['body'] as String?) ?? '',
      status: _AlertStatus.values.firstWhere(
        (s) => s.name == (j['status'] as String? ?? 'pending'),
        orElse: () => _AlertStatus.pending,
      ),
    );
  }
}

/// Snapshot lisible de l'état actuel pour l'UI.
class SurpriseScheduleSnapshot {
  final String windowId;
  final DateTime windowEnd;
  final int pendingAlertCount;

  SurpriseScheduleSnapshot({
    required this.windowId,
    required this.windowEnd,
    required this.pendingAlertCount,
  });
}

/// Singleton qui orchestre la programmation des notifications surprises.
/// Pattern aligné sur `LocaleService` / `CameraMotionService` : pas de
/// `ChangeNotifier` (pas d'UI bindée live — l'écran de réglage rebuild
/// après chaque action).
class SurpriseAlertService {
  SurpriseAlertService._();
  static final SurpriseAlertService instance = SurpriseAlertService._();

  static const String _kEnabled = 'surprise.enabled';
  static const String _kWindowSeconds = 'surprise.window_seconds';
  static const String _kAlertCount = 'surprise.alert_count';
  static const String _kDurationMin = 'surprise.duration_min_s';
  static const String _kDurationMax = 'surprise.duration_max_s';
  static const String _kScheduleState = 'surprise.schedule_state';
  static const String _kIntentPending = 'surprise.intent_pending';
  static const String _kIntentWindowId = 'surprise.intent_window_id';

  /// Range d'IDs réservés aux notifications surprise (évite d'écraser
  /// d'éventuelles autres notifs futures).
  static const int _idBase = 9000;
  static const int _idMaxOffset = 99;

  /// Clamping des réglages utilisateur.
  static const int windowSecondsMin = 15 * 60;
  static const int windowSecondsMax = 4 * 3600;
  static const int alertCountMin = 1;
  static const int alertCountMax = 5;
  static const int durationSecondsMin = 60;
  static const int durationSecondsMax = 240;

  /// Délais min entre 2 alertes successives, et avant la 1re alerte.
  /// 15 min entre 2 = règle implicite « max 2 alertes par 30 min ». Au-delà
  /// du confort de l'utilisatrice, ça borne aussi le cap effectif à
  /// `(window / 15 min) + 1` quel que soit le `alertCount` configuré.
  static const Duration _spacing = Duration(minutes: 15);
  static const Duration _firstAlertDelay = Duration(seconds: 30);

  /// Guard utilisé par `onAppResumed` : marque silenced toute alerte
  /// dont le déclenchement tombe dans cet intervalle après le `resumed`,
  /// sous l'hypothèse que l'utilisatrice reste foreground au moins ce
  /// temps. Plus court que `_spacing` (qui borne l'arming) — sinon on
  /// perdrait toutes les alertes des 15 prochaines minutes à chaque
  /// passage foreground.
  static const Duration _foregroundSilenceGuard = Duration(seconds: 60);

  /// Pénalité d'obéissance appliquée à chaque notif surprise tirée mais
  /// non acceptée (= non tapée). Comparable à un fail manuel (-2) avec
  /// une légère surcote pour matérialiser le refus actif d'un ordre.
  /// `StatsService.setObedienceLevel` borne à 0 (pas de score négatif).
  static const double _ignoredObediencePenalty = 3.0;

  bool _initialized = false;
  final Random _random = Random();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // Détection « notif tirée mais non tapée » à faire AVANT le clean-up
    // de fenêtre expirée (`_resyncFromState` jette le state si
    // `windowEnd < now`) — sinon on perd la pénalité d'obéissance pour
    // les ignores de la fenêtre passée.
    await _detectIgnoredAndApplyPenalty();
    // Re-schedule défensif : si le process Dart est relancé en cours de
    // fenêtre (boot, killed-restored), les alarms natives survivent —
    // mais on rejoue notre snapshot pour s'assurer qu'aucune n'a été
    // perdue par un cancel partiel.
    await _resyncFromState();
  }

  // ─── Réglages ──────────────────────────────────────────────────────────

  Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  Future<int> getWindowSeconds() async {
    final p = await SharedPreferences.getInstance();
    return _clampWindow(p.getInt(_kWindowSeconds) ?? 3600);
  }

  Future<void> setWindowSeconds(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kWindowSeconds, _clampWindow(v));
  }

  Future<int> getAlertCount() async {
    final p = await SharedPreferences.getInstance();
    return _clampCount(p.getInt(_kAlertCount) ?? 3);
  }

  Future<void> setAlertCount(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAlertCount, _clampCount(v));
  }

  Future<({int min, int max})> getDurationRangeSeconds() async {
    final p = await SharedPreferences.getInstance();
    final mn = _clampDuration(p.getInt(_kDurationMin) ?? 60);
    final mx = _clampDuration(p.getInt(_kDurationMax) ?? 240);
    return mx >= mn ? (min: mn, max: mx) : (min: mx, max: mn);
  }

  Future<void> setDurationRangeSeconds(int min, int max) async {
    final p = await SharedPreferences.getInstance();
    final a = _clampDuration(min);
    final b = _clampDuration(max);
    await p.setInt(_kDurationMin, a < b ? a : b);
    await p.setInt(_kDurationMax, a < b ? b : a);
  }

  /// Tirage uniforme dans `[durationMin, durationMax]`. Lu à chaque tap
  /// de notif pour que la durée reste imprévisible.
  Future<int> pickRandomDurationSeconds() async {
    final r = await getDurationRangeSeconds();
    if (r.max <= r.min) return r.min;
    return r.min + _random.nextInt(r.max - r.min + 1);
  }

  // ─── Arm / Disarm ──────────────────────────────────────────────────────

  /// Programme les alertes selon les réglages courants. Annule d'abord
  /// les alarmes existantes pour éviter les doublons. Persiste le state.
  /// Retourne `notificationPermissionDenied` si Android 13+ refuse la
  /// permission POST_NOTIFICATIONS.
  Future<SurpriseArmResult> arm({
    required List<String> bodyVariants,
  }) async {
    final permGranted =
        await SurpriseNotificationsBootstrap.ensureNotificationPermission();
    if (!permGranted) {
      return SurpriseArmResult.notificationPermissionDenied;
    }

    await _cancelAllScheduled();

    final now = DateTime.now();
    final windowSeconds = await getWindowSeconds();
    final alertCount = await getAlertCount();
    final windowEnd = now.add(Duration(seconds: windowSeconds));

    final times = _pickAlertTimes(
      now: now,
      windowEnd: windowEnd,
      count: alertCount,
    );
    if (times.isEmpty) {
      // Fenêtre trop courte pour respecter les contraintes — on persiste
      // un state vide mais "enabled" pour que l'UI affiche ce qui se
      // passe, et on retourne ok (rien à scheduler).
      await _persistEnabled(true);
      await _persistState(_buildState(windowEnd, const []));
      return SurpriseArmResult.ok;
    }

    final entries = <_SurpriseAlertEntry>[];
    for (var i = 0; i < times.length; i++) {
      final id = _idBase + i;
      final body = _pickBody(bodyVariants);
      entries.add(_SurpriseAlertEntry(
        id: id,
        scheduledAtEpoch: times[i].millisecondsSinceEpoch,
        body: body,
      ));
      await _scheduleNative(id: id, at: times[i], body: body);
    }

    await _persistEnabled(true);
    await _persistState(_buildState(windowEnd, entries));
    return SurpriseArmResult.ok;
  }

  /// Annule toutes les alertes pending et clear l'état.
  Future<void> disarm() async {
    await _cancelAllScheduled();
    await _persistEnabled(false);
    await _persistState(null);
  }

  /// Consomme la fenêtre courante : annule toutes les alarms restantes au
  /// niveau natif et marque la fenêtre terminée. Appelé au moment où une
  /// session surprise se lance — on ne veut plus aucune notif tomber tant
  /// que l'utilisatrice est en pleine séance, et on évite les notifs
  /// fantômes pendant qu'elle joue.
  ///
  /// Si elle veut un autre rappel, elle re-arm depuis l'écran de réglages.
  Future<void> consumeWindow() async {
    await _cancelAllScheduled();
    await _persistEnabled(false);
    await _persistState(null);
  }

  // ─── État courant ──────────────────────────────────────────────────────

  Future<SurpriseScheduleSnapshot?> currentState() async {
    final state = await _readState();
    if (state == null) return null;
    final windowEnd =
        DateTime.fromMillisecondsSinceEpoch(state['windowEndEpoch'] as int);
    if (windowEnd.isBefore(DateTime.now())) {
      // Fenêtre expirée — clean up silencieusement.
      await _persistState(null);
      await _persistEnabled(false);
      return null;
    }
    final alerts = (state['alerts'] as List<dynamic>)
        .map((e) => _SurpriseAlertEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final pending =
        alerts.where((a) => a.status == _AlertStatus.pending).length;
    return SurpriseScheduleSnapshot(
      windowId: state['windowId'] as String,
      windowEnd: windowEnd,
      pendingAlertCount: pending,
    );
  }

  // ─── Intent au tap ─────────────────────────────────────────────────────

  /// Appelé depuis le callback notification (ou depuis main au cold start
  /// via getNotificationAppLaunchDetails). Pose le flag persistant.
  static Future<void> markIntentPending(String windowId) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIntentPending, true);
    await p.setString(_kIntentWindowId, windowId);
  }

  /// Read+clear atomique du flag d'intent. Retourne true si une session
  /// surprise doit être lancée maintenant.
  ///
  /// Marque aussi l'alerte tapée comme `consumed` dans le state AVANT de
  /// clear le flag d'intent : `onAppResumed` peut tourner en parallèle et
  /// si elle lit intent_pending=false (déjà consommé) elle ne saura plus
  /// quelle alerte exclure de la pénalité. Avec ce marquage en amont,
  /// elle voit `status != pending` et ignore l'alerte naturellement.
  Future<bool> consumeNextIntent() async {
    final p = await SharedPreferences.getInstance();
    final pending = p.getBool(_kIntentPending) ?? false;
    if (!pending) return false;
    final tappedId = int.tryParse(p.getString(_kIntentWindowId) ?? '');
    if (tappedId != null) {
      await _markAlertConsumed(tappedId);
    }
    await p.remove(_kIntentPending);
    await p.remove(_kIntentWindowId);
    return true;
  }

  Future<void> _markAlertConsumed(int alertId) async {
    final state = await _readState();
    if (state == null) return;
    final alerts = (state['alerts'] as List<dynamic>)
        .map((e) => _SurpriseAlertEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    var changed = false;
    for (final a in alerts) {
      if (a.id == alertId && a.status == _AlertStatus.pending) {
        a.status = _AlertStatus.consumed;
        changed = true;
        break;
      }
    }
    if (changed) {
      state['alerts'] = alerts.map((e) => e.toJson()).toList(growable: false);
      await _persistStateRaw(state);
    }
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────

  /// App passe foreground : on annule toutes les alarms pending pour
  /// éviter qu'une notif s'affiche pendant qu'on est ouvert. Heuristique
  /// : on considère qu'on reste foreground ≥ 60s, donc on marque
  /// `silenced` les alertes dont scheduledAt - now < 60s.
  ///
  /// Pour les alertes déjà tirées (scheduledAt < now), on distingue :
  /// - tapée (id == intent.windowId) → `consumed`
  /// - non tapée → `ignored`, applique une pénalité d'obéissance
  Future<void> onAppResumed() async {
    final state = await _readState();
    if (state == null) return;
    final alerts = (state['alerts'] as List<dynamic>)
        .map((e) => _SurpriseAlertEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final now = DateTime.now();
    final plugin = SurpriseNotificationsBootstrap.plugin;
    final guardEnd = now.add(_foregroundSilenceGuard);
    final p = await SharedPreferences.getInstance();
    final hasIntent = p.getBool(_kIntentPending) ?? false;
    final tappedId =
        hasIntent ? int.tryParse(p.getString(_kIntentWindowId) ?? '') : null;
    var ignoredCount = 0;
    var changed = false;
    for (final a in alerts) {
      if (a.status != _AlertStatus.pending) continue;
      try {
        await plugin.cancel(a.id);
      } catch (_) {
        // Si le plugin n'est pas encore initialisé (race au cold start),
        // on persiste juste la transition de statut.
      }
      final at = DateTime.fromMillisecondsSinceEpoch(a.scheduledAtEpoch);
      if (at.isBefore(now)) {
        if (tappedId != null && tappedId == a.id) {
          a.status = _AlertStatus.consumed;
        } else {
          a.status = _AlertStatus.ignored;
          ignoredCount++;
        }
        changed = true;
      } else if (at.isBefore(guardEnd)) {
        a.status = _AlertStatus.silenced;
        changed = true;
      }
      // else: future au-delà du guard → laisse pending pour re-schedule
      // au prochain `onAppPaused`.
    }
    if (changed) {
      state['alerts'] = alerts.map((a) => a.toJson()).toList(growable: false);
      await _persistStateRaw(state);
    }
    if (ignoredCount > 0) {
      await _applyIgnoredObediencePenalty(ignoredCount);
    }
  }

  /// Détecte les alertes tirées dans une fenêtre passée mais non tapées,
  /// et applique la pénalité d'obéissance correspondante. Appelée au
  /// cold-start (`init`) pour rattraper les ignores survenues pendant
  /// que l'app était killed.
  Future<void> _detectIgnoredAndApplyPenalty() async {
    final state = await _readState();
    if (state == null) return;
    final alerts = (state['alerts'] as List<dynamic>)
        .map((e) => _SurpriseAlertEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final now = DateTime.now();
    final p = await SharedPreferences.getInstance();
    final hasIntent = p.getBool(_kIntentPending) ?? false;
    final tappedId =
        hasIntent ? int.tryParse(p.getString(_kIntentWindowId) ?? '') : null;
    var ignoredCount = 0;
    var changed = false;
    for (final a in alerts) {
      if (a.status != _AlertStatus.pending) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(a.scheduledAtEpoch);
      if (!at.isBefore(now)) continue;
      if (tappedId != null && tappedId == a.id) {
        a.status = _AlertStatus.consumed;
      } else {
        a.status = _AlertStatus.ignored;
        ignoredCount++;
      }
      changed = true;
    }
    if (changed) {
      state['alerts'] = alerts.map((e) => e.toJson()).toList(growable: false);
      await _persistStateRaw(state);
    }
    if (ignoredCount > 0) {
      await _applyIgnoredObediencePenalty(ignoredCount);
    }
  }

  Future<void> _applyIgnoredObediencePenalty(int count) async {
    final stats = StatsService();
    final current = await stats.getObedienceLevel();
    await stats.setObedienceLevel(
      current - _ignoredObediencePenalty * count,
    );
  }

  /// App passe background/inactive : on re-schedule (idempotent) les
  /// alertes pending non silenced dont scheduledAt > now.
  Future<void> onAppPaused() async {
    final state = await _readState();
    if (state == null) return;
    final alerts = (state['alerts'] as List<dynamic>)
        .map((e) => _SurpriseAlertEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    final now = DateTime.now();
    final windowEnd =
        DateTime.fromMillisecondsSinceEpoch(state['windowEndEpoch'] as int);
    for (final a in alerts) {
      if (a.status != _AlertStatus.pending) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(a.scheduledAtEpoch);
      if (at.isBefore(now) || at.isAfter(windowEnd)) continue;
      await _scheduleNative(id: a.id, at: at, body: a.body);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Future<void> _resyncFromState() async {
    final state = await _readState();
    if (state == null) return;
    final windowEnd =
        DateTime.fromMillisecondsSinceEpoch(state['windowEndEpoch'] as int);
    final now = DateTime.now();
    if (windowEnd.isBefore(now)) {
      await _persistState(null);
      await _persistEnabled(false);
      return;
    }
    // Le re-schedule effectif se fera à `onAppPaused` quand l'app passe
    // en arrière-plan. Au cold-start, le process est foreground, donc on
    // ne re-schedule pas (sinon la notif tomberait immédiatement après le
    // cold-start si l'app reste ouverte).
  }

  List<DateTime> _pickAlertTimes({
    required DateTime now,
    required DateTime windowEnd,
    required int count,
  }) {
    final start = now.add(_firstAlertDelay);
    if (!start.isBefore(windowEnd)) return const [];
    final spanSeconds = windowEnd.difference(start).inSeconds;
    if (spanSeconds <= 0) return const [];
    // Réduit count si l'espacement min ne tient pas dans la fenêtre.
    final maxFit = (spanSeconds ~/ _spacing.inSeconds) + 1;
    final effectiveCount = count.clamp(1, maxFit).clamp(1, alertCountMax);

    // Rejection sampling avec budget borné.
    for (var attempt = 0; attempt < 12; attempt++) {
      final picks = <DateTime>[];
      for (var i = 0; i < effectiveCount; i++) {
        final offset = _random.nextInt(spanSeconds + 1);
        picks.add(start.add(Duration(seconds: offset)));
      }
      picks.sort();
      var ok = true;
      for (var i = 1; i < picks.length; i++) {
        if (picks[i].difference(picks[i - 1]) < _spacing) {
          ok = false;
          break;
        }
      }
      if (ok) return picks;
    }

    // Fallback : répartition stratifiée. On découpe la fenêtre en
    // `effectiveCount` strates et tire un instant random dans chacune,
    // en respectant l'espacement min.
    final stratum = spanSeconds ~/ effectiveCount;
    final result = <DateTime>[];
    for (var i = 0; i < effectiveCount; i++) {
      final lo = i * stratum;
      final hi = (i == effectiveCount - 1) ? spanSeconds : (i + 1) * stratum;
      final picked = lo + _random.nextInt((hi - lo).clamp(1, spanSeconds));
      var t = start.add(Duration(seconds: picked));
      if (result.isNotEmpty && t.difference(result.last) < _spacing) {
        t = result.last.add(_spacing);
      }
      if (t.isAfter(windowEnd)) break;
      result.add(t);
    }
    return result;
  }

  Future<void> _scheduleNative({
    required int id,
    required DateTime at,
    required String body,
  }) async {
    try {
      await SurpriseNotificationsBootstrap.scheduleAlert(
        id: id,
        scheduledAt: tz.TZDateTime.from(at, tz.local),
        title: SurpriseNotificationsBootstrap.notificationTitle,
        body: body,
        // Payload = alert id (string). Permet au tap handler de remonter
        // l'identifiant exact via `markIntentPending`, et donc de
        // distinguer la notif acceptée des autres notifs ignorées dans
        // la même fenêtre (cf. `_detectIgnoredAndApplyPenalty`).
        payload: id.toString(),
      );
    } catch (e) {
      // Best-effort : on ne casse pas l'arming si une alarm individuelle
      // échoue (p.ex. exact-alarm refusé sur certains OEM).
      if (kDebugMode) {
        debugPrint('SurpriseAlert: zonedSchedule failed for id=$id: $e');
      }
    }
  }

  Future<void> _cancelAllScheduled() async {
    final plugin = SurpriseNotificationsBootstrap.plugin;
    for (var i = 0; i <= _idMaxOffset; i++) {
      try {
        await plugin.cancel(_idBase + i);
      } catch (_) {}
    }
  }

  String _pickBody(List<String> variants) {
    if (variants.isEmpty) {
      return SurpriseNotificationsBootstrap.notificationTitle;
    }
    return variants[_random.nextInt(variants.length)];
  }

  Future<Map<String, dynamic>?> _readState() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kScheduleState);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      await p.remove(_kScheduleState);
    }
    return null;
  }

  Future<void> _persistEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  Future<void> _persistState(Map<String, dynamic>? state) async {
    final p = await SharedPreferences.getInstance();
    if (state == null) {
      await p.remove(_kScheduleState);
    } else {
      await p.setString(_kScheduleState, json.encode(state));
    }
  }

  Future<void> _persistStateRaw(Map<String, dynamic> state) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kScheduleState, json.encode(state));
  }

  Map<String, dynamic> _buildState(
    DateTime windowEnd,
    List<_SurpriseAlertEntry> entries,
  ) {
    return {
      'windowId': _newWindowId(),
      'windowEndEpoch': windowEnd.millisecondsSinceEpoch,
      'alerts': entries.map((e) => e.toJson()).toList(growable: false),
    };
  }

  String _newWindowId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final r = _random.nextInt(1 << 30);
    return '${ts.toRadixString(36)}-${r.toRadixString(36)}';
  }

  int _clampWindow(int v) => v.clamp(windowSecondsMin, windowSecondsMax);
  int _clampCount(int v) => v.clamp(alertCountMin, alertCountMax);
  int _clampDuration(int v) => v.clamp(durationSecondsMin, durationSecondsMax);
}
