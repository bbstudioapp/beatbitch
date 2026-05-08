import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'surprise_alert_service.dart';

/// Initialisation centralisée du plugin `flutter_local_notifications` +
/// timezone. Statique : appelée une fois dans `main()` avant `runApp`.
///
/// Toutes les notifs surprise passent par cette couche pour rester
/// cohérentes (channel, importance, payload, callback de tap).
class SurpriseNotificationsBootstrap {
  SurpriseNotificationsBootstrap._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'surprise_alert';
  static const String _channelName = 'Rappel surprise';
  static const String _channelDescription =
      'Notifications aléatoires pour démarrer une session courte.';

  /// Titre par défaut de la notif. Remplacé par la valeur i18n au moment
  /// de l'arming (cf. `SurpriseAlertService.arm` qui passe le body localisé).
  static String notificationTitle = "C'est l'heure";

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static bool _initialized = false;

  /// À appeler dans `main()` après `WidgetsFlutterBinding.ensureInitialized()`.
  /// Hook le callback de tap. Doit être appelée AVANT `runApp` pour que les
  /// taps cold-start soient récupérables via `getNotificationAppLaunchDetails`.
  static Future<void> init({
    required String localizedTitle,
    required void Function(NotificationResponse) onTap,
  }) async {
    if (_initialized) return;
    _initialized = true;

    notificationTitle = localizedTitle;

    tzdata.initializeTimeZones();
    // tz.local est résolu via la timezone système dès initializeTimeZones().
    // Pas de setLocalLocation nécessaire — flutter_local_notifications utilise
    // tz.local pour les zonedSchedule.

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onTap,
    );

    // Crée le channel HIGH importance + vibration ON. Idempotent côté OS.
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
  }

  /// Demande la permission POST_NOTIFICATIONS (Android 13+) si nécessaire.
  /// Sur Android 12-, la permission est implicite et la fonction renvoie
  /// `true`.
  static Future<bool> ensureNotificationPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final granted =
        await androidPlugin.requestNotificationsPermission() ?? true;
    return granted;
  }

  /// Lit l'éventuel intent de cold-start. Retourne le payload (windowId)
  /// si l'app vient d'être lancée par un tap notif, sinon null.
  static Future<String?> consumeColdStartPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null) return null;
    if (details.didNotificationLaunchApp != true) return null;
    return details.notificationResponse?.payload;
  }

  /// Programme une notif via AlarmManager (`exactAllowWhileIdle`). Le
  /// `payload` est le `windowId` — au tap, on s'en sert pour retrouver
  /// quelle fenêtre a déclenché l'alerte.
  static Future<void> scheduleAlert({
    required int id,
    required tz.TZDateTime scheduledAt,
    required String title,
    required String body,
    String payload = '',
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.private,
      enableVibration: true,
      autoCancel: true,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledAt,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      // uiLocalNotificationDateInterpretation est requis par la signature
      // mais sans effet sur Android.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }
}

/// Callback top-level appelé par le plugin quand l'utilisatrice tape une
/// notification (warm path). Doit être top-level (pas de capture de
/// closure) parce que le plugin l'invoque via une isolate dédiée sur
/// certaines plateformes.
@pragma('vm:entry-point')
void surpriseNotificationTapHandler(NotificationResponse response) {
  final payload = response.payload ?? '';
  // Pose le flag d'intent — le routing UI consommera quand l'écran principal
  // sera prêt (cf. `SurpriseRouter.routeIfArmed`).
  // Note: SurpriseAlertService utilise uniquement SharedPreferences ici,
  // pas de dépendance UI. Sûr depuis un isolate top-level.
  // ignore: discarded_futures
  SurpriseAlertService.markIntentPending(payload).catchError((Object e) {
    if (kDebugMode) debugPrint('Surprise tap handler: $e');
  });
}
