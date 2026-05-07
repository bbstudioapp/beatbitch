import 'package:flutter/widgets.dart';

import 'surprise_alert_service.dart';

/// Observer global du cycle de vie de l'app. Quand l'utilisatrice ramène
/// l'app au foreground, on annule les notifs surprise pending pour ne
/// pas la déranger pendant qu'elle est en train d'utiliser l'app. Quand
/// elle la met en arrière-plan, on re-schedule (idempotent) les alertes
/// non encore consommées et toujours dans la fenêtre.
///
/// Attaché dans `main()` après `runApp` :
/// `WidgetsBinding.instance.addObserver(SurpriseLifecycleObserver());`
class SurpriseLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // ignore: discarded_futures
        SurpriseAlertService.instance.onAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // ignore: discarded_futures
        SurpriseAlertService.instance.onAppPaused();
        break;
    }
  }
}
