import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Trace si la sheet d'onboarding (3 étapes) a déjà été présentée. Lue au
/// boot de `ModeSelectionScreen` après l'adult gate ; mise à true à la
/// première fermeture de la sheet (skip ou complétion).
class OnboardingService extends ChangeNotifier {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const String _prefsKey = 'onboarding.shown';

  bool _shown = false;
  bool _initialized = false;

  bool get hasBeenShown => _shown;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _shown = prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> markShown() async {
    if (_shown) return;
    _shown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    notifyListeners();
  }

  Future<void> resetAll() async {
    _shown = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
