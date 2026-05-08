import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adult gate (18+) consent. Persisté dans SharedPreferences ; le boot lit
/// la valeur une fois et `ModeSelectionScreen` la consulte au mount pour
/// décider d'afficher le dialog d'acceptation. Pas d'expiration : un coup
/// accepté reste accepté tant que l'utilisatrice ne reset pas l'app.
class AdultConsentService extends ChangeNotifier {
  AdultConsentService._();
  static final AdultConsentService instance = AdultConsentService._();

  static const String _prefsKey = 'app.adult_consent_accepted';

  bool _accepted = false;
  bool _initialized = false;

  bool get isAccepted => _accepted;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _accepted = prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> accept() async {
    if (_accepted) return;
    _accepted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
    notifyListeners();
  }

  /// Reset utilisé par le bouton « Tout remettre à zéro » du ProfileScreen.
  Future<void> resetAll() async {
    _accepted = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }
}
