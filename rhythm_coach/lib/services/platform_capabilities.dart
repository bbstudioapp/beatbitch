import 'package:flutter/foundation.dart';

/// Capacités plateformes que l'app exige côté natif.
///
/// Utilisé par les écrans et le bootstrap pour masquer ou désactiver
/// proprement les fonctionnalités qui dépendent de plugins disponibles
/// uniquement sur Android (caméra ML Kit, notifications surprise zonées).
///
/// Sur les autres plateformes (Windows desktop notamment), les services
/// concernés tombent sur des stubs no-op et leur point d'entrée UI doit
/// être masqué : sans caméra ni alarme exacte, le toggle n'a rien à
/// piloter.
class PlatformCapabilities {
  PlatformCapabilities._();

  /// Vérif caméra des holds (`camera` + `google_mlkit_face_detection` +
  /// `sensors_plus`). Aucun de ces plugins ne fournit d'implémentation
  /// Windows, et le code s'appuie sur ML Kit on-device qui n'existe que
  /// sur mobile.
  static bool get supportsCameraHoldCheck {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Notifications surprise (`flutter_local_notifications` +
  /// `timezone.zonedSchedule` + canal Android avec `USE_EXACT_ALARM`).
  /// Le bootstrap actuel utilise `AndroidInitializationSettings` et la
  /// sémantique d'alarme exacte n'est pas portable.
  static bool get supportsSurpriseNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }
}
