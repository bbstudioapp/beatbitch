import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locales supportées par l'app. Ajouter une entrée + un fichier ARB
/// + un set de phrases JSON pour étendre.
const List<Locale> kSupportedLocales = [
  Locale('fr'),
  Locale('en'),
];

/// Locale de repli si aucune préférence persistée et que la locale système
/// n'est pas dans `kSupportedLocales`.
const Locale kFallbackLocale = Locale('fr');

const String _prefsKey = 'app.locale';

/// Singleton léger qui expose la locale active. Notifie les listeners quand
/// elle change. À instancier au démarrage (`await LocaleService.instance.init()`)
/// avant `runApp`.
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  Locale _current = kFallbackLocale;
  bool _initialized = false;

  Locale get current => _current;

  /// Code langue ISO-639 (ex: "fr", "en"). Pratique pour filtrer les JSON.
  String get languageCode => _current.languageCode;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && _isSupportedLanguage(stored)) {
      _current = Locale(stored);
      return;
    }

    final system = PlatformDispatcher.instance.locale;
    if (_isSupportedLanguage(system.languageCode)) {
      _current = Locale(system.languageCode);
    } else {
      _current = kFallbackLocale;
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!_isSupportedLanguage(locale.languageCode)) return;
    if (_current.languageCode == locale.languageCode) return;
    _current = Locale(locale.languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
    notifyListeners();
  }

  bool _isSupportedLanguage(String code) {
    for (final l in kSupportedLocales) {
      if (l.languageCode == code) return true;
    }
    return false;
  }
}
