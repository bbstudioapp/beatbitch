import 'package:flutter/foundation.dart';

class PlatformCapabilities {
  PlatformCapabilities._();

  /// ML Kit on-device n'existe que sur mobile ; la caméra n'a pas d'implémentation desktop.
  static bool get supportsCameraHoldCheck {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// L'alarme exacte (`USE_EXACT_ALARM`) n'est pas portable hors Android.
  static bool get supportsSurpriseNotifications {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Seuil Material entre téléphone et tablette, en pixels logiques.
  static const double phoneMaxShortestSide = 600;

  static bool locksPortrait({
    required bool isWeb,
    required TargetPlatform platform,
    required double shortestSide,
  }) {
    if (isWeb) return false;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      return false;
    }
    return shortestSide < phoneMaxShortestSide;
  }
}
